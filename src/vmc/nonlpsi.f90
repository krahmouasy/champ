module nonlpsi
      use error,   only: fatal_error
      contains
      function psinl(u,rri,rrj,it,iwfjas)
! Written by Claudia Filippi, modified by Cyrus Umrigar
      use vmc_mod, only: nwftypejas
      use jastrow, only: norda, nordb, nordc
      use jaspar6, only: asymp_r
      use jastrow, only: cutjas_en,cutjas_eni
      use jastrow, only: a4, c,ijas,nordj
      use multiple_geo, only: iwf
      use precision_kinds, only: dp
      use scale_dist_mod, only: switch_scale

      implicit none

      integer :: it, jp, k, l, l_hi
      integer :: ll, m, n, iwfjas
      real(dp) :: rri, rrj, rrri, rrrj, xi, xj
      real(dp) :: u, uuu
      real(dp) :: psinl
      real(dp), dimension(0:nordj) :: uu
      real(dp), dimension(0:nordj) :: ss
      real(dp), dimension(0:nordj) :: tt
      real(dp), parameter :: one = 1.d0
      real(dp), parameter :: two = 2.d0
      real(dp), parameter :: half = 0.5d0
      real(dp), parameter :: eps = 1.d-12

! Not updated for ijas=5,6 because we will probably stay with ijas=4
! If we want to use ijas=5,6 update this routine similarly to psi.f
      if(ijas.ge.5) call fatal_error('PSINL: ijas >= 5 not implemented')

      psinl=0.d0
      if(nordc.le.1) return



      if(nwftypejas.gt.1) iwf=iwfjas

      uuu=u
      rrri=rri
      rrrj=rrj

      if(ijas.eq.4) then
         if(rri.eq.asymp_r .or. rrj.eq.asymp_r) return
         call switch_scale(uuu)
         call switch_scale(rrri)
         call switch_scale(rrrj)
      elseif(ijas.eq.1) then
         if(rrri.gt.cutjas_en(it,iwf).or.rrrj.gt.cutjas_en(it,iwf)) return
      endif



      uu(0)=one
      ss(0)=two
      tt(0)=one
      do jp=1,nordc
        uu(jp)=uuu**uu(jp-1)
        ss(jp)=rrri**jp+rrrj**jp
        tt(jp)=(rrri*rrrj)**jp
      enddo

      ll=0
      do n=2,nordc
        do k=n-1,0,-1
          if(k.eq.0) then
            l_hi=n-k-2
           else
            l_hi=n-k
          endif
          do l=l_hi,0,-1
            m=(n-k-l)/2
            if(2*m.eq.n-k-l) then
              ll=ll+1
              psinl=psinl+c(ll,it,iwf)*uu(k)*ss(l)*tt(m)
            endif
          enddo
        enddo
      enddo


      if(ijas.eq.1) then
         xi=rrri*cutjas_eni(it,iwf)
         xj=rrrj*cutjas_eni(it,iwf)
         psinl=psinl*((1.d0-xi)*(1.d0-xj))**3
      endif


      return
      end
!-----------------------------------------------------------------------
      function psianl(rri,it,iwfjas)



      use jastrow, only: norda
      use jaspar6, only: asymp_r
      use jastrow, only: cutjas_en,cutjas_eni
      use jastrow, only: a4,asymp_jasa,ijas
      use multiple_geo, only: iwf
      use precision_kinds, only: dp
      use vmc_mod, only: nwftypejas

      implicit none

      integer :: i, it, iwfjas
      real(dp) :: rri, rrip, xi, a1_cusp
      real(dp) :: psianl


! Not updated for ijas=5,6 because we will probably stay with ijas=4
! If we want to use ijas=5,6 update this routine similarly to psi.f
      if(ijas.ge.5) call fatal_error('PSINL: ijas >= 5 not implemented')

      psianl=0.d0
      if(nwftypejas.gt.1) iwf=iwfjas

      if(ijas.eq.1) then

         if(rri.gt.cutjas_en(it,iwf)) return

         xi=rri*cutjas_eni(it,iwf)
         psianl=0.d0

         a1_cusp=3.d0*a4(1,it,iwf)*cutjas_eni(it,iwf)
         psianl=a1_cusp*rri+a4(1,it,iwf)

         rrip=rri
         do i=2,norda
            rrip=rrip*rri
            psianl=psianl+a4(i,it,iwf)*rrip
         enddo
         psianl=psianl*(1.d0-xi)**3

      else

         if(rri.eq.asymp_r) return
         psianl=a4(1,it,iwf)*rri/(1.d0+a4(2,it,iwf)*rri)-asymp_jasa(it,iwf)
         rrip=rri
         do i=2,norda
            rrip=rrip*rri
            psianl=psianl+a4(i+1,it,iwf)*rrip
         enddo

      endif


      return
      end
!-----------------------------------------------------------------------

      function psibnl(u,isb,ipar,iwfjas)

      use jastrow, only: nordb
      use jaspar6, only: asymp_r
      use jastrow, only: cutjas_ee, cutjas_eei
      use jastrow, only: asymp_jasb,b,ijas,sspinn
      use multiple_geo, only: iwf
      use precision_kinds, only: dp
      use vmc_mod, only: nwftypejas

      implicit none

      integer :: i, ipar, isb, iwfjas
      real(dp) :: b1_cusp, fee, psibnl, u, uu, xij

! Not updated for ijas=5,6 because we will probably stay with ijas=4
! If we want to use ijas=5,6 update this routine similarly to psi.f
      if(ijas.ge.5) call fatal_error('PSINL: ijas >= 5 not implemented')

      psibnl=0.d0
      if(nwftypejas.gt.1) iwf=iwfjas

      if(ijas.eq.1) then
        if(u.gt.cutjas_ee(isb,iwf)) return

        xij=u*cutjas_eei(isb,iwf)

        b1_cusp=sspinn*0.5+3.d0*b(1,isb,iwf)*cutjas_eei(isb,iwf)
        psibnl=b1_cusp*u+b(1,isb,iwf)
        uu=u
        do i=2,nordb
          uu=u*uu
          psibnl=psibnl+b(i,isb,iwf)*uu
        enddo
        psibnl=psibnl*(1.d0-xij)**3
       else
        if(u.eq.asymp_r) return

        fee=b(1,isb,iwf)*u/(1+b(2,isb,iwf)*u)
        psibnl=sspinn*fee-asymp_jasb(ipar+1,iwf)
        uu=u
        do i=2,nordb
          uu=u*uu
          psibnl=psibnl+b(i+1,isb,iwf)*uu
        enddo
      endif

      return
      end
!-----------------------------------------------------------------------
      function dpsianl(rri,it,iwfjas)

      use jastrow, only: norda
      use jaspar6, only: asymp_r
      use jastrow, only: cutjas_en, cutjas_eni
      use jastrow, only: a4,ijas
      use multiple_geo, only: iwf
      use precision_kinds, only: dp
      use vmc_mod, only: nwftypejas

      implicit none

      integer :: i, it, iwfjas
      real(dp) :: rri, xi
      real(dp) :: psianl, dpsianl, term, a1_cusp
      real(dp) :: bot, boti, top
      real(dp), dimension(norda) :: ri

! Not updated for ijas=5,6 because we will probably stay with ijas=4
! If we want to use ijas=5,6 update this routine similarly to psi.f
      if(ijas.ge.5) call fatal_error('PSINL: ijas >= 5 not implemented')

      dpsianl=0.d0

      if(nwftypejas.gt.1) iwf=iwfjas

      if(ijas.eq.1) then
         if(rri.gt.cutjas_en(it,iwf)) return
      else
         if(rri.eq.asymp_r) return
      endif

      ri(1)=rri
      do i=2,norda
         ri(i)=rri*ri(i-1)
      enddo

      if(ijas.eq.1) then
         xi=rri*cutjas_eni(it,iwf)
         term=(1.d0-xi)**3

         a1_cusp=3.d0*a4(1,it,iwf)*cutjas_eni(it,iwf)
         psianl=a1_cusp*ri(1)+a4(1,it,iwf)
         dpsianl=a1_cusp

         do i=2,norda
            psianl=psianl+a4(i,it,iwf)*ri(i)
            dpsianl=dpsianl+i*a4(i,it,iwf)*ri(i-1)
         enddo
         psianl=psianl*term
         dpsianl=dpsianl*term+3.d0*psianl*(1.d0-xi)**2*cutjas_eni(it,iwf)

      else
         top=a4(1,it,iwf)*rri
         bot=1.d0+a4(2,it,iwf)*rri
         boti=1.d0/bot

         dpsianl=(a4(1,it,iwf)-top*boti*a4(2,it,iwf))*boti
         do i=2,norda
            dpsianl=dpsianl+i*a4(i+1,it,iwf)*ri(i-1)
         enddo
      endif


      return
      end

!-----------------------------------------------------------------------
      function dpsibnl(u,isb,ipar,iwfjas)

      use jastrow, only: nordb
      use jaspar6, only: asymp_r
      use jastrow, only: cutjas_ee, cutjas_eei
      use jastrow, only: b,ijas,sspinn
      use multiple_geo, only: iwf
      use precision_kinds, only: dp
      use vmc_mod, only: nwftypejas

      implicit none

      integer :: i, isb, ipar, iwfjas
      real(dp) :: b1_cusp, bot, boti, dbot, dfee, dtop
      real(dp) :: term, top, u, xij
      real(dp) :: dpsibnl, psibnl
      real(dp), dimension(nordb) :: uu

! Not updated for ijas=5,6 because we will probably stay with ijas=4
! If we want to use ijas=5,6 update this routine similarly to psi.f
      if(ijas.ge.5) call fatal_error('PSINL: ijas >= 5 not implemented')

      dpsibnl=0.d0
      if(ijas.eq.1) then
         if(ijas.eq.1 .and. u.gt.cutjas_ee(isb,iwf)) return
      else
         if(u.eq.asymp_r) return
      endif
      if(nwftypejas.gt.1) iwf=iwfjas

      uu(1)=u
      do i=2,nordb
         uu(i)=u*uu(i-1)
      enddo

      if(ijas.eq.1) then
         xij=u*cutjas_eei(isb,iwf)
         term=(1.d0-xij)**3

         b1_cusp=sspinn*0.5+3.d0*b(1,isb,iwf)*cutjas_eei(isb,iwf)
         psibnl=b1_cusp*u+b(1,isb,iwf)
         dpsibnl=b1_cusp

         do i=2,nordb
            psibnl=psibnl+b(i,isb,iwf)*uu(i)
            dpsibnl=dpsibnl+i*b(i,isb,iwf)*uu(i-1)
         enddo
         psibnl=psibnl*term
         dpsibnl=dpsibnl*term-3.d0*psibnl*(1.d0-xij)**2*cutjas_eei(isb,iwf)

      else
         top=b(1,isb,iwf)*u
         dtop=b(1,isb,iwf)
         bot=1+b(2,isb,iwf)*u
         dbot=b(2,isb,iwf)
         boti=1.d0/bot

         dfee=(dtop-top*boti*dbot)*boti
         dpsibnl=sspinn*dfee
         do i=2,nordb
            dpsibnl=dpsibnl+i*b(i+1,isb,iwf)*uu(i-1)
         enddo

      endif




      return
      end
end module
