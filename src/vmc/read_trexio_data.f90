module trexio_read_data
    use error,                  only: fatal_error
    use precision_kinds,        only: dp
    use array_utils,            only: unique_elements

    logical :: trexio_has_molecule      = .false.
    logical :: trexio_has_symmetry      = .false.
    logical :: trexio_has_orbitals      = .false.
    logical :: trexio_has_basis         = .false.
    logical :: trexio_has_determinant   = .false.
    logical :: trexio_has_ecp           = .false.

    private
    public :: dp

    public :: trexio_has_molecule
    public :: trexio_has_symmetry
    public :: trexio_has_orbitals
    public :: trexio_has_basis
    public :: trexio_has_determinant
    public :: trexio_has_ecp

    public :: read_trexio_molecule_file
    public :: read_trexio_symmetry_file
    public :: read_trexio_orbitals_file
    public :: read_trexio_basis_file
    public :: read_trexio_determinant_file
    public :: read_trexio_ecp_file
    contains

    subroutine read_trexio_molecule_file(file_trexio)
        !> This subroutine reads the .hdf5 trexio generated file/folder. It then computes the
        !! number of types of atoms, nuclear charges (from the symbol), and
        !! number of valence electrons if pseudopotential is provided.
        !! @author Ravindra Shinde (r.l.shinde@utwente.nl)
        !! @date 07 October 2021
        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid
        use atom,               only: znuc, cent, pecent, iwctype, nctype, ncent, ncent_tot, nctype_tot, symbol, atomtyp
        use ghostatom, 		    only: newghostype, nghostcent
        use inputflags,         only: igeometry
        use periodic_table,     only: atom_t, element
        use elec,           	only: ndn, nup
        use const,          	only: nelec
        use contrl_file,        only: ounit, errunit
        use general,            only: pooldir
        use precision_kinds, only: dp
#if defined(TREXIO_FOUND)
        use trexio
        use contrl_file,        only: backend
#endif

        implicit none

        !   local use
        character(len=*), intent(in)   :: file_trexio
        character(len=40)               :: temp1, temp2, temp3, temp4
        character(len=80)               :: comment, file_trexio_path
        integer                         :: iostat, i, j, k, iunit
        logical                         :: exist
        type(atom_t)                    :: atoms
        character(len=2), allocatable   :: unique(:)

        ! trexio
        integer(8)                      :: trex_molecule_file
        integer                         :: rc = 1

        !   Formatting
        character(len=100)              :: int_format     = '(A, T60, I0)'
        character(len=100)              :: float_format   = '(A, T60, f12.8)'
        character(len=100)              :: string_format  = '(A, T60, A)'

        trex_molecule_file = 0

        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Reading molecular coordinates from the trexio file :: ",  file_trexio_path
        write(ounit,*) '-----------------------------------------------------------------------'

        ! Check if the file exists
        if (wid) then
#if defined(TREXIO_FOUND)
            trex_molecule_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_assert(rc, TREXIO_SUCCESS)
            rc = trexio_read_nucleus_num(trex_molecule_file, ncent)
            if (trexio_has_nucleus_num(trex_molecule_file) == 0) trexio_has_molecule = .true.
            call trexio_assert(rc, TREXIO_SUCCESS)
            rc = trexio_read_electron_up_num(trex_molecule_file, nup)
            call trexio_assert(rc, TREXIO_SUCCESS)
            rc = trexio_read_electron_dn_num(trex_molecule_file, ndn)
            call trexio_assert(rc, TREXIO_SUCCESS)
#endif
        endif
        call bcast(trexio_has_molecule)
        call bcast(ncent)
        call bcast(nup)
        call bcast(ndn)

        nelec = nup + ndn

        ! Do the allocations based on the ncent
        if (.not. allocated(cent))    allocate(cent(3,ncent))
        if (.not. allocated(symbol))  allocate(symbol(ncent))
        if (.not. allocated(iwctype)) allocate(iwctype(ncent))
        if (.not. allocated(unique))  allocate(unique(ncent))

        if (wid) then
#if defined(TREXIO_FOUND)
        rc = trexio_read_nucleus_coord(trex_molecule_file, cent)
        call trexio_assert(rc, TREXIO_SUCCESS)
        rc = trexio_read_nucleus_label(trex_molecule_file, symbol, 3)
        call trexio_assert(rc, TREXIO_SUCCESS)
        rc = trexio_close(trex_molecule_file)
        call trexio_assert(rc, TREXIO_SUCCESS)
#endif
        endif
        call bcast(cent)
        call bcast(symbol)


        write(ounit,fmt=int_format) " Number of atoms ::  ", ncent
        write(ounit,*)

        ! Count unique type of elements
        nctype = 1
        unique(1) = symbol(1)
        do j= 2, ncent
            if (any(unique == symbol(j) ))  cycle
            nctype = nctype + 1
            unique(nctype) = symbol(j)
        enddo

        write(ounit,fmt=int_format) " Number of distinct types of elements (nctype) :: ", nctype
        write(ounit,*)

        if (.not. allocated(atomtyp)) allocate(atomtyp(nctype))
        if (.not. allocated(znuc)) allocate(znuc(nctype))

        ! get the correspondence for each atom according to the rule defined for atomtypes
        do j = 1, ncent
            do k = 1, nctype
                if (symbol(j) == unique(k))   iwctype(j) = k
            enddo
        enddo

        ! Get the correspondence rule
        do k = 1, nctype
            atomtyp(k) = unique(k)
        enddo

        if (allocated(unique)) deallocate(unique)

        ! Get the znuc for each unique atom
        do j = 1, nctype
            atoms = element(atomtyp(j))
            znuc(j) = atoms%nvalence
        enddo

        ncent_tot = ncent + nghostcent
        nctype_tot = nctype + newghostype

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,'(a, t15, a, t27, a, t39, a, t45, a)') 'Symbol', 'x', 'y', 'z', 'Type'
        write(ounit,'(t14, a, t26, a, t38, a )') '(bohr)', '(bohr)', '(bohr)'
        write(ounit,*) '-----------------------------------------------------------------------'

        do j= 1, ncent
            write(ounit,'(A4, 2x, 3F12.8, 2x, i3)') symbol(j), (cent(i,j),i=1,3), iwctype(j)
        enddo

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Values of znuc (number of valence electrons) "
        write(ounit,'(10F12.6)') (znuc(j), j = 1, nctype)
        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*)
    end subroutine read_trexio_molecule_file


    subroutine read_trexio_orbitals_file(file_trexio)
        !> This subroutine reads the .hdf5 trexio generated file/folder. It then reads the
        !! number of molecular and atomic orbitals and their corresponding coefficients.
        !! @author Ravindra Shinde (r.l.shinde@utwente.nl)
        !! @date 12 October 2021
        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid
        use contrl_file,        only: ounit, errunit
        use atom,               only: ncent, ncent_tot
        use coefs,              only: coef, nbasis, norb
        use inputflags,         only: ilcao
        use numbas,             only: nrbas
        use orbval,             only: nadorb
        use pcm_fdc,            only: fs
        use vmc_mod,            only: norb_tot
        use wfsec,              only: nwftype
        use general,            only: pooldir
        use method_opt,         only: method
        use precision_kinds, only: dp
#if defined(TREXIO_FOUND)
        use trexio
        use error,              only: trexio_error
        use contrl_file,        only: backend
        use m_trexio_basis,     only: slm_per_l, index_slm, num_rad_per_cent, num_ao_per_cent
#endif
        implicit none

    !   local use
        character(len=72), intent(in)   :: file_trexio
        character(len=40)               :: temp1, temp2
        character(len=120)              :: temp3, file_trexio_path
        integer                         :: iunit, iostat, iwft
        integer                         :: iorb, ibasis, i, j, k, l
        integer                         :: counter, count1, count2, count3, summ
        integer                         :: index_ao, index_nrad
        integer                         :: cum_rad_per_cent, cum_ao_per_cent
        logical                         :: exist
        logical                         :: skip = .true.

!       trexio
        integer                         :: basis_num_shell
        integer, allocatable            :: basis_nucleus_index(:)
        integer, allocatable            :: basis_shell_ang_mom(:)


        !   Formatting
        character(len=100)               :: int_format     = '(A, T60, I0)'
        character(len=100)               :: string_format  = '(A, T60, A)'
        character(len=100)               :: float_format   = '(A, T60, f12.8)'

        ! trexio
        integer(8)                      :: trex_orbitals_file
        integer                         :: rc = 1, ii, jj

        iwft = 1
        trex_orbitals_file = 0
        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif

        write(ounit,*) '---------------------------------------------------------------------------'
        write(ounit,*) " Reading LCAO orbitals from the file :: ",  trim(file_trexio_path)
        write(ounit,*) '---------------------------------------------------------------------------'
        ! Check if the file exists

        if (wid) then
#if defined(TREXIO_FOUND)
            trex_orbitals_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio file open error', __FILE__, __LINE__)
            rc = trexio_read_mo_num(trex_orbitals_file, norb)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_mo_num', __FILE__, __LINE__)
            rc = trexio_read_ao_num(trex_orbitals_file, nbasis)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ao_num', __FILE__, __LINE__)
            rc = trexio_read_basis_shell_num(trex_orbitals_file, basis_num_shell)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_num', __FILE__, __LINE__)
#endif
        endif
        call bcast(norb)
        call bcast(nbasis)
        call bcast(basis_num_shell)

        ! Do the array allocations
        if( (method(1:3) == 'lin')) then
            if (.not. allocated(coef)) allocate (coef(nbasis, norb, 3))
        else
            if (.not. allocated(coef)) allocate (coef(nbasis, norb, nwftype))
        endif

        ! Do the allocations based on the number of shells and primitives
        if (.not. allocated(basis_nucleus_index))    allocate(basis_nucleus_index(basis_num_shell))
        if (.not. allocated(basis_shell_ang_mom))    allocate(basis_shell_ang_mom(basis_num_shell))
        if (.not. allocated(index_slm))              allocate(index_slm(nbasis))
        if (.not. allocated(num_rad_per_cent))       allocate(num_rad_per_cent(ncent_tot))
        if (.not. allocated(num_ao_per_cent))        allocate(num_ao_per_cent(ncent_tot))

        ! Read the orbitals
        if (wid) then
#if defined(TREXIO_FOUND)
            if (trexio_has_mo_coefficient(trex_orbitals_file) == 0) trexio_has_orbitals = .true.
            rc = trexio_read_mo_coefficient(trex_orbitals_file, coef(:,:,1))
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_mo_coeffs', __FILE__, __LINE__)
#endif
        endif
        call bcast(trexio_has_orbitals)
        call bcast(coef)

!   Generate the basis information (which radial to be read for which Slm)

#if defined(TREXIO_FOUND)
        rc = trexio_read_basis_shell_ang_mom(trex_orbitals_file, basis_shell_ang_mom)
        call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_ang_mom', __FILE__, __LINE__)
        rc = trexio_read_basis_nucleus_index(trex_orbitals_file, basis_nucleus_index)
        call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_nucleus_index', __FILE__, __LINE__)
#endif

        ! Generate the index of the slm for each AO
        ! i.e. index_slm(i) = the slm index of the i-th AO
        ! The list follows the following order:

        !   l   |   1  2  3  4    5   6   7   8   9   10
        ! ------+-----------------------------------------
        !   y   |   s  x  y  z    xx  xy  xz  yy  yz  zz

        !           11  12  13  14  15  16  17  18  19  20
        !       ------------------------------------------
        !           xxx xxy xxz xyy xyz xzz yyy yyz yzz zzz
        !
        !          21   22   23   24   25   26   27   28   29   30   31   32   33   34   35
        !       +-----------------------------------------------------------------------------
        !          xxxx xxxy xxxz xxyy xxyz xxzz xyyy xyyz xyzz xzzz yyyy yyyz yyzz yzzz zzzz

        counter = 0; count1 = 1; count2 = 0;
        cum_rad_per_cent = 0
        cum_ao_per_cent  = 0
        index_ao = 0
        ! The following loop will generate the index_slm array which tells
        ! which AO is of which type (from the above list)

        do l = 1, basis_num_shell
            k = basis_shell_ang_mom(l)
            counter = counter + slm_per_l(k+1)
            count2 = 0
            do ii = 1, slm_per_l(k+1)
                index_ao = index_ao + 1
                index_slm(index_ao) = sum(slm_per_l(1:k)) + 1 + count2
                count2 = count2 + 1
                cum_ao_per_cent = cum_ao_per_cent + 1
            end do
            cum_rad_per_cent = cum_rad_per_cent + 1

            ! The following if loop is for counting the number of radial functions
            ! and number of AOs per center
            if (count1 == basis_nucleus_index(l)) then
                num_rad_per_cent(count1) = cum_rad_per_cent
                num_ao_per_cent(count1) = cum_ao_per_cent
            else
                cum_rad_per_cent = 1
                cum_ao_per_cent  = 1
                count1 = count1 + 1
            end if
        enddo ! loop on shells

        do i = 1, nbasis
            print*, i, index_slm(i)
        enddo


#if defined(TREXIO_FOUND)
        if (wid) rc = trexio_close(trex_orbitals_file)
#endif


        write(ounit,*)
        ilcao = ilcao + 1
        write(ounit,*) "----------------------------------------------------------"

    end subroutine read_trexio_orbitals_file


    subroutine read_trexio_basis_file(file_trexio)
        !> This subroutine reads the .hdf5 trexio generated file/folder.
        !! It reads the exponents, coefficients, number of basis functions,
        !! shell angular momentum, and number of shells.
        !! @author Ravindra Shinde (r.l.shinde@utwente.nl)
        !! @date 23 May 2022
        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid
        use periodic_table,     only: atom_t, element
        use contrl_file,        only: ounit, errunit
        use general,            only: pooldir

        ! The following to be used to store the information
        use numbas_mod,         only: MRWF, MRWF_PTS
        use atom,               only: znuc, nctype, nctype_tot, ncent_tot
        use atom,               only: symbol, atomtyp
        use vmc_mod,            only: NCOEF
        use ghostatom,          only: newghostype
        use const,              only: ipr
        use numbas,             only: arg, d2rwf, igrid, nr, nrbas, r0, rwf!, rmax
        use numbas,             only: allocate_numbas
        use coefs,              only: nbasis
        use numexp,             only: ae, ce, ab, allocate_numexp
        use pseudo,             only: nloc
        use general,            only: filename, filenames_bas_num

        ! For processing the stored information
        use atom, 			    only: atomtyp
        use general, 			only: pooldir, bas_id
        use contrl_file,        only: ounit, errunit
        use spline2_mod,        only: spline2
        use fitting_methods,    only: exp_fit

#if defined(TREXIO_FOUND)
        use trexio
        use contrl_file,        only: backend
        use error,              only: trexio_error
#endif
        use m_trexio_basis,     only: gnorm

        implicit none

        !for local use.  To be read from trexio file
        integer                         :: basis_num_shell
        integer                         :: basis_num_prim
        integer, allocatable            :: basis_nucleus_index(:)
        integer, allocatable            :: basis_shell_index(:)
        integer, allocatable            :: basis_shell_ang_mom(:)
        real(dp), allocatable           :: basis_shell_factor(:)
        real(dp), allocatable           :: basis_exponent(:)
        real(dp), allocatable           :: basis_coefficient(:)
        real(dp), allocatable           :: basis_prim_factor(:)

        integer                         :: ao_num
        integer,allocatable             :: ao_shell(:)
        real(dp),allocatable            :: ao_normalization(:)

        ! for local use.
        character(len=72), intent(in)   :: file_trexio
        character(len=128)              :: file_trexio_path
        integer                         :: i, j, k, tcount1, tcount2, tcount3, tcount4
        integer                         :: counter, counter_shell, lower_shell, upper_shell, lower_prim, upper_prim

        ! trexio
        integer(8)                      :: trex_basis_file
        integer                         :: rc = 1

        !   Formatting
        character(len=128)              :: int_format     = '(A, T60, I0)'

        ! Grid related
        integer                         :: gridtype=3
        integer                         :: gridpoints=2000
        real(dp)                        :: gridarg=1.003d0
        real(dp)                        :: gridr0=20.0d0
        real(dp)                        :: gridr0_save = 20.0d0
        real(kind=dp), dimension(2000)  :: rgrid  ! Grid points
        integer, dimension(nctype_tot)  :: icusp
        real(dp)                        :: r, r2

        integer, dimension(:), allocatable :: atom_index(:), shell_index_atom(:), nshells_per_atom(:)
        integer, dimension(:), allocatable :: prim_index_atom(:), nprims_per_atom(:)
        integer, dimension(:), allocatable :: unique_atom_index(:), shell_prim_correspondence(:)
        integer                         :: count
        character(len=2), allocatable   :: unique(:) ! unique symbols of atoms

        ! needed for spline
        real(dp), dimension(MRWF_PTS)       ::  x, work
        real(dp), dimension(ncoef)          ::  y
        real(dp), dimension(ncoef*ncoef)    ::  dmatr
        real(dp), dimension(nbasis)         ::  l
        integer, dimension(ncoef)           :: ipiv
        integer         :: ic, ir, irb, ii, jj, ll, icoef, iff
        integer         :: iwf = 1
        integer         :: info
        real(dp)        :: val, dwf1, wfm, dwfn, dwfm, temp

        ! rmax cutoff
        real(dp)                            :: cutoff_rmax = 1.0d-12

        trex_basis_file = 0

        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Reading Basis Set information from the trexio file :: ", trim(adjustl(file_trexio_path))
        write(ounit,*) '-----------------------------------------------------------------------'

        ! Check if the file exists
        if (wid) then
#if defined(TREXIO_FOUND)
            trex_basis_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio file open error', __FILE__, __LINE__)
            rc = trexio_read_basis_prim_num(trex_basis_file, basis_num_prim)
            if (trexio_has_basis_prim_num(trex_basis_file) == 0) trexio_has_basis = .true.
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_prim_num', __FILE__, __LINE__)
            rc = trexio_read_basis_shell_num(trex_basis_file, basis_num_shell)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_num', __FILE__, __LINE__)
            rc = trexio_read_ao_num(trex_basis_file, ao_num)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ao_num', __FILE__, __LINE__)
#endif
        endif
        call bcast(trexio_has_basis)
        call bcast(basis_num_prim)
        call bcast(basis_num_shell)
        call bcast(ao_num)

        ! Do the allocations based on the number of shells and primitives
        if (.not. allocated(basis_nucleus_index))    allocate(basis_nucleus_index(basis_num_shell))
        if (.not. allocated(basis_shell_index))      allocate(basis_shell_index(basis_num_prim))
        if (.not. allocated(basis_shell_ang_mom))    allocate(basis_shell_ang_mom(basis_num_shell))
        if (.not. allocated(basis_shell_factor))     allocate(basis_shell_factor(basis_num_shell))
        if (.not. allocated(basis_exponent))         allocate(basis_exponent(basis_num_prim))
        if (.not. allocated(basis_coefficient))      allocate(basis_coefficient(basis_num_prim))
        if (.not. allocated(basis_prim_factor))      allocate(basis_prim_factor(basis_num_prim))
        if (.not. allocated(ao_shell))               allocate(ao_shell(ao_num))
        if (.not. allocated(ao_normalization))       allocate(ao_normalization(ao_num))

        if (wid) then
#if defined(TREXIO_FOUND)
            trex_basis_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio file open error', __FILE__, __LINE__)
            rc = trexio_read_basis_nucleus_index(trex_basis_file, basis_nucleus_index)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_nucleus_index', __FILE__, __LINE__)
            rc = trexio_read_basis_shell_index(trex_basis_file, basis_shell_index)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_index', __FILE__, __LINE__)
            rc = trexio_read_basis_shell_ang_mom(trex_basis_file, basis_shell_ang_mom)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_ang_mom', __FILE__, __LINE__)
            rc = trexio_read_basis_shell_factor(trex_basis_file, basis_shell_factor)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_shell_factor', __FILE__, __LINE__)
            rc = trexio_read_basis_exponent(trex_basis_file, basis_exponent)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_exponent', __FILE__, __LINE__)
            rc = trexio_read_basis_coefficient(trex_basis_file, basis_coefficient)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_coefficient', __FILE__, __LINE__)
            rc = trexio_read_basis_prim_factor(trex_basis_file, basis_prim_factor)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_basis_prim_factor', __FILE__, __LINE__)
            rc = trexio_read_ao_shell(trex_basis_file, ao_shell)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ao_shell', __FILE__, __LINE__)
            rc = trexio_read_ao_normalization(trex_basis_file, ao_normalization)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ao_normalization', __FILE__, __LINE__)
#endif
        endif
        call bcast(basis_nucleus_index)
        call bcast(basis_shell_index)
        call bcast(basis_shell_ang_mom)
        call bcast(basis_shell_factor)
        call bcast(basis_exponent)
        call bcast(basis_coefficient)
        call bcast(basis_prim_factor)
        call bcast(ao_shell)
        call bcast(ao_normalization)



        write(ounit,fmt=int_format) " Number of primitives  ::  ", basis_num_prim
        write(ounit,fmt=int_format) " Number of shells      ::  ", basis_num_shell
        write(ounit,fmt=int_format) " Number of AO          ::  ", ao_num
        write(ounit,*)
        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*)

        ! Processing the basis set information to get the numerican grid
        gridr0_save = gridr0


        ! Get the number of shells per atom (information needed to reshuffle AOs)

        allocate(atom_index(basis_num_shell))
        allocate(nshells_per_atom(ncent_tot*10))
        allocate(shell_index_atom(ncent_tot*10))




        call unique_elements(basis_num_shell, basis_nucleus_index, atom_index, count, nshells_per_atom, shell_index_atom)

        ! count                     :: "Number of unique elements"
        ! atom_index(1:count)       :: "Unique elements index (not used here)"
        ! nshells_per_atom(1:count) :: "frequency or count of shells per atom"
        ! shell_index_atom(1:count) :: "index number of the shell for each atom"
        ! The shells per atom can be obtained by accessing the shell_index_atom
        ! for a given atom index by the slice of size frequency.


        ! Now get the number of primitives per atom and their indices
        ! also obtain the number of primitives per shell for all the atoms
        allocate(nprims_per_atom(basis_num_prim))
        allocate(prim_index_atom(basis_num_prim))
        allocate(shell_prim_correspondence(basis_num_shell))

        prim_index_atom(1) = 1
        nprims_per_atom(1) = 0
        tcount4 = 0; tcount2 = 0
        do i = 1, ncent_tot
            tcount3 = 0
            do j = 1, nshells_per_atom(i)   ! frequency
                tcount4 = tcount4 + 1
                tcount3 = tcount3 + 1
                tcount1 = 0
                do k = 1, basis_num_prim
                    if (tcount4 == basis_shell_index(k)) then
                        tcount1 = tcount1 + 1
                        shell_prim_correspondence(tcount4) = tcount1
                    endif
                enddo

                nprims_per_atom(i) = nprims_per_atom(i) + shell_prim_correspondence(tcount4)
            enddo
            if (i .ne. ncent_tot) prim_index_atom(i+1) = prim_index_atom(i) + nprims_per_atom(i)
        enddo

        ! Obtain the number of unique types of atoms stored in the hdf5 file.
        if (.not. allocated(unique)) allocate(unique(nctype_tot))
        if (.not. allocated(unique_atom_index)) allocate(unique_atom_index(nctype_tot))


        tcount1 = 1; tcount2 = 1
        unique_atom_index(1) = 1
        unique(1) = symbol(1)
        do j= 2, ncent_tot
            if (any(unique == symbol(j) ))  then
                cycle
            endif
            tcount1 = tcount1 + 1
            unique_atom_index(tcount1) = j
            unique(tcount1) = symbol(j)
        enddo

        ! start putting in the information in the arrays and variables
        gridtype=3
        gridpoints=2000
        gridarg=1.003d0
        gridr0=20.0d0
        gridr0_save = gridr0

        ! Do the necessary allocation for the numerical basis set
        call allocate_numbas()
        call allocate_numexp()

        if (gridtype .eq. 3) gridr0 = gridr0/(gridarg**(gridpoints-1)-1)

        ! Populate the rgrid array.
        do i = 1, gridpoints
            if (gridtype .eq. 1) then
                rgrid(i) = gridr0 + (i-1)*gridarg
            else if (gridtype .eq. 2) then
                rgrid(i) = gridr0 * gridarg**(i-1)
            else if (gridtype .eq. 3) then
                rgrid(i) = gridr0*gridarg**(i-1) - gridr0
            endif
            x(i) = rgrid(i)
        enddo

        do ic = 1, nctype + newghostype            ! loop over all the unique atoms

            nrbas(ic)   = nshells_per_atom(ic)
            igrid(ic)   = gridtype       ! grid type default is 3
            nr(ic)      = gridpoints     ! number of grid points default is 2000
            arg(ic)     = gridarg        ! grid spacing default is 1.003
            r0(ic)      = gridr0         ! grid origin default is 20.0
            icusp(ic)   = 0              ! default is 0

            write(ounit,*)
            write(ounit,'(A, T60,  A)')     " For Nucleus           ::  ", unique(ic)
            write(ounit,'(A, T60, I0)')     " Number of Shells      ::  ", nrbas(ic)
            write(ounit,'(A, T60, I0)')     " Grid type             ::  ", igrid(ic)
            write(ounit,'(A, T60, I0)')     " Number of Grid Points ::  ", nr(ic)
            write(ounit,'(A, T56, F10.6)')  " Grid spacing          ::  ", arg(ic)
            write(ounit,'(A, T56, F10.6)')  " Grid origin           ::  ", r0(ic)
            write(ounit,'(A, T60, I0)')     " Icusp                 ::  ", icusp(ic)
            write(ounit,*)

            ! DEBUG following loop; Special case when nloc equals zero.
            ! Make sure that the trexio file stores this information.
!            if(nloc.eq.0) then
!                do irb = 1, nrbas(ic)
!                    l(irb) = 0
!                enddo
!            endif



            ! loop over all the primitives for the unique atom
            ! The lower and upper indices of primitive indices
            lower_shell = shell_index_atom(unique_atom_index(ic))
            upper_shell = shell_index_atom(unique_atom_index(ic)) + nshells_per_atom(unique_atom_index(ic)) - 1

            lower_prim = prim_index_atom(unique_atom_index(ic))
            upper_prim = prim_index_atom(unique_atom_index(ic)) + nprims_per_atom(unique_atom_index(ic)) - 1


            ! select the shells corresponding to the unique atoms only
            ! j is the running shell index for the unique atom i
            do i = 1, nr(ic)
                r = rgrid(i)
                r2 = r*r

                counter = lower_prim
                counter_shell = 1
                do j = lower_shell, upper_shell
                    ! loop on primitives in the given shell
                    val = 0.0d0
                    do k = counter, counter + shell_prim_correspondence(j) -1
                        val = val + gnorm(basis_exponent(k), basis_shell_ang_mom(j)) &
                                  * basis_coefficient(k) * dexp(-basis_exponent(k)*r2)
                    enddo
                    counter = counter + shell_prim_correspondence(j)
                    rwf(i,counter_shell,ic,1) = val
                    counter_shell = counter_shell + 1
                enddo

            enddo


!        Get the rmax value for each center. Set the cutoff to 10^-12
!        Scanning from the bottom up to avoid false zeros.
            ! rmax = x(nr(ic))  ! default rmax as the last point
            ! do irb = 1, nrbas(ic)
            !   do ir=nr(ic),1,-1
            !     if (abs(rwf(ir,irb,ic,1)) .lt. cutoff_rmax ) then
            !       rmax(irb, ic) = x(ir)
            !     endif
            !   enddo
            ! enddo

            ! write(ounit,*) "Rmax for center ic ", ic, " are ",  (rmax(irb, ic), irb=1, nrbas(ic))



            do irb=1,nrbas(ic)

                if(nloc.eq.0.and.l(irb).eq.0.and.icusp(ic).eq.1) then

        ! c small radii wf(r)=ce1-znuc*ce1*r+ce3*r**2+ce4*r**3+ce5*r**4
                do ii=1,NCOEF-1
                    dmatr(ii)=1.d0-znuc(ic)*x(ii)
                enddo
                y(1)=rwf(1,irb,ic,iwf)
                ll=NCOEF-1
                do jj=2,NCOEF-1
                    y(jj)=rwf(jj,irb,ic,iwf)
                    do ii=2,NCOEF-1
                    ll=ll+1
                    dmatr(ll)=x(ii)**jj
                    enddo
                enddo

                call dgesv(NCOEF-1,1,dmatr,NCOEF-1,ipiv,y,NCOEF,info)
                ce(1,irb,ic,iwf)=y(1)
                ce(2,irb,ic,iwf)=-znuc(ic)*ce(1,irb,ic,iwf)
                ce(3,irb,ic,iwf)=y(2)
                ce(4,irb,ic,iwf)=y(3)
                ce(5,irb,ic,iwf)=y(4)
                else

        ! c small radii wf(r)=ce1+ce2*r+ce3*r**2+ce4*r**3+ce5*r**4
                ll=0
                do jj=1,NCOEF
                    y(jj)=rwf(jj,irb,ic,iwf)
                    do ii=1,NCOEF
                    ll=ll+1
                    dmatr(ll)=x(ii)**(jj-1)
                    enddo
                enddo
                call dgesv(NCOEF,1,dmatr,NCOEF,ipiv,y,NCOEF,info)

                do icoef=1,NCOEF
                    ce(icoef,irb,ic,iwf)=y(icoef)
                enddo
                endif



        ! c       if(ipr.gt.1) then
                write(45,'(''basis = '',i4)') irb
                write(45,'(''check the small radius expansion'')')
                write(45,'(''coefficients'',1p10e22.10)') &
                            (ce(iff,irb,ic,iwf),iff=1,NCOEF)
                write(45,'(''check the small radius expansion'')')
                write(45,'(''irad, rad, extrapolated value, correct value'')')
                do ir=1,10
                    val=ce(1,irb,ic,iwf)
                    do icoef=2,NCOEF
                    val=val+ce(icoef,irb,ic,iwf)*x(ir)**(icoef-1)
                    enddo
                    write(45,'(i2,1p3e22.14)')ir,x(ir),val,rwf(ir,irb,ic,iwf)
                enddo
        ! c       endif

                dwf1=0.d0
                do icoef=2,NCOEF
                dwf1=dwf1+(icoef-1)*ce(icoef,irb,ic,iwf)*x(1)**(icoef-2)
                enddo

        ! c large radii wf(r)=a0*exp(-ak*r)
        ! c       xm=0.5d0*(x(nr(ic))+x(nr(ic)-1))
                wfm=0.5d0*(rwf(nr(ic),irb,ic,iwf)+rwf(nr(ic)-1,irb,ic,iwf))
                dwfm=(rwf(nr(ic),irb,ic,iwf)-rwf(nr(ic)-1,irb,ic,iwf))/  &
                (x(nr(ic))-x(nr(ic)-1))
                if(dabs(wfm).gt.1.d-99) then
                ae(2,irb,ic,iwf)=-dwfm/wfm
                ae(1,irb,ic,iwf)=rwf(nr(ic),irb,ic,iwf)*    &
                                dexp(ae(2,irb,ic,iwf)*x(nr(ic)))
                dwfn=-ae(2,irb,ic,iwf)*rwf(nr(ic),irb,ic,iwf)
                else
                ae(1,irb,ic,iwf)=0.d0
                ae(2,irb,ic,iwf)=0.d0
                dwfn=0.d0
                endif

        ! Nonzero basis at the boundary : Ravindra Shinde
                if(rwf(nr(ic),irb,ic,iwf).gt.1.d-12) then
                    call exp_fit(x(nr(ic)-9:nr(ic)),rwf(nr(ic)-9:nr(ic),irb,ic,iwf), 10, ab(1,irb,ic,iwf), ab(2,irb,ic,iwf))
                    write(45, *) 'DEBUG :: exp_fit: ', ab(1,irb,ic,iwf), ab(2,irb,ic,iwf)
                endif

        ! c       if(ipr.gt.1) then
                write(45,'(''check the large radius expansion'')')
                write(45,'(''a0,ak'',1p2e22.10)')     &
                                    ae(1,irb,ic,iwf),ae(2,irb,ic,iwf)
                write(45,'(''irad, rad, extrapolated value, correct value,  DEBUG new fit'')')
                do ir=1,10
                    val=ae(1,irb,ic,iwf)*dexp(-ae(2,irb,ic,iwf)*x(nr(ic)-ir))
                    temp = ab(1,irb,ic,iwf)*dexp(-ab(2,irb,ic,iwf)*x(nr(ic)-ir))
                    write(45,'(i2,1p4e22.14)')      &
                    ir,x(nr(ic)-ir),val,rwf(nr(ic)-ir,irb,ic,iwf), temp
                enddo
                write(45,*) 'dwf1,dwfn',dwf1,dwfn
        ! c       endif
                if(ae(2,irb,ic,iwf).lt.0) call fatal_error ('BASIS_READ_NUM: ak<0')

                call spline2(x,rwf(1,irb,ic,iwf),nr(ic),dwf1,dwfn, d2rwf(1,irb,ic,iwf), work)

            enddo ! loop on irb : number of radial shells
        enddo ! loop on ic : the unique atom types

        ! ! debug part
        ! do ic = 1, nctype_tot
        !     do ir=1,nr(ic)
        !         write(200+ic,'(6(E22.15,1x))') x(ir),(rwf(ir,irb,ic,iwf),irb=1,nrbas(ic))
        !     enddo
        ! enddo


        ! Do the deallocations of local arrays
        if (allocated(unique)) deallocate(unique)
        if (allocated(unique_atom_index)) deallocate(unique_atom_index)

        if (allocated(nprims_per_atom)) deallocate(nprims_per_atom)
        if (allocated(prim_index_atom)) deallocate(prim_index_atom)
        if (allocated(shell_prim_correspondence)) deallocate(shell_prim_correspondence)

        if (allocated(atom_index)) deallocate(atom_index)
        if (allocated(nshells_per_atom)) deallocate(nshells_per_atom)
        if (allocated(shell_index_atom)) deallocate(shell_index_atom)

        if (allocated(basis_nucleus_index))    deallocate(basis_nucleus_index)
        if (allocated(basis_shell_index))      deallocate(basis_shell_index)
        if (allocated(basis_shell_ang_mom))    deallocate(basis_shell_ang_mom)
        if (allocated(basis_shell_factor))     deallocate(basis_shell_factor)
        if (allocated(basis_exponent))         deallocate(basis_exponent)
        if (allocated(basis_coefficient))      deallocate(basis_coefficient)
        if (allocated(basis_prim_factor))      deallocate(basis_prim_factor)
        if (allocated(ao_shell))               deallocate(ao_shell)
        if (allocated(ao_normalization))       deallocate(ao_normalization)

    end subroutine read_trexio_basis_file



    subroutine read_trexio_symmetry_file(file_trexio)
        ! Ravindra

        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid, idtask

        use contrl_file,        only: ounit, errunit
        use coefs,              only: norb
        use optorb,             only: irrep
        use vmc_mod,            only: norb_tot
        use general,            only: pooldir
        use precision_kinds,    only: dp
        use array_utils,        only: unique_string_elements



#if defined(TREXIO_FOUND)
        use trexio
        use contrl_file,        only: backend
        use error,              only: trexio_error
#endif

        implicit none

        !   local use
        character(len=72), intent(in)   :: file_trexio
        character(len=128)              :: file_trexio_path
        integer                         :: iostat, i, j, k, iunit
        logical                         :: exist, skip = .true.
        character(len=40)               :: label
        integer                         :: io, nsym, mo_num
        character(len=3), allocatable   :: mo_symmetry(:)


        ! trexio
        integer(8)                      :: trex_symmetry_file
        integer                         :: rc = 1

        character(len=3), dimension(:), allocatable :: unique_irrep       ! The output
        integer                                     :: num_irrep          ! The number of unique elements




        !   Formatting
        character(len=100)               :: int_format     = '(A, T60, I0)'
        character(len=100)               :: string_format  = '(A, T60, A)'

        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Reading orbital symmetries information from the trexio file :: ", trim(adjustl(file_trexio_path))
        write(ounit,*) '-----------------------------------------------------------------------'

        ! Check if the file exists
        if (wid) then
#if defined(TREXIO_FOUND)
            trex_symmetry_file = trexio_open(file_trexio_path, 'r', backend, rc)
            rc = trexio_read_mo_num(trex_symmetry_file, mo_num)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_mo_num failed', __FILE__, __LINE__)
#endif
        endif
        call bcast(mo_num)
        ! safe allocate
        if (.not. allocated(irrep)) allocate (irrep(mo_num))
        if (.not. allocated(mo_symmetry)) allocate (mo_symmetry(mo_num))
        if (.not. allocated(unique_irrep)) allocate (unique_irrep(mo_num))

        if (wid) then
#if defined(TREXIO_FOUND)
            rc = trexio_read_mo_symmetry(trex_symmetry_file, mo_symmetry, 2)
            if (trexio_has_mo_symmetry(trex_symmetry_file) == 0) trexio_has_symmetry = .true.
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_mo_symmetry failed', __FILE__, __LINE__)
#endif
        endif
        call bcast(trexio_has_symmetry)
        call bcast(mo_symmetry)

        write(ounit,fmt=int_format) " Number of molecular orbital symmetries read ::  ", mo_num

        call unique_string_elements(mo_num, mo_symmetry, unique_irrep, num_irrep)


        write(ounit,fmt=int_format) " Number of irreducible representations       ::  ", num_irrep
        write(ounit,*)
        write(ounit,'(a)')          " Irreducible representations correspondence  ::  "
        write(ounit,'(1x,10(a2,a,i2,a,x))') (unique_irrep(i), "=", i ,";", i=1, num_irrep)
        write(ounit,*)

        ! get the correspondence for each atom according to the rule defined for atomtypes
        do j = 1, mo_num
            do k = 1, num_irrep
                if (mo_symmetry(j) == unique_irrep(k))   irrep(j) = k
            enddo
        enddo


        write(ounit,*)  "Irreducible representation correspondence for all molecular orbitals"
        write(ounit, '(10(1x, i3))') (irrep(i), i=1, mo_num)


    end subroutine read_trexio_symmetry_file


    subroutine read_trexio_determinant_file(file_trexio)
        !> This subroutine reads the .hdf5 trexio generated file/folder. It then reads the
        !> determinant coefficients and orbital occupations .
        !! @author Ravindra Shinde (r.l.shinde@utwente.nl)
        !! @date 25 May 2022
        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid
        use contrl_file,        only: ounit, errunit
        use general,            only: pooldir
        use dets,               only: cdet, ndet
        use dorb_m,             only: iworbd
        use coefs,              only: norb
        use inputflags,         only: ideterminants
        use wfsec,              only: nwftype
        use csfs,               only: nstates
        use mstates_mod,        only: MSTATES
        use general,            only: pooldir
        use elec,               only: ndn, nup
        use const,              only: nelec
        use method_opt,         only: method
        use precision_kinds,    only: dp

#if defined(TREXIO_FOUND)
        use trexio
        use contrl_file,        only: backend
        use error,              only: trexio_error
#endif

        implicit none

        !   local use
        character(len=72), intent(in)   :: file_trexio
        character(len=40)               :: temp
        character(len=80)               :: comment, file_trexio_path
        integer                         :: iostat, i, j, k, iunit, jj
        logical                         :: exist
        character(len=2), allocatable   :: unique(:)

        ! trexio
        integer(8)                      :: trex_determinant_file
        integer                         :: rc = 1

        !   Formatting
        character(len=100)              :: int_format     = '(A, T60, I0)'
        character(len=100)              :: float_format   = '(A, T60, f12.8)'
        character(len=100)              :: string_format  = '(A, T60, A)'

        ! determinant data
        integer*8, allocatable          :: buffer(:,:,:)
        integer(8)                      :: offset, icount, BUFSIZE
        integer                         :: int64_num, m           ! Number of intergers required per spin component
        integer*8                       :: determinant_num
        integer*4, allocatable          :: orb_list_up(:), orb_list_dn(:)
        integer*4                       :: occ_num_up, occ_num_dn, occupied_num


        trex_determinant_file = 0

        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Reading determinants from the trexio file :: ",  file_trexio_path
        write(ounit,*) '-----------------------------------------------------------------------'

        ! Check if the file exists
        if (wid) then
#if defined(TREXIO_FOUND)
            trex_determinant_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_assert(rc, TREXIO_SUCCESS)
            rc = trexio_has_determinant_num (trex_determinant_file)
            if (rc == TREXIO_SUCCESS) then
                rc = trexio_read_determinant_num(trex_determinant_file, ndet)
                call trexio_assert(rc, TREXIO_SUCCESS)
                rc = trexio_get_int64_num(trex_determinant_file, int64_num)
                call trexio_assert(rc, TREXIO_SUCCESS)
            else
                write(errunit,*) "trexio file does not have number of determinant  stored :: ", rc
                call trexio_error(rc, TREXIO_SUCCESS, 'trexio_has_determinant_num failed', __FILE__, __LINE__)
            endif
#endif
        endif
        call bcast(ndet)
        call bcast(int64_num)

        determinant_num = ndet
        write(ounit,int_format) " Number of determinants (read from trexio) :: ", ndet

!       Do the allocations based on the number of determinants and the method
        if( (method(1:3) == 'lin')) then
            if (.not. allocated(cdet)) allocate(cdet(ndet,MSTATES,3))
        else
            if (.not. allocated(cdet)) allocate(cdet(ndet,MSTATES,nwftype))
        endif

        BUFSIZE = determinant_num
        offset = 0_8

        allocate(buffer(int64_num, 2, BUFSIZE))
        allocate(orb_list_up(int64_num*64), orb_list_dn(int64_num*64))


        if (wid) then
#if defined(TREXIO_FOUND)
        rc = trexio_read_determinant_coefficient(trex_determinant_file, offset, BUFSIZE, cdet(:,1,nwftype))
        if (trexio_has_determinant_coefficient(trex_determinant_file) == 0) trexio_has_determinant = .true.
        call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_determinant_coeff failed', __FILE__, __LINE__)
#endif
        endif
        call bcast(trexio_has_determinant)
        call bcast(cdet)


        write(ounit,*)
        write(ounit,*) " Determinant coefficients "
        write(ounit,'(10(1x, f11.8, 1x))') (cdet(i,1,nwftype), i=1, BUFSIZE)

!       allocate the orbital mapping array
        if (.not. allocated(iworbd)) allocate(iworbd(nelec, determinant_num))

        write(ounit, *)
        write(ounit, *) "Orbitals <--> Determinants mapping read from a trexio file :: "
        write(ounit, *) "Serial numbers of orbitals that are occupied               :: "
        write(ounit, *) "'alpha (spin up)'  <---------------------->  'beta (spin down)' "
        write(ounit, *)
        ! convert one given determinant into lists of orbitals

        offset = 0_8
        icount = BUFSIZE

#if defined(TREXIO_FOUND)
        do while (icount == BUFSIZE)
            if (offset < ndet) then
                rc = trexio_read_determinant_list(trex_determinant_file, offset, icount, buffer)
                call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_determinant_list failed', __FILE__, __LINE__)
                offset = offset + icount
            else
                icount = 0
            end if

            do m=1,icount
                rc = trexio_to_orbital_list_up_dn(int64_num, buffer(1,1,m), orb_list_up, orb_list_dn, occ_num_up, occ_num_dn)
                call trexio_error(rc, TREXIO_SUCCESS, 'trexio_to_orbital_list_up_dn filed', __FILE__, __LINE__)
                write(temp, '(1x,a,i0,a,i0,a)') '(', occ_num_up, '(i4,1x),', occ_num_dn, '(i4,1x))'
                write(ounit, temp) (orb_list_up(i), i = 1, occ_num_up), (orb_list_dn(i), i = 1, occ_num_dn)

                do i = 1, occ_num_up
                    iworbd(i, m) = orb_list_up(i)
                enddo
                do i = 1, occ_num_dn
                    iworbd(occ_num_up + i, m) = orb_list_dn(i)
                enddo

            end do
         end do
#endif

        deallocate(buffer)
        deallocate(orb_list_up)
        deallocate(orb_list_dn)

        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*)
    end subroutine read_trexio_determinant_file


    subroutine read_trexio_ecp_file(file_trexio)
        !> This subroutine reads the .hdf5 trexio generated file/folder. It then reads the
        !> ECP information for all the unique atoms.
        !! @author Ravindra Shinde (r.l.shinde@utwente.nl)
        !! @date 01 June 2022

        use custom_broadcast,   only: bcast
        use mpiconf,            only: wid

#if defined(TREXIO_FOUND)
        use trexio
        use contrl_file,        only: backend
        use error,              only: trexio_error
#endif

        use pseudo_mod,         only: MPS_L, MGAUSS, MPS_QUAD
        use atom,               only: symbol, nctype_tot, ncent_tot
        use gauss_ecp,          only: ecp_coef, ecp_exponent, necp_power, necp_term
        use gauss_ecp,          only: allocate_gauss_ecp
        use pseudo,             only: lpot
        use qua,                only: nquad, wq, xq0, yq0, zq0
        use general,            only: pooldir
        use contrl_file,        only: ounit
        use rotqua_mod,         only: gesqua

        use precision_kinds,    only: dp

        implicit none

        !   local use
        character(len=72), intent(in)   :: file_trexio
        character(len=80)               :: file_trexio_path


        ! trexio
        integer(8)                      :: trex_ecp_file
        integer                         :: rc = 1

        ! local variables
        integer                         :: ecp_num
        integer, allocatable            :: flat_ecp_ang_mom(:)
        integer, allocatable            :: flat_ecp_nucleus_index(:)
        integer, allocatable            :: flat_ecp_max_ang_mom_plus_1(:)
        integer, allocatable            :: flat_ecp_power(:)
        integer, allocatable            :: flat_ecp_z_core(:)
        real(dp), allocatable           :: flat_ecp_coefficient(:)
        real(dp), allocatable           :: flat_ecp_exponent(:)

        integer, allocatable            :: unique_atom_index(:)
        character(len=2), allocatable   :: unique(:) ! unique symbols of atoms

        integer, dimension(:), allocatable :: atom_index(:), component_index_atom(:), components_per_atom(:)
        integer, dimension(:), allocatable :: nterms_per_component(:), term_index_component(:)
        integer                         :: count, lower_comp, upper_comp, counter_comp


        integer         :: i, ic, idx, l, tcount1, j

        trex_ecp_file = 0

        !   External file reading

        if((file_trexio(1:6) == '$pool/') .or. (file_trexio(1:6) == '$POOL/')) then
            file_trexio_path = pooldir // file_trexio(7:)
        else
            file_trexio_path = file_trexio
        endif


        write(ounit,*) '-----------------------------------------------------------------------'
        write(ounit,*) " Reading ECP data from the trexio file :: ",  file_trexio_path
        write(ounit,*) '-----------------------------------------------------------------------'



        ! Check if the file exists
        if (wid) then
#if defined(TREXIO_FOUND)
            trex_ecp_file = trexio_open(file_trexio_path, 'r', backend, rc)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio file open', __FILE__, __LINE__)
            rc = trexio_read_ecp_num(trex_ecp_file, ecp_num)
            if (trexio_has_ecp_num(trex_ecp_file) == 0) trexio_has_ecp = .true.
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_num', __FILE__, __LINE__)
#endif
        endif
        call bcast(trexio_has_ecp)
        call bcast(ecp_num)
        allocate (flat_ecp_ang_mom(ecp_num))
        allocate (flat_ecp_nucleus_index(ecp_num))
        allocate (flat_ecp_max_ang_mom_plus_1(ncent_tot))
        allocate (flat_ecp_power(ecp_num))
        allocate (flat_ecp_z_core(ncent_tot))
        allocate (flat_ecp_coefficient(ecp_num))
        allocate (flat_ecp_exponent(ecp_num))

        if (wid) then
#if defined(TREXIO_FOUND)
            rc = trexio_read_ecp_ang_mom(trex_ecp_file, flat_ecp_ang_mom)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_ang_mom', __FILE__, __LINE__)
            rc = trexio_read_ecp_nucleus_index(trex_ecp_file, flat_ecp_nucleus_index)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_nucleus_index', __FILE__, __LINE__)
            rc = trexio_read_ecp_max_ang_mom_plus_1(trex_ecp_file, flat_ecp_max_ang_mom_plus_1)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_max_ang_mom_plus_1', __FILE__, __LINE__)
            rc = trexio_read_ecp_power(trex_ecp_file, flat_ecp_power)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_power', __FILE__, __LINE__)
            rc = trexio_read_ecp_z_core(trex_ecp_file, flat_ecp_z_core)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_z_core', __FILE__, __LINE__)
            rc = trexio_read_ecp_coefficient(trex_ecp_file, flat_ecp_coefficient)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_coefficient', __FILE__, __LINE__)
            rc = trexio_read_ecp_exponent(trex_ecp_file, flat_ecp_exponent)
            call trexio_error(rc, TREXIO_SUCCESS, 'trexio_read_ecp_exponent', __FILE__, __LINE__)
#endif
        endif
        call bcast(flat_ecp_ang_mom)
        call bcast(flat_ecp_nucleus_index)
        call bcast(flat_ecp_max_ang_mom_plus_1)
        call bcast(flat_ecp_power)
        call bcast(flat_ecp_z_core)
        call bcast(flat_ecp_coefficient)
        call bcast(flat_ecp_exponent)

        ! Obtain the number of unique types of atoms stored in the hdf5 file.
        if (.not. allocated(unique)) allocate(unique(nctype_tot))
        if (.not. allocated(unique_atom_index)) allocate(unique_atom_index(nctype_tot))


        tcount1 = 1
        unique_atom_index(1) = 1
        unique(1) = symbol(1)
        do j= 2, ncent_tot
            if (any(unique == symbol(j) ))  then
                cycle
            endif
            tcount1 = tcount1 + 1
            unique_atom_index(tcount1) = j
            unique(tcount1) = symbol(j)
        enddo

        if (.not. allocated(lpot)) allocate (lpot(nctype_tot))
        call allocate_gauss_ecp()

        allocate(atom_index(ecp_num), source=0)
        allocate(components_per_atom(ncent_tot*10), source=0)
        allocate(component_index_atom(ncent_tot*10), source=0)

        call unique_elements(ecp_num, flat_ecp_nucleus_index, atom_index, count, components_per_atom, component_index_atom)

        ! count                     :: "Number of unique elements". Not used
        ! atom_index(1:count)       :: "Unique elements index (not used here)"
        ! components_per_atom(1:count) :: "frequency or count of shells per atom"
        ! component_index_atom(1:count) :: "index number of the shell for each atom"
        ! The components per atom can be obtained by accessing the component_index_atom
        ! for a given atom index by the slice of size frequency.


        do ic = 1, nctype_tot

            ! loop over all the primitives for the unique atom
            ! The lower and upper indices of primitive indices
            lower_comp = component_index_atom(unique_atom_index(ic))
            upper_comp = component_index_atom(unique_atom_index(ic)) + components_per_atom(unique_atom_index(ic)) - 1

            lpot(ic) = flat_ecp_max_ang_mom_plus_1(ic) + 1

            write(ounit,'(a,i4,a,a)') 'ECP for atom type ', ic, ' Element = ', unique(ic)
            write(ounit,*) '-----------------------------------------------------------------------'
            write(ounit,*)
            write(ounit,'(a,i4,a,i4)') 'ECP for atom type ', ic, ' lpot = ', lpot(ic)

            if(lpot(ic).gt.MPS_L) call fatal_error('READPS_GAUSS: increase MPS_L')

            if (.not. allocated(nterms_per_component)) allocate(nterms_per_component(lpot(ic)))
            if (.not. allocated(term_index_component)) allocate(term_index_component(lpot(ic)))


            counter_comp = 0
            do l = 1, lpot(ic)
                if(l.eq.1)then
                    idx=lpot(ic)
                else
                    idx=l-1
                endif

                atom_index = 0
                call unique_elements(components_per_atom(ic), flat_ecp_ang_mom(lower_comp:upper_comp), atom_index, count, nterms_per_component, term_index_component)
                necp_term(idx,ic) = nterms_per_component(l)
                write(ounit,*)
                write(ounit,'(a,2i6)') '    component, #terms ', l,necp_term(idx,ic)

                do i=1,necp_term(idx,ic)
                    ecp_coef(i,idx,ic) = flat_ecp_coefficient(lower_comp + counter_comp)
                    necp_power(i,idx,ic) = flat_ecp_power(lower_comp + counter_comp) + 2
                    ecp_exponent(i,idx,ic) = flat_ecp_exponent(lower_comp + counter_comp)
                    counter_comp = counter_comp + 1

                    write(ounit,'(a,f16.8,i2,f16.8)') '    coef, power, expo ', ecp_coef(i,idx,ic), &
                    necp_power(i,idx,ic), ecp_exponent(i,idx,ic)

                enddo
            enddo  ! loop on l upto lpot(ic)
            if (allocated(nterms_per_component)) deallocate(nterms_per_component)
            if (allocated(term_index_component)) deallocate(term_index_component)
            write(ounit,*) '-----------------------------------------------------------------------'
            write(ounit,*)
        enddo

        deallocate(atom_index)
        deallocate(components_per_atom)
        deallocate(component_index_atom)

        deallocate(flat_ecp_ang_mom)
        deallocate(flat_ecp_nucleus_index)
        deallocate(flat_ecp_max_ang_mom_plus_1)
        deallocate(flat_ecp_power)
        deallocate(flat_ecp_z_core)
        deallocate(flat_ecp_coefficient)
        deallocate(flat_ecp_exponent)

        if (.not. allocated(wq)) allocate (wq(MPS_QUAD))
        if (.not. allocated(xq0)) allocate (xq0(MPS_QUAD))
        if (.not. allocated(yq0)) allocate (yq0(MPS_QUAD))
        if (.not. allocated(zq0)) allocate (zq0(MPS_QUAD))

        call gesqua(nquad,xq0,yq0,zq0,wq)
    end subroutine read_trexio_ecp_file


end module
