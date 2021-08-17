      subroutine mc_configs_start

      use mpi
      use atom, only: znuc, iwctype, ncent, ncent_tot
      use const, only: nelec
      use config, only: xnew, xold
      use mpiconf, only: idtask, nproc
      !use contrl, only: irstar, isite, nconf_new, icharged_atom
      use control_vmc, only: vmc_irstar, vmc_isite, vmc_nconf_new, vmc_icharged_atom
      use mpi
      use contrl_file,    only: ounit, errunit
      use precision_kinds, only: dp

      implicit none

      interface
        function rannyu(idum)
           use precision_kinds, only: dp
           implicit none
           integer,intent(in) :: idum
           real(dp) :: rannyu
        end function rannyu
      end interface

      integer :: i, ic, icharge_system, id, ierr
      integer :: index, k, l, ntotal_sites
      integer, dimension(4) :: irn
      integer, dimension(ncent_tot) :: nsite
      integer, dimension(MPI_STATUS_SIZE) :: istatus
      integer, dimension(4) :: irn_temp
      real(dp) :: err, rnd
      character*20 filename

c set the random number seed differently on each processor
c call to setrn must be in read_input since irn local there
      if(vmc_irstar.ne.1) then

c         if(idtask.ne.0) then
c          call mpi_isend(irn,4,mpi_integer,0,1,MPI_COMM_WORLD,irequest,ierr)
c         else
c          write(ounit,*) 0, irn
c          do 1 id=1,nproc-1
c            call mpi_recv(irn_temp,4,mpi_integer,id,1,MPI_COMM_WORLD,istatus,ierr)
c            write(ounit,*) id, irn_temp
c   1      continue
c         endif

        if(nproc.gt.1) then
          do 5 id=1,(3*nelec)*idtask
    5       rnd=rannyu(0)
          call savern(irn)
          do 6 i=1,4
    6       irn(i)=mod(irn(i)+int(rannyu(0)*idtask*9999),9999)
          call setrn(irn)
        endif

c check sites flag if one gets initial configuration from sites routine
        if (vmc_isite.eq.1) goto 20
        open(unit=9,err=20,file='mc_configs_start')
        rewind 9
        do 10 id=0,idtask
   10     read(9,*,end=20,err=20) ((xold(k,i),k=1,3),i=1,nelec)
        write(ounit,'(/,''initial configuration from unit 9'')')
        goto 40

   20   continue
	ntotal_sites=0
        do 25 i=1,ncent
   25     ntotal_sites=ntotal_sites+int(znuc(iwctype(i))+0.5d0)
        icharge_system=ntotal_sites-nelec

        l=0
        do 30 i=1,ncent
          nsite(i)=int(znuc(iwctype(i))+0.5d0)
          if (vmc_icharged_atom.eq.i) then
            nsite(i)=int(znuc(iwctype(i))+0.5d0)-icharge_system
	    if (nsite(i).lt.0) call fatal_error('MC_CONFIG: error in icharged_atom')
	  endif
          l=l+nsite(i)
          if (l.gt.nelec) then
            nsite(i)=nsite(i)-(l-nelec)
            l=nelec
          endif
   30   continue
        if (l.lt.nelec) nsite(1)=nsite(1)+(nelec-l)

        call sites(xold,nelec,nsite)
        open(unit=9,file='mc_configs_start')
        rewind 9

        write(ounit,'(/,''initial configuration from sites'')')
   40   continue

c If we are moving one electron at a time, then we need to initialize
c xnew, since only the first electron gets initialized in metrop
        do 50 i=1,nelec
          do 50 k=1,3
   50       xnew(k,i)=xold(k,i)
      endif

c If nconf_new > 0 then we want to dump configurations for a future
c optimization or dmc calculation. So figure out how often we need to write a
c configuration to produce nconf_new configurations. If nconf_new = 0
c then set up so no configurations are written.
      if (vmc_nconf_new.gt.0) then
        if(idtask.lt.10) then
          write(filename,'(i1)') idtask
         elseif(idtask.lt.100) then
          write(filename,'(i2)') idtask
         elseif(idtask.lt.1000) then
          write(filename,'(i3)') idtask
         else
          write(filename,'(i4)') idtask
        endif
        filename='mc_configs_new'//filename(1:index(filename,' ')-1)
        open(unit=7,form='formatted',file=filename)
        rewind 7
      endif
      call pcm_qvol(nproc)
      return

c-----------------------------------------------------------------------
      entry mc_configs_write

      if(idtask.ne.0) then
        call mpi_send(xold,3*nelec,mpi_double_precision,0
     &  ,1,MPI_COMM_WORLD,ierr)
c    &  ,1,MPI_COMM_WORLD,irequest,ierr)
       else
        rewind 9
        write(9,*) ((xold(ic,i),ic=1,3),i=1,nelec)
        do 60 id=1,nproc-1
          call mpi_recv(xnew,3*nelec,mpi_double_precision,id
     &    ,1,MPI_COMM_WORLD,istatus,ierr)
   60     write(9,*) ((xnew(ic,i),ic=1,3),i=1,nelec)
      endif
      close(9)

c reduce cum1 estimates, density and related quantities
      call fin_reduce

      return
      end
