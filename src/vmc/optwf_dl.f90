!------------------------------------------------------------------------------
!        Optimization routine using ML inspired optimizers
!------------------------------------------------------------------------------
!> @author
!> Claudia Filippi
!
! DESCRIPTION:
!> Opitmize the wave function parameters using the ADAM optimizer
!
! URL           : https://github.com/filippi-claudia/champ
!---------------------------------------------------------------------------

module optwf_dl_mod

    use precision_kinds, only: dp

    implicit None

    real(dp), dimension(:), allocatable :: deltap
    real(dp), dimension(:), allocatable :: dl_momentum
    real(dp), dimension(:), allocatable :: dl_EG_sq
    real(dp), dimension(:), allocatable :: dl_EG
    real(dp), dimension(:), allocatable :: parameters

    private
    public :: optwf_dl
    save

contains

    subroutine optwf_dl()

        use precision_kinds, only: dp
        use sr_mod, only: MPARM
        use optwf_contrl, only: ioptci, ioptjas, ioptorb, nparm
        use optwf_contrl, only: idl_flag, dl_mom, dl_alg
        use optwf_corsam, only: energy, energy_err, force
        use optwf_contrl, only: dparm_norm_min, nopt_iter
        use optwf_contrl, only: sr_tau , sr_adiag, sr_eps 
        use contrl, only: nblk, nblk_max
        use method_opt, only: method

        implicit None

        integer :: iter, iflag
        real(dp) :: dparm_norm
        real(dp) :: denergy, energy_sav, denergy_err, energy_err_sav

        write (6, '(''Started dl optimization'')')

        call set_nparms_tot

        call sanity_check()
        write (6, '(''Starting dparm_norm_min'',g12.4)') dparm_norm_min

        call init_arrays()

        call save_nparms()

        call fetch_parameters()

        ! do iteration
        do iter = 1, nopt_iter
            write (6, '(/,''DL Optimization iteration'',i5,'' of'',i5)') iter, nopt_iter

            call vmc()

            write (6, '(/,''Completed sampling'')')

            call optimization_step(iter)

            ! historically, we input -deltap in compute_parameters,
            ! so we multiply actual deltap by -1
            call dscal(nparm, -1.d0, deltap, 1)

            call test_solution_parm(nparm, deltap, dparm_norm, &
                                    dparm_norm_min, sr_adiag, iflag)
            write (6, '(''Norm of parm variation '',g12.5)') dparm_norm

            if (iflag .ne. 0) then
                write (6, '(''Warning: dparm_norm>1'')')
                stop
            endif

            call compute_parameters(deltap, iflag, 1)
            call write_wf(1, iter)
            call save_wf

            if (iter .ge. 2) then
                denergy = energy(1) - energy_sav
                denergy_err = sqrt(energy_err(1)**2 + energy_err_sav**2)
                nblk = nblk*1.2
                nblk = min(nblk, nblk_max)
            endif
            write (6, '(''nblk = '',i6)') nblk

            energy_sav = energy(1)
            energy_err_sav = energy_err(1)
        enddo
        ! enddo iteration

        write (6, '(/,''Check last iteration'')')

        ! Why ??!!
        ioptjas = 0
        ioptorb = 0
        ioptci = 0

        call set_nparms_tot

        call qmc

        call write_wf(1, -1)

        call deallocate_arrays()

        return
    end subroutine optwf_dl

    subroutine sanity_check()

        use sr_mod, only: MPARM
        use optwf_contrl, only: nparm
        use optwf_contrl, only: idl_flag
        use method_opt, only: method

        if (method .ne. 'sr_n' .or. idl_flag .eq. 0) return
        if (nparm .gt. MPARM) call fatal_error('SR_OPTWF: nparmtot gt MPARM')

    end subroutine sanity_check

    subroutine init_arrays()
        !> Allocate and initialize to 0 all arrays
        use optwf_contrl, only: nparm

        !> allocate
        allocate (deltap(nparm))
        allocate (dl_momentum(nparm))  !< 'momentum' variables
        allocate (dl_EG_sq(nparm))     !< moving average of past squared gradients
        allocate (dl_EG(nparm))        !< moving average of past gradients
        allocate (parameters(nparm))   !< vector of wave function parameters

        !> init
        dl_momentum(:) = 0.d0
        dl_EG_sq(:) = 0.d0
        dl_EG(:) = 0.d0
        parameters(:) = 0.d0

    end subroutine init_arrays

    subroutine deallocate_arrays()
        !> Deallocate arrays

        deallocate (deltap)
        deallocate (dl_momentum)
        deallocate (dl_EG_sq)
        deallocate (dl_EG)
        deallocate (parameters)

    end subroutine deallocate_arrays

    subroutine optimization_step(iter)
        !> do 1 optimization step
        use mpi
        use precision_kinds, only: dp
        use mpiconf, only: idtask
        use optwf_sr_mod, only: sr_hs
        use optwf_contrl, only: nparm
        use optwf_contrl, only: sr_tau , sr_adiag, sr_eps 

        ! in/out variable
        integer, intent(in) :: iter
        integer :: ierr

        ! we only need h_sr = - grad_parm E
        call sr_hs(nparm, sr_adiag)

        if (idtask .eq. 0) then
            call one_iter(iter)
        endif

        call MPI_BCAST(deltap, nparm, MPI_REAL8, 0, MPI_COMM_WORLD, ierr)

        return
    end subroutine optimization_step

    subroutine one_iter(iter)
        !> Individual routine to optimize the parameters
        use precision_kinds, only: dp
        use sr_mat_n, only: h_sr
        use optwf_contrl, only: nparm
        use optwf_contrl, only: dl_alg, dl_mom
        use optwf_contrl, only: sr_tau !, sr_adiag, sr_eps 

        integer, intent(in) :: iter

        integer :: i
        real(dp) :: dl_EG_corr, dl_EG_sq_corr, dl_momentum_prev, parm_old, dl_EG_old
        real(dp) :: v_corr
        real(dp) :: damp

        ! Damping parameter for Nesterov gradient descent
        damp = 10.d0
        select case (dl_alg)
        case ('mom')
            do i = 1, nparm
                dl_momentum(i) = dl_mom*dl_momentum(i) + sr_tau*h_sr(i)
                deltap(i) = dl_momentum(i)
                parameters(i) = parameters(i) + deltap(i)
            enddo
        case ('nag')
            do i = 1, nparm
                dl_momentum_prev = dl_momentum(i)
                dl_momentum(i) = dl_mom*dl_momentum(i) - sr_tau*h_sr(i)
                deltap(i) = -(dl_mom*dl_momentum_prev + (1 + dl_mom)*dl_momentum(i))
                parameters(i) = parameters(i) + deltap(i)
            enddo
        case ('rmsprop')
            ! Actually an altered version of rmsprop that uses nesterov momentum as well
            ! magic numbers: gamma = 0.9
            do i = 1, nparm
                dl_EG_sq(i) = 0.9*dl_EG_sq(i) + 0.1*(-h_sr(i))**2
                parameters(i) = parameters(i) + deltap(i)
                parm_old = parameters(i)
                dl_momentum_prev = dl_momentum(i)
                dl_momentum(i) = parameters(i) + sr_tau*h_sr(i)/sqrt(dl_EG_sq(i) + 10.d0**(-8.d0))

                ! To avoid declaring more arrays, use dl_EG for \lambda, dl_EG_sq = gamma
                ! Better solution needed (custom types for each iterator a la Fortran 2003 or C++ classes?)
                dl_EG_old = dl_EG(i)
                dl_EG(i) = 0.5 + 0.5*sqrt(1 + 4*dl_EG(i)**2)
                dl_EG_sq(i) = (1 - dl_EG_old)/dl_EG(i)
                dl_EG_sq_corr = dl_EG_sq(i)*exp(-(iter - 1)/damp)
                parameters(i) = (1 - v_corr)*dl_momentum(i) + v_corr*dl_momentum_prev
                deltap(i) = parameters(i) - parm_old
            enddo
        case ('adam')
            ! Magic numbers: beta1 = 0.9, beta2 = 0.999
            do i = 1, nparm
                dl_EG(i) = 0.9*dl_EG(i) + 0.1*(-h_sr(i))
                dl_EG_sq(i) = 0.999*dl_EG_sq(i) + 0.001*(-h_sr(i))**2
                dl_EG_corr = dl_EG(i)/(1 - 0.9**iter)
                dl_EG_sq_corr = dl_EG_sq(i)/(1 - 0.999**iter)
                deltap(i) = -sr_tau*dl_EG_corr/(sqrt(dl_EG_sq_corr) + 10.d0**(-8.d0))
                parameters(i) = parameters(i) + deltap(i)
            enddo
        case ('cnag')
            do i = 1, nparm
                parm_old = parameters(i)
                dl_momentum_prev = dl_momentum(i)
                dl_momentum(i) = parameters(i) + sr_tau*h_sr(i)
                ! To avoid declaring more arrays, use dl_EG for \lambda, dl_EG_sq = gamma
                dl_EG_old = dl_EG(i)
                dl_EG(i) = 0.5 + 0.5*sqrt(1 + 4*dl_EG(i)**2)
                dl_EG_sq(i) = (1 - dl_EG_old)/dl_EG(i)
                parameters(i) = (1 - dl_EG_sq(i))*dl_momentum(i) + dl_EG_sq(i)*dl_momentum_prev
                deltap(i) = parameters(i) - parm_old
            enddo
        end select

        return
    end subroutine one_iter

end module optwf_dl_mod
!=================================================