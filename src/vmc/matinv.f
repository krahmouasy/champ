      subroutine matinv(a,nsub,determinant)
      use vmc_mod, only: MELEC, MORB, MBASIS, MDET, MCENT, MCTYPE, MCTYP3X
      use vmc_mod, only: NSPLIN, nrad, MORDJ, MORDJ1, MMAT_DIM, MMAT_DIM2, MMAT_DIM20
      use vmc_mod, only: radmax, delri
      use vmc_mod, only: NEQSX, MTERMS
      use vmc_mod, only: MCENT3, NCOEF, MEXCIT
      use const, only: nelec
      use precision_kinds, only: dp
      implicit none

      integer :: i, info, nsub
      integer, dimension(nsub) :: ipvt
      real(dp) :: aux, determinant, deti
      real(dp) :: ten
      real(dp), dimension(nsub, nsub) :: a
      real(dp), dimension(nsub) :: work

      real(dp), dimension(2) :: det
      real(dp), parameter :: eps = 10.d0**(-40)
      integer :: ii,jj
c routine to calculate inverse and determinant of matrix a
c assumed to be dimensioned a(nsub,nsub).
c the matrix a is replaced by its inverse.


      if(nsub.eq.1) then
        determinant=a(1,1)
        a(1,1)=1.0d0/a(1,1)
       elseif(nsub.eq.2) then
        determinant=a(1,1)*a(2,2)-a(1,2)*a(2,1)
        deti=1.d0/determinant
        aux=a(1,1)
        a(1,1)= a(2,2)*deti
        a(2,2)= aux   *deti
        a(2,1)=-a(2,1)*deti
        a(1,2)=-a(1,2)*deti
       else

        call dgetrf(nsub,nsub,a,nsub,ipvt,info)

        if(info.gt.0) then
          write(6,'(''MATINV: u(k,k)=0 with k= '',i5)') info
          call fatal_error('MATINV: info ne 0 in dgetrf')

        endif

        det(1) = 1.0d0
        det(2) = 0.0d0
        ten = 10.0d0
        do 50 i = 1, nsub
          if (ipvt(i) .ne. i) det(1) = -det(1)
          det(1) = a(i,i)*det(1)
c        ...exit
          if (det(1) .eq. 0.0d0) go to 60
   10     if (dabs(det(1)) .ge. 1.0d0) go to 20
          det(1) = ten*det(1)
          det(2) = det(2) - 1.0d0
          go to 10
   20     continue
   30     if (dabs(det(1)) .lt. ten) go to 40
            det(1) = det(1)/ten
            det(2) = det(2) + 1.0d0
          go to 30
   40     continue
   50   continue
   60   continue

        determinant = det(1)*10.0**det(2)

        call dgetri(nsub,a,nsub,ipvt,work,nelec,info)

      endif

      return

      end

