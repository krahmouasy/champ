      module dmc_ps_mov1
      contains

      subroutine dmc_ps(lpass,irun)

      use age,     only: iage,ioldest,ioldestmx
      use averages, only: average
      use branch,  only: eest,esigma,eigv,eold,ff,fprod,nwalk,pwt,wdsumo
      use branch,  only: wgdsumo,wt,wthist
      use casula,  only: i_vpsp,icasula
      use config,  only: psido_dmc,psijo_dmc,vold_dmc,xold_dmc
      use const,   only: etrial,esigmatrial
      use constants, only: hb
      use contrl_file, only: ounit
      use contrldmc, only: iacc_rej,icross,icut_br,icut_e,idmc,ipq,limit_wt_dmc
      use contrldmc, only: nfprod,rttau,tau
      use control, only: ipr
      use control_dmc, only: dmc_irstar,dmc_nconf
      use da_energy_now, only: da_energy,da_psi
      use derivest, only: derivsum
      use determinante_mod, only: compute_determinante_grad
      use detsav_mod, only: detsav
      use distances_mod, only: distances,distancese_restore
      use estcum,  only: ipass
      use estsum,  only: efsum1,egsum1,esum1_dmc,pesum_dmc
      use estsum,  only: tausum,tpbsum_dmc,wfsum1,wgsum1
      use estsum,  only: wsum1
      use force_analytic, only: force_analy_sum, force_analy_save
      use force_analytic, only: force_analy_vd
      use force_pth, only: PTH
      use gauss_mod, only: gauss
      use general, only: write_walkalize
      use hpsi_mod, only: hpsi
      use hpsiedmc, only: psiedmc
      use inputflags, only: eps_node_cutoff,icircular
      use inputflags, only: node_cutoff
      use jacobsave, only: ajacob,ajacold
      use jassav_mod, only: jassav
      use mmpol_dmc, only: mmpol_save,mmpol_sum
      use multideterminant_mod, only: update_ymat
      use multideterminant_tmove_mod, only: multideterminant_tmove
      use multiple_geo, only: istrech,itausec,nforce,nwprod
      use m_force_analytic, only: iforce_analy
      use nodes_distance_mod, only: nodes_distance,rnorm_nodes_num
      use nonloc_grid_mod, only: nonloc_grid,t_vpsp_get,t_vpsp_sav
      use optci_mod, only: optci_sum
      use optjas_mod, only: optjas_sum
      use optorb_f_mod, only: optorb_sum
      use optwf_handle_wf, only: optwf_store
      use optx_jas_ci, only: optx_jas_ci_sum
      use optx_jas_orb, only: optx_jas_orb_sum
      use optx_orb_ci, only: optx_orb_ci_sum
      use pathak_mod, only: ipathak, eps_pathak, pold, pnew, pathak
      use pcm_dmc, only: pcm_save,pcm_sum
      use precision_kinds, only: dp
      use prop_dmc, only: prop_save_dmc,prop_sum_dmc
      use random_mod, only: random_dp
      use splitj_mod, only: splitj
      use stats, only: acc,dfus2ac,dfus2un,nacc,nodecr
      use stats, only: trymove
      use strech_mod, only: strech
      use system,  only: cent,nelec,nup, ncent
      use velratio, only: fratio
      use vd_mod, only: dmc_ivd
      use vmc_mod, only: delri,nrad
      use walksav_det_mod, only: walksav_det,walkstrdet
      use walksav_jas_mod, only: walksav_jas,walkstrjas

      implicit none

      integer :: i, iaccept, iel, ic, iph
      integer :: iflag_dn, iflag_up, ifr, ii
      integer :: imove, imove_dn, imove_up, ipmod, ipmod2, iw, irun
      integer :: iwmod, j, jel, k, lpass
      integer :: ncall, ncount_casula, nmove_casula
      integer, dimension(nelec) :: itryo
      integer, dimension(nelec) :: itryn
      integer, dimension(nelec) :: iacc_elec
      real(dp) :: d2n, den, deo, dfus
      real(dp) :: dfus2n, dfus2o, distance_node, distance_node_ratio2
      real(dp) :: dmin1, dr2, drifdif, drifdifgfunc
      real(dp) :: drifdifr, drifdifs, drift, dwt
      real(dp) :: ecuto, ecutn
      real(dp) :: dx, e_cutoff, dwt_cutoff, ekino(1), enew(1)
      real(dp) :: ewtn, ewto, expon, ffi
      real(dp) :: ffn, fration, ginv
      real(dp) :: p, pen, pp, psi2savo
      real(dp) :: psidn(1), psijn(1), q, r2n, r2o
      real(dp) :: rminn, rmino, rnorm_nodes, rnorm_nodes_new
      real(dp) :: rnorm_nodes_old, ro, taunow
      real(dp) :: tauprim, tratio, v2new, v2old
      real(dp) :: v2sumn, v2sumo, vav2sumn, vav2sumo
      real(dp) :: vavvn, vavvo, vavvt, wtg(1), wtg_sqrt(1)
      real(dp) :: wtg_derivsum1, wtnow

      real(dp), dimension(3, nelec) :: xstrech
      real(dp), dimension(3) :: xnew
      real(dp), dimension(3, nelec) :: vnew
      real(dp), dimension(3) :: xbac
      real(dp), dimension(nelec) :: unacp
      real(dp), dimension(10, 3, ncent) :: deriv_esum
      real(dp), dimension(3, ncent) :: deriv_energy_new

      real(dp), parameter :: zero = 0.d0
      real(dp), parameter :: one = 1.d0
      real(dp), parameter :: two = 2.d0
      real(dp), parameter :: half = .5d0
      real(dp), parameter :: adrift = 0.5d0
      real(dp), parameter :: small = 1.d-10
      real(dp), parameter :: zero_1d(1) = (/0.d0/)

      data ncall /0/

      eps_node_cutoff=eps_node_cutoff*sqrt(tau)
      e_cutoff=0.2d0*sqrt(nelec/tau)

      if(idmc.lt.0) then
        expon=1
        dwt=1
      endif
! Undo products
      ipmod=mod(ipass,nfprod)
      ipmod2=mod(ipass+1,nfprod)
      ginv=min(1.d0,tau)
      ffn=eigv*(wdsumo/dmc_nconf)**ginv
      ffi=one/ffn
      fprod=fprod*ffn/ff(ipmod)
      ff(ipmod)=ffn

! Undo weights
      iwmod=mod(ipass,nwprod)

! Store (well behaved velocity/velocity)
      if(ncall.eq.0.and.dmc_irstar.eq.0) then
        do ifr=1,nforce
          do iw=1,nwalk
            tratio = one
            call dmc_eloc_cutoff(vold_dmc(1,1,iw,ifr), adrift, tratio, vav2sumo, v2sumo)
            fratio(iw,ifr)=dsqrt(vav2sumo/v2sumo)
          enddo
        enddo
        ncall=ncall+1
      endif

      imove=0
      ioldest=0
      ncount_casula=0
      nmove_casula=0
      do iw=1,nwalk
! Loop over primary walker

        call distances(0,xold_dmc(1,1,iw,1))
! Set nuclear coordinates and n-n potential (0 flag = no strech e-coord)
        if(nforce.gt.1) &
        call strech(xold_dmc(1,1,iw,1),xold_dmc(1,1,iw,1),ajacob,1,0)

        call walkstrdet(iw)
        call walkstrjas(iw)

! Sample Green function for forward move
        dfus2ac=zero
        dfus2un=zero
        drifdif=zero
        iaccept=0

        if(icasula.eq.3) then
          imove_up=0
          imove_dn=0
          do i=1,nelec
            imove=0
            call nonloc_grid(i,iw,xnew,psido_dmc(iw,1),imove)
            ncount_casula=ncount_casula+1

            if(imove.gt.0) then
              write(ounit,*) 'icasula3', imove
              if(i.le.nup) then
                imove_up=1
               else
                imove_dn=1
              endif
              call psiedmc(i,iw,xnew,psidn,psijn,0)
              nmove_casula=nmove_casula+1

              iaccept=1
              iage(iw)=0
              do k=1,3
                xold_dmc(k,i,iw,1)=xnew(k)
              enddo
              psido_dmc(iw,1)=psidn(1)
              psijo_dmc(iw,1)=psijn(1)
              call jassav(i,0)
              call detsav(i,0)
             else
              call distancese_restore(i)
            endif
            if(imove_up.eq.1.and.i.eq.nup) call update_ymat(i)
            if(imove_dn.eq.1.and.i.eq.nelec) call update_ymat(i)
          enddo
          if(nforce.gt.1.and.istrech.gt.0) then
            do ifr=1,nforce
              call strech(xold_dmc(1,1,iw,1),xstrech,ajacob,ifr,1)
              do k=1,3
                do j=1,nelec
                  xold_dmc(k,j,iw,ifr)=xstrech(k,j)
                enddo
              enddo
            enddo
          endif
        endif

        dwt=1

!     to initilialize pp
        pp=1.d0
        do i=1,nelec

          if(i.le.nup) then
            iflag_up=2
            iflag_dn=3
           else
            iflag_up=3
            iflag_dn=2
          endif
          call compute_determinante_grad(i,psido_dmc(iw,1),psido_dmc(iw,1),psijo_dmc(iw,1),vold_dmc(1,i,iw,1),1)

! Use more accurate formula for the drift
          v2old=vold_dmc(1,i,iw,1)**2+vold_dmc(2,i,iw,1)**2+vold_dmc( 3,i,iw,1)**2
! Tau primary -> tratio=one
          vavvt=(dsqrt(one+two*adrift*v2old*tau)-one)/(adrift*v2old)

          dr2=zero
          dfus2o=zero
          do k=1,3
            drift=vavvt*vold_dmc(k,i,iw,1)
            dfus=gauss()*rttau
            dx=drift+dfus
            dr2=dr2+dx**2
            dfus2o=dfus2o+dfus**2
            xnew(k)=xold_dmc(k,i,iw,1)+dx
          enddo

          if(ipr.ge.1) then
            write(ounit,'(''xold_dmc'',2i4,9f8.5)') iw,i,(xold_dmc(k,i,iw,1),k=1,3)
            write(ounit,'(''vold_dmc'',2i4,9f8.5)') iw,i,(vold_dmc(k,i,iw,1),k=1,3)
            write(ounit,'(''psido_dmc'',2i4,9f8.5)') iw,i,psido_dmc(iw,1)
            write(ounit,'(''xnewdr'',2i4,9f8.5)') iw,i,(xnew(k),k=1,3)
          endif

! calculate psi and velocity at new configuration
          call psiedmc(i,iw,xnew,psidn,psijn,0)

          call compute_determinante_grad(i,psidn(1),psidn,psijn,vnew(1,i),0)

          distance_node_ratio2=1.d0
          if(node_cutoff.gt.0) then
            do jel=1,nup
              if(jel.ne.i) call compute_determinante_grad(jel,psidn(1),psidn,psijn,vnew(1,jel),iflag_up)
            enddo

            do jel=nup+1,nelec
              if(jel.ne.i) call compute_determinante_grad(jel,psidn(1),psidn,psijn,vnew(1,jel),iflag_dn)
            enddo

            call nodes_distance(vold_dmc(1,1,iw,1),distance_node,1)
            rnorm_nodes_old=rnorm_nodes_num(distance_node,eps_node_cutoff)/distance_node

            call nodes_distance(vnew,distance_node,0)
            rnorm_nodes_new=rnorm_nodes_num(distance_node,eps_node_cutoff)/distance_node
            distance_node_ratio2=(rnorm_nodes_new/rnorm_nodes_old)**2
          endif

! Check for node crossings
          if(psidn(1)*psido_dmc(iw,1).le.zero) then
            nodecr=nodecr+1
            if(icross.le.0) then
              p=zero
              goto 160
            endif
          endif

! Calculate Green function for the reverse move

          v2new=vnew(1,i)**2+vnew(2,i)**2+vnew(3,i)**2
          vavvt=(dsqrt(one+two*adrift*v2new*tau)-one)/(adrift*v2new)

          dfus2n=zero
          do k=1,3
            drift=vavvt*vnew(k,i)
            xbac(k)=xnew(k)+drift
            dfus=xbac(k)-xold_dmc(k,i,iw,1)
            dfus2n=dfus2n+dfus**2
          enddo

          if(ipr.ge.1) then
            write(ounit,'(''xold_dmc'',9f10.6)')(xold_dmc(k,i,iw,1),k=1,3), &
            (xnew(k),k=1,3), (xbac(k),k=1,3)
            write(ounit,'(''dfus2o'',9f10.6)')dfus2o,dfus2n, &
            psido_dmc(iw,1),psidn,psijo_dmc(iw,1),psijn(1)
          endif

          p=(psidn(1)/psido_dmc(iw,1))**2*exp(2*(psijn(1)-psijo_dmc(iw,1)))* &
          exp((dfus2o-dfus2n)/(two*tau))*distance_node_ratio2

          if(ipr.ge.1) write(ounit,'(''p'',11f10.6)') &
          p,(psidn/psido_dmc(iw,1))**2*exp(2*(psijn(1)-psijo_dmc(iw,1))), &
          exp((dfus2o-dfus2n)/(two*tau)),psidn,psido_dmc(iw,1), &
               psijn(1),psijo_dmc(iw,1),dfus2o,dfus2n


!          if(ipr.ge.1) write(ounit,'(''parts p'',11f10.6)')
!     &         psidn(1), psijn, psido_dmc(iw,1), dfus2o, dfus2n, distance_node_ratio2

! Way to cure persistent configurations; not needed if itau_eff <=0; in practice never needed
          if(iage(iw).gt.50) p=p*1.1d0**(iage(iw)-50)

          pp=pp*p
          p=dmin1(one,p)
      160     q=one-p

          acc=acc+p
          trymove=trymove+1
          dfus2ac=dfus2ac+p*dfus2o
          dfus2un=dfus2un+dfus2o

! Calculate density and moments of r for primary walk
          r2o=zero
          r2n=zero
          rmino=zero
          rminn=zero
          do k=1,3
            r2o=r2o+xold_dmc(k,i,iw,1)**2
            r2n=r2n+xnew(k)**2
            rmino=rmino+(xold_dmc(k,i,iw,1)-cent(k,1))**2
            rminn=rminn+(xnew(k)-cent(k,1))**2
          enddo
          rmino=sqrt(rmino)
          rminn=sqrt(rminn)

! If we are using weights rather than accept/reject
          if(iacc_rej.le.0) then
            p=one
            q=zero
          endif

          iacc_elec(i)=0
          if(random_dp().lt.p) then
            iaccept=1
            nacc=nacc+1
            iacc_elec(i)=1
            if(ipq.le.0) p=one

            iage(iw)=0
            do k=1,3
              drifdif=drifdif+(xold_dmc(k,i,iw,1)-xnew(k))**2
              xold_dmc(k,i,iw,1)=xnew(k)
            enddo
            psido_dmc(iw,1)=psidn(1)
            psijo_dmc(iw,1)=psijn(1)
            call jassav(i,0)
            call detsav(i,0)

           else
            if(ipq.le.0) p=zero
            call distancese_restore(i)
          endif
          q=one-p

! Calculate moments of r and save rejection probability for primary walk
          unacp(i)=q

          call update_ymat(i)

        enddo

! Effective tau for branching
        tauprim=tau*dfus2ac/dfus2un

        do ifr=1,nforce

          if(ifr.eq.1) then
! Primary configuration
            if(icasula.lt.0) i_vpsp=icasula
            drifdifr=one
            if(nforce.gt.1) &
            call strech(xold_dmc(1,1,iw,1),xold_dmc(1,1,iw,1),ajacob,1,0)
            call hpsi(xold_dmc(1,1,iw,1),psidn(1),psijn,ekino,enew,ipass,1)

            if(irun.eq.1) then
               wtg_sqrt(1)=dsqrt(wtg(1))
               call optwf_store(lpass,wtg(1),wtg_sqrt(1),psidn(1),enew(1))
            endif

            deriv_energy_new=da_energy

            call walksav_det(iw)
            call walksav_jas(iw)
            if(icasula.lt.0) call multideterminant_tmove(psidn(1),0)
!           call t_vpsp_sav(iw)
            call t_vpsp_sav
            i_vpsp=0
            rnorm_nodes=1.d0
            if(node_cutoff.gt.0) then
              call nodes_distance(vold_dmc(1,1,iw,1),distance_node,1)
              rnorm_nodes=rnorm_nodes_num(distance_node,eps_node_cutoff)/distance_node
            endif
           else
! Secondary configuration
            if(istrech.eq.0) then
              call strech(xold_dmc(1,1,iw,ifr),xold_dmc(1,1,iw,ifr),ajacob,ifr,0)
              drifdifr=one
! No streched positions for electrons
              do i=1,nelec
                do k=1,3
                  xold_dmc(k,i,iw,ifr)=xold_dmc(k,i,iw,1)
                enddo
              enddo
              ajacold(iw,ifr)=one
             else
! Compute streched electronic positions for all nucleus displacement
              call strech(xold_dmc(1,1,iw,1),xstrech,ajacob,ifr,1)
              drifdifs=zero
              do i=1,nelec
                do k=1,3
                  drifdifs=drifdifs+(xstrech(k,i)-xold_dmc(k,i,iw,ifr))**2
                  xold_dmc(k,i,iw,ifr)=xstrech(k,i)
                enddo
              enddo
              ajacold(iw,ifr)=ajacob
              if(drifdif.eq.0.d0) then
                drifdifr=one
               else
                drifdifr=drifdifs/drifdif
              endif
            endif
            if(icasula.lt.0) i_vpsp=icasula
            call hpsi(xold_dmc(1,1,iw,ifr),psidn,psijn,ekino,enew,ipass,ifr)
            i_vpsp=0
          endif

          do i=1,nelec
              call compute_determinante_grad(i,psidn(1),psidn,psijn,vold_dmc(1,i,iw,ifr),1)
          enddo

          tratio=one
          if(ifr.gt.1.and.itausec.eq.1) tratio=drifdifr
          call dmc_eloc_cutoff(vold_dmc(1,1,iw,ifr), adrift, tratio, vav2sumn, v2sumn)

          fration=dsqrt(vav2sumn/v2sumn)

          taunow=tauprim*drifdifr

          if(ipr.ge.1)write(ounit,'(''wt'',9f10.5)') wt(iw),etrial,eest

          deo=eest-eold(iw,ifr)
          den=eest-enew(1)
          ecuto=min(e_cutoff,dabs(deo))
          ecutn=min(e_cutoff,dabs(den))
          if(icut_e.eq.0) then
            ewto=eest-(eest-eold(iw,ifr))*fratio(iw,ifr)
            ewtn=eest-(eest-enew(1))*fration
           else
            ewto=eest-sign(1.d0,deo)*ecuto
            ewtn=eest-sign(1.d0,den)*ecutn
          endif

          if(idmc.gt.0) then
            expon=(etrial-half*(ewto+ewtn))*taunow
            if(icut_br.le.0) then
              dwt=dexp(expon)
             else
              dwt=0.5d0+1/(1+exp(-4*expon))
            endif
          endif

! Limit the weights for LA
          if(limit_wt_dmc.gt.0) then
            dwt_cutoff=exp((etrial-eest+limit_wt_dmc*esigma/rttau)*tau)
            if(dwt.gt.dwt_cutoff) dwt=dwt_cutoff
          endif

! If we are using weights rather than accept/reject
          if(iacc_rej.eq.0) dwt=dwt*pp

! Exercise population control if dmc or vmc with weights
          if(idmc.gt.0.or.iacc_rej.eq.0) dwt=dwt*ffi

! Set weights and product of weights over last nwprod steps
          if(ifr.eq.1) then

            wt(iw)=wt(iw)*dwt
            wtnow=wt(iw)
            pwt(iw,ifr)=pwt(iw,ifr)+log(dwt)-wthist(iw,iwmod,ifr)
            wthist(iw,iwmod,ifr)=dlog(dwt)

           elseif(ifr.gt.1) then

            pwt(iw,ifr)=pwt(iw,ifr)+dlog(dwt)-wthist(iw,iwmod,ifr)
            wthist(iw,iwmod,ifr)=dlog(dwt)
            wtnow=wt(iw)*dexp(pwt(iw,ifr)-pwt(iw,1))

          endif

          wtnow=wtnow/rnorm_nodes**2

          if(ipr.ge.1)write(ounit,'(''eold,enew,wt'',9f10.5)') &
          eold(iw,ifr),enew,wtnow

          if(idmc.gt.0) then
            wtg=wtnow*fprod
           else
            wtg=wtnow
          endif
          tausum(ifr)=tausum(ifr)+wtg(1)*taunow

          if(ipr.gt.5.and.dabs((enew(1)-etrial)/etrial).gt.0.2d+0) then
           write(18,'(i6,f8.2,2d10.2,(8f8.4))') ipass,  &
            enew(1)-etrial,psidn,psijn(1),(xnew(ii),ii=1,3)
          endif

          if(ipr.gt.5.and.wt(iw).gt.3) write(18,'(i6,i4,3f8.2,30f8.4)') ipass,iw, &
            wt(iw),enew(1)-etrial,eold(iw,ifr)-etrial,(xnew(ii),ii=1,3)

          eold(iw,ifr)=enew(1)
          psido_dmc(iw,ifr)=psidn(1)
          psijo_dmc(iw,ifr)=psijn(1)
          fratio(iw,ifr)=fration
          call prop_save_dmc(iw)
          call pcm_save(iw)
          call mmpol_save(iw)
          call force_analy_save

          if(ifr.eq.1) then
            if(iaccept.eq.0) then
              iage(iw)=iage(iw)+1
              ioldest=max(ioldest,iage(iw))
              ioldestmx=max(ioldestmx,iage(iw))
            endif

            psi2savo=2*(dlog(dabs(psido_dmc(iw,1)))+psijo_dmc(iw,1))

            wsum1(ifr)=wsum1(ifr)+wtnow
            esum1_dmc(ifr)=esum1_dmc(ifr)+wtnow*eold(iw,ifr)
            pesum_dmc(ifr)=pesum_dmc(ifr)+wtg(1)*(eold(iw,ifr)-ekino(1))
            tpbsum_dmc(ifr)=tpbsum_dmc(ifr)+wtg(1)*ekino(1)

            if(iforce_analy.eq.1) then
              if (ipathak.gt.0) then
                call nodes_distance(vold_dmc(1,1,iw,ifr),distance_node,1)
                do iph=1,PTH
                  call pathak(distance_node,pnew(iph),eps_pathak(iph))
                enddo
              endif
              if (dmc_ivd.gt.0) then
                call force_analy_vd(ecutn, ecuto, e_cutoff, iw, iwmod)
              endif

              do iph=1,PTH
                do ic=1,ncent
                  do k=1,3
                    if (ipathak.gt.0) then
                      derivsum(1,k,ic,iph)=derivsum(1,k,ic,iph)+wtg(1)*da_energy(k,ic)*pnew(iph)
                      derivsum(2,k,ic,iph)=derivsum(2,k,ic,iph)+wtg(1)*eold(iw,1)*da_psi(k,ic)*pnew(iph)
                      derivsum(3,k,ic,iph)=derivsum(3,k,ic,iph)+wtg(1)*da_psi(k,ic)*pnew(iph)
                    else
                      derivsum(1,k,ic,iph)=derivsum(1,k,ic,iph)+wtg(1)*da_energy(k,ic)
                      derivsum(2,k,ic,iph)=derivsum(2,k,ic,iph)+wtg(1)*eold(iw,1)*da_psi(k,ic)
                      derivsum(3,k,ic,iph)=derivsum(3,k,ic,iph)+wtg(1)*da_psi(k,ic)
                    endif
                  enddo
                enddo
              enddo

            endif

            call prop_sum_dmc(0.d0,wtg(1),iw)
            call pcm_sum(0.d0,wtg(1),iw)
            call mmpol_sum(0.d0,wtg(1),iw)
            call force_analy_sum(wtg(1),0.d0,eold(iw,1),0.0d0)

            call optjas_sum(wtg,zero_1d,eold(iw,1),eold(iw,1),0)
            call optorb_sum(wtg,zero_1d,eold(iw,1),eold(iw,1),0)
            call optci_sum(wtg(1),0.d0,eold(iw,1),eold(iw,1))

            call optx_jas_orb_sum(wtg,zero_1d,0)
            call optx_jas_ci_sum(wtg(1),0.d0,eold(iw,1),eold(iw,1))
            call optx_orb_ci_sum(wtg(1),0.d0)

          else

            ro=ajacold(iw,ifr)*psido_dmc(iw,ifr)**2*exp(2*psijo_dmc(iw,ifr)-psi2savo)

            wsum1(ifr)=wsum1(ifr)+wtnow*ro
            esum1_dmc(ifr)=esum1_dmc(ifr)+wtnow*eold(iw,ifr)*ro
            pesum_dmc(ifr)=pesum_dmc(ifr)+wtg(1)*(eold(iw,ifr)-ekino(1))*ro
            tpbsum_dmc(ifr)=tpbsum_dmc(ifr)+wtg(1)*ekino(1)*ro

            wtg=wt(iw)*fprod/rnorm_nodes**2
            wtg_derivsum1=wtg(1)
          endif
        enddo

        if(icasula.eq.-1) then

! Set nuclear coordinates (0 flag = no strech e-coord)
          if(nforce.gt.1) &
          call strech(xold_dmc(1,1,iw,1),xold_dmc(1,1,iw,1),ajacob,1,0)

          call walkstrdet(iw)
          call walkstrjas(iw)
!         call t_vpsp_get(iw)
          call t_vpsp_get

          imove=0
          call nonloc_grid(iel,iw,xnew,psido_dmc(iw,1),imove)

          ncount_casula=ncount_casula+1
          if(imove.gt.0) then
            call psiedmc(iel,iw,xnew,psidn,psijn,0)
            nmove_casula=nmove_casula+1

!           call compute_determinante_grad(iel,psidn,psidn,vnew(1,iel),0)

            iage(iw)=0
            do k=1,3
              xold_dmc(k,iel,iw,1)=xnew(k)
            enddo
! 290         vold_dmc(k,iel,iw,1)=vnew(k,iel)
            psido_dmc(iw,1)=psidn(1)
            psijo_dmc(iw,1)=psijn(1)
            call jassav(iel,0)
            call detsav(iel,0)

            if(iel.le.nup) call update_ymat(nup)
            if(iel.gt.nup) call update_ymat(nelec)

            call walksav_det(iw)
            call walksav_jas(iw)
            if(nforce.gt.1.and.istrech.gt.0) then
              do ifr=1,nforce
                call strech(xold_dmc(1,1,iw,1),xstrech,ajacob,ifr,1)
                do k=1,3
                  do i=1,nelec
                     xold_dmc(k,i,iw,ifr)=xstrech(k,i)
                  enddo
                enddo
              enddo
            endif


          endif
        endif

      ! call average(1)
      enddo

      if(ipr.gt.5.and.wsum1(1).gt.1.1d0*dmc_nconf) write(18,'(i6,9d12.4)') ipass,ffn,fprod,fprod/ff(ipmod2),wsum1(1),wgdsumo

      if(idmc.gt.0.or.iacc_rej.eq.0) then
        wfsum1=wsum1(1)*ffn
        efsum1=esum1_dmc(1)*ffn
      endif
      do ifr=1,nforce
        if(idmc.gt.0.or.iacc_rej.eq.0) then
          wgsum1(ifr)=wsum1(ifr)*fprod
          egsum1(ifr)=esum1_dmc(ifr)*fprod
         else
          wgsum1(ifr)=wsum1(ifr)
          egsum1(ifr)=esum1_dmc(ifr)
        endif
      enddo

      call splitj
      if(icasula.eq.0) ncount_casula=1
      if(write_walkalize) write(11,'(i8,f9.6,f12.5,f11.6,i5,f11.5)') ipass,ffn, &
      wsum1(1),esum1_dmc(1)/wsum1(1),nwalk &
      ,float(nmove_casula)/float(ncount_casula)

      return
      end

      subroutine dmc_eloc_cutoff(v, adrift, tratio, vav2sum, v2sum)

      use contrldmc, only: tau
      use precision_kinds, only: dp
      use system,  only: nelec

      implicit none

      integer  :: i
      real(dp) :: adrift, tratio
      real(dp) :: v2, vavvt, vavvn
      real(dp) :: vav2sum, v2sum
      real(dp), dimension(3, nelec) :: v

      vav2sum = 0.d0
      v2sum = 0.d0
      do i=1,nelec
        v2    = v(1,i)**2 + v(2,i)**2 + v(3,i)**2
        vavvt = (dsqrt(1.d0+2.d0*adrift*v2*tau*tratio)-1.d0)/(adrift*v2)
        vavvn = vavvt/(tau*tratio)

        vav2sum = vav2sum + vavvn**2 * v2
        v2sum = v2sum + v2

      enddo

      return
      endsubroutine

      end module
