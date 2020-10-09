!------------------------------------------------------------------------------
!        Optimization routine using stochastic reconfiguration
!------------------------------------------------------------------------------
!> @author
!> Claudia Filippi
!
! DESCRIPTION:
!> Opitmize the wave function parameters using the ADAM optimizer
!
! URL           : https://github.com/filippi-claudia/champ
!---------------------------------------------------------------------------

module optwf_sr_mod

    use precision_kinds, only: dp

    integer :: nopt_iter, nblk_max
    real(dp) ::  energy_tol
    real(dp) :: dparm_norm_min
    real(dp) :: sr_tau, sr_adiag, sr_eps
    real(dp) :: omega0
    integer :: i_sr_rescale, i_func_omega
    integer :: n_omegaf, n_omegat
    integer :: micro_iter_sr
    integer :: izvzb

    real(dp) :: sr_adiag_sav
    integer :: ioptjas_sav, ioptorb_sav, ioptci_sav, iforce_analy_sav

    real(dp), dimension(:), allocatable :: deltap

    private
    public :: optwf_sr, sr, sr_hs
    save

contains

    subroutine optwf_sr

        use precision_kinds, only: dp
        use sr_mod, only: MPARM
        use optwf_contrl, only: ioptci, ioptjas, ioptorb, nparm
        use mstates_mod, only: MSTATES
        use optwf_corsam, only: energy, energy_err, force
        use optwf_func, only: ifunc_omega, omega, omega_hes
        use contrl, only: nblk
        use force_analy, only: iforce_analy, alfgeo

        use method_opt, only: method

        implicit real*8(a - h, o - z)

        allocate (deltap(MPARM*MSTATES))

        if (method .ne. 'sr_n') return

        call set_nparms_tot

        if (nparm .gt. MPARM) call fatal_error('SR_OPTWF: nparmtot gt MPARM')

        call read_input()

        call save_params()

        call save_nparms

        call write_geometry(0)

        ! do iteration
        do iter = 1, nopt_iter
            write (6, '(/,''Optimization iteration'',i5,'' of'',i5)') iter, nopt_iter

            iforce_analy = 0

            if (ifunc_omega .gt. 0) then
                omega_hes = energy_sav
                if (iter .gt. n_omegaf) then
                    alpha_omega = dfloat(n_omegaf + n_omegat - iter)/n_omegat
                    omega = alpha_omega*omega0 + (1.d0 - alpha_omega)*(energy_sav - sigma_sav)
                    if (ifunc_omega .eq. 1 .or. ifunc_omega .eq. 2) omega = alpha_omega*omega0 + (1.d0 - alpha_omega)*energy_sav
                endif
                if (iter .gt. n_omegaf + n_omegat) then
                    omega = energy_sav - sigma_sav
                    if (ifunc_omega .eq. 1 .or. ifunc_omega .eq. 2) omega = energy_sav
                endif
                write (6, '(''SR omega: '',f10.5)') omega
            endif

            ! do micro_iteration
            do miter = 1, micro_iter_sr

                if (micro_iter_sr .gt. 1) write (6, '(/,''Micro iteration'',i5,'' of'',i5)') miter, micro_iter_sr

                if (miter .eq. micro_iter_sr) iforce_analy = iforce_analy_sav

                call qmc

                write (6, '(/,''Completed sampling'')')

6               continue

                call sr(nparm, deltap, sr_adiag, sr_eps, i)
                call dscal(nparm, -sr_tau, deltap, 1)

                adiag = sr_adiag
                call test_solution_parm(nparm, deltap, dparm_norm, dparm_norm_min, adiag, iflag)
                write (6, '(''Norm of parm variation '',d12.5)') dparm_norm
                if (iflag .ne. 0) then
                    write (6, '(''Warning: dparm_norm>1'')')
                    adiag = 10*adiag
                    write (6, '(''adiag increased to '',f10.5)') adiag

                    sr_adiag = adiag
                    go to 6
                else
                    sr_adiag = sr_adiag_sav
                endif

                call compute_parameters(deltap, iflag, 1)
                call write_wf(1, iter)

                call save_wf

                if (iforce_analy .gt. 0) then

                    if (izvzb .gt. 0) call forces_zvzb(nparm)

                    call compute_positions
                    call write_geometry(iter)
                endif
            enddo
            ! enddo micro_iteration

            if (iter .ge. 2) then
                denergy = energy(1) - energy_sav
                denergy_err = sqrt(energy_err(1)**2 + energy_err_sav**2)

                nblk = nblk*1.2
                nblk = min(nblk, nblk_max)

            endif
            write (6, '(''nblk = '',i6)') nblk
            write (6, '(''alfgeo = '',f10.4)') alfgeo

            energy_sav = energy(1)
            energy_err_sav = energy_err(1)
            sigma_sav = sigma
        enddo
        ! enddo iteration

        write (6, '(/,''Check last iteration'')')

        ioptjas = 0
        ioptorb = 0
        ioptci = 0
        iforce_analy = 0

        call set_nparms

        call qmc

        call write_wf(1, -1)
        call write_geometry(-1)

        deallocate (deltap)

        return
    end

    subroutine read_input()

        use contrl, only: nblk
        use optwf_func, only: ifunc_omega, omega
        implicit None

        call p2gtid('optwf:nopt_iter', nopt_iter, 6, 1)
        call p2gtid('optwf:nblk_max', nblk_max, nblk, 1)
        call p2gtfd('optwf:energy_tol', energy_tol, 1.d-3, 1)

        call p2gtfd('optwf:dparm_norm_min', dparm_norm_min, 1.0d0, 1)
        write (6, '(''Starting dparm_norm_min'',g12.4)') dparm_norm_min

        call p2gtfd('optwf:sr_tau', sr_tau, 0.02, 1)
        call p2gtfd('optwf:sr_adiag', sr_adiag, 0.01, 1)
        call p2gtfd('optwf:sr_eps', sr_eps, 0.001, 1)
        call p2gtid('optwf:sr_rescale', i_sr_rescale, 0, 1)

        call p2gtid('optwf:func_omega', ifunc_omega, 0, 1)
        if (ifunc_omega .gt. 0) then
            call p2gtfd('optwf:omega', omega0, 0.d0, 1)
            call p2gtid('optwf:n_omegaf', n_omegaf, nopt_iter, 1)
            call p2gtid('optwf:n_omegat', n_omegat, 0, 1)
            if (n_omegaf + n_omegat .gt. nopt_iter) call fatal_error('SR_OPTWF: n_omegaf+n_omegat > nopt_iter')
            omega = omega0
            write (6, '(/,''SR ifunc_omega: '',i3)') ifunc_omega
            write (6, '(''SR omega: '',f10.5)') omega
            write (6, '(''SR n_omegaf: '',i4)') n_omegaf
            write (6, '(''SR n_omegat: '',i4)') n_omegat
        endif

        call p2gtid('optwf:micro_iter_sr', micro_iter_sr, 1, 1)

        call p2gtid('optgeo:izvzb', izvzb, 0, 1)
        call p2gtid('optwf:sr_rescale', i_sr_rescale, 0, 1)
        write (6, '(/,''SR adiag: '',f10.5)') sr_adiag
        write (6, '(''SR tau:   '',f10.5)') sr_tau
        write (6, '(''SR eps:   '',f10.5)') sr_eps

    end subroutine read_input

    subroutine save_params()
        sr_adiag_sav = sr_adiag
        iforce_analy_sav = iforce_analy
        ioptjas_sav = ioptjas
        ioptorb_sav = ioptorb
        ioptci_sav = ioptci
    end subroutine save_params

    subroutine sr(nparm, deltap, sr_adiag, sr_eps, i)
        ! solve S*deltap=h_sr (call in optwf)
        use sr_mat_n, only: h_sr
        implicit real*8(a - h, o - z)

        integer, intent(in) :: nparm
        real(dp), dimension(:), intent(inout) :: deltap
        real(dp), intent(in) :: sr_adiag
        real(dp), intent(in) :: sr_eps
        integer, intent(inout) :: i

        call sr_hs(nparm, sr_adiag)

        imax = nparm          ! max n. iterations conjugate gradients
        imod = 50             ! inv. freq. of calc. r=b-Ax vs. r=r-alpha q (see pcg)
        do i = 1, nparm
            deltap(i) = 0.d0     ! initial guess of solution
        enddo
        call pcg(nparm, h_sr, deltap, i, imax, imod, sr_eps)
        write (6, *) 'CG iter ', i

        call sr_rescale_deltap(nparm, deltap)

        return

    end subroutine sr

    subroutine check_length_run_sr(iter, increase_nblk, nblk, nblk_max, denergy, denergy_err, energy_err_sav, energy_tol)

        implicit real*8(a - h, o - z)

        ! Increase nblk if near convergence to value needed to get desired statistical error
        increase_nblk = increase_nblk + 1

        ! Increase if subsequent energies are within errorbar
        if (dabs(denergy) .lt. 3*denergy_err .and. energy_tol .gt. 0.d0) then
            nblk_new = nblk*max(1.d0, (energy_err_sav/energy_tol)**2)
            nblk_new = min(nblk_new, nblk_max)
            if (nblk_new .gt. nblk) then
                increase_nblk = 0
                nblk = nblk_new
                write (6, '(''nblk reset to'',i8,9d12.4)') nblk, dabs(denergy), energy_tol
            endif
        endif

        ! Always increase nblk by a factor of 2 every other iteration
        if (increase_nblk .eq. 2 .and. nblk .lt. nblk_max) then
            increase_nblk = 0
            nbkl = 1.2*nblk
            nblk = min(nblk, nblk_max)
            write (6, '(''nblk reset to'',i8,9d12.4)') nblk
        endif

        return
    end

    subroutine sr_hs(nparm, sr_adiag)
        ! <elo>, <o_i>, <elo o_i>, <o_i o_i>; s_diag, s_ii_inv, h_sr

        use mpi
        use sr_mod, only: MOBS
        use csfs, only: nstates
        use mstates_mod, only: MSTATES
        use mpiconf, only: idtask
        use optwf_func, only: ifunc_omega, omega
        use sa_weights, only: weights
        use sr_index, only: jelo, jelo2, jelohfj
        use sr_mat_n, only: elocal, h_sr, jefj, jfj, jhfj, nconf_n, obs, s_diag, s_ii_inv, sr_ho
        use sr_mat_n, only: sr_o, wtg, obs_tot
        use optorb_cblock, only: norbterm

        use method_opt, only: method

        implicit real*8(a - h, o - z)

        real(dp), DIMENSION(:), allocatable :: obs_wtg
        real(dp), DIMENSION(:), allocatable :: obs_wtg_tot

        allocate (obs_wtg(MSTATES))
        allocate (obs_wtg_tot(MSTATES))

        nstates_eff = nstates
        if (method .eq. 'lin_d') nstates_eff = 1

        jwtg = 1
        jelo = 2
        n_obs = 2
        jfj = n_obs + 1
        n_obs = n_obs + nparm
        jefj = n_obs + 1
        n_obs = n_obs + nparm
        jfifj = n_obs + 1
        n_obs = n_obs + nparm

        jhfj = n_obs + 1
        n_obs = n_obs + nparm
        jfhfj = n_obs + 1
        n_obs = n_obs + nparm

        ! for omega functional
        jelo2 = n_obs + 1
        n_obs = n_obs + 1
        jelohfj = n_obs + 1
        n_obs = n_obs + nparm

        if (n_obs .gt. MOBS) call fatal_error('SR_HS LIN: n_obs > MOBS)')

        do k = 1, nparm
            h_sr(k) = 0.d0
            s_ii_inv(k) = 0.d0
        enddo

        nparm_jasci = max(nparm - norbterm, 0)

        do istate = 1, nstates
            obs(jwtg, istate) = 0.d0
            do iconf = 1, nconf_n
                obs(jwtg, istate) = obs(jwtg, istate) + wtg(iconf, istate)
            enddo
            obs_wtg(istate) = obs(jwtg, istate)
        enddo

        call MPI_REDUCE(obs_wtg, obs_wtg_tot, nstates, MPI_REAL8, MPI_SUM, 0, MPI_COMM_WORLD, ier)
        do istate = 1, nstates
            obs_tot(jwtg, istate) = obs_wtg_tot(istate)
        enddo

        do istate = 1, nstates_eff
            do i = 2, n_obs
                obs(i, istate) = 0.d0
            enddo

            ish = (istate - 1)*norbterm
            do iconf = 1, nconf_n
                obs(jelo, istate) = obs(jelo, istate) + elocal(iconf, istate)*wtg(iconf, istate)
                do i = 1, nparm_jasci
                    obs(jfj + i - 1, istate) = obs(jfj + i - 1, istate) + sr_o(i, iconf)*wtg(iconf, istate)
                    obs(jefj + i - 1, istate) = obs(jefj + i - 1, istate) + elocal(iconf, istate)*sr_o(i, iconf)*wtg(iconf, istate)
                    obs(jfifj + i - 1, istate) = obs(jfifj + i - 1, istate) + sr_o(i, iconf)*sr_o(i, iconf)*wtg(iconf, istate)
                enddo
                do i = nparm_jasci + 1, nparm
                    obs(jfj + i - 1, istate) = obs(jfj + i - 1, istate) + sr_o(ish + i, iconf)*wtg(iconf, istate)
               obs(jefj + i - 1, istate) = obs(jefj + i - 1, istate) + elocal(iconf, istate)*sr_o(ish + i, iconf)*wtg(iconf, istate)
              obs(jfifj + i - 1, istate) = obs(jfifj + i - 1, istate) + sr_o(ish + i, iconf)*sr_o(ish + i, iconf)*wtg(iconf, istate)
                enddo
            enddo

            call MPI_REDUCE(obs(1, istate), obs_tot(1, istate), n_obs, MPI_REAL8, MPI_SUM, 0, MPI_COMM_WORLD, ier)
        enddo

        if (idtask .eq. 0) then
            do istate = 1, nstates_eff
                wts = weights(istate)
                if (method .eq. 'lin_d') wts = 1.d0

                do i = 2, n_obs
                    obs_tot(i, istate) = obs_tot(i, istate)/obs_tot(1, istate)
                enddo

                do k = 1, nparm
                    aux = obs_tot(jfifj + k - 1, istate) - obs_tot(jfj + k - 1, istate)*obs_tot(jfj + k - 1, istate)
                    s_diag(k, istate) = aux*sr_adiag
                    s_ii_inv(k) = s_ii_inv(k) + wts*(aux + s_diag(k, istate))
                    h_sr(k) = h_sr(k) - 2*wts*(obs_tot(jefj + k - 1, istate) - obs_tot(jfj + k - 1, istate)*obs_tot(jelo, istate))
                enddo
            enddo

            smax = 0.d0
            do k = 1, nparm
                if (s_ii_inv(k) .gt. smax) smax = s_ii_inv(k)
            enddo
            write (6, '(''max S diagonal element '',t41,d8.2)') smax

            kk = 0
            do k = 1, nparm
                if (s_ii_inv(k)/smax .gt. eps_eigval) then
                    kk = kk + 1
                    s_ii_inv(k) = 1.d0/s_ii_inv(k)
                else
                    s_ii_inv(k) = 0.d0
                endif
            enddo
            write (6, '(''nparm, non-zero S diag'',t41,2i5)') nparm, kk

        endif

        if (method .eq. 'sr_n' .and. i_sr_rescale .eq. 0 .and. izvzb .eq. 0 .and. ifunc_omega .eq. 0) return

        if (method .ne. 'sr_n') then
            s_diag(1, 1) = sr_adiag !!!

            do k = 1, nparm
                h_sr(k) = -0.5d0*h_sr(k)
            enddo
        elseif (ifunc_omega .ne. 0) then
            s_diag(1, 1) = sr_adiag !!!
        endif

        if (n_obs .gt. MOBS) call fatal_error('SR_HS LIN: n_obs > MOBS)')

        do i = jhfj, n_obs
            obs(i, 1) = 0.d0
        enddo
        do iconf = 1, nconf_n
            obs(jelo2, 1) = obs(jelo2, 1) + elocal(iconf, 1)*elocal(iconf, 1)*wtg(iconf, 1)
            do i = 1, nparm
                obs(jhfj + i - 1, 1) = obs(jhfj + i - 1, 1) + sr_ho(i, iconf)*wtg(iconf, 1)
                obs(jfhfj + i - 1, 1) = obs(jfhfj + i - 1, 1) + sr_o(i, iconf)*sr_ho(i, iconf)*wtg(iconf, 1)
                obs(jelohfj + i - 1, 1) = obs(jelohfj + i - 1, 1) + elocal(iconf, 1)*sr_ho(i, iconf)*wtg(iconf, 1)
            enddo
        enddo

        nreduce = n_obs - jhfj + 1
        call MPI_REDUCE(obs(jhfj, 1), obs_tot(jhfj, 1), nreduce, MPI_REAL8, MPI_SUM, 0, MPI_COMM_WORLD, j)

        if (idtask .eq. 0) then
            do i = jhfj, n_obs
                obs_tot(i, 1) = obs_tot(i, 1)/obs_tot(1, 1)
            enddo

            if (ifunc_omega .eq. 1) then
                ! variance
                var = obs_tot(jelo2, 1) - obs_tot(jelo, 1)**2
                do k = 1, nparm
                h_sr(k) = -2*(obs_tot(jelohfj + k - 1, 1) - (obs_tot(jhfj + k - 1, 1) - obs_tot(jefj + k - 1, 1))*obs_tot(jelo, 1) &
                                  - obs_tot(jfj + k - 1, 1)*obs_tot(jelo2, 1) &
                                  - 2*obs_tot(jelo, 1)*(obs_tot(jefj + k - 1, 1) - obs_tot(jfj + k - 1, 1)*obs_tot(jelo, 1)))
                enddo
            elseif (ifunc_omega .eq. 2) then
                ! variance with fixed average energy (omega)
                var = omega*omega + obs_tot(jelo2, 1) - 2*omega*obs_tot(jelo, 1)
                dum1 = -2
                do k = 1, nparm
                    h_sr(k) = dum1*(omega*omega*obs_tot(jfj + k - 1, 1) + obs_tot(jelohfj + k - 1, 1) &
                                    - omega*(obs_tot(jhfj + k - 1, 1) + obs_tot(jefj + k - 1, 1)) &
                                    - var*obs_tot(jfj + k - 1, 1))
                    ! adding a term which intergrates to zero
                    !    &     -(obs_tot(jelo,1)-omega)*(obs_tot(jhfj+k-1,1)-obs_tot(jefj+k-1,1)))
                enddo

            elseif (ifunc_omega .eq. 3 .and. method .eq. 'sr_n') then
                !  Neuscamman's functional
                den = omega*omega + obs_tot(jelo2, 1) - 2*omega*obs_tot(jelo, 1)
                dum1 = -2/den
                dum2 = (omega - obs_tot(jelo, 1))/den
                do k = 1, nparm
                    h_sr(k) = dum1*(omega*obs_tot(jfj + k - 1, 1) - obs_tot(jefj + k - 1, 1) &
                                    - dum2*(omega*omega*obs_tot(jfj + k - 1, 1) + obs_tot(jelohfj + k - 1, 1) &
                                            - omega*(obs_tot(jhfj + k - 1, 1) + obs_tot(jefj + k - 1, 1))))
                enddo
            endif

        endif

        return
    end

    subroutine sr_rescale_deltap(nparm, deltap)

        use mpi
        use mpiconf, only: idtask
        use sr_mat_n, only: jefj, jfj, jhfj
        use sr_mat_n, only: obs_tot
        use sr_index, only: jelo, jelo2, jelohfj !< are they needed ?

        implicit real*8(a - h, o - z)

        integer, intent(in)                     :: nparm
        real(dp), dimension(:), intent(inout)   :: deltap

        if (i_sr_rescale .eq. 0) return

        jwtg = 1
        jelo = 2
        n_obs = 2
        jfj = n_obs + 1
        n_obs = n_obs + nparm
        jefj = n_obs + 1
        n_obs = n_obs + nparm
        jfifj = n_obs + 1
        n_obs = n_obs + nparm

        jhfj = n_obs + 1
        n_obs = n_obs + nparm
        jfhfj = n_obs + 1
        n_obs = n_obs + nparm

        jelo2 = n_obs + 1
        n_obs = n_obs + 1
        jelohfj = n_obs + 1
        n_obs = n_obs + nparm

        if (idtask .eq. 0) then
        do i = 1, nparm
            write (6, *) 'CIAO', obs_tot(jfhfj + i - 1, 1)/obs_tot(jfifj + i - 1, 1), obs_tot(jelo, 1), &
                obs_tot(jfhfj + i - 1, 1)/obs_tot(jfifj + i - 1, 1) - obs_tot(jelo, 1)
            deltap(i) = deltap(i)/(obs_tot(jfhfj + i - 1, 1)/obs_tot(jfifj + i - 1, 1) - obs_tot(jelo, 1))
        enddo
        endif

        call MPI_BCAST(deltap, nparm, MPI_REAL8, 0, MPI_COMM_WORLD, j)

        return
    end subroutine sr_rescale_deltap

    subroutine forces_zvzb(nparm)

        use mpi
        use precision_kinds, only: dp
        use sr_mod, only: MPARM
        use atom, only: ncent

        use force_fin, only: da_energy_ave
        use force_mat_n, only: force_o
        use mpiconf, only: idtask
        use sr_mat_n, only: elocal, jefj, jfj, jhfj, nconf_n, obs, sr_ho
        use sr_mat_n, only: sr_o, wtg
        use sr_index, only: jelo

        implicit real*8(a - h, o - z)

        integer, parameter :: MTEST = 1500
        real(dp), dimension(:, :), allocatable :: cloc
        real(dp), dimension(:, :), allocatable :: c
        real(dp), dimension(:), allocatable :: oloc
        real(dp), dimension(:), allocatable :: o
        real(dp), dimension(:), allocatable :: p
        real(dp), dimension(:), allocatable :: tmp
        real(dp), dimension(:), allocatable :: work
        integer, dimension(:), allocatable :: ipvt

        allocate (cloc(MTEST, MTEST))
        allocate (c(MTEST, MTEST))
        allocate (oloc(MPARM))
        allocate (o(MPARM))
        allocate (p(MPARM))
        allocate (tmp(MPARM))
        allocate (work(MTEST))
        allocate (ipvt(MTEST))

        if (nparm .gt. MTEST) stop 'MPARM>MTEST'

        jwtg = 1
        jelo = 2
        n_obs = 2
        jfj = n_obs + 1
        n_obs = n_obs + nparm
        jefj = n_obs + 1
        n_obs = n_obs + nparm
        jfifj = n_obs + 1
        n_obs = n_obs + nparm

        jhfj = n_obs + 1
        n_obs = n_obs + nparm
        jfhfj = n_obs + 1
        n_obs = n_obs + nparm

        do i = 1, nparm
            do j = i, nparm
                cloc(i, j) = 0.d0
            enddo
        enddo

        do l = 1, nconf_n
            do i = 1, nparm
                tmp(i) = (sr_ho(i, l) - elocal(l, 1)*sr_o(i, l))*sqrt(wtg(l, 1))
            enddo

            do k = 1, nparm
                do j = k, nparm
                    cloc(k, j) = cloc(k, j) + tmp(k)*tmp(j)
                enddo
            enddo
        enddo

        call MPI_REDUCE(cloc, c, MTEST*nparm, MPI_REAL8, MPI_SUM, 0, MPI_COMM_WORLD, i)

        if (idtask .eq. 0) then

            wtoti = 1.d0/obs(1, 1)
            do i = 1, nparm
                dum = (obs(jhfj + i - 1, 1) - obs(jefj + i - 1, 1))
                c(i, i) = c(i, i)*wtoti - dum*dum
                do j = i + 1, nparm
                    c(i, j) = c(i, j)*wtoti - dum*(obs(jhfj + j - 1, 1) - obs(jefj + j - 1, 1))
                    c(j, i) = c(i, j)
                enddo
            enddo

            call dgetrf(nparm, nparm, c, MTEST, ipvt, info)
            if (info .gt. 0) then
                write (6, '(''MATINV: u(k,k)=0 with k= '',i5)') info
                call fatal_error('MATINV: info ne 0 in dgetrf')
            endif
            call dgetri(nparm, c, MTEST, ipvt, work, MTEST, info)

            do iparm = 1, nparm
                tmp(iparm) = obs(jhfj + iparm - 1, 1) - obs(jefj + iparm - 1, 1)
            enddo

        endif

        energy_tot = obs(2, 1)

        call MPI_BCAST(energy_tot, 1, MPI_REAL8, 0, MPI_COMM_WORLD, j)

        ia = 0
        ish = 3*ncent
        do icent = 1, ncent
            write (6, '(''FORCE before'',i4,3e15.7)') icent, (da_energy_ave(k, icent), k=1, 3)
            do k = 1, 3
                ia = ia + 1

                do i = 1, nparm
                    oloc(i) = 0.d0
                    do l = 1, nconf_n
                        oloc(i) = oloc(i) + (sr_ho(i, l) - elocal(l, 1)*sr_o(i, l)) &
                                  *(force_o(ia + ish, l) - 2*energy_tot*force_o(ia, l))*wtg(l, 1)
                    enddo
                enddo

                call MPI_REDUCE(oloc, o, nparm, MPI_REAL8, MPI_SUM, 0, MPI_COMM_WORLD, i)

                if (idtask .eq. 0) then

                    do i = 1, nparm
                        o(i) = o(i)*wtoti - (obs(jhfj + i - 1, 1) - obs(jefj + i - 1, 1))*da_energy_ave(k, icent)
                    enddo

                    do iparm = 1, nparm
                        p(iparm) = 0.d0
                        do jparm = 1, nparm
                            p(iparm) = p(iparm) + c(iparm, jparm)*o(jparm)
                        enddo
                        p(iparm) = -0.5*p(iparm)
                    enddo

                    force_tmp = da_energy_ave(k, icent)
                    do iparm = 1, nparm
                        force_tmp = force_tmp + p(iparm)*tmp(iparm)
                    enddo
                    da_energy_ave(k, icent) = force_tmp

                endif
            enddo
            write (6, '(''FORCE after '',i4,3e15.7)') icent, (da_energy_ave(k, icent), k=1, 3)
        enddo

        return
    end subroutine forces_zvzb

end module optwf_sr_mod
