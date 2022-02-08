module header
    !> Arguments: date, title

    implicit none

    character*20 title
    character*24 date

    private
    public :: date, title
    save
end module header

module inputflags
    !> Arguments: iznuc,igeometry,ibasis_num,ilcao,iexponents,
    !             ideterminants,ijastrow_parameter, ioptorb_def,ilattice,
    !             ici_def,iforces,icsfs,imstates,igradients,icharge_efield,
    !             imultideterminants,ioptorb_mixvirt,imodify_zmat,izmatrix_check,
    !             ihessian_zmat, node_cutoff, eps_node_cutoff, scalecoef, iqmmm
    use precision_kinds, only: dp

    implicit none

    integer :: iznuc
    integer :: igeometry
    integer :: ibasis_num
    integer :: ilcao
    integer :: iexponents
    integer :: ideterminants
    integer :: ijastrow_parameter
    integer :: ioptorb_def
    integer :: ilattice
    integer :: ici_def
    integer :: iforces
    integer :: icsfs
    integer :: imstates
    integer :: igradients
    integer :: icharge_efield
    integer :: imultideterminants
    integer :: ioptorb_mixvirt
    integer :: imodify_zmat
    integer :: izmatrix_check
    integer :: ihessian_zmat
    integer :: node_cutoff, dmc_node_cutoff
    real(dp) :: eps_node_cutoff, dmc_eps_node_cutoff
    real(dp) :: scalecoef
    integer :: iqmmm
 ! dmc specifics:
    real(dp) :: enode_cutoff
    integer :: icircular
    integer :: idrifdifgfunc
    integer :: ibranch_elec

    private
    public :: iznuc, igeometry, ibasis_num, ilcao, iexponents
    public :: ideterminants, ijastrow_parameter, ioptorb_def, ilattice
    public :: ici_def, iforces, icsfs, imstates, igradients, icharge_efield
    public :: imultideterminants, ioptorb_mixvirt, imodify_zmat, izmatrix_check
    public :: ihessian_zmat
    public :: node_cutoff, dmc_node_cutoff, eps_node_cutoff, dmc_eps_node_cutoff, scalecoef
    public :: enode_cutoff, icircular, idrifdifgfunc, ibranch_elec
    public :: iqmmm
    save
end module inputflags

module general
    !> Arguments: pooldir, pp_id, bas_id, filename, filenames_bas_num,
    !>            filenames_ps_gauss, filenames_ps_tm, atomtyp,
    !>            atomsymbol
    implicit none
    character(:), allocatable :: pooldir
    character(:), allocatable :: pp_id
    character(:), allocatable :: bas_id
    character(:), allocatable :: filename
    character*256, allocatable, dimension(:) :: filenames_bas_num
    character*256, allocatable, dimension(:) :: filenames_ps_gauss
    character*256, allocatable, dimension(:) :: filenames_ps_champ
    character*256, allocatable, dimension(:) :: filenames_ps_tm
    character(:), allocatable :: atomtyp
    character(:), allocatable :: atomsymbol

    private
    public :: pooldir, pp_id, bas_id, atomtyp, filename
    public :: filenames_bas_num, filenames_ps_gauss
    public :: filenames_ps_champ, filenames_ps_tm, atomsymbol
    save
end module general

module method_opt
    !> should be in the input somehow no ?
    !> Arguments: method

    implicit none

    character(:), allocatable :: method

    private
    public :: method
    save
end module method_opt