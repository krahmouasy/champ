!! The current implementation uses a general  davidson algorithm, meaning
!! that it compute all the eigenvalues simultaneusly using a variable size block approach.
!! The family of Davidson algorithm only differ in the way that the correction
!! vector is computed.
!! Computed pairs of eigenvalues/eigenvectors are deflated using algorithm
!! described at: https://doi.org/10.1023/A:101919970
!!
!! Authors: Felipe Zapata and revised by P. Lopez-Tarifa NLeSC(2019)
!> 
!> \brief Solves the Davidson diagonalisation without storing matrices in memory. 
!> 
!> Matrices mtx and stx are calculated on the fly using the fun_mtx_gemv and fun_stx_gemv
!> functions. 
!>
!> \author Felipe Zapata and P. Lopez-Tarifa NLeSC(2019)
!> 
!> \param[in] mtx: Matrix to diagonalize
!> \param[inout] stx: Optional matrix for the general eigenvalue problem:
!> \f$ mtx \lambda = V stx \lambda \f$
!> \param[out] eigenvalues Computed eigenvalues
!> \param[out] ritz_vectors Approximation to the eigenvectors
!> \param[in] lowest Number of lowest eigenvalues/ritz_vectors to compute
!> \param[in] method Method to compute the correction vector. Available
!> methods are:
!>    - DPR: Diagonal-Preconditioned-Residue.
!>    - GJD: Generalized Jacobi Davidsoni.
!> \param[in] max_iters: Maximum number of iterations.
!> \param[in] tolerance Norm**2 error of the eigenvalues.
!> \param[in] method: Method to compute the correction vectors.
!> \param[out] iters: Number of iterations until convergence.
!> \return eigenvalues and ritz_vectors of the matrix `mtx`.
module davidson
  use numeric_kinds, only: dp
  use lapack_wrapper, only: lapack_generalized_eigensolver, lapack_matmul, lapack_matrix_vector, &
       lapack_qr, lapack_solver
  use array_utils, only: concatenate, initialize_subspace, norm, write_matrix, write_vector, & 
                        eye, check_deallocate_matrix, check_deallocate_vector, modified_gram_schmidt
  implicit none

  type davidson_parameters
     INTEGER :: nparm
     INTEGER :: nparm_max
     INTEGER :: lowest
     INTEGER :: nvecx 
     INTEGER :: basis_size 
  end type davidson_parameters

  !> \private
  private
  !> \public
  public :: generalized_eigensolver, davidson_parameters, die
  
contains

  subroutine generalized_eigensolver (fun_mtx_gemv, eigenvalues, eigenvectors, nparm, nparm_max, &
       lowest, nvecx, method, max_iters, tolerance, iters, fun_stx_gemv, nproc, idtask)
    !> \brief use a pair of functions fun_mtx and fun_stx to compute on the fly the matrices to solve
    !>  the general eigenvalue problem
    !> The current implementation uses a general  davidson algorithm, meaning
    !> that it compute all the eigenvalues simultaneusly using a block approach.
    !> The family of Davidson algorithm only differ in the way that the correction
    !> vector is computed.
    
    !> \param[in] fun_mtx_gemv: Function to apply the matrix to a buncof vectors
    !> \param[in, opt] fun_stx_gemv: (optional) function to apply the pencil to a bunch of vectors.
    !> \param[out] eigenvalues Computed eigenvalues
    !> \param[inout] eigenvectors approximation to the eigenvectors
    !> \param nparm[in] Leading dimension of the matrix to diagonalize
    !> \param nparm_max[in] Maximum dimension of the matrix to diagonalize
    !> \param[in] lowest Number of lowest eigenvalues/ritz_vectors to compute
    !> \param[in] method Method to compute the correction vector. Available
    !> methods are,
    !>    DPR: Diagonal-Preconditioned-Residue
    !>    GJD: Generalized Jacobi Davidson
    !> \param[in] max_iters: Maximum number of iterations
    !> \param[in] tolerance norm-2 error of the eigenvalues
    !> \param[in] method: Method to compute the correction vectors
    !> \param[out] iters: Number of iterations until convergence
    !> \return eigenvalues and ritz_vectors of the matrix `mtx`

    implicit none

    include 'mpif.h'

    ! input/output variable
    integer, intent(in) :: nparm, nparm_max, nvecx, lowest, nproc, idtask
    real(dp), dimension(lowest), intent(out) :: eigenvalues
    real(dp), dimension(:, :), allocatable, intent(out) :: eigenvectors
    integer, intent(in) :: max_iters
    real(dp), intent(in) :: tolerance
    character(len=*), intent(in) :: method
    integer, intent(out) :: iters
    
    ! Function to compute the target matrix on the fly
    interface

     function fun_mtx_gemv(parameters, input_vect) result(output_vect)
       !> \brief Function to compute the action of the hamiltonian on the fly
       !> \param[in] dimension of the arrays to compute the action of the hamiltonian
       !> \param[in] input_vec Array to project
       !> \return Projected matrix

       use numeric_kinds, only: dp
       import :: davidson_parameters
       type(davidson_parameters) :: parameters
       real (dp), dimension(:,:), intent(in) :: input_vect
       real (dp), dimension(size(input_vect,1),size(input_vect,2)) :: output_vect
       
     end function fun_mtx_gemv
     
     function fun_stx_gemv(parameters, input_vect) result(output_vect)
       !> \brief Fucntion to compute the optional stx matrix on the fly
       !> \param[in] dimension of the arrays to compute the action of the hamiltonian
       !> \param[in] input_vec Array to project
       !> \return Projected matrix
       
       use numeric_kinds, only: dp
       import :: davidson_parameters
       type(davidson_parameters) :: parameters
       real (dp), dimension(:,:), intent(in) :: input_vect
       real (dp), dimension(size(input_vect,1), size(input_vect,2)) :: output_vect
       
       end function fun_stx_gemv

    end interface

    ! Local variables
    integer :: i, j, ier
    integer :: init_subspace_size, max_size_basis, size_update

    ! Basis of subspace of approximants
    real(dp), dimension(:), allocatable :: diag_mtx, diag_stx
    real(dp), dimension(:,:), allocatable :: residues
    real(dp), dimension(lowest):: errors
    
    ! Working arrays
    real( dp), dimension(:), allocatable :: eigenvalues_sub
    real( dp), dimension(:,:), allocatable :: ritz_vectors
    real( dp), dimension(:, :), allocatable :: correction, eigenvectors_sub, mtx_proj, stx_proj, V
    real( dp), dimension(:, :), allocatable :: mtxV, stxV 
    real( dp), dimension(nparm, 1) :: xs, gs

    ! real( dp), dimension(:,:), allocatable :: lambda              ! eigenvalues_sub in a diagonal matrix 
    ! real( dp), dimension(:,:), allocatable :: tmp_res_array       ! tmp array for vectorized res calculation  

    ! Arrays dimension
    type(davidson_parameters) :: parameters

    ! Indices of the eigenvalues/eigenvectors pair that have not converged
    logical, dimension( lowest) :: has_converged
    logical :: update_proj
    integer :: n_converged ! Number of converged eigenvalue/eigenvector pairs
    
    ! Iteration subpsace dimension
    init_subspace_size = lowest  * 2

    ! number of correction vectors appended to V at each iteration
    size_update = lowest * 2

    ! Lapack qr safety check 
    if (nvecx > nparm) then 
      if( idtask == 1) call die('DAV: nvecx > nparm, increase nparm or decrease lin_nvecx')
    endif

    ! Dimension of the matrix
    parameters = davidson_parameters(nparm, nparm_max, lowest, nvecx, init_subspace_size) 

    ! 1. Variables initialization
    ! extract the diagonals of the matrices

    write(6,'(''DAV: Compute diagonals of S and H'')')

    ! Initial number of converged eigenvalue/eigenvector pairs
    n_converged = 0
    has_converged = .false.
    update_proj = .false.

    ! Diagonal of the arrays
    allocate(diag_mtx(parameters%nparm))
    allocate(diag_stx(parameters%nparm))

    if (idtask==0) call store_diag_hs(parameters%nparm, diag_mtx, diag_stx)

    ! why ?
    ! wouldn't it be faster to have all the procs computing that
    ! instead of master computes and then broadcast ?
    ! Needed for initalizing V so we need it
    if (nproc > 1) then  
       call MPI_BCAST( diag_mtx, parameters%nparm, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
       call MPI_BCAST( diag_stx, parameters%nparm, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
    endif 

 
    ! 2.  Select the initial ortogonal subspace based on lowest elements
    !     of the diagonal of the matrix.
    ! No we should find the min elements along the entire diagonal not just the first init_subspace_size elements !
    ! V = initialize_subspace( diag_mtx( 1: init_subspace_size), init_subspace_size, nparm) ! Initial orthonormal basis
    V = initialize_subspace( diag_mtx, init_subspace_size, nparm) ! Initial orthonormal basis
    
    if( idtask== 0) write(6,'(''DAV: Setup subspace problem'')')

    ! allocate mtxV and stxV
    allocate( mtxV( parameters%nparm, parameters%basis_size))
    allocate( stxV( parameters%nparm, parameters%basis_size)) 

    ! Calculation of HV and SV
    ! Only the master has the correct matrix
    ! nut only the master needs it
    mtxV = fun_mtx_gemv( parameters, V)
    stxV = fun_stx_gemv( parameters, V)

    ! they all just computed it ! why broadcasting !
    ! apparently needed for the correction.
    ! I don't think they are needed on the slaves
    ! if (nproc> 1) then
    !   call MPI_BCAST( mtxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
    !   call MPI_BCAST( stxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
    ! endif

    ! 3. Outer loop block Davidson
    outer_loop: do i= 1, max_iters

      ! do most of the calculation on the master
      ! we could try to use openMP here via the lapack routines
      if( idtask == 0) then
      
        write(6,'(''DAV: Davidson iteration: '', I10)') i
      
        ! needed if we want to vectorix the residue calculation
        ! call check_deallocate_matrix(lambda)
        ! call check_deallocate_matrix(tmp_res_array)
        ! allocate( lambda(size_update, size_update ))
        ! allocate( tmp_res_array(parameters%nparm, size_update ))

        ! reallocate eigenpairs of the small system
        call check_deallocate_vector(eigenvalues_sub)
        call check_deallocate_matrix(eigenvectors_sub)
        allocate( eigenvalues_sub( parameters%basis_size)) 
        allocate( eigenvectors_sub( parameters%basis_size, parameters%basis_size)) 

        ! deallocate the corection/residues
        call check_deallocate_matrix(residues)
        call check_deallocate_matrix(correction)
        allocate( residues( parameters%nparm,size_update))
        allocate( correction( parameters%nparm, size_update ))

        ! deallocate ritz vectors
        call check_deallocate_matrix(ritz_vectors)

        ! update the projected matrices in the small subspace
        if(update_proj) then

          ! update the projected matrices  
          call update_projection(V, mtxV, mtx_proj)
          call update_projection(V, stxV, stx_proj)   

        ! recompute it from scratch when restarting
        else 

          ! Array deallocation/allocation.
          call check_deallocate_matrix(mtx_proj)
          call check_deallocate_matrix(stx_proj)

          ! recompute the projected matrix
          mtx_proj = lapack_matmul('T','N',V,mtxV)
          stx_proj = lapack_matmul('T','N',V,stxV)

        end if

        ! 5. Solve the small eigenvalue problem
        write( 6, '(''DAV: enter lapack_generalized_eigensolver'')') 
        call lapack_generalized_eigensolver( mtx_proj, eigenvalues_sub, eigenvectors_sub, stx_proj)
        write( 6, '(''DAV: exit lapack_generalized_eigensolver'')') 
        write( 6, '(''DAV: eigv'',1000f12.5)')( eigenvalues_sub( j), j= 1,parameters%lowest)

        ! Compute the necessary ritz vectors
        ritz_vectors = lapack_matmul( 'N', 'N', V, eigenvectors_sub(:,:size_update))
      
        ! 7. Residue calculation (vectorized)
        ! lambda= diag_mat(eigenvalues_sub(:size_update))
        ! tmp_res_array = lapack_matmul('N', 'N', lapack_matmul( 'N', 'N', stxV, eigenvectors_sub(:,:size_update), lambda))
        ! residues = lapack_matmul( 'N', 'N', mtxV, eigenvectors_sub) - tmp_res_array 

        ! Residue calculation loop
        do j=1, size_update          
          residues(:, j) = eigenvalues_sub(j) * lapack_matrix_vector('N', stxV, eigenvectors_sub(:, j))
          residues(:, j) = lapack_matrix_vector('N', mtxV, eigenvectors_sub(:, j)) - residues(:, j)
       end do

        ! Check which eigenvalues has converged
        ! not sure if the reshape is necessary, norm2 also exists 
        do j= 1, parameters%lowest
          errors( j) = norm( reshape( residues( :, j), (/ parameters%nparm/)))
          if( errors( j)< tolerance) has_converged( j)= .true.
        end do

      !! ENDIF IDTASK
      !! endif <- we continue on the master
      
      ! Are those needed as well ?!!
      ! I would say no 
      ! if( nproc> 1) then
      !   call MPI_BCAST(has_converged, parameters%lowest, MPI_LOGICAL, 0, MPI_COMM_WORLD, ier)
      !   call MPI_BCAST(residues, parameters%nparm* size_update, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      !   call MPI_BCAST(eigenvalues_sub, parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      !   call MPI_BCAST(eigenvectors_sub, parameters%basis_size* parameters%basis_size, & 
      !                 MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      ! endif       


        ! 8. Check for convergence

        if( all( has_converged)) then
          iters= i
          write( 6, '(''DAV: roots are converged'')') 
          eigenvalues= eigenvalues_sub(:parameters%lowest)
          exit outer_loop
        end if

        ! 9. Calculate correction vectors.  

        ! if(( parameters%basis_size<= nvecx) .and.( 2*parameters%basis_size< nparm)) then
        ! I'm not sure I get the reason behind the second condition.
        ! I hope that our basis size nevers goes as large as half the matrix dimension !
        if(( parameters%basis_size + size_update <= nvecx) .and.( 2*parameters%basis_size< nparm)) then
          
          update_proj = .true.

          ! compute the correction vectors
          select case( method)
          case( "DPR")
            if( idtask== 0)  write( 6,'(''DAV: Diagonal-Preconditioned-Residue (DPR)'')')
            correction= compute_DPR( residues, parameters, eigenvalues_sub,                     &
                                          diag_mtx, diag_stx)
          case( "GJD")
            if( idtask== 0)  write( 6,'(''DAV: Generalized Jacobi-Davidson (GJD)'')')
            correction= compute_GJD_free( parameters, ritz_vectors, residues, eigenvectors_sub,      &
                                          eigenvalues_sub)
          end select

          ! 10. Add the correction vectors to the current basis.
          call concatenate( V, correction)
            
          ! 11. Orthogonalize basis using modified GS
          call modified_gram_schmidt(V, parameters%basis_size+1)
          ! call lapack_qr( V)
   
        else

          update_proj = .false.
          
          ! 12. Otherwise reduce the basis of the subspace to the current correction
          V = ritz_vectors(:, :init_subspace_size)

        end if
      
      !! ENDIF IDTASK
      end if 

      ! broadcast the basis vector
      if (nproc > 1) then
        call MPI_BCAST( V, size( V, 1)* size( V, 2), MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      endif 

      ! Update basis size
      parameters%basis_size = size( V, 2) 

      ! Calculation of HV and SV
      call check_deallocate_matrix(mtxV)
      mtxV = fun_mtx_gemv( parameters, V)

      call check_deallocate_matrix(stxV)
      stxV = fun_stx_gemv( parameters, V)
  
      ! there again they all have it so should we broadcast ??!!
      ! if (nproc> 1) then
      !   call MPI_BCAST( mtxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      !   call MPI_BCAST( stxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      ! endif


    end do outer_loop

    !  13. print convergence
    if ( idtask== 0) then
      if( i > max_iters) then
       iters= i  
         do j=1, parameters%lowest
          if( has_converged( j) .eqv. .false.) &
            write(6,'(''DAV: Davidson eingenpair: '', I10, '' not converged'')') j 
         enddo
       write( 6, *), "DAV Warninng: Algorithm did not converge!!"
       end if
    end if

    ! Select the lowest eigenvalues and their corresponding ritz_vectors
    ! They are sort in increasing order
    ! where are stored the eigenvectors !
    if( nproc > 1) then
      

      if (idtask > 0) then 
        allocate(ritz_vectors(parameters%nparm, size_update))     
        allocate(eigenvalues_sub(parameters%basis_size))
      end if  

      call MPI_BCAST(eigenvalues_sub, parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      call MPI_BCAST(ritz_vectors, parameters%nparm * size_update, & 
                    MPI_REAL8, 0, MPI_COMM_WORLD, ier) 
    endif   
    eigenvalues = eigenvalues_sub( :parameters%lowest)
    eigenvectors = ritz_vectors(:,:parameters%lowest)

    ! Free memory
    deallocate( eigenvalues_sub, ritz_vectors)
    deallocate( V, mtxV, stxV)

    if (idtask == 0) then  
      call check_deallocate_matrix( correction)
      deallocate( eigenvectors_sub)
      deallocate( diag_mtx, diag_stx)
      deallocate( residues )
      ! deallocate( lambda, tmp_array)
       deallocate( mtx_proj)
       call check_deallocate_matrix( stx_proj)
    endif 
    
    
  end subroutine generalized_eigensolver
!  
  subroutine update_projection(V, mtxV, mtx_proj)
    !> update the projected matrices
    !> \param mtxV: full matrix x projector
    !> \param V: projector
    !> \param mtx_proj: projected matrix
 
    implicit none
    real(dp), dimension(:, :), intent(in) :: mtxV
    real(dp), dimension(:, :), intent(in) :: V
    real(dp), dimension(:, :), intent(inout), allocatable :: mtx_proj
    real(dp), dimension(:, :), allocatable :: tmp_array
 
    ! local variables
    integer :: nvec, old_dim
 
    ! dimension of the matrices
    nvec = size(mtxV,2)
    old_dim = size(mtx_proj,1)    
 
    ! move to temporal array
    allocate(tmp_array(nvec, nvec))
    tmp_array(:old_dim, :old_dim) = mtx_proj
    tmp_array(:,old_dim+1:) = lapack_matmul('T', 'N', V, mtxV(:, old_dim+1:))
    tmp_array( old_dim+1:,:old_dim ) = transpose(tmp_array(:old_dim, old_dim+1:))
 
    ! Move to new expanded matrix
    deallocate(mtx_proj)
    call move_alloc(tmp_array, mtx_proj)

  end subroutine update_projection

  subroutine die(msg)
  !> Subroutine that dies the calculation raising an errror message
  !
  character msg*(*)
  integer ierr
  include 'mpif.h'

  write(6,'(''Fatal error: '',a)') msg
  call mpi_abort(MPI_COMM_WORLD,0,ierr)

  end subroutine

  function compute_DPR(residues, parameters, eigenvalues, diag_mtx, diag_stx) &
                            result(correction)

    !> compute the correction vector using the DPR method for a matrix free diagonalization
    !> See correction_methods submodule for the implementations
    !> \param[in] fun_mtx: function to compute matrix
    !> \param[in] fun_stx: function to compute the matrix for the generalized case
    !> \param[in] V: Basis of the iteration subspace
    !> \param[in] eigenvalues: of the reduce problem
    !> \param[in] eigenvectors: of the reduce problem
    !> \return correction matrix
    !
    use array_utils, only: eye
    !
    real(dp), dimension(:, :), intent(in) :: residues
    real(dp), dimension(:), intent(in) :: eigenvalues  
    real(dp), dimension(:), intent(in) :: diag_mtx, diag_stx

    ! local variables
    type(davidson_parameters) :: parameters

    ! that's :
    !   1 - never used   
    !   2 - the size of the matrix we **don't want to store**
    ! real(dp), dimension(parameters%nparm, parameters%nparm) :: diag

    real(dp), dimension(parameters%nparm, size(residues,2)) :: correction
    integer :: ii, j
    integer :: m
    
    ! calculate the correction vectors
    m= parameters%nparm


    do j = 1, size(residues, 2) 

     correction( :, j)= residues( :, j) 

     do ii= 1, size( correction, 1)
       correction( ii, j)= correction( ii, j)/( eigenvalues( j)* diag_stx( ii)- diag_mtx( ii))
     end do

    end do

  end function compute_DPR

  function compute_GJD_free( parameters, ritz_vectors, residues, eigenvectors, & 
             eigenvalues) result( correction)

    !> Compute the correction vector using the GJD method for a matrix free
    !> diagonalization. We follow the notation of:
    !> I. Sabzevari, A. Mahajan and S. Sharma,  arXiv:1908.04423 (2019)
    !>
    !> \param[in] ritz_vectors: ritz_vectors.
    !> \param[in] residues: residue vectors.
    !> \param[in] parameter: davidson_parameters type.
    !> \param[in] eigenvectors. 
    !> \param[in] eigenvalues. 
    !> \return correction matrix

    use array_utils, only: eye

    type( davidson_parameters)               :: parameters
    real( dp), dimension( :, :), intent( in) :: ritz_vectors
    real( dp), dimension( :, :), intent( in) :: residues
    real( dp), dimension( :, :), intent( in) :: eigenvectors
    real( dp), dimension( :),    intent( in) :: eigenvalues 
    !
    ! local variables
    !
    real( dp), dimension( parameters%nparm, parameters%basis_size) :: correction
    integer :: k, m
    logical :: gev
    real( dp), dimension( :, :), allocatable   ::  F
    real( dp), dimension( parameters%nparm, 1) :: brr

    do k= 1, parameters%basis_size 

      F= fun_F_matrix( ritz_vectors, parameters, k, eigenvalues( k))  
      call write_matrix( "F.txt", F) 
      brr( :, 1) = -residues(:,k)
     call lapack_solver( F, brr)
      call write_matrix( "brr.txt", brr) 
      correction( :, k)= brr( :, 1)

    end do

     ! Deallocate
     deallocate( F)

  end function compute_GJD_free

  function fun_F_matrix( ritz_vectors, parameters, eigen_index, eigenvalue) &
           result( F_matrix)
    !> \brief Function that computes the F matrix: 
    !> F= ubut*( A- theta* B)* uubt
    !> in a pseudo-free way for a given engenvalue. 
    !> 
    !> ritz_vectors( in) :: ritz_vectors.  
    !> parameters( in)   :: array_sizes  
    !> eigen_index( in)  :: index of the passing eingenvalue.
    !> eigenvalue( in)   :: eigen_index eigenvalue.  

    use array_utils, only: eye

    real( dp), dimension( :, :), intent( in) :: ritz_vectors 
    type( davidson_parameters) :: parameters
    integer   :: eigen_index 
    real( dp) :: eigenvalue 

    interface

     function fun_mtx_gemv( parameters, input_vect) result( output_vect)
       !> \brief Function to compute the action of the hamiltonian on the fly
       !> \param[in] dimension of the arrays to compute the action of the
       !             hamiltonian
       !> \param[in] input_vec Array to project
       !> \return Projected matrix
       use numeric_kinds, only: dp
       import                                   :: davidson_parameters
       type( davidson_parameters)               :: parameters
       real( dp), dimension( :, :), intent( in) :: input_vect
       real( dp), dimension( size( input_vect, 1), size( input_vect, 2)) :: output_vect
     end function fun_mtx_gemv

     function fun_stx_gemv( parameters, input_vect) result( output_vect)
       !> \brief Fucntion to compute the optional stx matrix on the fly
       !> \param[in] dimension of the arrays to compute the action of the
       !             hamiltonian
       !> \param[in] input_vec Array to project
       !> \return Projected matrix
       use numeric_kinds, only: dp
       import                                   :: davidson_parameters
       type( davidson_parameters)               :: parameters
       real( dp), dimension( :, :), intent( in) :: input_vect
       real( dp), dimension( size( input_vect, 1), size( input_vect, 2)) :: output_vect
     end function fun_stx_gemv

    end interface
 
    real( dp), dimension( parameters%nparm, parameters%nparm) :: F_matrix, lambda
    real( dp), dimension( parameters%nparm, 1) :: ritz_tmp
    real( dp), dimension( :, :), allocatable :: ys 
    real( dp), dimension( parameters%nparm, parameters%nparm) :: ubut, uubt

    ritz_tmp( :, 1)= ritz_vectors( :, eigen_index)

    lambda= eye( parameters%nparm, parameters%nparm, eigenvalue)

    ubut= eye( parameters%nparm, parameters%nparm)- &
          lapack_matmul( 'N', 'T', fun_stx_gemv( parameters, ritz_tmp), ritz_tmp)

    uubt= eye( parameters%nparm, parameters%nparm)- &
          lapack_matmul( 'N', 'T', ritz_tmp, fun_stx_gemv( parameters, ritz_tmp)) 

    ys = lapack_matmul( 'N', 'N', lambda, fun_stx_gemv( parameters, uubt)) 

    F_matrix= lapack_matmul( 'N', 'N', ubut, fun_mtx_gemv( parameters, uubt)) - &
              lapack_matmul( 'N', 'N', ubut, ys) 

  end function fun_F_matrix

end module davidson
