      module orbitals_mod
      interface !LAPACK interface
        SUBROUTINE dgemm(TRANSA,TRANSB,M,N,K,ALPHA,A,LDA,B,LDB,BETA,C,LDC)
! *  -- Reference BLAS level3 routine --
! *  -- Reference BLAS is a software package provided by Univ. of Tennessee,    --
! *  -- Univ. of California Berkeley, Univ. of Colorado Denver and NAG Ltd..--
          DOUBLE PRECISION ALPHA,BETA
          INTEGER K,LDA,LDB,LDC,M,N
          CHARACTER TRANSA,TRANSB
          DOUBLE PRECISION A(LDA,*),B(LDB,*),C(LDC,*)
        END SUBROUTINE
        SUBROUTINE dcopy(N,DX,INCX,DY,INCY)
          INTEGER INCX,INCY,N
          DOUBLE PRECISION DX(*),DY(*)
        END SUBROUTINE
      end interface
      contains
      subroutine orbitals(x,rvec_en,r_en)
c Written by Cyrus Umrigar starting from Kevin Schmidt's routine
c Modified by A. Scemama

      use const, only: nelec, ipr
      use wfsec, only: iwf
      use phifun, only: phin, dphin, d2phin, n0_ibasis, n0_nbasis
      use coefs, only: coef, nbasis, norb
      use contrl_per, only: iperiodic
      use force_analy, only: iforce_analy
      use grid3dflag, only: i3dlagorb, i3dsplorb
      use atom, only: ncent_tot
      use orbval, only: ddorb, dorb, nadorb, orb
      use precision_kinds, only: dp
      use contrl_file,    only: ounit
      use grid3d_orbitals, only: spline_mo
      use grid3d_orbitals, only: lagrange_mos, lagrange_mos_grad, lagrange_mos_2
#if defined(TREXIO_FOUND)
      use trexio_basis_fns_mod, only: trexio_basis_fns
      use trexio_read_data, only: trexio_has_group_orbitals
#endif
      use basis_fns_mod, only: basis_fns


      use pw_orbitals, only: orbitals_pw
      implicit none

      integer :: i, ier, ider, iorb, k, m
      integer :: m0

      real(dp), dimension(3,*) :: x
      real(dp), dimension(3,nelec,ncent_tot) :: rvec_en
      real(dp), dimension(nelec,ncent_tot) :: r_en
c     real(dp), dimension(nelec,nbasis) :: bhin
c     real(dp), dimension(3*nelec,nbasis) :: dbhin
c     real(dp), dimension(nelec,nbasis) :: d2bhin

      ier=1
      if(iperiodic.eq.0) then

c spline interpolation
        if(i3dsplorb.eq.2) then
          do i=1,nelec
            ier = 0.d0
            do iorb=1,norb+nadorb
              ddorb(iorb,i)=1.d0    ! compute the laplacian
              dorb(iorb,i,1)=1.d0   ! compute the gradients
              dorb(iorb,i,2)=1.d0   ! compute the gradients
              dorb(iorb,i,3)=1.d0   ! compute the gradients
              call spline_mo (x(1,i),iorb,orb(i,iorb),dorb(iorb,i,:),ddorb(iorb,i),ier)
            enddo

            if(ier.eq.1) then
              if (trexio_has_group_orbitals) then
                call trexio_basis_fns(i,i,rvec_en,r_en,2)
              else
                call basis_fns(i,i,rvec_en,r_en,2)
              endif
              do iorb=1,norb+nadorb
                orb(i,iorb)=0.d0
                dorb(iorb,i,1)=0.d0
                dorb(iorb,i,2)=0.d0
                dorb(iorb,i,3)=0.d0
                ddorb(iorb,i)=0.d0
                do m0=1,n0_nbasis(i)
                  m=n0_ibasis(m0,i)
                  orb(i,iorb)=orb(i,iorb)+coef(m,iorb,iwf)*phin(m,i)
                  dorb(iorb,i,1)=dorb(iorb,i,1)+coef(m,iorb,iwf)*dphin(m,i,1)
                  dorb(iorb,i,2)=dorb(iorb,i,2)+coef(m,iorb,iwf)*dphin(m,i,2)
                  dorb(iorb,i,3)=dorb(iorb,i,3)+coef(m,iorb,iwf)*dphin(m,i,3)
                  ddorb(iorb,i)=ddorb(iorb,i)+coef(m,iorb,iwf)*d2phin(m,i)
                enddo
              enddo
            endif
          enddo
!
! Lagrange interpolation
        elseif(i3dlagorb.eq.2) then
         do i=1,nelec
           ier=0
           call lagrange_mos(1,x(1,i),orb,i,ier)
           call lagrange_mos_grad(2,x(1,i),dorb,i,ier)
           call lagrange_mos_grad(3,x(1,i),dorb,i,ier)
           call lagrange_mos_grad(4,x(1,i),dorb,i,ier)
           call lagrange_mos_2(5,x(1,i),ddorb,i,ier)

           if(ier.eq.1) then
            if (trexio_has_group_orbitals) then
              call trexio_basis_fns(i,i,rvec_en,r_en,2)
            else
              call basis_fns(i,i,rvec_en,r_en,2)
            endif
             do iorb=1,norb+nadorb
               orb(i,iorb)=0.d0
               dorb(iorb,i,1)=0.d0
               dorb(iorb,i,2)=0.d0
               dorb(iorb,i,3)=0.d0
               ddorb(iorb,i)=0.d0
               do m0=1,n0_nbasis(i)
                 m=n0_ibasis(m0,i)
                 orb(i,iorb)=orb(i,iorb)+coef(m,iorb,iwf)*phin(m,i)
                 dorb(iorb,i,1)=dorb(iorb,i,1)+coef(m,iorb,iwf)*dphin(m,i,1)
                 dorb(iorb,i,2)=dorb(iorb,i,2)+coef(m,iorb,iwf)*dphin(m,i,2)
                 dorb(iorb,i,3)=dorb(iorb,i,3)+coef(m,iorb,iwf)*dphin(m,i,3)
                 ddorb(iorb,i)=ddorb(iorb,i)+coef(m,iorb,iwf)*d2phin(m,i)
               enddo
             enddo
           endif
         enddo

c no 3d interpolation
        else

c get basis functions for all electrons
         ider=2
         if(iforce_analy.eq.1) ider=3
         if (trexio_has_group_orbitals) then
          print*, "trexio_found  but not being used"
          call trexio_basis_fns(1,nelec,rvec_en,r_en,ider)
         else
          call basis_fns(1,nelec,rvec_en,r_en,ider)
         endif


c in alternativa al loop 26
c        do jbasis=1,nbasis
c         i=0
c         do ielec=1,nelec
c          bhin(ielec,jbasis)=phin(jbasis,ielec)
c          do l=1,3
c           i=i+1
c           dbhin(i,jbasis)=dphin(jbasis,ielec,l)
c          enddo
c          d2bhin(ielec,jbasis)=d2phin(jbasis,ielec)
c         enddo
c        enddo
c        call dgemm('n','n',  nelec,norb,nbasis,1.d0,bhin,   nelec,  coef(1,1,iwf),nbasis,0.d0,orb,   nelec)
c        call dgemm('n','n',3*nelec,norb,nbasis,1.d0,dbhin,3*nelec,  coef(1,1,iwf),nbasis,0.d0,dorb,3*nelec)
c        call dgemm('n','n',  nelec,norb,nbasis,1.d0,d2bhin, nelec,  coef(1,1,iwf),nbasis,0.d0,ddorb, nelec)

!        Vectorization dependent code selection
#ifdef VECTORIZATION
!     Following loop changed for better vectorization AVX512/AVX2
          do i=1,nelec
             do iorb=1,norb+nadorb
                orb(i,iorb)=0.d0
                dorb(iorb,i,1)=0.d0
                dorb(iorb,i,2)=0.d0
                dorb(iorb,i,3)=0.d0
                ddorb(iorb,i)=0.d0
                do m=1,nbasis
                   orb  (  i,iorb)=orb  (  i,iorb)+coef(m,iorb,iwf)*phin  ( m,i)
                   dorb (iorb,i,1)=dorb (iorb,i,1)+coef(m,iorb,iwf)*dphin (m,i,1)
                   dorb (iorb,i,2)=dorb (iorb,i,2)+coef(m,iorb,iwf)*dphin (m,i,2)
                   dorb (iorb,i,3)=dorb (iorb,i,3)+coef(m,iorb,iwf)*dphin (m,i,3)
                   ddorb(  iorb,i)=ddorb(iorb,i)+coef(m,iorb,iwf)*d2phin( m,i)
                enddo
             enddo
          enddo
#else
!     keep the old localization code if no vectorization instructions available
          do i=1,nelec
             do iorb=1,norb+nadorb
                orb(i,iorb)=0.d0
                dorb(iorb,i,1)=0.d0
                dorb(iorb,i,2)=0.d0
                dorb(iorb,i,3)=0.d0
                ddorb(iorb,i)=0.d0
                do m0=1,n0_nbasis(i)
                   m=n0_ibasis(m0,i)
                   orb  (  i,iorb)=orb  (  i,iorb)+coef(m,iorb,iwf)*phin  ( m,i)
                   dorb (iorb,i,1)=dorb (iorb,i,1)+coef(m,iorb,iwf)*dphin (m,i,1)
                   dorb (iorb,i,2)=dorb (iorb,i,2)+coef(m,iorb,iwf)*dphin (m,i,2)
                   dorb (iorb,i,3)=dorb (iorb,i,3)+coef(m,iorb,iwf)*dphin (m,i,3)
                   ddorb(iorb,i)=ddorb(iorb,i)+coef(m,iorb,iwf)*d2phin( m,i)
                enddo
             enddo
          enddo
#endif
       endif

       if(iforce_analy.eq.1) call da_orbitals

       else
        call orbitals_pw(x,orb,dorb,ddorb)
      endif

      if(ipr.ge.0) then
        do iorb=1,norb+nadorb
          write(ounit,'(''iorb,orb='',i4,1000f15.11)') iorb,(orb(i,iorb),i=1,nelec)
        enddo
         do iorb=1,norb+nadorb
          write(ounit,'(''iorb,d2orb='',i4,1000f15.11)') iorb,(ddorb(iorb,i),i=1,nelec)
         enddo
        do k=1,3
          do iorb=1,norb+nadorb
            write(ounit,'(''iorb,dorb='',2i4,1000f12.8)') k,iorb,(dorb(iorb,i,k),i=1,nelec)
          enddo
        enddo
      endif

      return
      end
c------------------------------------------------------------------------------------

      subroutine da_orbitals

      use atom, only: ncent
      use const, only: nelec
      use da_orbval, only: da_d2orb, da_dorb, da_orb
      use numbas2, only: ibas0, ibas1
      use phifun, only: d2phin_all, d3phin, dphin
      use wfsec, only: iwf
      use coefs, only: coef, nbasis, norb
      use contrl_per, only: ibasis
      use precision_kinds, only: dp

      implicit none

      integer :: i, ic, ielec, j, k
      integer :: l, m, n

      real(dp), dimension(3*nelec,nbasis) :: tphin
      real(dp), dimension(3*3*nelec,nbasis) :: t2phin_all
      real(dp), dimension(3*nelec,nbasis) :: t3phin

      do ibasis=1,nbasis
       i=0
       j=0
       do ielec=1,nelec
        do l=1,3
         i=i+1
         tphin(i,ibasis)=dphin(ibasis,ielec,l)
         t3phin(i,ibasis)=d3phin(l,ibasis,ielec)
         do k=1,3
          j=j+1
          t2phin_all(j,ibasis)=d2phin_all(k,l,ibasis,ielec)
         enddo
        enddo
       enddo
      enddo
      n=3*nelec
      m=3*nelec
      do ic=1,ncent
        k=ibas1(ic)-ibas0(ic)+1
        j=ibas0(ic)
      call dgemm('n','n',  n,norb,k,-1.d0,tphin(1,j)     ,  m,coef(j,1,iwf),nbasis,0.d0,da_orb(1,1,1,ic)   ,  m)
      call dgemm('n','n',  n,norb,k,-1.d0,t3phin(1,j)    ,  m,coef(j,1,iwf),nbasis,0.d0,da_d2orb(1,1,1,ic) ,  m)
      call dgemm('n','n',3*n,norb,k,-1.d0,t2phin_all(1,j),3*m,coef(j,1,iwf),nbasis,0.d0,da_dorb(1,1,1,1,ic),3*m)
      enddo

      return
      end
c------------------------------------------------------------------------------------
      subroutine orbitalse(iel,x,rvec_en,r_en,iflag)

      use phifun, only: d2phin, dphin, n0_ibasis, n0_nbasis
      use phifun, only: phin
      use wfsec, only: iwf
      use coefs, only: coef, norb, nbasis
      use contrl_per, only: iperiodic
      use atom, only: ncent_tot
      use grid3dflag, only: i3dlagorb, i3dsplorb
      use multislatern, only: ddorbn, dorbn, orbn
      use const, only: nelec
      use precision_kinds, only: dp
      use grid3d_orbitals, only: spline_mo, lagrange_mose
      use grid3d_orbitals, only: lagrange_mos_grade
      use basis_fns_mod, only: basis_fns
      use pw_orbitals, only: orbitals_pw_grade

      implicit none

      integer :: iel, ier, ider, iflag, iorb, m
      integer :: m0

      real(dp), dimension(3,*) :: x
      real(dp), dimension(3,nelec,ncent_tot) :: rvec_en
      real(dp), dimension(nelec,ncent_tot) :: r_en

      if(iperiodic.eq.0) then

c get the value and gradients from the 3d-interpolated orbitals
         ier=0
c spline interplolation
         if(i3dsplorb.ge.1) then
            do iorb=1,norb
               ddorbn(iorb)=0   ! Don't compute the laplacian
               dorbn(iorb,1)=1  ! compute the gradients
               dorbn(iorb,2)=1  ! compute the gradients
               dorbn(iorb,3)=1  ! compute the gradients
               call spline_mo (x(1,iel),iorb,orbn(iorb),dorbn(iorb,:),ddorbn(iorb),ier)
            enddo

c     Lagrange interpolation
         elseif(i3dlagorb.ge.1) then
            call lagrange_mose(1,x(1,iel),orbn,ier)
            call lagrange_mos_grade(2,x(1,iel),dorbn,ier)
            call lagrange_mos_grade(3,x(1,iel),dorbn,ier)
            call lagrange_mos_grade(4,x(1,iel),dorbn,ier)
         else
            ier=1
         endif

         if(ier.eq.1) then
c get basis functions for electron iel

            ider=1
            if(iflag.gt.0) ider=2
            call basis_fns(iel,iel,rvec_en,r_en,ider)

!     Vectorization dependent code. useful for AVX512 and AVX2
#ifdef VECTORIZATION

            if(iflag.gt.0) then

               do iorb=1,norb
                  orbn(iorb)=0.d0
                  dorbn(iorb,1)=0.d0
                  dorbn(iorb,2)=0.d0
                  dorbn(iorb,3)=0.d0
                  ddorbn(iorb)=0.d0
                  do m=1,nbasis
                     orbn(iorb)=orbn(iorb)+coef(m,iorb,iwf)*phin(m,iel)
                     dorbn(iorb,1)=dorbn(iorb,1)+coef(m,iorb,iwf)*dphin(m,iel,1)
                     dorbn(iorb,2)=dorbn(iorb,2)+coef(m,iorb,iwf)*dphin(m,iel,2)
                     dorbn(iorb,3)=dorbn(iorb,3)+coef(m,iorb,iwf)*dphin(m,iel,3)
                     ddorbn(iorb)=ddorbn(iorb)+coef(m,iorb,iwf)*d2phin(m,iel)
                  enddo
               enddo


            else


               do iorb=1,norb
                  orbn(iorb)=0.d0
                  dorbn(iorb,1)=0.d0
                  dorbn(iorb,2)=0.d0
                  dorbn(iorb,3)=0.d0
                  do m=1,nbasis
                     orbn(iorb)=orbn(iorb)+coef(m,iorb,iwf)*phin(m,iel)
                     dorbn(iorb,1)=dorbn(iorb,1)+coef(m,iorb,iwf)*dphin(m,iel,1)
                     dorbn(iorb,2)=dorbn(iorb,2)+coef(m,iorb,iwf)*dphin(m,iel,2)
                     dorbn(iorb,3)=dorbn(iorb,3)+coef(m,iorb,iwf)*dphin(m,iel,3)
                  enddo
               enddo


            endif


#else
!     Keep the localization for the non-vectorized code


            if(iflag.gt.0) then

               do iorb=1,norb
                  orbn(iorb)=0.d0
                  dorbn(iorb,1)=0.d0
                  dorbn(iorb,2)=0.d0
                  dorbn(iorb,3)=0.d0
                  ddorbn(iorb)=0.d0
                  do m0=1,n0_nbasis(iel)
                     m=n0_ibasis(m0,iel)
                     orbn(iorb)=orbn(iorb)+coef(m,iorb,iwf)*phin(m,iel)
                     dorbn(iorb,1)=dorbn(iorb,1)+coef(m,iorb,iwf)*dphin(m,iel,1)
                     dorbn(iorb,2)=dorbn(iorb,2)+coef(m,iorb,iwf)*dphin(m,iel,2)
                     dorbn(iorb,3)=dorbn(iorb,3)+coef(m,iorb,iwf)*dphin(m,iel,3)
                     ddorbn(iorb)=ddorbn(iorb)+coef(m,iorb,iwf)*d2phin(m,iel)
                  enddo
               enddo


            else


               do iorb=1,norb
                  orbn(iorb)=0.d0
                  dorbn(iorb,1)=0.d0
                  dorbn(iorb,2)=0.d0
                  dorbn(iorb,3)=0.d0
                  do m0=1,n0_nbasis(iel)
                     m=n0_ibasis(m0,iel)
                     orbn(iorb)=orbn(iorb)+coef(m,iorb,iwf)*phin(m,iel)
                     dorbn(iorb,1)=dorbn(iorb,1)+coef(m,iorb,iwf)*dphin(m,iel,1)
                     dorbn(iorb,2)=dorbn(iorb,2)+coef(m,iorb,iwf)*dphin(m,iel,2)
                     dorbn(iorb,3)=dorbn(iorb,3)+coef(m,iorb,iwf)*dphin(m,iel,3)
                  enddo
               enddo


            endif


#endif
         endif

      else
         call orbitals_pw_grade(iel,x(1,iel),orbn,dorbn,ddorbn)
      endif

      return
      end
c------------------------------------------------------------------------------------
      end module
