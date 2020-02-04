!--------------------------------------------------------------------------------------------------!
! O92UTIL
!
! Utility for computing displacements, strains, and stresses in an elastic half-space resulting from
! point source and rectangular shear dislocations. Most of the heavy lifting is done in the module
! OKADA92_MODULE.F90.
!
! References
! Okada, Y. (1992) Internal deformation due to shear and tensile faults in a half-space. Bulletin of
! the Seismological Society of America, vol. 82, no. 2, pp. 1018-1040.
!--------------------------------------------------------------------------------------------------!

module o92util

! Fault inputs
character(len=512) :: ffm_file                    ! source faults: USGS .param format
character(len=512) :: fsp_file                    ! source faults: SRCMOD FSP format
character(len=512) :: mag_file                    ! source faults: ... mag format
character(len=512) :: flt_file                    ! source faults: ... slip wid len format
logical :: isFaultFileDefined                     ! input fault tag
character(len=16) :: fault_type                   ! point or finite source tag
character(len=16) :: empirical_relation           ! conversion from magnitude to slip wid len
double precision :: slip_threshold                ! minimum slip to calculate (NOT USED)

! Station/target/receiver inputs
character(len=512) :: station_file                ! station locations
logical :: isStationFileDefined                   ! station location tag
double precision :: auto_depth                    ! depth of automatically generated station grid
integer :: auto_n                                 ! number of automatically generated stations (1d)
logical :: autoStations                           ! automatic station tag
character(len=512) :: target_file                 ! target/receiver fault geometry
logical :: isTargetFileDefined                    ! target fault tag

! Elastic half-space inputs
character(len=512) :: halfspace_file              ! elastic half-space parameters
double precision :: poisson                       ! poisson's ratio
double precision :: lame                          ! lame parameter
double precision :: shearmod                      ! shear modulus

! Outputs
character(len=512) :: displacement_file           ! output: displacement
character(len=4) :: disp_output_mode              ! enz, amz
character(len=512) :: disp_file_save              ! temporary displacement file
character(len=512) :: strain_file                 ! output: strain tensor
character(len=512) :: stress_file                 ! output: stress tensor
character(len=512) :: estress_file                ! output: effective (maximum) shear stress
character(len=512) :: normal_file                 ! output: normal stress
character(len=512) :: shear_file                  ! output: shear stress (resolved, maximum)
character(len=512) :: coulomb_file                ! output: coulomb stress
logical :: isOutputFileDefined                    ! output file tag
logical :: iWantDisp                              ! displacement calculation tag
logical :: iWantStrain                            ! strain calculation tag
logical :: iWantStress                            ! stress calculation tag
logical :: iWantTraction                          ! traction calculation tag
character(len=16) :: coord_type                   ! cartesian-m, cartesian-km, geographic
logical :: iWantProg                              ! progress indicator tag

! Program variables
integer :: nfaults                                ! Number of fault sources
integer :: nstations                              ! Number of stations/targets/receivers
double precision, allocatable :: faults(:,:)      ! Fault parameter array
double precision, allocatable :: stations(:,:)    ! Station location array
double precision, allocatable :: targets(:,:)     ! Target/receiver geometry array

end module

!==================================================================================================!

program main

use o92util, only: isOutputFileDefined, &
                   autoStations

implicit none

call gcmdln()
if (.not.isOutputFileDefined) then
    call usage('o92util: no output defined')
endif

call read_halfspace()
call read_faults()

if (autoStations) then
    call auto_stations()
endif

call read_stations()
call read_targets()
call calc_deformation()

if (autoStations) then
    call update_auto_stations()
    call calc_deformation()
endif

end


!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!------------------------------------------- INPUTS -----------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

subroutine read_halfspace()
!----
! Read half-space parameters with the subroutine read_halfspace_file in the elast module.
!----
use elast, only: read_halfspace_file
use o92util, only: halfspace_file, &
                   poisson, &
                   lame, &
                   shearmod
implicit none
call read_halfspace_file(halfspace_file,poisson,shearmod,lame)
return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine read_faults()
!----
! Read the input rectangular or point fault source data in one of the following formats:
!     mag: lon lat dep str dip rak mag
!     flt: lon lat dep str dip rak slip wid len
!     ffm: U.S. Geological Survey .param format
!     fsp: SRCMOD FSP format
!----

use io, only: stderr, line_count
use ffm, only: read_usgs_param, read_srcmod_fsp, read_mag, read_flt, ffm_data
use eq, only: empirical, sdr2ter, mag2mom

use o92util, only: ffm_file, &
                   fsp_file, &
                   mag_file, &
                   flt_file, &
                   isFaultFileDefined, &
                   empirical_relation, &
                   shearmod, &
                   coord_type, &
                   nfaults, &
                   faults

implicit none

! Local variables
integer :: ierr, i
logical :: areFaultsRead
type(ffm_data) :: param_data, fsp_data, mag_data, flt_data
character(len=8) :: fault_type
double precision :: fth, fss, fno, mom, area


! Initialize variables
areFaultsRead = .false.
nfaults = 0

! Check that a fault file is defined
if (.not.isFaultFileDefined) then
    call usage('read_faults: no fault file defined')
endif


! Read faults in one of available formats

! Read faults from USGS param file
if (ffm_file.ne.'') then
    call read_usgs_param(ffm_file,param_data,ierr)
    if (ierr.eq.0) then
        areFaultsRead = .true.
    endif
    nfaults = nfaults + param_data%nflt
endif

! Read faults from SRCMOD FSP file
if (fsp_file.ne.'') then
    call read_srcmod_fsp(fsp_file,fsp_data,ierr)
    if (ierr.eq.0) then
        areFaultsRead = .true.
    endif
    nfaults = nfaults + fsp_data%nflt
endif

! Read faults in GMT psmeca -Sa format
if (mag_file.ne.'') then
    call read_mag(mag_file,mag_data,ierr)
    if (ierr.eq.0) then
        areFaultsRead = .true.
    endif

    ! Calculate fault slip, width, and length
    do i = 1,mag_data%nflt

        ! Determine the type of focal mechanism for empirical relation
        call sdr2ter(mag_data%subflt(i,4),mag_data%subflt(i,5),mag_data%subflt(i,6),fth,fss,fno)
        if (fth.gt.0.60d0) then
            fault_type = 'th'
        elseif (fss.gt.0.60d0) then
            fault_type = 'ss'
        elseif (fno.gt.0.60d0) then
            fault_type = 'no'
        else
            fault_type = 'ot'
        endif

        ! Calculate width and length from empirical relation
        call empirical(mag_data%subflt(i,7),mag_data%subflt(i,8),mag_data%subflt(i,9),&
                       empirical_relation,fault_type)
        mag_data%subflt(i,8) = mag_data%subflt(i,8)*1.0d3 ! km->m
        mag_data%subflt(i,9) = mag_data%subflt(i,9)*1.0d3 ! km->m

        ! Calculate slip from seismic moment, area, and shear_modulus
        call mag2mom(mag_data%subflt(i,7),mom)
        area = mag_data%subflt(i,8)*mag_data%subflt(i,9)
        mag_data%subflt(i,7) = mom/(shearmod*area)
    enddo

    nfaults = nfaults + mag_data%nflt
endif

! Read faults in GMT psmeca -Sa format, except with slip wid len in place of magnitude
if (flt_file.ne.'') then
    call read_flt(flt_file,flt_data,ierr)
    if (ierr.eq.0) then
        areFaultsRead = .true.
    endif
    nfaults = nfaults + flt_data%nflt
endif


! Sanity check: make sure something has been read before proceeding
if (.not.areFaultsRead) then
    write(stderr,*) 'read_faults: no faults were read'
    call usage('check files specified by -mag, -flt, -ffm, or -fsp')
endif


! Allocate memory for master fault array
if (allocated(faults)) then
    deallocate(faults)
endif
allocate(faults(nfaults,9))


! Load the master array with the values read from files
nfaults = 0

if (fsp_file.ne.''.and.fsp_data%nflt.gt.0) then
    faults(nfaults+1:nfaults+fsp_data%nflt,:) = fsp_data%subflt(1:fsp_data%nflt,1:9)
    nfaults = nfaults + fsp_data%nflt
endif

if (ffm_file.ne.''.and.param_data%nflt.gt.0) then
    faults(nfaults+1:nfaults+param_data%nflt,:) = param_data%subflt(1:param_data%nflt,1:9)
    nfaults = nfaults + param_data%nflt
endif

if (flt_file.ne.''.and.flt_data%nflt.gt.0) then
    faults(nfaults+1:nfaults+flt_data%nflt,:) = flt_data%subflt
    nfaults = nfaults + flt_data%nflt
endif

if (mag_file.ne.''.and.mag_data%nflt.gt.0) then
    faults(nfaults+1:nfaults+mag_data%nflt,:) = mag_data%subflt
    nfaults = nfaults + mag_data%nflt
endif


! Check coordinates
if (coord_type.eq.'geographic'.and. &
        (maxval(abs(faults(:,1))).gt.360.0d0 .or. maxval(abs(faults(:,2))).gt.90.0d0)) then
    write(stderr,*) 'read_faults: found fault coordinates outside geographic range; ',&
                    'did you mean to use the -xy flag?'
endif

! do i = 1,nfaults
!     write(0,*) faults(i,:)
! enddo

return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine read_stations()
!----
! Read the input station file, in format:
!
!     x1 y1 z1
!
! where (x1,y1) are geographic or cartesian coordinates (depending on coord_type), and z1 is depth
! in km, positive down.
!----

use io, only: stderr, line_count, fileExists

use o92util, only: station_file, &
                   nstations, &
                   stations, &
                   isStationFileDefined, &
                   coord_type

implicit none

! Local variables
integer :: i, j, ios
character(len=512) :: input_line


! Check that station file is defined and the file exists
if (.not.isStationFileDefined) then
    call usage('read_stations: no station file defined')
endif
if (.not.fileExists(station_file)) then
    call usage('read_stations: no station file named '//trim(station_file)//' found')
endif


! Count number of stations and allocate memory to station array (x y z)
nstations = line_count(station_file)
allocate(stations(nstations,3))


! Read stations
open(unit=13,file=station_file,status='old')
do i = 1,nstations
    read(13,'(A)') input_line
    read(input_line,*,iostat=ios,err=1003,end=1004) (stations(i,j),j=1,3)
enddo
close(13)


! Check coordinates
if (coord_type.eq.'geographic'.and. &
        (maxval(abs(stations(:,1))).gt.360.0d0 .or. maxval(abs(stations(:,2))).gt.90.0d0)) then
    write(stderr,*) 'read_stations: found station coordinates outside geographic range; ',&
                    'did you mean to use the -xy flag?'
endif


! Error messages
1003 if (ios.ne.0) then
    write(stderr,*) 'read_stations: read error'
    call usage('offending line: '//trim(input_line))
endif
1004 if (ios.ne.0) then
    write(stderr,*) 'read_stations: line end'
    call usage('offending line: '//trim(input_line))
endif

return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine read_targets()
!----
! Read the input target fault geometry file, in format:
!     str dip rak fric
!----

use io, only: stderr, line_count, fileExists

use o92util, only: target_file, &
                   targets, &
                   isTargetFileDefined, &
                   iWantTraction, &
                   nstations

implicit none


! Local variables
integer :: i, j, ios, ntargets
character(len=512) :: input_line


! Check that tractions need to be resolved, target fault file is defined, and the file exists
if (.not.iWantTraction) then
    return
else
    if (.not.isTargetFileDefined) then
        call usage('read_targets: no target geometry file defined')
    endif
endif
if (.not.fileExists(target_file)) then
    call usage('read_targets: no target geometry file named '//trim(target_file)//' found')
endif


! Count number of target geometries and allocate memory to target array (str dip rak fric)
ntargets = line_count(target_file)
if (ntargets.ne.1.and.ntargets.ne.nstations) then
    call usage('read_targets: number of target geometries must be 1 or nstations')
endif
allocate(targets(nstations,4))


! Read target fault geometries
open(unit=14,file=target_file,status='old')
do i = 1,ntargets
    read(14,'(A)') input_line
    read(input_line,*,iostat=ios,err=1005,end=1006) (targets(i,j),j=1,4)
enddo
close(14)


! Fill target array if only one is specified
if (ntargets.eq.1) then
    do i = 2,nstations
        targets(i,:) = targets(1,:)
    enddo
endif


! Error messages
1005 if (ios.ne.0) then
    write(stderr,*) 'read_targets: read error'
    call usage('offending line: '//trim(input_line))
endif
1006 if (ios.ne.0) then
    write(stderr,*) 'read_targets: line end'
    call usage('offending line: '//trim(input_line))
endif

return
end subroutine


!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!----------------------------------------- OUTPUTS ------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

subroutine calc_deformation()
!----
! Calculate all requested deformation values at station locations.
!----

use io, only: stderr, verbosity, progress_indicator
use trig, only: d2r, r2d
use algebra, only: rotate_vector_angle_axis, rotate_matrix_angle_axis
use earth, only: radius_earth_m
use elast, only: strain2stress, stress2traction, max_shear_stress, traction_components
use eq, only: sdr2sv
use geom, only: lola2distaz, strdip2normal
use okada92, only: o92_pt_disp, o92_rect_disp, o92_pt_strain, o92_rect_strain

use o92util, only: iWantDisp, &
                   iWantStrain, &
                   iWantStress, &
                   iWantTraction, &
                   displacement_file, &
                   disp_output_mode, &
                   strain_file, &
                   stress_file, &
                   estress_file, &
                   normal_file, &
                   shear_file, &
                   coulomb_file, &
                   lame, &
                   shearmod, &
                   fault_type, &
                   coord_type, &
                   nfaults, &
                   nstations, &
                   faults, &
                   stations, &
                   targets, &
                   iWantProg

implicit none

! Local variables
integer :: ierr, iSta, iFlt, file_unit
logical :: isThisUnitOpen, coordTypeWarning
double precision :: evlo, evla, evdp, str, dip, rak, slip_mag, wid, len, slip(3), mom(4)
double precision :: sta_coord(3), dist, az, warn_dist
double precision :: disp(3), disptmp(3), stn(3,3), stntmp(3,3), sts(3,3), ests, trac(3), tshr, &
                    tshrmx, tnor, coul
double precision :: nvec(3), svec(3), tstr, tupd


! Check which calculations are specified and open output files if requested

! Displacement
if (iWantDisp) then
    if (verbosity.ge.1) then
        write(stderr,*) 'calc_deformation: calculating displacements'
    endif
    if (displacement_file.ne.'') then
        open(unit=101,file=displacement_file,status='unknown')
    endif
endif

! Strain
if (iWantStrain) then
    if (verbosity.ge.1) then
        write(stderr,*) 'calc_deformation: calculating strains'
    endif
    if (strain_file.ne.'') then
        open(unit=111,file=strain_file,status='unknown')
    endif
endif

! Stress
if (iWantStress) then
    if (verbosity.ge.1) then
        write(stderr,*) 'calc_deformation: calculating stresses'
    endif
    if (stress_file.ne.'') then
        open(unit=121,file=stress_file,status='unknown')
    endif
    if (estress_file.ne.'') then
        open(unit=122,file=estress_file,status='unknown')
    endif
endif

! Resolved tractions
if (iWantTraction) then
    if (verbosity.ge.1) then
        write(stderr,*) 'calc_deformation: calculating resolved tractions'
    endif
    if (normal_file.ne.'') then
        open(unit=131,file=normal_file,status='unknown')
    endif
    if (shear_file.ne.'') then
        open(unit=132,file=shear_file,status='unknown')
    endif
    if (coulomb_file.ne.'') then
        open(unit=133,file=coulomb_file,status='unknown')
    endif
endif


! Distance to trigger coordinate type warning
warn_dist = 500.0d0
coordTypeWarning = .false.

! Calculate the requested quantities at each station
do iSta = 1,nstations

    disp = 0.0d0
    stn = 0.0d0
    sta_coord(3) = stations(iSta,3)*1.0d3

    ! Superimpose deformation quantities produced by all fault sources at each station
    do iFlt = 1,nfaults

        ! Fault parameters
        evlo = faults(iFlt,1)
        evla = faults(iFlt,2)
        evdp = faults(iFlt,3)
        str = faults(iFlt,4)
        dip = faults(iFlt,5)
        rak = faults(iFlt,6)
        slip_mag = faults(iFlt,7)
        wid = faults(iFlt,8)
        len = faults(iFlt,9)

        ! Station location relative to fault at origin (ENZ coordinates)
        if (coord_type.eq.'geographic') then
            call lola2distaz(evlo,evla,stations(iSta,1),stations(iSta,2),dist,az, &
                        'radians','radians',ierr)

            ! Check distance for coordinate type errors; if user forgot the -xy flag to use
            ! Cartesian coordinates, then the calculated distance will be much higher than
            ! expected, for example:
            !     fault coordinates: (0,0)    }        geographic distance = 111.19 km
            !     station coordinates: (0,1)  }   =>   Cartesian distance = 1 km
            if (abs(dist*radius_earth_m).gt.warn_dist*1d3.and..not.coordTypeWarning) then
                write(stderr,*) 'calc_deformation: found fault-station distance >',warn_dist,'km'
                write(stderr,*) 'Are your coordinates geographic or did you mean to use the -xy flag?'
                coordTypeWarning = .true.
            endif

            sta_coord(1) = dist*radius_earth_m*sin(az)
            sta_coord(2) = dist*radius_earth_m*cos(az)

        elseif (coord_type.eq.'cartesian') then
            sta_coord(1) = (stations(iSta,1) - evlo)*1.0d3
            sta_coord(2) = (stations(iSta,2) - evla)*1.0d3

        else
            call usage('calc_deformation: no coordinate type named "'//trim(coord_type)//'"')
        endif

        ! Rotate coordinate axes so x is parallel to strike and y is horizontal up-dip
        call rotate_vector_angle_axis(sta_coord,str-90.0d0,'z',sta_coord,ierr)
        if (ierr.ne.0) then
            call usage('calc_deformation: error in rotating station coordinate axes to strike')
        endif

        ! Fault slip vector in strike-slip, dip-slip, and tensile-slip (NOT IMPLEMENTED)
        slip(1) = slip_mag*cos(rak*d2r)
        slip(2) = slip_mag*sin(rak*d2r)
        slip(3) = 0.0d0
        if (fault_type.eq.'point') then
            mom(1) = slip(1)*wid*len*shearmod
            mom(2) = slip(2)*wid*len*shearmod
            mom(3:4) = 0.0d0
        elseif (fault_type.eq.'rect') then
            ! Everything is set up for rectangular sources already
        else
            call usage('calc_deformation: no fault type named "'//trim(fault_type)//'"')
        endif

        ! Calculate deformation for each fault-station pair and add to total at current station
        ! Calculate displacement
        if (iWantDisp) then
            if (fault_type.eq.'point') then
                call o92_pt_disp(disptmp,sta_coord,evdp,dip,mom,lame,shearmod)
            elseif (fault_type.eq.'rect') then
                call o92_rect_disp(disptmp,sta_coord,evdp,dip,slip,wid,len,lame,shearmod)
            endif
            ! Rotate displacements back to x=E, y=N, z=up
            call rotate_vector_angle_axis(disptmp,90.0d0-str,'z',disptmp,ierr)
            if (ierr.ne.0) then
                call usage('calc_deformation: error in rotating displacement vector to ENV')
            endif
            ! Add to total
            disp = disp + disptmp
        endif

        ! Calculate strain
        if (iWantStrain) then
            if (fault_type.eq.'point') then
                call o92_pt_strain(stntmp,sta_coord,evdp,dip,mom,lame,shearmod)
            elseif (fault_type.eq.'rect') then
                call o92_rect_strain(stntmp,sta_coord,evdp,dip,slip,wid,len,lame,shearmod)
            endif
            ! Rotate strain tensor back to x=E, y=N, z=up
            call rotate_matrix_angle_axis(stntmp,90.0d0-str,'z',stntmp,ierr)
            if (ierr.ne.0) then
                call usage('calc_deformation: error in rotating strain tensor to ENV')
            endif
            ! Add to total
            stn = stn + stntmp
        endif
    enddo


    ! Displacement: ux, uy, uz
    if (displacement_file.ne.'') then
        if (disp_output_mode.eq.'enz') then
            write(101,*) stations(iSta,:),disp
        elseif (disp_output_mode.eq.'amz') then
            write(101,*) stations(iSta,:), &
                         atan2(disp(1),disp(2))*r2d, &
                         sqrt(disp(1)*disp(1)+disp(2)*disp(2)), &
                         disp(3)
        else
            write(stderr,*) 'calc_deformation: no displacement output mode named "',trim(disp_output_mode),'"'
        endif
    endif

    ! Strain tensor: exx, eyy, ezz, exy, exz, eyz
    if (strain_file.ne.'') then
        write(111,*) stations(iSta,:),stn(1,1),stn(2,2),stn(3,3),stn(1,2),stn(1,3),stn(2,3)
    endif

    ! Stress
    if (iWantStress) then
        call strain2stress(stn,lame,shearmod,sts)

        ! Stress tensor: sxx, syy, szz, sxy, sxz, syz
        if (stress_file.ne.'') then
            write(121,*) stations(iSta,:),sts(1,1),sts(2,2),sts(3,3),sts(1,2),sts(1,3),sts(2,3)
        endif

        ! Maximum (effective) shear stress: ests
        if (estress_file.ne.'') then
            call max_shear_stress(sts,ests)
            write(122,*) stations(iSta,:),ests
        endif
    endif

    if (iWantTraction) then
        ! Calculate components of traction resolved onto plane
        call sdr2sv(targets(iSta,1),targets(iSta,2),targets(iSta,3),svec)
        call strdip2normal(targets(iSta,1),targets(iSta,2),nvec)
        call stress2traction(sts,nvec,trac)
        call traction_components(trac,nvec,tnor,tstr,tupd)
        tshr = tstr*cos(targets(iSta,3)*d2r) + tupd*sin(targets(iSta,3)*d2r)

        ! Normal traction: normal (positive=dilation)
        if (normal_file.ne.'') then
            write(131,*) stations(iSta,:),tnor
        endif

        ! Shear traction: resolved_onto_rake, max_shear_on_plane
        if (shear_file.ne.'') then
            tshrmx = sqrt(tstr*tstr+tupd*tupd)
            write(132,*) stations(iSta,:),tshr,tshrmx
        endif

        ! Coulomb stress: coulomb
        if (coulomb_file.ne.'') then
            coul = tshr + targets(iSta,4)*tnor
            write(133,*) stations(iSta,:),coul
        endif
    endif

    if (iWantProg) then
        call progress_indicator(iSta,nstations,'o92util calc_deformation',ierr)
        if (ierr.ne.0) then
            call usage('calc_deformation: error in progress_indicator')
        endif
    endif
enddo

! Close files that were opened for writing
inquire(file=displacement_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=strain_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=stress_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=estress_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=normal_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=shear_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif
inquire(file=coulomb_file,number=file_unit,opened=isThisUnitOpen)
if (isThisUnitOpen) then
    close(file_unit)
endif

return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine auto_stations()

use earth, only: radius_earth_km
use geom, only: distaz2lola

use o92util, only: station_file, &
                   coord_type, &
                   nfaults, &
                   faults, &
                   auto_depth, &
                   displacement_file, &
                   disp_file_save, &
                   iWantDisp

implicit none

! Local variables
integer :: i, ierr
double precision :: centroid(3), moment, lon, lat, x, y, dx, dy

if (station_file.ne.'o92_autosta_86_this_when_finished') then
    return
else
    open(unit=81,file=station_file,status='unknown')
endif

! Calculate centroid
centroid = 0.0d0
moment = 0.0d0
do i = 1,nfaults
    centroid(1) = centroid(1) + faults(i,1)*faults(i,7)*faults(i,8)*faults(i,9)
    centroid(2) = centroid(2) + faults(i,2)*faults(i,7)*faults(i,8)*faults(i,9)
    centroid(3) = centroid(3) + faults(i,3)*faults(i,7)*faults(i,8)*faults(i,9)
    moment = moment + faults(i,7)*faults(i,8)*faults(i,9)
enddo
centroid = centroid/moment


! Get points 500 km north, south, east, and west of centroid
if (coord_type.eq.'geographic') then
    dx = -500.0d0
    do while (dx.le.500.0d0)
        call distaz2lola(centroid(1),centroid(2),dx/radius_earth_km,90.0d0,lon,lat, &
                         'radians','degrees',ierr)
        if (ierr.ne.0) then
            call usage('auto_stations: error computing longitude and latitude')
        endif
        write(81,*) lon,lat,auto_depth
        dx = dx + 1.0d0
    enddo
    dy = -500.0d0
    do while (dy.le.500.0d0)
        call distaz2lola(centroid(1),centroid(2),dy/radius_earth_km,0.0d0,lon,lat, &
                         'radians','degrees',ierr)
        write(81,*) lon,lat,auto_depth
        if (ierr.ne.0) then
            call usage('auto_stations: error computing longitude and latitude')
        endif
        dy = dy + 1.0d0
    enddo

elseif (coord_type.eq.'cartesian') then
    dx = -500.0d0
    do while (dx.le.500.0d0)
        x = centroid(1) + dx
        write(81,*) x,centroid(2),auto_depth
        dx = dx + 1.0d0
    enddo
    dy = -500.0d0
    do while (dy.le.500.0d0)
        y = centroid(2) + dy
        write(81,*) centroid(1),y,auto_depth
        dy = dy + 1.0d0
    enddo

endif

close(81)


disp_file_save = displacement_file
displacement_file = 'o92_autosta_disp_86_this_when_finished'
iWantDisp = .true.

return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine update_auto_stations()

use o92util, only: displacement_file, &
                   disp_file_save, &
                   station_file, &
                   nstations, &
                   stations, &
                   auto_n, &
                   auto_depth

implicit none

! Local variables
integer :: i, j
double precision :: disp(2002,6), xmin, xmax, ymin, ymax


if (station_file.ne.'o92_autosta_86_this_when_finished') then
    return
else
    open(unit=81,file=station_file,status='old')
    open(unit=82,file=displacement_file,status='old')
endif

! Read the displacements
do i = 1,2002
    read(82,*) (disp(i,j),j=1,6)
enddo


xmin = disp(1,1)
xmax = disp(1001,1)
ymin = disp(1002,2)
ymax = disp(2002,2)

! Find xmin
do i = 1,501
    if (sqrt(disp(i,4)**2+disp(i,5)**2+disp(i,6)**2).ge.0.001d0) then
        xmin = disp(i,1)
        exit
    endif
enddo

! Find xmax
do i = 501,1001
    if (sqrt(disp(i,4)**2+disp(i,5)**2+disp(i,6)**2).le.0.001d0) then
        xmax = disp(i,1)
        exit
    endif
enddo

! Find ymin
do i = 1002,1502
    if (sqrt(disp(i,4)**2+disp(i,5)**2+disp(i,6)**2).ge.0.001d0) then
        ymin = disp(i,2)
        exit
    endif
enddo

! Find ymax
do i = 1502,2002
    if (sqrt(disp(i,4)**2+disp(i,5)**2+disp(i,6)**2).le.0.001d0) then
        ymax = disp(i,2)
        exit
    endif
enddo

close(81,status='delete')
close(82,status='delete')


deallocate(stations)
nstations = auto_n*auto_n
allocate(stations(nstations,3))
do i = 1,auto_n
    do j = 1,auto_n
        stations((i-1)*auto_n+j,1) = xmin + dble(i-1)*(xmax-xmin)/dble(auto_n-1)
        stations((i-1)*auto_n+j,2) = ymin + dble(j-1)*(ymax-ymin)/dble(auto_n-1)
        stations((i-1)*auto_n+j,3) = auto_depth
    enddo
enddo

displacement_file = disp_file_save


return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine gcmdln()

use io, only: stdout, verbosity
use o92util, only: ffm_file, &
                   fsp_file, &
                   mag_file, &
                   flt_file, &
                   isFaultFileDefined, &
                   fault_type, &
                   empirical_relation, &
                   slip_threshold, &
                   station_file, &
                   isStationFileDefined, &
                   auto_depth, &
                   auto_n, &
                   autoStations, &
                   target_file, &
                   isTargetFileDefined, &
                   halfspace_file, &
                   poisson, &
                   lame, &
                   shearmod, &
                   displacement_file, &
                   disp_output_mode, &
                   strain_file, &
                   stress_file, &
                   estress_file, &
                   normal_file, &
                   shear_file, &
                   coulomb_file, &
                   isOutputFileDefined, &
                   iWantDisp, &
                   iWantStrain, &
                   iWantStress, &
                   iWantTraction, &
                   coord_type, &
                   iWantProg

implicit none

! Local variables
character(len=512) tag
integer :: i, narg

! Initialize control variables
ffm_file = ''
fsp_file = ''
flt_file = ''
mag_file = ''
isFaultFileDefined = .false.
fault_type = 'rect'
empirical_relation = 'WC'
slip_threshold = 0.0d0

station_file = ''
isStationFileDefined = .false.
autoStations = .false.
auto_depth = 0.0d0
auto_n = 10
target_file = ''
isTargetFileDefined = .false.

halfspace_file = ''
poisson = 0.25d0
lame = 40.0d9
shearmod = 40.0d9

displacement_file = ''
disp_output_mode = 'enz'
strain_file = ''
stress_file = ''
estress_file = ''
normal_file = ''
shear_file = ''
coulomb_file = ''
isOutputFileDefined = .false.
iWantDisp = .false.
iWantStrain = .false.
iWantStress = .false.
iWantTraction = .false.

coord_type = 'geographic'

verbosity = 0
iWantProg = .false.


narg = command_argument_count()
if (narg.eq.0) then
    call usage('')
endif

i = 1
do while (i.le.narg)

    call get_command_argument(i,tag)

    ! Input fault options
    if (trim(tag).eq.'-ffm') then
        i = i + 1
        call get_command_argument(i,ffm_file)
        isFaultFileDefined = .true.

    elseif (trim(tag).eq.'-fsp') then
        i = i + 1
        call get_command_argument(i,fsp_file)
        isFaultFileDefined = .true.

    elseif (trim(tag).eq.'-mag') then
        i = i + 1
        call get_command_argument(i,mag_file)
        isFaultFileDefined = .true.

    elseif (trim(tag).eq.'-flt') then
        i = i + 1
        call get_command_argument(i,flt_file)
        isFaultFileDefined = .true.

    elseif (trim(tag).eq.'-fn') then
        fault_type = 'rect'
    elseif (trim(tag).eq.'-pt') then
        fault_type = 'point'

    elseif (trim(tag).eq.'-empirical'.or.trim(tag).eq.'-emp') then
          i = i + 1
          call get_command_argument(i,empirical_relation)

    elseif (trim(tag).eq.'-thr') then
        i = i + 1
        call get_command_argument(i,tag)
        read(tag,*) slip_threshold


    ! Input receiver options
    elseif (trim(tag).eq.'-sta') then
        i = i + 1
        call get_command_argument(i,station_file)
        isStationFileDefined = .true.

    elseif (trim(tag).eq.'-auto') then
        station_file = 'o92_autosta_86_this_when_finished'
        isStationFileDefined = .true.
        autoStations = .true.
        i = i + 1
        call get_command_argument(i,tag)
        read(tag,*) auto_depth
        i = i + 1
        call get_command_argument(i,tag)
        read(tag,*) auto_n

    elseif (trim(tag).eq.'-trg') then
        i = i + 1
        call get_command_argument(i,target_file)
        isTargetFileDefined = .true.


    ! Input half-space options
    elseif (trim(tag).eq.'-haf') then
        i = i + 1
        call get_command_argument(i,halfspace_file)


    ! Output deformation options
    elseif (trim(tag).eq.'-disp') then
        i = i + 1
        call get_command_argument(i,displacement_file)
        isOutputFileDefined = .true.
        iWantDisp = .true.

    elseif (trim(tag).eq.'-strain') then
        i = i + 1
        call get_command_argument(i,strain_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.

    elseif (trim(tag).eq.'-stress') then
        i = i + 1
        call get_command_argument(i,stress_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.
        iWantStress = .true.

    elseif (trim(tag).eq.'-estress') then
        i = i + 1
        call get_command_argument(i,estress_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.
        iWantStress = .true.

    elseif (trim(tag).eq.'-normal') then
        i = i + 1
        call get_command_argument(i,normal_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.
        iWantStress = .true.
        iWantTraction = .true.

    elseif (trim(tag).eq.'-shear'.or.trim(tag).eq.'-shearmax') then
        i = i + 1
        call get_command_argument(i,shear_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.
        iWantStress = .true.
        iWantTraction = .true.

    elseif (trim(tag).eq.'-coul') then
        i = i + 1
        call get_command_argument(i,coulomb_file)
        isOutputFileDefined = .true.
        iWantStrain = .true.
        iWantStress = .true.
        iWantTraction = .true.


    ! Miscellaneous options
    elseif (trim(tag).eq.'-cartesian'.or.trim(tag).eq.'-xy') then
        coord_type = 'cartesian'
    elseif (trim(tag).eq.'-geographic'.or.trim(tag).eq.'-geo') then
        coord_type = 'geographic'

    elseif (tag.eq.'-az') then
        disp_output_mode = 'amz'

    elseif (trim(tag).eq.'-v'.or.trim(tag).eq.'-verbose'.or.trim(tag).eq.'-verbosity') then
        i = i + 1
        call get_command_argument(i,tag)
        read(tag,*) verbosity

    elseif (trim(tag).eq.'-prog') then
        iWantProg = .true.

    else
        call usage('o92util: no option '//trim(tag))
    endif

    i = i + 1
enddo

if (verbosity.eq.3) then
    write(stdout,*) 'gcmdln: finished parsing the command line'
    write(stdout,*) 'ffm_file:                 ',trim(ffm_file)
    write(stdout,*) 'fsp_file:                 ',trim(fsp_file)
    write(stdout,*) 'flt_file:                 ',trim(flt_file)
    write(stdout,*) 'mag_file:                 ',trim(mag_file)
    write(stdout,*) 'isFaultFileDefined:       ',isFaultFileDefined
    write(stdout,*) 'fault_type:               ',trim(fault_type)
    write(stdout,*) 'empirical_relation:       ',trim(empirical_relation)
    ! write(stdout,*) 'slip_threshold:           ',slip_threshold
    write(stdout,*) 'station_file:             ',trim(station_file)
    write(stdout,*) 'isStationFileDefined:     ',isStationFileDefined
    write(stdout,*) 'auto_depth:               ',auto_depth
    write(stdout,*) 'auto_n:                   ',auto_n
    write(stdout,*) 'target_file:              ',trim(target_file)
    write(stdout,*) 'isTargetFileDefined:      ',isTargetFileDefined
    write(stdout,*) 'halfspace_file:           ',trim(halfspace_file)
    write(stdout,*) 'poisson:                  ',poisson
    write(stdout,*) 'lame:                     ',lame
    write(stdout,*) 'shearmod:                 ',shearmod
    write(stdout,*) 'displacement_file:        ',trim(displacement_file)
    write(stdout,*) 'disp_output_mode:         ',trim(disp_output_mode)
    write(stdout,*) 'strain_file:              ',trim(strain_file)
    write(stdout,*) 'stress_file:              ',trim(stress_file)
    write(stdout,*) 'estress_file:             ',trim(estress_file)
    write(stdout,*) 'normal_file:              ',trim(normal_file)
    write(stdout,*) 'shear_file:               ',trim(shear_file)
    write(stdout,*) 'coulomb_file:             ',trim(coulomb_file)
    write(stdout,*) 'isOutputFileDefined:      ',isOutputFileDefined
    write(stdout,*) 'iWantDisp:                ',iWantDisp
    write(stdout,*) 'iWantStrain:              ',iWantStrain
    write(stdout,*) 'iWantStress:              ',iWantStress
    write(stdout,*) 'iWantTraction:            ',iWantTraction
    write(stdout,*) 'coord_type:               ',trim(coord_type)
    write(stdout,*) 'prog:                     ',iWantProg
endif

return
end subroutine

!--------------------------------------------------------------------------------------------------!

subroutine usage(str)

use io, only: stderr

implicit none

! Arguments
character(len=*) :: str

if (str.ne.'') then
    write(stderr,*) trim(str)
    write(stderr,*)
endif

write(stderr,*) 'Usage: o92util ...options...'
write(stderr,*)
write(stderr,*) 'Input fault options'
write(stderr,*) '-ffm FFMFILE         Fault file in USGS .param format'
write(stderr,*) '-fsp FSPFILE         Fault file in SRCMOD FSP format'
write(stderr,*) '-mag MAGFILE         Fault file in "psmeca -Sa" format (...mag)'
write(stderr,*) '-flt FLTFILE         Fault file with slip and dimensions (...slip wid len)'
write(stderr,*) '-fn|-pt              Treat faults as finite rectangular (default) or point'
write(stderr,*) '-empirical OPT       Empirical scaling relation'
! write(stderr,*) '-thr THR             Minimum slip threshold'
write(stderr,*)
write(stderr,*) 'Input receiver options'
write(stderr,*) '-sta STAFILE         Station/receiver locations'
write(stderr,*) '-auto DEPTH N        Generate automatic location grid'
write(stderr,*) '-trg TRGFILE         Target/receiver geometry'
write(stderr,*)
write(stderr,*) 'Input half-space options'
write(stderr,*) '-haf HAFSPCFILE      Elastic half-space properties'
write(stderr,*)
write(stderr,*) 'Output options'
write(stderr,*) '-disp DSPFILE        Displacement (E N Z)'
write(stderr,*) '-strain STNFILE      Strain matrix (EE NN ZZ EN EZ NZ)'
write(stderr,*) '-stress STSFILE      Stress matrix (EE NN ZZ EN EZ NZ)'
write(stderr,*) '-estress ESTSFILE    Effective (maximum) shear stress'
write(stderr,*) '-normal NORFILE      Normal traction on target faults (requires -trg)'
write(stderr,*) '-shear SHRFILE       Shear traction on target faults (requires -trg)'
write(stderr,*) '-coul COULFILE       Coulomb stress on target faults (requires -trg)'
write(stderr,*)
write(stderr,*) 'Miscellaneous options'
write(stderr,*) '-geo|-xy             Use geographic (default) or cartesian coordinates'
write(stderr,*) '-az                  Displacement vector outputs (AZ HMAG Z)'
write(stderr,*) '-prog                Turn on progress indicator'
write(stderr,*) '-v LVL               Turn on verbose mode'
write(stderr,*)
write(stderr,*) 'See man page for details'
write(stderr,*)

stop
end subroutine
