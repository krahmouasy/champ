      subroutine optx_jas_orb_reduce
c Written by Claudia Filippi

      use optorb_mod, only: mxreduced
      use optwf_parms, only: nparmj
      use csfs, only: nstates
      use optwf_contrl, only: ioptjas, ioptorb
      use optwf_parms, only: nparmj
      use mix_jas_orb, only: de_o, dj_ho, dj_o, dj_oe
      use method_opt, only: method
      use mpi
      use precision_kinds, only: dp

      implicit none

      integer :: i, ierr, istate, j, nreduced
      real(dp), dimension(nparmj,mxreduced) :: collect


      if(ioptjas.eq.0.or.ioptorb.eq.0.or.method.eq.'sr_n'.or.method.eq.'lin_d') return

      do 40 istate=1,nstates

        call mpi_reduce(dj_o(1,1,istate),collect,nparmj*nreduced
     &       ,mpi_double_precision,mpi_sum,0,MPI_COMM_WORLD,ierr)

        call mpi_bcast(collect,nparmj*nreduced
     &       ,mpi_double_precision,0,MPI_COMM_WORLD,ierr)

        do 10 j=1,nreduced
          do 10 i=1,nparmj
  10       dj_o(i,j,istate)=collect(i,j)

        call mpi_reduce(dj_oe(1,1,istate),collect,nparmj*nreduced
     &       ,mpi_double_precision,mpi_sum,0,MPI_COMM_WORLD,ierr)

        call mpi_bcast(collect,nparmj*nreduced
     &       ,mpi_double_precision,0,MPI_COMM_WORLD,ierr)

        do 20 j=1,nreduced
          do 20 i=1,nparmj
  20       dj_oe(i,j,istate)=collect(i,j)

        call mpi_reduce(de_o(1,1,istate),collect,nparmj*nreduced
     &       ,mpi_double_precision,mpi_sum,0,MPI_COMM_WORLD,ierr)

        call mpi_bcast(collect,nparmj*nreduced
     &       ,mpi_double_precision,0,MPI_COMM_WORLD,ierr)

        do 30 j=1,nreduced
          do 30 i=1,nparmj
  30       de_o(i,j,istate)=collect(i,j)

        call mpi_reduce(dj_ho(1,1,istate),collect,nparmj*nreduced
     &       ,mpi_double_precision,mpi_sum,0,MPI_COMM_WORLD,ierr)

        call mpi_bcast(collect,nparmj*nreduced
     &       ,mpi_double_precision,0,MPI_COMM_WORLD,ierr)

        do 40 j=1,nreduced
          do 40 i=1,nparmj
  40       dj_ho(i,j,istate)=collect(i,j)

      call mpi_barrier(MPI_COMM_WORLD,ierr)

      return
      end
