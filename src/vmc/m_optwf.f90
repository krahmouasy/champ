module optwf_contrl
    !> Arguments: ioptci, ioptjas, ioptorb, idl_flag, ilbfgs_flag, ilbfgs_m, nparm,
    !>            nopt_iter, micro_iter_sr, energy_tol,
    !>            dparm_norm_min, nvec, nvecx, alin_adiag, alin_eps, lin_jdav ibeta, ratio_j, 
    !>            iapprox, ncore, iuse_orbeigv, no_active, multiple_adiag, iroot_geo,
    !>            ilastvmc, sr_tau, sr_adig, sr_adiag, sr_eps 

    use precision_kinds, only: dp

    integer :: ioptwf
    integer :: ioptci
    integer :: ioptjas
    integer :: ioptorb
    integer :: idl_flag
    integer :: ilbfgs_flag
    integer :: ilbfgs_m
    integer :: nparm
    integer :: nopt_iter
    integer :: micro_iter_sr
    real(dp) :: energy_tol
    real(dp) :: dparm_norm_min 
    integer :: nvec
    integer :: nvecx
    real(dp) :: alin_adiag
    real(dp) :: alin_eps
    integer :: lin_jdav
    integer :: ibeta
    integer :: ratio_j
    integer :: iapprox
    integer :: ncore 
    integer :: iuse_orbeigv 
    integer :: no_active 
    integer :: multiple_adiag
    integer  :: iroot_geo
    integer :: ilastvmc
    real(dp) :: sr_tau
    real(dp) :: sr_adiag
    real(dp) :: sr_eps
    character(20) :: dl_alg
    real(dp) :: dl_mom

    private
    public :: ioptwf
    public :: idl_flag, ilbfgs_flag, ilbfgs_m
    public :: ioptci, ioptjas, ioptorb, nparm
    public :: nopt_iter, micro_iter_sr, energy_tol, dparm_norm_min
    public :: nvec, nvecx, alin_adiag, alin_eps, lin_jdav
    public :: ibeta, ratio_j
    public :: iapprox, ncore, iuse_orbeigv, no_active
    public :: multiple_adiag
    public :: iroot_geo
    public :: ilastvmc
    public :: sr_tau, sr_adiag, sr_eps
    public :: dl_alg, dl_mom
    save

end module optwf_contrl

module optwf_corsam
    !> Arguments: add_diag, add_diag_tmp, energy, energy_err, force, force_err
    use force_mod, only: MFORCE
    use precision_kinds, only: dp

    real(dp), dimension(:), allocatable :: add_diag !(MFORCE)
    real(dp), dimension(:), allocatable :: add_diag_tmp !(MFORCE)
    real(dp), dimension(:), allocatable :: energy !(MFORCE)
    real(dp), dimension(:), allocatable :: energy_err !(MFORCE)
    real(dp), dimension(:), allocatable :: force !(MFORCE)
    real(dp), dimension(:), allocatable :: force_err !(MFORCE)

    private
    public :: add_diag, add_diag_tmp, energy, energy_err, force, force_err
    public :: allocate_optwf_corsam, deallocate_optwf_corsam
    save
contains
    subroutine allocate_optwf_corsam()
        use force_mod, only: MFORCE
        use precision_kinds, only: dp
        if (.not. allocated(add_diag)) allocate (add_diag(MFORCE))
        if (.not. allocated(add_diag_tmp)) allocate (add_diag_tmp(MFORCE))
        if (.not. allocated(energy)) allocate (energy(MFORCE))
        if (.not. allocated(energy_err)) allocate (energy_err(MFORCE))
        if (.not. allocated(force)) allocate (force(MFORCE))
        if (.not. allocated(force_err)) allocate (force_err(MFORCE))
    end subroutine allocate_optwf_corsam

    subroutine deallocate_optwf_corsam()
        if (allocated(force_err)) deallocate (force_err)
        if (allocated(force)) deallocate (force)
        if (allocated(energy_err)) deallocate (energy_err)
        if (allocated(energy)) deallocate (energy)
        if (allocated(add_diag_tmp)) deallocate (add_diag_tmp)
        if (allocated(add_diag)) deallocate (add_diag)
    end subroutine deallocate_optwf_corsam

end module optwf_corsam

module optwf_func
    !> Arguments: ifunc_omega, omega, omega0, omega_hes, n_omegaf, n_omegat
    use precision_kinds, only: dp

    integer :: ifunc_omega
    real(dp) :: omega
    real(dp) :: omega0
    real(dp) :: omega_hes
    integer :: n_omegaf
    integer :: n_omegat

    private
    public :: ifunc_omega, omega, omega0, omega_hes, n_omegaf, n_omegat
    save
end module optwf_func

module optwf_nparmj
    !> Arguments: nparma, nparmb, nparmc, nparmf
    use vmc_mod, only: MCTYPE, MCTYP3X

    integer, dimension(:), allocatable :: nparma !(MCTYP3X)
    integer, dimension(:), allocatable :: nparmb !(3)
    integer, dimension(:), allocatable :: nparmc !(MCTYPE)
    integer, dimension(:), allocatable :: nparmf !(MCTYPE)

    private
    public :: nparma, nparmb, nparmc, nparmf
    public :: allocate_optwf_nparmj, deallocate_optwf_nparmj
    save
contains
    subroutine allocate_optwf_nparmj()
        use vmc_mod, only: MCTYPE, MCTYP3X
        if (.not. allocated(nparma)) allocate (nparma(MCTYP3X))
        if (.not. allocated(nparmb)) allocate (nparmb(3))
        if (.not. allocated(nparmc)) allocate (nparmc(MCTYPE))
        if (.not. allocated(nparmf)) allocate (nparmf(MCTYPE))
    end subroutine allocate_optwf_nparmj

    subroutine deallocate_optwf_nparmj()
        if (allocated(nparmf)) deallocate (nparmf)
        if (allocated(nparmc)) deallocate (nparmc)
        if (allocated(nparmb)) deallocate (nparmb)
        if (allocated(nparma)) deallocate (nparma)
    end subroutine deallocate_optwf_nparmj

end module optwf_nparmj

module optwf_parms
    !> Arguments: nparmd, nparme, nparmg, nparmj, nparml, nparms

    integer :: nparmd
    integer :: nparme
    integer :: nparmg
    integer :: nparmj
    integer :: nparml
    integer :: nparms

    private
    public :: nparmd, nparme, nparmg, nparmj, nparml, nparms
    save
end module optwf_parms

module optwf_wjas
    !> Arguments: iwjasa, iwjasb, iwjasc, iwjasf
    use vmc_mod, only: MCTYPE, MCTYP3X

    integer, dimension(:, :), allocatable :: iwjasa !(83,MCTYP3X)
    integer, dimension(:, :), allocatable :: iwjasb !(83,3)
    integer, dimension(:, :), allocatable :: iwjasc !(83,MCTYPE)
    integer, dimension(:, :), allocatable :: iwjasf !(15,MCTYPE)

    private
    public :: iwjasa, iwjasb, iwjasc, iwjasf
    public :: allocate_optwf_wjas, deallocate_optwf_wjas
    save
contains
    subroutine allocate_optwf_wjas()
        use vmc_mod, only: MCTYPE, MCTYP3X
        if (.not. allocated(iwjasa)) allocate (iwjasa(83, MCTYP3X))
        if (.not. allocated(iwjasb)) allocate (iwjasb(83, 3))
        if (.not. allocated(iwjasc)) allocate (iwjasc(83, MCTYPE))
        if (.not. allocated(iwjasf)) allocate (iwjasf(15, MCTYPE))
    end subroutine allocate_optwf_wjas

    subroutine deallocate_optwf_wjas()
        if (allocated(iwjasf)) deallocate (iwjasf)
        if (allocated(iwjasc)) deallocate (iwjasc)
        if (allocated(iwjasb)) deallocate (iwjasb)
        if (allocated(iwjasa)) deallocate (iwjasa)
    end subroutine deallocate_optwf_wjas

end module optwf_wjas

subroutine allocate_m_optwf()
    use optwf_corsam, only: allocate_optwf_corsam
    use optwf_nparmj, only: allocate_optwf_nparmj
    use optwf_wjas, only: allocate_optwf_wjas

    call allocate_optwf_corsam()
    call allocate_optwf_nparmj()
    call allocate_optwf_wjas()
end subroutine allocate_m_optwf