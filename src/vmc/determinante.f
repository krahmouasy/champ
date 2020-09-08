      subroutine determinante(iel,x,rvec_en,r_en,iflag)

      use force_mod, only: MFORCE, MFORCE_WT_PRD, MWF
      use vmc, only: MELEC, MORB, MBASIS, MDET, MCENT, MCTYPE, MCTYP3X
      use vmc, only: NSPLIN, nrad, MORDJ, MORDJ1, MMAT_DIM, MMAT_DIM2, MMAT_DIM20
      use vmc, only: radmax, delri
      use vmc, only: NEQSX, MTERMS
      use vmc, only: MCENT3, NCOEF, MEXCIT
      use elec, only: ndn, nup
      use multidet, only: kref
      use slatn, only: slmin
      use dorb_m, only: iworbd

      implicit real*8(a-h,o-z)


      common /slater/ slmi(MMAT_DIM,2)
     &,fp(3,MMAT_DIM,2)
     &,fpp(MMAT_DIM,2)
     &,ddx(3,MELEC),d2dx2(MELEC)
      common /multislater/ detiab(MDET,2)
      common /multislatern/ detn(MDET)
     &,orbn(MORB),dorbn(3,MORB),ddorbn(MORB)

      dimension x(3,*),rvec_en(3,MELEC,MCENT),r_en(MELEC,MCENT)

      call orbitalse(iel,x,rvec_en,r_en,iflag)

      if(iel.le.nup) then
        iab=1
        nel=nup
        ish=0
       else
        iab=2
        nel=ndn
        ish=nup
      endif

      ikel=nel*(iel-ish-1)

      ratio_kref=0
      do 55 j=1,nel
   55   ratio_kref=ratio_kref+slmi(j+ikel,iab)*orbn(iworbd(j+ish,kref))

      detn(kref)=detiab(kref,iab)*ratio_kref

      if(ratio_kref.eq.0.d0) return

      do 70 i=1,nel
        if(i+ish.ne.iel) then
          ik=nel*(i-1)
          sum=0
          do 60 j=1,nel
   60       sum=sum+slmi(j+ik,iab)*orbn(iworbd(j+ish,kref))
          sum=sum/ratio_kref
          do 65 j=1,nel
   65      slmin(j+ik)=slmi(j+ik,iab)-slmi(j+ikel,iab)*sum
        endif
   70 continue
      do 75 j=1,nel
   75   slmin(j+ikel)=slmi(j+ikel,iab)/ratio_kref

      return
      end
c-----------------------------------------------------------------------
      subroutine compute_determinante_grad(iel,psig,psid,vd,iflag_move)

      use force_mod, only: MFORCE, MFORCE_WT_PRD, MWF
      use vmc, only: MELEC, MORB, MBASIS, MDET, MCENT, MCTYPE, MCTYP3X
      use vmc, only: NSPLIN, nrad, MORDJ, MORDJ1, MMAT_DIM, MMAT_DIM2, MMAT_DIM20
      use vmc, only: radmax, delri
      use vmc, only: NEQSX, MTERMS
      use vmc, only: MCENT3, NCOEF, MEXCIT
      use csfs, only: nstates
      use elec, only: nup
      use multidet, only: kref
      use slatn, only: slmin
      use ycompact, only: ymat
      use ycompactn, only: ymatn
      use coefs, only: norb
      use multimat, only: aa, wfmat
      use multimatn, only: aan, wfmatn

      use velocity_jastrow, only: vj, vjn
      use mstates_ctrl, only: iguiding
      use mstates3, only: iweight_g, weights_g

      implicit real*8(a-h,o-z)





      common /slater/ slmi(MMAT_DIM,2)
     &,fp(3,MMAT_DIM,2)
     &,fpp(MMAT_DIM,2)
      common /multislater/ detiab(MDET,2)
      common /multislatern/ detn(MDET)
     &,orbn(MORB),dorbn(3,MORB),ddorbn(MORB)
      common /orbval/ orb(MELEC,MORB),dorb(3,MELEC,MORB),ddorb(MELEC,MORB),ndetorb,nadorb

      dimension psid(*),vd(3),vref(3),vd_s(3),dorb_tmp(3,MORB)
      dimension ymat_tmp(MORB,MELEC)

      save ymat_tmp

      if(iel.le.nup) then
        iab=1
       else
        iab=2
      endif

      psi2g=psig*psig
      psi2gi=1.d0/psi2g

c All quantities saved (old) avaliable
      if(iflag_move.eq.1) then

        do kk=1,3
          do iorb=1,norb
            dorb_tmp(kk,iorb)=dorb(kk,iel,iorb)
          enddo
        enddo

        call determinante_ref_grad(iel,slmi(1,iab),dorb_tmp,vref)

        if(iguiding.eq.0) then
          detratio=detiab(kref,1)*detiab(kref,2)/psid(1)
          call multideterminante_grad(iel,dorb_tmp,detratio,slmi(1,iab),aa(1,1,iab),wfmat(1,1,iab),ymat(1,1,iab,1),vd)

          do kk=1,3
            vd(kk)=vd(kk)+vref(kk)
          enddo
         else
          do kk=1,3
            vd(kk)=0.d0
          enddo
          do i=1,nstates
            istate=iweight_g(i)

            detratio=detiab(kref,1)*detiab(kref,2)/psid(istate)
            call multideterminante_grad(iel,dorb_tmp,detratio,slmi(1,iab),aa(1,1,iab),wfmat(1,1,iab),ymat(1,1,iab,istate),vd_s)

            do kk=1,3
              vd(kk)=vd(kk)+weights_g(i)*psid(istate)*psid(istate)*(vd_s(kk)+vref(kk))
            enddo
          enddo
          vd(1)=vd(1)*psi2gi
          vd(2)=vd(2)*psi2gi
          vd(3)=vd(3)*psi2gi
        endif

c       write(6,*) 'VJ',(vj(kk,iel),kk=1,3)
c       write(6,*) 'V0',(vref(kk),kk=1,3)
c       write(6,*) 'VD',(vd(kk),kk=1,3)

        vd(1)=vj(1,iel)+vd(1)
        vd(2)=vj(2,iel)+vd(2)
        vd(3)=vj(3,iel)+vd(3)

c Within single-electron move - quantities of electron iel not saved 
       elseif(iflag_move.eq.0) then
       
        call determinante_ref_grad(iel,slmin,dorbn,vref)

        if(iguiding.eq.0) then

          if(iab.eq.1) then
            detratio=detn(kref)*detiab(kref,2)/psid(1)
           else
            detratio=detiab(kref,1)*detn(kref)/psid(1)
          endif
          call multideterminante_grad(iel,dorbn,detratio,slmin,aan,wfmatn,ymatn,vd)

          do kk=1,3
            vd(kk)=vd(kk)+vref(kk)
          enddo

         else

          do kk=1,3
            vd(kk)=0.d0
          enddo
          do i=1,nstates
            istate=iweight_g(i)

            if(iab.eq.1) then
              detratio=detn(kref)*detiab(kref,2)/psid(istate)
             else
              detratio=detiab(kref,1)*detn(kref)/psid(istate)
            endif
            call multideterminante_grad(iel,dorbn,detratio,slmin,aan,wfmatn,ymatn(1,1,istate),vd_s)

            do kk=1,3
              vd(kk)=vd(kk)+weights_g(i)*psid(istate)*psid(istate)*(vd_s(kk)+vref(kk))
            enddo
          enddo
          vd(1)=vd(1)*psi2gi
          vd(2)=vd(2)*psi2gi
          vd(3)=vd(3)*psi2gi
        endif

c       write(6,*) 'VJ',(vjn(kk,iel),kk=1,3)
c       write(6,*) 'V0',(vref(kk),kk=1,3)
c       write(6,*) 'VD',(vd(kk),kk=1,3)

        vd(1)=vjn(1,iel)+vd(1)
        vd(2)=vjn(2,iel)+vd(2)
        vd(3)=vjn(3,iel)+vd(3)

       else

c Within single-electron move - iel not equal to electron moved - quantities of electron iel not saved 
        do kk=1,3
          do iorb=1,norb
            dorb_tmp(kk,iorb)=dorb(kk,iel,iorb)
          enddo
        enddo


c iel has same spin as electron moved
        if(iflag_move.eq.2) then

          if(iab.eq.1) then
            detratio=detn(kref)*detiab(kref,2)/psid(1)
           else
            detratio=detiab(kref,1)*detn(kref)/psid(1)
          endif

          call determinante_ref_grad(iel,slmin,dorb_tmp,vref)

          call multideterminante_grad(iel,dorb_tmp,detratio,slmin,aan,wfmatn,ymatn,vd)

c iel has different spin than the electron moved
         else
          if(iab.eq.1) then
            detratio=detiab(kref,1)*detn(kref)/psid(1)
           else
            detratio=detn(kref)*detiab(kref,2)/psid(1)
          endif

          call determinante_ref_grad(iel,slmi(1,iab),dorb_tmp,vref)

          if(iel.eq.1) call compute_ymat(1,detiab(1,1),detn,wfmat(1,1,1),ymat_tmp,1)

          if(iel.eq.nup+1) call compute_ymat(2,detn,detiab(1,2),wfmat(1,1,2),ymat_tmp,1)

          call multideterminante_grad(iel,dorb_tmp,detratio,slmi(1,iab),aa(1,1,iab),wfmat(1,1,iab),ymat_tmp(1,1),vd)
        endif

        vd(1)=vjn(1,iel)+vd(1)+vref(1)
        vd(2)=vjn(2,iel)+vd(2)+vref(2)
        vd(3)=vjn(3,iel)+vd(3)+vref(3)
      endif


      return 
      end
c-----------------------------------------------------------------------
      subroutine determinante_ref_grad(iel,slmi,dorb,ddx_ref)

      use force_mod, only: MFORCE, MFORCE_WT_PRD, MWF
      use vmc, only: MELEC, MORB, MBASIS, MDET, MCENT, MCTYPE, MCTYP3X
      use vmc, only: NSPLIN, nrad, MORDJ, MORDJ1, MMAT_DIM, MMAT_DIM2, MMAT_DIM20
      use vmc, only: radmax, delri
      use vmc, only: NEQSX, MTERMS
      use vmc, only: MCENT3, NCOEF, MEXCIT
      use elec, only: ndn, nup
      use multidet, only: kref
      use dorb_m, only: iworbd

      implicit real*8(a-h,o-z)


      dimension slmi(MMAT_DIM),dorb(3,MORB)
      dimension ddx_ref(3)

      ddx_ref(1)=0
      ddx_ref(2)=0
      ddx_ref(3)=0

      if(iel.le.nup) then
        ish=0
        jel=iel
        nel=nup
       else
        ish=nup
        jel=iel-nup
        nel=ndn
      endif

      ik=(jel-1)*nel
      do 84 j=1,nel
        ddx_ref(1)=ddx_ref(1)+slmi(j+ik)*dorb(1,iworbd(j+ish,kref))
        ddx_ref(2)=ddx_ref(2)+slmi(j+ik)*dorb(2,iworbd(j+ish,kref))
   84   ddx_ref(3)=ddx_ref(3)+slmi(j+ik)*dorb(3,iworbd(j+ish,kref))

      return
      end
c-----------------------------------------------------------------------
