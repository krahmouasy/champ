module dumper_gpop_mod
contains
      subroutine dumper_gpop
! MPI version created by Claudia Filippi starting from serial version
! routine to pick up and dump everything needed to restart
! job where it left off

      use age, only: iage, ioldest, ioldestmx
      use basis, only: zex
      use branch, only: eest, eigv, ff, fprod, nwalk, wdsumo, wgdsumo, wt, wtgen
      use coefs, only: nbasis
      use config, only: xold_dmc
      use constants, only: hb
      use contrldmc, only: idmc, nfprod, rttau, tau
      use contrl_file,    only: ounit
      use control_dmc, only: dmc_nconf
      use dmc_mod, only: MWALK
      use estcum, only: iblk, ipass
      use estcum, only: ecum1_dmc, ecum_dmc, efcum, efcum1, egcum, egcum1
      use estcum, only: pecum_dmc, taucum, tpbcum_dmc
      use estcum, only: wcum1, wcum_dmc, wfcum, wfcum1, wgcum, wgcum1
      use est2cm, only: ecm21_dmc, ecm2_dmc, efcm2, efcm21, egcm2, egcm21
      use est2cm, only: pecm2_dmc, tpbcm2_dmc, wcm2, wcm21
      use est2cm, only: wfcm2, wfcm21, wgcm2, wgcm21
      use jacobsave, only: ajacob
      use mpiconf, only: idtask, nproc, wid
      use mpi
      use multiple_geo, only: fgcm2, fgcum, nforce, pecent
      use precision_kinds, only: dp
      use qua, only: nquad, wq, xq, yq, zq
      use velratio, only: fratio
      use random_mod, only: savern
      use pseudo, only: nloc
      use slater,  only: cdet,coef,ndet,norb
      use stats, only: acc, dfus2ac, dfus2un, nacc, nbrnch, nodecr, trymove
      use stats,   only: nodecr,trymove
      use strech_mod, only: strech
      use system, only: cent, iwctype, ncent, nctype, znuc, nelec, ndn, nup, newghostype, nghostcent

      implicit none

      integer :: i, ib, ic, id, ierr
      integer :: ifr, irequest, iw, j
      integer :: k, nscounts
      integer, dimension(8, 0:nproc) :: irn
      integer, dimension(MPI_STATUS_SIZE) :: istatus
      integer, dimension(8, 0:nproc) :: irn_tmp

      real(dp), parameter :: zero = 0.d0
      real(dp), parameter :: one = 1.d0



      if(nforce.gt.1) call strech(xold_dmc,xold_dmc,ajacob,1,0)

      call savern(irn(1,idtask))

      nscounts=8
      call mpi_gather(irn(1,idtask),nscounts,mpi_integer &
      ,irn_tmp,nscounts,mpi_integer,0,MPI_COMM_WORLD,ierr)

      if(.not.wid) then
        call mpi_isend(nwalk,1,mpi_integer,0 &
        ,1,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(xold_dmc,3*nelec*nwalk,mpi_double_precision,0 &
        ,2,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(wt,nwalk,mpi_double_precision,0 &
        ,3,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(fratio,MWALK*nforce,mpi_double_precision,0 &
        ,4,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(iage,nwalk,mpi_integer,0 &
        ,5,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(xq,nquad,mpi_double_precision,0 &
        ,6,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(yq,nquad,mpi_double_precision,0 &
        ,7,MPI_COMM_WORLD,irequest,ierr)
        call mpi_isend(zq,nquad,mpi_double_precision,0 &
        ,8,MPI_COMM_WORLD,irequest,ierr)
       else
        open(unit=10,status='unknown',form='unformatted',file='restart_dmc')
        write(10) nproc
        write(10) nfprod,(ff(i),i=0,nfprod),fprod,eigv,eest,wdsumo &
        ,ioldest,ioldestmx
        write(10) nwalk
        write(10) (wt(i),i=1,nwalk),(iage(i),i=1,nwalk)
        write(10) (((xold_dmc(ic,i,iw,1),ic=1,3),i=1,nelec),iw=1,nwalk)
        write(10) nforce,((fratio(iw,ifr),iw=1,nwalk),ifr=1,nforce)
        if(nloc.gt.0) &
        write(10) nquad,(xq(i),yq(i),zq(i),wq(i),i=1,nquad)
!       if(nforce.gt.1) write(10) nwprod
!    &  ,((pwt(i,j),i=1,nwalk),j=1,nforce)
!    &  ,(((wthist(i,l,j),i=1,nwalk),l=0,nwprod-1),j=1,nforce)
        do id=1,nproc-1
          call mpi_recv(nwalk,1,mpi_integer,id &
          ,1,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(xold_dmc,3*nelec*nwalk,mpi_double_precision,id &
          ,2,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(wt,nwalk,mpi_double_precision,id &
          ,3,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(fratio,MWALK*nforce,mpi_double_precision,id &
          ,4,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(iage,nwalk,mpi_integer,id &
          ,5,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(xq,nquad,mpi_double_precision,id &
          ,6,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(yq,nquad,mpi_double_precision,id &
          ,7,MPI_COMM_WORLD,istatus,ierr)
          call mpi_recv(zq,nquad,mpi_double_precision,id &
          ,8,MPI_COMM_WORLD,istatus,ierr)
          write(10) nwalk
          write(10) (wt(i),i=1,nwalk),(iage(i),i=1,nwalk)
          write(10) (((xold_dmc(ic,i,iw,1),ic=1,3),i=1,nelec),iw=1,nwalk)
          write(10) nforce,((fratio(iw,ifr),iw=1,nwalk),ifr=1,nforce)
          if(nloc.gt.0) &
          write(10) nquad,(xq(i),yq(i),zq(i),wq(i),i=1,nquad)
!         if(nforce.gt.1) write(10) nwprod
!    &    ,((pwt(i,j),i=1,nwalk),j=1,nforce)
!    &    ,(((wthist(i,l,j),i=1,nwalk),l=0,nwprod-1),j=1,nforce)
        enddo
      endif

      if(.not.wid) return

      write(10) (wgcum(i),egcum(i),pecum_dmc(i),tpbcum_dmc(i) &
      ,wgcm2(i),egcm2(i),pecm2_dmc(i),tpbcm2_dmc(i),taucum(i) &
      ,i=1,nforce)
      write(10) ((irn_tmp(i,j),i=1,8),j=0,nproc-1)
      write(10) hb
      write(10) tau,rttau,idmc
      write(10) nelec,dmc_nconf
      write(10) (wtgen(i),i=0,nfprod),wgdsumo
      write(10) wcum_dmc,wfcum,wcum1,wfcum1,(wgcum1(i),i=1,nforce), &
                ecum_dmc,efcum,ecum1_dmc,efcum1,(egcum1(i),i=1,nforce)
      write(10) ipass,iblk
      write(10) wcm2,wfcm2,wcm21,wfcm21,(wgcm21(i),i=1,nforce),ecm2_dmc,efcm2, &
                ecm21_dmc,efcm21,(egcm21(i),i=1,nforce)
      write(10) (fgcum(i),i=1,nforce),(fgcm2(i),i=1,nforce)
      write(10) dfus2ac,dfus2un,acc,trymove,nacc,nbrnch,nodecr

      write(10) ((coef(ib,i,1),ib=1,nbasis),i=1,norb)
      write(10) nbasis
      write(10) (zex(ib,1),ib=1,nbasis)
      write(10) nctype,ncent,newghostype,nghostcent,(iwctype(i),i=1,ncent+nghostcent)
      write(10) ((cent(k,ic),k=1,3),ic=1,ncent+nghostcent)
      write(10) pecent
      write(10) (znuc(i),i=1,nctype)
      write(10) (cdet(i,1,1),i=1,ndet)
      write(10) ndet,nup,ndn
      close (unit=10)
      write(ounit,'(1x,''successful dump to unit 10'')')

      return
      end
end module
