      module jastrow_mod
      contains
      subroutine jastrow_factor(x,v,d2j,psij,ifr)
c Written by Cyrus Umrigar

      use system, only: nelec
      use optwf_control, only: ioptjas
      use precision_kinds, only: dp
      use jastrow4_mod, only: jastrow4
      use deriv_jastrow4_mod, only: deriv_jastrow4
      use jastrow_update, only: d2ijo, d2o, fijo, fjo, fso, fsumo
      use multiple_geo, only: iwf, nforce
      use vmc_mod, only: nwftypejas
      use derivjas, only: d2g, g, go, gvalue
      use contrl_file, only: ounit
      use jastrow, only: ijas
      implicit none

      integer :: i, j, ifr
      real(dp), dimension(3, *) :: x
      real(dp), dimension(3, nelec, *) :: v
      real(dp), dimension(*) :: psij
      real(dp), dimension(*) :: d2j
c     keep an option for ifr 1 and ioptjas 0 so we don't play with iwf
      if (nforce.gt.1) then
        if(ifr.gt.1.or.ioptjas.eq.0) then
          call jastrow4(x,fjo(1,1,1),d2o(1),fsumo(1),fso(1,1,1),fijo(1,1,1,1),d2ijo(1,1,1))
          psij(1)=fsumo(1)
          d2j(1)=d2o(1)
          do i=1,nelec
            v(1,i,1)=fjo(1,i,1)
            v(2,i,1)=fjo(2,i,1)
            v(3,i,1)=fjo(3,i,1)
          enddo
        else
          call deriv_jastrow4(x,fjo(1,1,1),d2o(1),fsumo(1),fso(1,1,1),
     &                        fijo(1,1,1,1),d2ijo(1,1,1),g(1,1,1,1),
     &                        go(1,1,1,1),d2g(1,1),gvalue(1,1))
          psij(1)=fsumo(1)
          d2j(1)=d2o(1)
          do i=1,nelec
            v(1,i,1)=fjo(1,i,1)
            v(2,i,1)=fjo(2,i,1)
            v(3,i,1)=fjo(3,i,1)
          enddo
        endif
      else
        if(ioptjas.eq.0) then
          if(nwftypejas.eq.1) then
            iwf=1
            call jastrow4(x,fjo(1,1,1),d2o(1),fsumo(1),fso(1,1,1),fijo(1,1,1,1),d2ijo(1,1,1))
            psij(1)=fsumo(1)
            d2j(1)=d2o(1)
            do i=1,nelec
              v(1,i,1)=fjo(1,i,1)
              v(2,i,1)=fjo(2,i,1)
              v(3,i,1)=fjo(3,i,1)
            enddo
          elseif(nwftypejas.gt.1) then
            do iwf=1,nwftypejas
              call jastrow4(x,fjo(1,1,iwf),d2o(iwf),fsumo(iwf),fso(1,1,iwf),
     &                      fijo(1,1,1,iwf),d2ijo(1,1,iwf))
              psij(iwf)=fsumo(iwf)
              d2j(iwf)=d2o(iwf)
              do i=1,nelec
                v(1,i,iwf)=fjo(1,i,iwf)
                v(2,i,iwf)=fjo(2,i,iwf)
                v(3,i,iwf)=fjo(3,i,iwf)
              enddo
            enddo
          endif
        elseif(ioptjas.gt.0) then
          if(nwftypejas.eq.1) then
            iwf=1
            call deriv_jastrow4(x,fjo(1,1,1),d2o(1),fsumo(1),fso(1,1,1),
     &                          fijo(1,1,1,1),d2ijo(1,1,1),g(1,1,1,1),
     &                          go(1,1,1,1),d2g(1,1),gvalue(1,1))
            psij(1)=fsumo(1)
            d2j(1)=d2o(1)
            do i=1,nelec
              v(1,i,1)=fjo(1,i,1)
              v(2,i,1)=fjo(2,i,1)
              v(3,i,1)=fjo(3,i,1)
            enddo
          elseif(nwftypejas.gt.1) then
            do iwf=1,nwftypejas
              call deriv_jastrow4(x,fjo(1,1,iwf),d2o(iwf),fsumo(iwf),
     &                            fso(1,1,iwf),fijo(1,1,1,iwf),
     &                            d2ijo(1,1,iwf),g(1,1,1,iwf),go(1,1,1,iwf),
     &                           d2g(1,iwf),gvalue(1,iwf))
              psij(iwf)=fsumo(iwf)
              d2j(iwf)=d2o(iwf)
              do i=1,nelec
                v(1,i,iwf)=fjo(1,i,iwf)
                v(2,i,iwf)=fjo(2,i,iwf)
                v(3,i,iwf)=fjo(3,i,iwf)
              enddo
            enddo
          endif
        endif
      endif

      return
      end
      end module
