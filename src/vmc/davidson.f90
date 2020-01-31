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
!> \param[in, opt] max_dim_sub: maximum dimension of the subspace search.   
!> \param[out] iters: Number of iterations until convergence.
!> \return eigenvalues and ritz_vectors of the matrix `mtx`.
module davidson
  use numeric_kinds, only: dp
  use lapack_wrapper, only: lapack_generalized_eigensolver, lapack_matmul, lapack_matrix_vector, &
       lapack_qr, lapack_solver
  use array_utils, only: concatenate, generate_preconditioner, norm, write_matrix, write_vector, & 
                        eye, check_deallocate_matrices, check_deallocate_matrix
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

  subroutine generalized_eigensolver (fun_mtx_gemv, eigenvalues, ritz_vectors, nparm, nparm_max, &
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
    !> \param[inout] ritz_vectors approximation to the eigenvectors
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
    !> \param[in, opt] max_dim_sub: maximum dimension of the subspace search   
    !> \param[out] iters: Number of iterations until convergence
    !> \return eigenvalues and ritz_vectors of the matrix `mtx`

    implicit none

    include 'mpif.h'

    ! input/output variable
    integer, intent(in) :: nparm, nparm_max, nvecx, lowest, nproc, idtask
    real(dp), dimension(lowest), intent(out) :: eigenvalues
    real(dp), dimension(:, :), allocatable, intent(out) :: ritz_vectors
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
    integer :: dim_sub, max_size_basis, i, j, ier

    ! Basis of subspace of approximants
    real(dp), dimension(:), allocatable :: diag_mtx, diag_stx
    real(dp), dimension(:,:), allocatable :: guess, rs 
    real(dp), dimension(lowest):: errors
    
    ! Working arrays
    real( dp), dimension(:), allocatable :: eigenvalues_sub
    real( dp), dimension(:,:), allocatable :: lambda       ! eigenvalues_sub in a diagonal matrix 
    real( dp), dimension(:, :), allocatable :: correction, eigenvectors_sub, mtx_proj, stx_proj, V
    real( dp), dimension(:, :), allocatable :: mtxV, stxV 
    real( dp), dimension(nparm, 1) :: xs, gs

    ! Arrays dimension
    type(davidson_parameters) :: parameters

    ! Indices of the eigenvalues/eigenvectors pair that have not converged
    logical, dimension( lowest) :: has_converged
    integer :: n_converged ! Number of converged eigenvalue/eigenvector pairs
    
    ! Iteration subpsace dimension
    dim_sub = lowest  * 2

    ! Lapack qr safety check 
    if (nvecx > nparm) then 
      if( idtask == 1) call die('DAV: nvecx > nparm, increase nparm or decrese lin_nvecx')
    endif

    ! Dimension of the matrix
    parameters = davidson_parameters(nparm, nparm_max, lowest, nvecx, dim_sub) 

    ! 1. Variables initialization
    ! extract the diagonals of the matrices

    write(6,'(''DAV: Compute diagonals of S and H'')')

    ! Initial number of converged eigenvalue/eigenvector pairs
    n_converged = 0
    has_converged = .false.

    ! Diagonal of the arrays
    allocate(diag_mtx(parameters%nparm))
    allocate(diag_stx(parameters%nparm))

    if (idtask==0) call store_daig_hs(parameters%nparm, diag_mtx, diag_stx)

    if (nproc > 1) then  
       call MPI_BCAST( diag_mtx, parameters%nparm, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
       call MPI_BCAST( diag_stx, parameters%nparm, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
    endif 
!    if (idtask==0) call write_vector( 'diag_0.txt', diag_mtx)
 
    ! 2.  Select the initial ortogonal subspace based on lowest elements
    !     of the diagonal of the matrix

    V= generate_preconditioner( diag_mtx( 1: dim_sub), dim_sub, nparm) ! Initial orthonormal basis
    
    if( idtask== 0) write(6,'(''DAV: Setup subspace problem'')')

    ! 3. Outer loop block Davidson schema

    outer_loop: do i= 1, max_iters

      if( idtask== 0) write(6,'(''DAV: Davidson iteration: '', I10)') i

      ! Array deallocation/allocation
      call check_deallocate_matrices(mtx_proj, stx_proj, lambda, eigenvectors_sub, ritz_vectors, mtxV, stxV)
      call check_deallocate_matrix( guess)
      call check_deallocate_matrix( rs)
      if( allocated( eigenvalues_sub)) then
          deallocate( eigenvalues_sub)
      end if
      allocate( mtxV( parameters%nparm, parameters%basis_size), stxV(parameters%nparm, parameters%basis_size)) 
      allocate( guess( parameters%nparm, parameters%basis_size), rs( parameters%nparm,parameters%basis_size))
      allocate( eigenvalues_sub( parameters%basis_size)) 
      allocate( lambda( parameters%basis_size, parameters%basis_size)) 
      allocate( eigenvectors_sub( parameters%basis_size, parameters%basis_size)) 

      ! 4. Projection of H and S matrices

      mtxV= fun_mtx_gemv( parameters, V)
      stxV= fun_stx_gemv( parameters, V)

      if (nproc> 1) then
        call MPI_BCAST( mtxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
        call MPI_BCAST( stxV, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      endif

      mtx_proj= lapack_matmul( 'T', 'N', V, mtxV)
      stx_proj= lapack_matmul( 'T', 'N', V, stxV)

      !! IF IDTASK=0
      if( idtask.eq. 0) then

        ! 5.Compute the eigenvalues and their corresponding ritz_vectors
        ! for the projected matrix using lapack
        
        write( 6, '(''DAV: enter lapack_generalized_eigensolver'')') 
        call lapack_generalized_eigensolver( mtx_proj, eigenvalues_sub, eigenvectors_sub, stx_proj)
        write( 6, '(''DAV: exit lapack_generalized_eigensolver'')') 
        write( 6, '(''DAV: eigv'',1000f12.5)')( eigenvalues_sub( j), j= 1,parameters%lowest)
    
        ! 6. Construction of lambda matrix (a squared one with eigenvalues_sub in the diagonal)

        lambda= eye( parameters%basis_size, parameters%basis_size) 
        do j= 1, parameters%basis_size 
          lambda( j, j)= eigenvalues_sub( j)
        enddo
 
        ! 7. Residue calculation  

        rs= lapack_matmul( 'N', 'N', stxV, eigenvectors_sub)
        guess= lapack_matmul('N', 'N', rs, lambda)  
        deallocate( rs)
        rs= lapack_matmul( 'N', 'N', mtxV, eigenvectors_sub) - guess 

        ! Check which eigenvalues has converged
        do j= 1, parameters%lowest

          errors( j) = norm( reshape( rs( :, j), (/ parameters%nparm/)))
          if( errors( j)< tolerance) has_converged( j)= .true.

        end do

      !! ENDIF IDTASK
      endif

      if( nproc> 1) then
        call MPI_BCAST(has_converged, parameters%lowest, MPI_LOGICAL, 0, MPI_COMM_WORLD, ier)
        call MPI_BCAST(rs, parameters%nparm* parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
        call MPI_BCAST(eigenvalues_sub, parameters%basis_size, MPI_REAL8, 0, MPI_COMM_WORLD, ier)
        call MPI_BCAST(eigenvectors_sub, parameters%basis_size* parameters%basis_size, & 
                      MPI_REAL8, 0, MPI_COMM_WORLD, ier)
      endif       

      ritz_vectors= lapack_matmul( 'N', 'N', V, eigenvectors_sub)

      ! 8. Check for convergence

      if( all( has_converged)) then
        iters= i
        write( 6, '(''DAV: roots are converged'')') 
        eigenvalues= eigenvalues_sub(:parameters%lowest)
        exit outer_loop
      end if

      ! 9. Calculate correction vectors.  

      if(( parameters%basis_size<= nvecx).and.( 2*parameters%basis_size< nparm)) then

        ! append correction to the current basis
        call check_deallocate_matrix( correction)
        allocate( correction( size( ritz_vectors, 1), size( V, 2)))

        select case( method)
        case( "DPR")
          if( idtask== 0)  write( 6,'(''DAV: Diagonal-Preconditioned-Residue (DPR)'')')
          correction= compute_DPR_free( rs, parameters, eigenvalues_sub,                     &
                                        diag_mtx, diag_stx)
        case( "GJD")
          if( idtask== 0)  write( 6,'(''DAV: Generalized Jacobi-Davidson (GJD)'')')
          correction= compute_GJD_free( parameters, ritz_vectors, rs, eigenvectors_sub,      &
                                        eigenvalues_sub)
        end select

        ! 10. Add the correction vectors to the current basis.

        call concatenate( V, correction)
           
        ! IF IDTASK=0
        if( idtask .eq. 0) then

          ! 11. Orthogonalize basis

          call lapack_qr( V)

        ! ENDIF IDTASK
        endif

        if (nproc > 1) then
          call MPI_BCAST( V, size( V, 1)* size( V, 2), MPI_REAL8, 0, MPI_COMM_WORLD, ier)
        endif 

      else

        ! 12. Otherwise reduce the basis of the subspace to the current correction
        V = lapack_matmul('N', 'N', V, eigenvectors_sub(:, :dim_sub))

      end if
    
    ! Update basis size
      parameters%basis_size = size( V, 2) 

    end do outer_loop

    !  13. Check convergence
    if( i> max_iters) then
       iters= i
       if ( idtask== 0) then 
         do j=1, parameters%lowest
          if( has_converged( j) .eqv. .false.) &
            write(6,'(''DAV: Davidson eingenpair: '', I10, '' not converged'')') j 
         enddo
       write( 6, *), "DAV Warninng: Algorithm did not converge!!"
       end if
    end if

    ! Select the lowest eigenvalues and their corresponding ritz_vectors
    ! They are sort in increasing order
    eigenvalues= eigenvalues_sub( :parameters%lowest)
    
    ! Free memory
    call check_deallocate_matrix( correction)
    deallocate( eigenvalues_sub, eigenvectors_sub, mtx_proj, diag_mtx, diag_stx)
    deallocate( V, mtxV, stxV, guess, rs, lambda)
    
    ! free optional matrix
    call check_deallocate_matrix( stx_proj)
    
  end subroutine generalized_eigensolver
!  
  subroutine die(msg)
  !> Subroutine that dies the calculation raising an errror message
  !
  character msg*(*)
  integer ierr
  include 'mpif.h'

  write(6,'(''Fatal error: '',a)') msg
  call mpi_abort(MPI_COMM_WORLD,0,ierr)

  end subroutine

  function compute_DPR_free(rs, parameters, eigenvalues, diag_mtx, diag_stx) &
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
    real(dp), dimension(:, :), intent(in) :: rs
    real(dp), dimension(:), intent(in) :: eigenvalues  
    real(dp), dimension(:), intent(in) :: diag_mtx, diag_stx

    ! local variables
    type(davidson_parameters) :: parameters
    real(dp), dimension(parameters%nparm,parameters%nparm) :: diag
    real(dp), dimension(parameters%nparm, parameters%basis_size) :: correction
    integer :: ii, j
    integer :: m
    
    ! calculate the correction vectors
    m= parameters%nparm

    ! computed the projected matrices
    diag = 0.0_dp

    do j = 1, parameters%basis_size 
     diag= eye( m , m, eigenvalues( j))
     correction( :, j)= rs( :, j) 

     do ii= 1, size( correction, 1)
       correction( ii, j)= correction( ii, j)/( eigenvalues( j)* diag_stx( ii)- diag_mtx( ii))
     end do

    end do

  end function compute_DPR_free

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
