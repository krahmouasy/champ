      subroutine verify_orbitals
      use const, only: nelec
      use mstates_mod, only: MSTATES, MDETCSFX
      use dets, only: ndet
      use optwf_contrl, only: ioptorb
      use coefs, only: norb
      use dorb_m, only: iworbd
      use inputflags, only: iznuc,igeometry,ibasis_num,ilcao,iexponents,
     &             ideterminants,ijastrow_parameter, ioptorb_def,ilattice,
     &             ici_def,iforces,icsfs,imstates,igradients,icharge_efield,
     &             imultideterminants,ioptorb_mixvirt,imodify_zmat,izmatrix_check,
     &             ihessian_zmat 

      implicit real*8(a-h,o-z)

      include 'vmc.h'
      include 'force.h'
      include 'embed.h'
      include 'optorb.h'
      include 'optci.h'

      common /orbval/ orb(MELEC,MORB),dorb(3,MELEC,MORB),ddorb(MELEC,MORB),ndetorb,nadorb

c orbital indices in determinants of trial wave function
      ndetorb=0

      do i=1,ndet
       do j=1,nelec
        if(iworbd(j,i).gt.norb) then
         write (10,*) i,j,iworbd(j,i),norb
         call fatal_error('VERIFY: orbital index out of range')
        endif
        if(iworbd(j,i).gt.ndetorb) then
         ndetorb=iworbd(j,i)
        endif
       enddo
      enddo
 10   format('Det ',i4,' column ',i4,' orb index ',i4,' norb ',i4)

      call p2gtid('optwf:ioptorb',ioptorb,0,1)

      if(ioptorb.eq.0) then
        norb=ndetorb
        nadorb=0
      endif

      return
      end
