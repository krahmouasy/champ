      subroutine multideterminante(iel)

      use vmc_mod, only: norb_tot
      use vmc_mod, only: MEXCIT
      use csfs, only: nstates
      use dets, only: ndet
      use elec, only: ndn, nup
      use multidet, only: irepcol_det, ireporb_det, ivirt, iwundet, kref, numrep_det
      use slatn, only: slmin
      use ycompactn, only: ymatn
      use coefs, only: norb
      use multimatn, only: aan, wfmatn
      use multislatern, only: detn, orbn
      use const, only: nelec
      use orbval, only: orb
      use multislater, only: detiab
      use precision_kinds, only: dp
      use contrl_file,    only: ounit
      implicit none

      integer :: i, iab, iel, index_det, iorb
      integer :: irep, ish, istate, jj
      integer :: jorb, jrep, k, ndim, ndim2
      integer :: nel
      real(dp) :: det, dum1
      real(dp), dimension(nelec, norb_tot, 3) :: gmat
      real(dp), dimension(MEXCIT**2, 3) :: gmatn
      real(dp), dimension(norb_tot, 3) :: b
      real(dp), dimension(3) :: ddx_mdet
      real(dp), dimension(norb_tot) :: orb_sav
      real(dp), parameter :: one = 1.d0
      real(dp), parameter :: half = 0.5d0








      if(ndet.eq.1) return

      iab=1
      nel=nup
      ish=0
      if(iel.gt.nup) then
        iab=2
        nel=ndn
        ish=nup
      endif

c temporarely copy orbn to orb
      do iorb=1,norb
        orb_sav(iorb)=orb(iel,iorb)
        orb(iel,iorb)=orbn(iorb)
      enddo

      do jrep=ivirt(iab),norb
        do irep=1,nel

          dum1=0.d0
          do i=1,nel
           dum1=dum1+slmin(irep+(i-1)*nel)*orb(i+ish,jrep)
          enddo
          aan(irep,jrep)=dum1

        enddo
      enddo

c compute wave function
      do k=1,kref-1

        if(iwundet(k,iab).eq.k) then

          ndim=numrep_det(k,iab)
          ndim2=ndim*ndim
          
          jj=0
          do jrep=1,ndim
            jorb=ireporb_det(jrep,k,iab)
            do irep=1,ndim
              iorb=irepcol_det(irep,k,iab)
              jj=jj+1

              wfmatn(k,jj)=aan(iorb,jorb)
            enddo
          enddo


          call matinv(wfmatn(k,1:ndim2),ndim,det)

          detn(k)=det

         else
          index_det=iwundet(k,iab)
          detn(k)=detn(index_det)

        endif

      enddo

      do k=kref+1,ndet


        if(iwundet(k,iab).eq.k) then

          ndim=numrep_det(k,iab)
          ndim2=ndim*ndim
          
          jj=0
          do jrep=1,ndim
            jorb=ireporb_det(jrep,k,iab)
            do irep=1,ndim
              iorb=irepcol_det(irep,k,iab)
              jj=jj+1

              wfmatn(k,jj)=aan(iorb,jorb)
            enddo
          enddo


          call matinv(wfmatn(k,1:ndim2),ndim,det)
          
          detn(k)=det

         else
          index_det=iwundet(k,iab)
          detn(k)=detn(index_det)

        endif


      enddo

      do k=1,kref-1
        if(iwundet(k,iab).ne.kref) then
          detn(k)=detn(k)*detn(kref)
        endif
      enddo

      do k=kref+1,ndet
        if(iwundet(k,iab).ne.kref) then
          detn(k)=detn(k)*detn(kref)
        endif
      enddo

c      do k=1,ndet
c        if(k.ne.kref.and.iwundet(k,iab).ne.kref) then
c          detn(k)=detn(k)*detn(kref)
c        endif
c      enddo

      do istate=1,nstates
        if(iab.eq.1) call compute_ymat(iab,detn,detiab(1,2),wfmatn,ymatn(1,1,istate),istate)
        if(iab.eq.2) call compute_ymat(iab,detiab(1,1),detn,wfmatn,ymatn(1,1,istate),istate)
      enddo

      do iorb=1,norb
        orb(iel,iorb)=orb_sav(iorb)
      enddo

      return
      end

c-----------------------------------------------------------------------

      subroutine multideterminante_grad(iel,b,norbs,detratio,slmi,aa,ymat,velocity)

      use precision_kinds, only: dp
      use vmc_mod, only: norb_tot
      use vmc_mod, only: nmat_dim
      use vmc_mod, only: MEXCIT
      use dets, only: ndet
      use elec, only: ndn, nup
      use multidet, only: iactv, ivirt, kref
      use coefs, only: norb
      use dorb_m, only: iworbd
      use const, only: nelec

      implicit none

      integer :: iab, iel, iorb, irep, ish, norbs
      integer :: j, jel, jrep, k
      integer :: kk, nel
      real(dp) :: detratio, dum
      real(dp), dimension(nelec, norb_tot) :: aa
      real(dp), dimension(norb_tot, nelec) :: ymat
      real(dp), dimension(norbs, 3) :: b
      real(dp), dimension(nelec, norb_tot, 3) :: gmat
      real(dp), dimension(3) :: velocity
      real(dp), dimension(nmat_dim) :: slmi
      real(dp), parameter :: one = 1.d0
      real(dp), parameter :: half = 0.5d0



      do k=1,3
        velocity(k)=0.d0
      enddo
      if(ndet.eq.1) return

      if(iel.le.nup) then
        iab=1
        nel=nup
        ish=0
       else
        iab=2
        nel=ndn
        ish=nup
      endif

      jel=iel-ish


      do kk=1,3

        do jrep=ivirt(iab),norb
          dum=0
          do j=1,nel
             dum=dum+b(iworbd(j+ish,kref),kk)*aa(j,jrep)
          enddo
          dum=b(jrep,kk)-dum
          do irep=iactv(iab),nel
            gmat(irep,jrep,kk)=dum*slmi(irep+(jel-1)*nel)
          enddo
        enddo

      enddo

c     if(iab.eq.2) write(ounit,*) 'gmat ',(((gmat(irep,jrep,kk),irep=iactv(iab),nel),jrep=ivirt(iab),norb),kk=1,3)

      do kk=1,3
        dum=0
        do jrep=ivirt(iab),norb
          do irep=iactv(iab),nel
            dum=dum+ymat(jrep,irep)*gmat(irep,jrep,kk)
          enddo
        enddo
        velocity(kk)=dum*detratio
      enddo

c     if(iab.eq.2) write(ounit,*) 'ymat ',((ymat(jrep,irep),irep=iactv(iab),nel),jrep=ivirt(iab),norb)
      return
      end
c-----------------------------------------------------------------------
