module timestep_module


   ! Time steps in XBeach
   !
   ! Relevant time variables
   !
   ! [Main time loop]
   ! tstop: stop time simulation (set in params, used in boundaryconditions groundwater output params readtide readwind timestep varoutput waveparams xbeach)
   !
   ! [Output]
   ! tint: time interval output global values (set in params, used in nonhydrostatic output params timestep timestep_old, varoutput)
   !
   ! tintg: time interval output global values  (set in params, used in params timestep)
   ! tintm: time interval output mean global values (set in params timestep varoutput, used in params timestep varianceupdate varoutput)
   ! tintp: time interval output point values (set in params, used in drifters params timestep)
   !
   ! tsglobal: file with list of output times for global values (set in timestep, used in timestep)
   ! tsmean: file with list of output times for meanglobal values (set in timestep, used in timestep)
   ! tspoints: file with list of output times for point values (set in timestep, used in timestep)
   !
   ! tnext: (set in params timestep timestep_old varoutput, used in params timestep timestep_old varoutput)
   !
   ! [Hydrodynamic]
   ! tstart: start time of simulation (or output?!)  (set in params, used in nonhydrostatic output params timestep)
   ! CFL: maximum courant number (set in params, used in params timestep timestep_old)
   !
   ! [Boundary condition]
   ! rt:   the record length of the boundary condition (set in params, waveparams, used in boundaryconditions params timestep waveparams)
   ! dtbc:  boundary condition file time step dtbc (set in params, waveparams, used in params timestep waveparams)
   ! taper: time to spin up wave boundary conditions (set in params, used in  nonhydrostatic output params timestep timestep_old varoutput)
   !
   ! [Morphology]
   ! morfac: (set in params, used in boundaryconditions morphevolution params readtide readwind timestep varoutput waveparams)
   ! morstart: (set in params, used in morphevolution params timestep)
   !
   ! [Waves]
   ! wavint: interval between stationary wave module calls (set in params, used in params timestep xbeach)
   !
   ! [Tides]
   ! tidelen: length of tidal record (set in params readtide, used in boundaryconditions params readtide timestep)
   ! tideloc: number of input tidal time series (set in boundaryconditions groundwater params, used in boundaryconditions groundwater initialize params readtide timestep)
   !
   ! Relevant Time functions and subroutines
   ! outputtimes_update
   !
   !      XBeach time loop
   !      0                                                                                    tstop[s]
   !      |------------------------------------------------------------------------------------------|
   !
   !      Hydrodynamic time scale flow_timestep(input: par%dt, output:s%hh)
   !      |--------------------|------------------|------------------|---------------|--------|------|
   !      The hydrodynamic timeloop computes at varying intervals.
   !      The interval (input:s%hh, par%CFL, par%dt, par%xz, s%nx, s%xz, s%nx, output=par%dt) is computed
   !      in timestep module
   !
   !      The morphodynamic time scale(input: par%dt, par%morstart, p%morfac)
   !                  |--------|------------------|------------------|---------------|--------|------|
   !      This scale can start at a different point in time (morstart) and uses a multiplication factor
   !      (morfac [s/s] (>=1)).
   !
   !      Wave time scale
   !      |----------------|----------------|----------------|----------------|----------------|-----|
   !      At different time scales using wavint.
   !      Wave dispersion
   !                       |
   !      Only calculated if par%t == par%dt
   !
   !      Global output time scale fixed interval (tintg)
   !      |---------------------------|---------------------------|---------------------------|-------
   !
   !      Mean output time scale fixed interval (tintm)
   !      |------------------------|------------------------|------------------------|----------------
   !
   !      Point out time scale fixed inteval(tintp)
   !      |---------------------------------|---------------------------------|------------------------
   !
   !      Global output time scale varying interval (tsglobal)
   !      |--------------------|-----------|---------------|-|-|------------|-------------|-------------
   !
   !      Global output time scale varying interval (tsmean)
   !      |-----------------|-----------|-----------|-|-|------------|-------------|--------------------
   !
   !      Global output time scale varying interval (tspoint)
   !      |-------------------------|-----------|---------------|-|-|------------|-------------|--------
   !
   !      Boundary condition length [s] (rt)
   !      |-------------|-------------|-------------|-------------|-------------|-------------|----------

   implicit none
   save

   ! This structure contains the time variables which are computed during the simulation.
   ! Parameters which can be configured by users should go in params structure.
   type timepars
      real*8,dimension(:),allocatable     :: tpg ! global output times
      real*8,dimension(:),allocatable     :: tpp ! point oputput times
      real*8,dimension(:),allocatable     :: tpm ! time average output times
      real*8,dimension(:),allocatable     :: tpc ! crosssection output times
      real*8,dimension(:),allocatable     :: tpw ! wave computation times
      real*8 :: tnext     = -123                 ! next time point for output

      integer                             :: itg ! global output index (1 based)
      integer                             :: itp ! point output index (1 based)
      integer                             :: itm ! time average output index (1 based)
      integer                             :: itc ! cross section output index (1 based)
      integer                             :: itw ! wave computation index (1 based)

      logical                             :: outputg ! output global variables?
      logical                             :: outputp ! output point variables?
      logical                             :: outputm ! output time average variables?
      logical                             :: outputc ! output cross section variables?
      logical                             :: outputw ! stop for wave computation
      logical                             :: output  ! output any variable
   end type timepars



contains

   subroutine timestep_init(par, tpar)
      use params
      use xmpi_module
      use readkey_module
      use logging_module
      implicit none

      type(parameters),intent(inout)      :: par
      type(timepars),intent(inout)        :: tpar

      real*8                              :: iir
      integer                             :: i,ii,ier
      !character(80)                       :: fname

#ifdef USEMPI
      logical, parameter :: toall = .true.
      logical, parameter :: tocomp = .false.
#endif

      ! initialize the time to 0
      par%t = 0.0d0

      tpar%tnext = 0.0d0
      ! initialize timestep counters
      tpar%itg = 0
      tpar%itp = 0
      tpar%itm = 0
      tpar%itc = 0
      tpar%itw = 0
      ! initialize output, default no output
      tpar%outputg = .FALSE.
      tpar%outputp = .FALSE.
      tpar%outputm = .FALSE.
      tpar%outputc = .FALSE.
      tpar%outputw = .FALSE.
      tpar%output  = .FALSE.


      !!!!! OUTPUT TIME POINTS !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! If working in instat 0 or instat 40 we want time to coincide at wavint timesteps
      if (par%instat==INSTAT_STAT .or. par%instat==INSTAT_STAT_TABLE .or. par%single_dir==1) then
         if(xmaster) then
            ii=ceiling(par%tstop/par%wavint)
            allocate(tpar%tpw(ii))
            do i=1,ii
               tpar%tpw(i)=real(i)*par%wavint
            enddo
         endif
#ifdef USEMPI
         call xmpi_bcast(ii,toall)
         if (.not.xmaster) then
            allocate(tpar%tpw(ii))
         endif
         call xmpi_bcast(tpar%tpw,toall)
#endif
      else
         allocate(tpar%tpw(0))
      endif

      ! If we want global output then
      if (par%nglobalvar/=0) then
         if(xmaster) then
            if (par%tsglobal/=' ') then
               open(10,file=par%tsglobal)
               read(10,*,iostat=ier)iir
               if (ier .ne. 0) then
                  call report_file_read_error(par%tsglobal)
               endif
               ii = nint(iir)
               allocate(tpar%tpg(ii))
               do i=1,ii
                  read(10,*,iostat=ier)tpar%tpg(i)
                  if (ier .ne. 0) then
                     call report_file_read_error(par%tsglobal)
                  endif
               enddo
               tpar%tpg=tpar%tpg/max(par%morfac,1.d0)
               close(10)
            else
               ii=floor((par%tstop-par%tstart)/par%tintg)+1
               allocate(tpar%tpg(ii))
               do i=1,ii
                  tpar%tpg(i)=par%tstart+par%tintg*real(i-1)
               enddo
            endif
         endif  !xmaster
#ifdef USEMPI
         call xmpi_bcast(ii,toall)
         if (.not.xmaster) then
            allocate(tpar%tpg(ii))
         endif
         call xmpi_bcast(tpar%tpg,toall)
#endif
      else
         allocate(tpar%tpg(0))
      endif ! nglobalvar /=0

      ! If we want point output then
      if ((par%npoints+par%nrugauge+par%ndrifter)>0) then
         if (xmaster) then
            if (par%tspoints/=' ') then
               open(10,file=par%tspoints)
               read(10,*,iostat=ier)iir
               if (ier .ne. 0) then
                  call report_file_read_error(par%tspoints)
               endif
               ii = nint(iir)
               allocate(tpar%tpp(ii))
               do i=1,ii
                  read(10,*,iostat=ier)tpar%tpp(i)
                  if (ier .ne. 0) then
                     call report_file_read_error(par%tspoints)
                  endif
               enddo
               tpar%tpp=tpar%tpp/max(par%morfac,1.d0)
               close(10)
            else
               ii=floor((par%tstop-par%tstart)/par%tintp)+1
               allocate(tpar%tpp(ii))
               do i=1,ii
                  tpar%tpp(i)=par%tstart+par%tintp*real(i-1)
               enddo
            endif
         endif    ! xmaster
#ifdef USEMPI
         call xmpi_bcast(ii,toall)
         if (.not.xmaster) then
            allocate(tpar%tpp(ii))
         endif
         call xmpi_bcast(tpar%tpp,toall)
#endif
      else
         allocate(tpar%tpp(0))
      endif ! (npoints+nrugauge)>0

      ! If we want cross section output then
      if ((par%ncross)>0) then
         if (xmaster) then
            if (par%tscross/=' ') then
               open(10,file=par%tscross)
               read(10,*,iostat=ier)iir
               if (ier .ne. 0) then
                  call report_file_read_error(par%tscross)
               endif
               ii = nint(iir)
               allocate(tpar%tpc(ii))
               do i=1,ii
                  read(10,*,iostat=ier)tpar%tpc(i)
                  if (ier .ne. 0) then
                     call report_file_read_error(par%tscross)
                  endif
               enddo
               close(10)
            else
               ii=floor((par%tstop-par%tstart)/par%tintc)+1
               allocate(tpar%tpc(ii))
               do i=1,ii
                  tpar%tpc(i)=par%tstart+par%tintc*real(i-1)
               enddo
            endif
         endif    ! xmaster
#ifdef USEMPI
         call xmpi_bcast(ii,toall)
         if (.not.xmaster) then
            allocate(tpar%tpc(ii))
         endif
         call xmpi_bcast(tpar%tpc,toall)
#endif
      else
         allocate(tpar%tpc(0))
      endif ! (ncross)>0

      ! If we want time-average output then
      if (par%nmeanvar>0) then
         if(xmaster) then
            if (par%tsmean/=' ') then
               open(10,file=par%tsmean)
               read(10,*,iostat=ier)iir
               if (ier .ne. 0) then
                  call report_file_read_error(par%tsmean)
               endif
               ii = nint(iir)
               allocate(tpar%tpm(ii))
               do i=1,ii
                  read(10,*,iostat=ier)tpar%tpm(i)
                  if (ier .ne. 0) then
                     call report_file_read_error(par%tsmean)
                  endif
               enddo
               tpar%tpm=tpar%tpm/max(par%morfac,1.d0)
               close(10)
            else
               ii=floor((par%tstop-par%tstart)/par%tintm)+1
               if (ii<=1) then
                  call writelog('lse','','Tintm is larger than output simulation time ')
                  call halt_program
               endif
               allocate(tpar%tpm(ii))
               do i=1,ii
                  tpar%tpm(i)=par%tstart+par%tintm*real(i-1)
               enddo
            endif
         endif
#ifdef USEMPI
         call xmpi_bcast(ii,toall)
         if (.not.xmaster) then
            allocate(tpar%tpm(ii))
         endif
         call xmpi_bcast(tpar%tpm,toall)
#endif
      else
         allocate(tpar%tpm(0))

      endif  ! nmeanvar > 0

   end subroutine timestep_init


   subroutine outputtimes_update(par, tpar)
      use params
      use xmpi_module
      use logging_module
      implicit none
      type(parameters),intent(inout)      :: par
      type(timepars), intent(inout)       :: tpar
      real*8                              :: t1,t2,t3,t4,t5

      !if (tpar%outputm .or. tpar%itm .eq. 0) then
      !   par%tintm = tpar%tpm(min(tpar%itm+2,size(tpar%tpm)))-tpar%tpm(tpar%itm+1)
      !   par%tintm = max(par%tintm,tiny(0.d0))
      !end if

      ! Current timestep:
      ! check if we need output at the current timestep
      ! do we have anymore  output time points, is it equal to the current?
      if (size(tpar%tpg) .gt. 0) then
         tpar%outputg = abs(tpar%tpg(min(tpar%itg+1,size(tpar%tpg)))-par%t) .le. 0.0000001d0
         ! if global output has last output before tstop, this minimum is necessary
      endif
      if (size(tpar%tpp) .gt. 0) then
         tpar%outputp = abs(tpar%tpp(min(tpar%itp+1,size(tpar%tpp)))-par%t) .le. 0.0000001d0
      endif
      if (size(tpar%tpc) .gt. 0) then
         tpar%outputc = abs(tpar%tpc(min(tpar%itc+1,size(tpar%tpc)))-par%t) .le. 0.0000001d0
      endif
      if (size(tpar%tpm) .gt. 0) then
         tpar%outputm = abs(tpar%tpm(min(tpar%itm+1,size(tpar%tpm)))-par%t) .le. 0.0000001d0
      endif
      if (size(tpar%tpw) .gt. 0) then
         tpar%outputw = abs(tpar%tpw(min(tpar%itw+1,size(tpar%tpw)))-par%t) .le. 0.0000001d0
      endif

      !  tpar%outputg = (size(tpar%tpg) .gt. tpar%itg) .and. (abs(tpar%tpg(tpar%itg+1)-par%t) .le. 0.0000001d0)
      !  tpar%outputp = (size(tpar%tpp) .gt. tpar%itp) .and. (abs(tpar%tpp(tpar%itp+1)-par%t) .le. 0.0000001d0)
      !  tpar%outputm = (size(tpar%tpm) .gt. tpar%itm) .and. (abs(tpar%tpm(tpar%itm+1)-par%t) .le. 0.0000001d0)
      !  tpar%outputc = (size(tpar%tpc) .gt. tpar%itc) .and. (abs(tpar%tpc(tpar%itc+1)-par%t) .le. 0.0000001d0)
      !  tpar%outputw = (size(tpar%tpw) .gt. tpar%itw) .and. (abs(tpar%tpw(tpar%itw+1)-par%t) .le. 0.0000001d0)
      tpar%output  = (tpar%outputg .or. tpar%outputp .or. tpar%outputm .or. tpar%outputc .or. tpar%outputw)

      ! if we are updating at the current timestep, increase the counter by 1
      !
      ! update output counter
      if (tpar%outputg) tpar%itg = tpar%itg + 1
      if (tpar%outputp) tpar%itp = tpar%itp + 1
      if (tpar%outputm) tpar%itm = tpar%itm + 1
      if (tpar%outputc) tpar%itc = tpar%itc + 1
      if (tpar%outputw) tpar%itw = tpar%itw + 1

      ! Next time step:
      ! calculate the output for the following time
      ! this routine computes the next timestep at which output should be generated
      ! Determine next time step
      t1=minval(tpar%tpg,MASK=tpar%tpg .gt. par%t+0.0000001d0)
      t2=minval(tpar%tpp,MASK=tpar%tpp .gt. par%t+0.0000001d0)
      t3=minval(tpar%tpm,MASK=tpar%tpm .gt. par%t+0.0000001d0)
      t4=minval(tpar%tpw,MASK=tpar%tpw .gt. par%t+0.0000001d0)
      t5=minval(tpar%tpc,MASK=tpar%tpc .gt. par%t+0.0000001d0)

      tpar%tnext=min(t1,t2,t3,t4,t5,par%tstop)

      if (tpar%tnext .eq. huge(tpar%tpg) .and. par%t .eq. 0) then
         call writelog('ls','', 'no output times found, setting tnext to tstop')
         tpar%tnext = par%tstop
      end if

   end subroutine outputtimes_update


   subroutine timestep(s,par, tpar, it, dt, ierr)
      use params
      use spaceparams
      use xmpi_module
      use logging_module
      use paramsconst

      IMPLICIT NONE

      type(spacepars), intent(inout)   :: s
      type(parameters), intent(inout)  :: par
      type(timepars), intent(inout)    :: tpar
      integer, intent(inout)           :: it
      integer, intent(out), optional   :: ierr
      real*8, intent(in), optional :: dt
      integer                     :: i,ilim
      integer                     :: j,j1,j2,jlim
      integer                     :: n,limtype
      real*8                              :: mdx,mdy,tny,fac
      real*8,save                         :: dtref,dtold

      if(.not. xcompute) return

      limtype = 0

      ! Super fast 1D
      if (s%ny==0) then
         j1 = 1
      else
         j1 = 2
      endif

      ! Calculate dt based on the Courant number.
      ! Check when we need next output.
      ! Next time step will be, min(output times, t+dt)

      if (present(ierr)) then
         ierr = 0
      endif
      tny = tiny(0.d0)

      ! Robert new time step criterion
      if (par%t<=0.0d0) then          ! conservative estimate
         par%dt    = par%CFL*min(minval(s%dsu(1:s%nx+1,1:s%ny+1)),   &
         minval(s%dnv(1:s%nx+1,1:s%ny+1)))   &
         /sqrt(maxval(s%hh)*par%g)
         dtref = 0.d0
         if (tpar%tnext > par%dt) then
            n = ceiling((tpar%tnext-par%t)/par%dt)
            par%dt = (tpar%tnext-par%t)/n
         end if
      else
         par%dt=huge(0.0d0)      ! Seed dt
         dtold = par%dt
         limtype = 0
         if (s%ny>2) then
            do j=2,s%ny
               do i=2,s%nx
                  if(s%wetu(i,j)==1) then
                     ! u-points
                     mdx=s%dsu(i+1,j)
                     mdy=min(s%dnv(i,j),s%dnv(i,j-1))
                     ! x-component
                     par%dt=min(par%dt,mdx/max(tny,max(sqrt(par%g*s%hu(i,j))+abs(s%uu(i,j)),abs(s%ueu(i,j))))) !Jaap: include sediment advection velocities
                     ! y-component
                     par%dt=min(par%dt,mdy/max(tny,(sqrt(par%g*s%hu(i,j))+abs(s%vu(i,j)))))
                     if (par%dt<dtold) then
                        ilim = i
                        jlim = j
                        limtype = 1
                        dtold = par%dt
                     endif
                  endif
                  if(s%wetv(i,j)==1) then
                     ! v-points
                     mdx=min(s%dsu(i,j),s%dsu(i-1,j))
                     mdy=s%dnv(i,j)
                     ! x-component
                     par%dt=min(par%dt,mdx/max(tny,(sqrt(par%g*s%hv(i,j))+abs(s%uv(i,j)))))
                     ! y-component
                     par%dt=min(par%dt,mdy/max(tny,max(sqrt(par%g*s%hv(i,j))+abs(s%vv(i,j)),abs(s%vev(i,j))))) !Jaap: include sediment advection velocities

                     if (par%dt<dtold) then
                        ilim = i
                        jlim = j
                        limtype = 2
                        dtold = par%dt
                     endif
                  endif
                  if(s%wetz(i,j)==1) then
                     mdx = min(s%dsu(i,j),s%dsz(i,j))**2
                     mdy = min(s%dnv(i,j),s%dnz(i,j))**2

                     par%dt=min(par%dt,0.5d0*mdx*mdy/(mdx+mdy)/max(s%nuh(i,j),1e-6))

                     if (par%dt<dtold) then
                        ilim = i
                        jlim = j
                        limtype = 3
                        dtold = par%dt
                     endif

                     !Bas: the following criterion is not yet tested for 2D
                     !par%dt=min(par%dt,0.5d0*mdx/max(s%Dc(i,j)*s%wetz(i,j),1e-6))
                     !par%dt=min(par%dt,0.5d0*mdy/max(s%Dc(i,j)*s%wetz(i,j),1e-6))
                  endif
               enddo
            enddo
         else
            j2=max(s%ny,1)  ! Robert: hmmm, in sf1D this should be 1, in "old" 1d this should be 2
            do i=2,s%nx
               if(s%wetu(i,j2)==1) then
                  ! u-points
                  mdx=s%dsu(i,j2)
                  par%dt=min(par%dt,mdx/max(tny,max(sqrt(par%g*s%hu(i,j2))+abs(s%uu(i,j2)),abs(s%ueu(i,j2))))) !Jaap: include sediment advection velocities
                  if (par%dt<dtold) then
                     ilim = i
                     jlim = j2
                     limtype = 1
                     dtold = par%dt
                  endif
               endif
               if(s%wetz(i,j2)==1) then
                  ! v-points
                  mdx=min(s%dsu(i,j2),s%dsu(i-1,j2))
                  par%dt=min(par%dt,mdx/max(tny,(sqrt(par%g*s%hv(i,j2))+abs(s%uv(i,j2)))))
                  if (par%dt<dtold) then
                     ilim = i
                     jlim = j2
                     limtype = 2
                     dtold = par%dt
                  endif

                  mdx = min(s%dsu(i,j2),s%dsz(i,j2))**2

                  if (par%dy > 0.d0) then
                     mdy = par%dy
                  else
                     mdy = mdx
                  endif

                  par%dt=min(par%dt,0.5d0*mdx*mdy/(mdx+mdy)/max(s%nuh(i,j2),1e-6))
                  if (par%dt<dtold) then
                     ilim = i
                     jlim = j
                     limtype = 3
                     dtold = par%dt
                  endif
                  if (par%sedtrans==1) then
                     par%dt=min(par%dt,0.5d0*mdx/max(s%Dc(i,j2)*s%wetz(i,j2),1e-6))
                  endif
               endif
            enddo
         endif

         if (s%ny>0) then
            par%dt=par%dt*par%CFL*0.5d0
         else
            par%dt=par%dt*par%CFL*0.5d0
         endif

         ! groundwater stability
         if (par%gwflow==1 .and. par%gwnonh==0) then
            j2=max(s%ny,1)
            do j=j1,j2
               do i=2,s%nx
                  ! Vreugdenhil:
                  ! 2*kx*gwheight*dt/dx2 < CFL   -> dt = (CFL*dx2)/(2*kx*gwheight)
                  ! par%dt=min(par%dt,par%CFL*s%dsc(i,j)**2/(2*par%kx*s%gwheight(i,j)))
                  !
                  ! Wikipedia: http://en.wikipedia.org/wiki/Von_Neumann_stability_analysis for FTCS:
                  ! 2*a*dt/dx2 < 1 , where dh/dt = a *d2h/dx2 -> a = k/por
                  ! 2*k/por*dt/dx2 = CFL -> dt = CFL*dx2*por/2/k
                  par%dt=min(par%dt,par%CFL*s%dsc(i,j)**2*par%por/(2*par%kx))
                  if (par%dt<dtold) then
                     ilim = i
                     jlim = j
                     limtype = 4
                     dtold = par%dt
                  endif
               enddo
            enddo
            if (par%ny>2) then
               do j=j1,j2
                  do i=2,s%nx
                     ! 2*ky*gwheight*dt/dy2 < CFL   -> dt = (CFL*dy2)/(2*ky*gwheight)
                     ! par%dt=min(par%dt,par%CFL*s%dnc(i,j)**2/(2*par%ky*s%gwheight(i,j)))
                     par%dt=min(par%dt,par%CFL*s%dnc(i,j)**2*par%por/(2*par%ky))
                     if (par%dt<dtold) then
                        ilim = i
                        jlim = j
                        limtype = 4
                        dtold = par%dt
                     endif
                  enddo
               enddo
            endif
         endif

         if (par%swave==1) then
#ifdef USEMPI
            ! Dano: no refraction if ntheta==1 so no need for this check
            if (s%ntheta>1) then
               par%dt=min(par%dt,par%CFL*s%dtheta/(maxval(maxval(abs(s%ctheta),3)*real(s%wetz))+tny))
            endif
#else
            ! if (par%instat(1:4)/='stat') then
            ! wwvv: hoping that this is a correct translation:
            select case (par%instat)
             case(INSTAT_STAT,INSTAT_STAT_TABLE)
               continue
             case default
               par%dt=min(par%dt,par%CFL*s%dtheta/(maxval(maxval(abs(s%ctheta),3)*real(s%wetz))+tny))
            end select
#endif
         endif
         !To avoid large timestep differences due to output, which can cause instabities
         !in the hanssen (leapfrog) scheme, we smooth the timestep.

         if (tpar%tnext > par%t) then
            n = ceiling((tpar%tnext-par%t)/par%dt)
            par%dt = (tpar%tnext-par%t)/n
         end if
      end if ! first, or other time step

      if (dtref .eq. 0.0d0) then
         ! If dtref is not yet set.
         dtref = par%dt
#ifdef USEMPI
         ! Use the same dtref everywhere.
         call xmpi_allreduce(dtref,MPI_MIN)
#endif
      end if

      ! wwvv: In the mpi version par%dt will be calculated different
      ! on different processes. So, we take the minimum of all dt's
#ifdef USEMPI
      call xmpi_allreduce(par%dt,MPI_MIN)
#endif

      ! maximize dt with given dt
      if (present(dt)) then
         par%dt = min(dt, par%dt)
      end if

      par%t=par%t+par%dt

      if(par%t >= tpar%tnext) then
         par%dt  = par%dt-(par%t-tpar%tnext)
         par%t   = tpar%tnext
         it      = it+1
      end if

      ! Sometimes dtref is set incorrectly in intialization. We want to stop sudden changes
      ! in time step size, so allow dtref to change slowely to current situations. If simulation
      ! requires smaller timestep due to e.g. overwash, this should not stop the simulation.
      ! Errors occur in O(1-10) timesteps. Therefore filter on O(1000-10000) timesteps
      fac = 1.d0/5000
      dtref = (1.d0-fac)*dtref + fac*par%dt

      if (((dtref/par%dt>par%maxdtfac .and. par%t<tpar%tnext) .or. par%dt/dtref>par%maxdtfac) &
           .and. par%defuse==1) then
         
         call writelog('lswe','','Quit XBeach since computational time implodes/explodes')
         call writelog('lswe','','Please check output at the end of the simulation')
         select case (limtype)
          case (1)
            call writelog('lswe','(a,i0,a,i0,a)','U-velocities are too high in cell (',ilim,',',jlim,')(M,N)')
          case (2)
            call writelog('lswe','(a,i0,a,i0,a)','V-velocities are too high in cell (',ilim,',',jlim,')(M,N)')
          case (3)
            call writelog('lswe','(a,i0,a,i0,a)','Viscosity condition is too high in cell (',ilim,',',jlim,')(M,N)')
          case (4)
            call writelog('lswe','(a,i0,a,i0,a)','Groundwater condition is too high in cell (',ilim,',',jlim,')(M,N)')
         end select
         call writelog('lswe','','dtref: ',dtref)
         call writelog('lswe','','par%dt: ',par%dt)

         ! Force output before exit in main time loop
         tpar%outputg = (size(tpar%tpg) .gt. 0)
         tpar%outputp = (size(tpar%tpp) .gt. 0)
         tpar%outputm = (size(tpar%tpm) .gt. 0)
         tpar%outputc = (size(tpar%tpc) .gt. 0)
         ! set output time to current time
         if (tpar%outputg) tpar%tpg=min(tpar%tpg,par%t)
         if (tpar%outputp) tpar%tpp=min(tpar%tpp,par%t)
         if (tpar%outputm) tpar%tpm=min(tpar%tpm,par%t)
         if (tpar%outputc) tpar%tpc=min(tpar%tpc,par%t)
         tpar%output = (tpar%outputg .or. tpar%outputp .or. tpar%outputm .or. tpar%outputc)
         if (present(ierr)) then
            ierr = 1
         endif
      endif

   end subroutine timestep
end module timestep_module
