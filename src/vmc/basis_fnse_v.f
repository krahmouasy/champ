      module basis_fnse_v_mod
      contains
      subroutine basis_fnse_v(k,rvec_en,r_en)
c Written by Claudia Filippi by modifying basis_fns
c routine to calculate basis functions for electron k
      use numbas_mod, only: MRWF
      use atom, only: iwctype, ncent, ncent_tot
      use ghostatom, only: nghostcent
      use numbas, only: iwrwf, nrbas, numr
      use numbas1, only: iwlbas, nbastyp
      use phifun, only: d2phin, d2phin_all, d3phin, dphin, n0_nbasis
      use phifun, only: phin
      use wfsec, only: iwf
      use force_analy, only: iforce_analy
      use const, only: nelec
      use contrl_file,    only: ounit
      use precision_kinds, only: dp
      use splfit_mod, only: splfit
      use slm_mod, only: slm
      use basis_fns_vgl_mod, only: n0_inc, phi_combine, phie_combine
      implicit none

      integer :: i, ic, irb, iwlbas0, j
      integer :: k, l, ll
      real(dp) :: cd1, cd2, cf, cf2, cf3
      real(dp) :: cp, cs, ddy_lap, r
      real(dp) :: r2, ri, ri2, ri3
      real(dp) :: rt3, rt3b2, y
      real(dp), dimension(4, MRWF) :: wfv
      real(dp), dimension(3) :: xc
      real(dp), dimension(3, nelec, ncent_tot) :: rvec_en
      real(dp), dimension(nelec, ncent_tot) :: r_en
      real(dp), dimension(3) :: dy
      real(dp), dimension(3, 3) :: ddy
      real(dp), dimension(3) :: dlapy
      real(dp), parameter :: one = 1.d0
      real(dp), parameter :: three = 3.d0
      real(dp), parameter :: half = 0.5d0




      data rt3,rt3b2/1.732050808d0,0.866025404d0/
c cs=1/sqrt(4*pi), cp=sqrt(3/(4*pi)), cd1=sqrt(5/(4*pi)), cd2=sqrt(15/(4*pi))
      data cs,cp,cd1,cd2/0.28209479d0,0.48860251d0,
     &0.63078313d0,1.0925484d0/
c cf=sqrt(7/(4*pi)),cf2=cf*sqrt(5),cf3=cf*sqrt(15)
      data cf,cf2,cf3/0.746352665180231d0,1.66889529453114d0,
     &2.89061144264055d0/

      l=0
      n0_nbasis(k)=0

c loop through centers

      do ic=1,ncent+nghostcent
      ll=0

      i=iwctype(ic)

c get distance to center

      xc(1)=rvec_en(1,k,ic)
      xc(2)=rvec_en(2,k,ic)
      xc(3)=rvec_en(3,k,ic)
c     write(ounit,'(''xc='',9f9.5)') xc(1),xc(2),xc(3)
      r=r_en(k,ic)
      r2=r*r
      ri=one/r
      ri2=ri**2
      ri3=ri2*ri


c analytical orbital

      if(numr.gt.0) then

c numerical orbitals
      do irb=1,nrbas(i)
      call splfit(r,irb,i,iwf,wfv(1,irb),iforce_analy)
      enddo

      ll=0
      iwlbas0=0
      do j=1,nbastyp(i)
      l=l+1
      ll=ll+1
      irb=iwrwf(ll,i)
      if(iwlbas(ll,i).ne.iwlbas0) then
        iwlbas0=iwlbas(ll,i)
        call slm(iwlbas0,xc,r2,y,dy,ddy,ddy_lap,dlapy,iforce_analy)
      endif
      if(iforce_analy.gt.0) then
        call phi_combine(iwlbas0,xc,ri,ri2,wfv(1,irb),y,dy,ddy,ddy_lap,dlapy,
     &       phin(l,k),dphin(1,l,k),d2phin(l,k),d2phin_all(1,1,l,k),d3phin(1,l,k),iforce_analy)
       else
        call phie_combine(iwlbas0,ri,ri2,wfv(1,irb),y,phin(l,k))
      endif
      call n0_inc(l,k,ic)
      enddo

c end of numerical orbitals
      else
       stop
      endif

c loop over all atoms
      enddo

      return
      end
      end module
