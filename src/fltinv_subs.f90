subroutine read_fltinv_inputs()
!----
! Read the input files and initialize the inversion parameters
!----
use io_module, only: stderr, verbosity, read_program_data_file
use variable_module, only: inversion_mode, &
                           displacement, prestress, los, fault, &
                           gf_type, gf_disp, gf_stress, gf_los, &
                           smoothing, rake_constraint, slip_constraint, &
                           halfspace, coord_type
use elast, only: calc_plane_unit_vectors, calc_traction, calc_traction_components
use tri_disloc_module, only: tri_geometry, tri_geo2cart
implicit none
! Local variables
integer :: i, ios
double precision :: stress(3,3), nor(3), str(3), upd(3), traction(3), traction_comp(3), dist, az, &
                    pt1(3), pt2(3), pt3(3)
character(len=256) :: line

if (verbosity.ge.1) then
    write(stderr,'(A)') 'read_fltinv_inputs says: starting'
endif


!----
! Either displacement/los or pre-stress data is required
!----
if (displacement%file.eq.'none'.and.prestress%file.eq.'none'.and.los%file.eq.'none') then
    call print_usage('!! read_fltinv_inputs: no displacement or pre-stress file defined')
else
    if (displacement%file.ne.'none') then
        displacement%nfields = 6 ! x y z ux uy uz
        call read_program_data_file(displacement)
    endif
    if (prestress%file.ne.'none') then
        prestress%nfields = 6 ! sxx syy szz sxy sxz syz
        call read_program_data_file(prestress)
    endif
    if (los%file.ne.'none') then
        los%nfields = 6 ! x y z ulos az inc
        call read_program_data_file(los)
    endif
endif


!----
! Fault file is required
!----
if (fault%file.eq.'none') then
    call print_usage('!! read_fltinv_inputs: no fault file defined')
else
    ! If Green's functions are pre-computed, we only need to read the number of lines
    if (gf_disp%file.ne.'none'.and.displacement%file.ne.'none') then
        fault%nfields = 1
    elseif(gf_stress%file.ne.'none'.and.prestress%file.ne.'none') then
        fault%nfields = 1

    ! If we need to compute Green's functions, the fault file needs to be in the right format
    elseif (gf_type.eq.'okada_rect') then
        fault%nfields = 7
    elseif (gf_type.eq.'okada_pt') then
        fault%nfields = 6
    elseif (gf_type.eq.'triangle') then
        fault%nfields = 9

    ! Need to have Green's functions for an inversion
    else
        call print_usage('!! read_fltinv_inputs: neither GF computation mode nor precomputed '//&
                         'GFs are defined')
    endif

    ! Read the fault data
    call read_program_data_file(fault)

    ! Check that fault depth, dimensions/area seem roughly right
    if (maxval(fault%array(:,3)).lt.1000.0d0) then
        write(0,'(A)') '!! Warning: fault depths all less than +1000 m'
        write(0,'(A)') '!! Make sure depth units are meters, positive down'
    endif
    if (gf_type.eq.'okada_rect') then
        if (maxval(fault%array(:,6)).lt.100.0d0.and.maxval(fault%array(:,7)).lt.100.0d0) then
            write(0,'(A)') '!! Warning: fault dimensions all less than 100 m'
            write(0,'(A)') '!! Make sure units are meters, not kilometers'
        endif
    endif
    if (gf_type.eq.'okada_pt') then
        if (maxval(fault%array(:,6)).lt.10000.0d0) then
            write(0,'(A)') '!! Warning: fault areas all less than 100 m x 100 m'
            write(0,'(A)') '!! Make sure units are square meters, not square kilometers'
        endif
    endif
    if (gf_type.eq.'triangle') then
        if (maxval(fault%array(:,6)).lt.1000.0d0) then
            write(0,'(A)') '!! Warning: fault depths all less than +1000 m'
            write(0,'(A)') '!! Make sure depth units are meters, positive down'
        endif
        if (maxval(fault%array(:,9)).lt.1000.0d0) then
            write(0,'(A)') '!! Warning: fault depths all less than +1000 m'
            write(0,'(A)') '!! Make sure depth units are meters, positive down'
        endif
    endif
endif

! Check that coordinates make sense for input type
if (coord_type.eq.'cartesian') then
    if (displacement%file.ne.'none') then
        do i = 1,fault%nrecords
            dist = (displacement%array(1,1)-fault%array(i,1))**2 + &
                       (displacement%array(1,2)-fault%array(i,2))**2
            if (dsqrt(dist).le.10.0d0) then
                write(0,'(A)') '!! Warning: very small distance found'
                write(0,'(A)') '!! Did you mean to use -geo?'
                exit
            endif
        enddo
    endif
    if (los%file.ne.'none') then
        do i = 1,fault%nrecords
            dist = (los%array(1,1)-fault%array(i,1))**2 + &
                       (los%array(1,2)-fault%array(i,2))**2
            if (dsqrt(dist).le.10.0d0) then
                write(0,'(A)') '!! Warning: very small distance found'
                write(0,'(A)') '!! Did you mean to use -geo?'
                exit
            endif
        enddo
    endif
endif

! If pre-stresses are defined, calculate the shear stresses on the faults
if (prestress%file.ne.'none') then
    ! Calculate shear stresses from stress tensor
    do i = 1,fault%nrecords
        if (gf_type.eq.'okada_rect'.or.gf_type.eq.'okada_pt') then
            call calc_plane_unit_vectors(fault%array(i,4),fault%array(i,5),nor,str,upd)
        elseif (gf_type.eq.'triangle') then
            if (coord_type.eq.'cartesian') then
                call tri_geometry(nor,str,upd,fault%array(i,1:3),fault%array(i,4:6),&
                                  fault%array(i,7:9))
            elseif (coord_type.eq.'geographic') then
                ! Triangle points: lon lat dep(m) to x y z
                call tri_geo2cart(pt1,pt2,pt3,fault%array(i,1:3),fault%array(i,4:6), &
                                  fault%array(i,7:9),'m')
                ! write(0,*) 'pt1',pt1
                ! write(0,*) 'pt2',pt2
                ! write(0,*) 'pt3',pt3
                call tri_geometry(nor,str,upd,pt1,pt2,pt3)
                ! write(0,*) 'nor',nor
                ! write(0,*) 'str',str
                ! write(0,*) 'upd',upd
            endif
        endif
        stress(1,1) = prestress%array(i,1)
        stress(2,2) = prestress%array(i,2)
        stress(3,3) = prestress%array(i,3)
        stress(1,2) = prestress%array(i,4)
        stress(2,1) = prestress%array(i,4)
        stress(1,3) = prestress%array(i,5)
        stress(3,1) = prestress%array(i,5)
        stress(2,3) = prestress%array(i,6)
        stress(3,2) = prestress%array(i,6)
        call calc_traction(stress,nor,traction)
        call calc_traction_components(traction,nor,str,upd,traction_comp)
        prestress%array(i,1) = traction_comp(2)
        prestress%array(i,2) = traction_comp(3)
        ! write(0,*) 'trac_ss:',traction_comp(2)
        ! write(0,*) 'trac_ds:',traction_comp(3)
    enddo
endif
! stop

!----
! Displacement Green's functions?
!----
if (displacement%file.ne.'none') then
    ! Assign array for displacement Green's functions maximum possible size to start
    gf_disp%nfields = 2*fault%nrecords

    ! Read pre-computed displacement Green's functions
    if (gf_disp%file.ne.'none') then
        call read_program_data_file(gf_disp)
        ! Verify that there are the correct number of lines here
        if (gf_disp%nrecords .ne. 3*displacement%nrecords) then
            call print_usage('!! read_fltinv_inputs: number of lines in displacement GF file '// &
                             'must be 3*ndisplacements (one line per displacement DOF)')
        endif

    ! Allocate memory to calculate Green's functions
    else
        gf_disp%nrecords = 3*displacement%nrecords
        if (allocated(gf_disp%array)) then
            deallocate(gf_disp%array)
        endif
        allocate(gf_disp%array(gf_disp%nrecords,gf_disp%nfields))
    endif
endif

!----
! Stress Green's functions?
!----
if (prestress%file.ne.'none') then
    ! Assign array for stress Green's functions maximum possible size to start
    gf_stress%nfields = 2*fault%nrecords

    ! Read pre-computed displacement Green's functions
    if (gf_stress%file.ne.'none') then
        call read_program_data_file(gf_stress)
        ! Verify that there are the correct number of lines here
        if (gf_stress%nrecords .ne. 2*fault%nrecords) then
            call print_usage('!! read_fltinv_inputs: Number of lines in stress GF file must be '//&
                             '2*nfaults (one line per fault slip DOF)')
        endif

    ! Allocate memory to calculate Green's functions
    else
        gf_stress%nrecords = 2*fault%nrecords
        if (allocated(gf_stress%array)) then
            deallocate(gf_stress%array)
        endif
        allocate(gf_stress%array(gf_stress%nrecords,gf_stress%nfields))
    endif
endif
if (inversion_mode.eq.'anneal-psc') then
    gf_stress%nfields = 2*fault%nrecords
    gf_stress%nrecords = 2*fault%nrecords
    if (allocated(gf_stress%array)) then
        deallocate(gf_stress%array)
    endif
    allocate(gf_stress%array(gf_stress%nrecords,gf_stress%nfields))
endif

!----
! Line-of-sight displacement Green's functions?
!----
if (los%file.ne.'none') then
    ! Assign array for LOS displacement Green's functions maximum possible size to start
    gf_los%nfields = 2*fault%nrecords

    ! Read pre-computed LOS displacement Green's functions
    if (gf_los%file.ne.'none') then
        call read_program_data_file(gf_los)
        ! Verify that there are the correct number of lines here
        if (gf_los%nrecords .ne. los%nrecords) then
            call print_usage('!! read_fltinv_inputs: number of lines in LOS displacement GF '// &
                             'file must be ndisplacements (one line per displacement DOF)')
        endif

    ! Allocate memory to calculate Green's functions
    else
        gf_los%nrecords = los%nrecords
        if (allocated(gf_los%array)) then
            deallocate(gf_los%array)
        endif
        allocate(gf_los%array(gf_los%nrecords,gf_los%nfields))
    endif
endif

!----
! Smoothing
!----
if (smoothing%file.ne.'none') then
    ! Read the smoothing linking file into a pointer array (smoothing%intarray)
    smoothing%array_type = 'int'
    smoothing%nfields = 3
    call read_program_data_file(smoothing)
    if (smoothing%nrecords.gt.fault%nrecords) then
        call print_usage('!! read_fltinv_inputs: number of faults to smooth is larger than '//&
                         'number of faults')
    endif

    ! Read the smoothing linking file into a fault neighbors array (smoothing_neighbors)
    call read_smoothing_neighbors()
endif

!----
! Rake constraints
!----
if (rake_constraint%file.ne.'none') then
    if (inversion_mode.eq.'lsqr') then
        ! Check how many rake constraints there are (may want to rotate rakes for nnls inversion, then need two rakes)
        open(unit=33,file=rake_constraint%file,status="old")
        read(33,'(A)') line
        read(line,*,iostat=ios) dist,az
        if (ios.eq.0) then
            rake_constraint%nfields = 2
        else
            rake_constraint%nfields = 1
        endif
        close(33)
    elseif (inversion_mode.eq.'anneal') then
        rake_constraint%nfields = 2
    else
        call print_usage('!! read_fltinv_inputs: I do not know how many fields rake_constraint '//&
                         'should have for this inversion mode...')
    endif
    call read_program_data_file(rake_constraint)
    if (rake_constraint%nrecords.ne.1.and.rake_constraint%nrecords.ne.fault%nrecords) then
        write(0,'(A,I5,A)') '!! read_fltinv_inputs: found ',rake_constraint%nrecords,' rake '//&
                            'constraint records'
        write(0,'(A,I5,A)') '!! and ',fault%nrecords,' input faults'
        call print_usage('!! Number of rake constraints must be 1 or number of faults')
    endif
endif

!----
! Slip magnitude constraints
!----
if (slip_constraint%file.ne.'none') then
    slip_constraint%nfields = 2
    call read_program_data_file(slip_constraint)
    if (slip_constraint%nrecords.ne.1.and.slip_constraint%nrecords.ne.fault%nrecords) then
        call print_usage('!! read_fltinv_inputs: number of slip constraints must be 1 or '//&
                         'number of faults')
    endif
    if (slip_constraint%nrecords.eq.1) then
        dist = slip_constraint%array(1,1)
        az = slip_constraint%array(1,2)
        deallocate(slip_constraint%array)
        allocate(slip_constraint%array(fault%nrecords,slip_constraint%nfields))
        slip_constraint%nrecords = fault%nrecords
        slip_constraint%array(:,1) = dist
        slip_constraint%array(:,2) = az
    endif
endif

!----
! Read half-space data or use hard-coded default values
!----
if (gf_type.eq.'okada_rect'.or.gf_type.eq.'okada_pt'.or.gf_type.eq.'triangle') then
    if (halfspace%file.ne.'none') then
        if (halfspace%flag.eq.'velodens') then
            halfspace%nfields = 3
        elseif (halfspace%flag.eq.'lame') then
            halfspace%nfields = 2
        else
            call print_usage('!! read_fltinv_inputs: no halfspace read option named '//&
                             trim(halfspace%flag))
        endif
        call read_program_data_file(halfspace)
    else
        halfspace%flag = 'velodens'
        halfspace%nrecords = 1
        halfspace%nfields = 3
        if (allocated(halfspace%array)) then
            deallocate(halfspace%array)
        endif
        allocate(halfspace%array(halfspace%nrecords,halfspace%nfields))
        halfspace%array(1,1) = 6800.0d0
        halfspace%array(1,2) = 3926.0d0
        halfspace%array(1,3) = 3000.0d0
    endif
endif

if (verbosity.ge.1) then
    write(stderr,'(A)') 'read_fltinv_inputs says: finished'
    write(stderr,*)
endif

return
end subroutine read_fltinv_inputs

!--------------------------------------------------------------------------------------------------!

subroutine read_smoothing_neighbors()
!----
! Read in file defining fault neighbors for Laplacian smoothing
!----
use io_module, only: verbosity, stderr
use variable_module, only: smoothing, smoothing_neighbors
implicit none
! Local variables
integer :: i, j, nentries, ineighbor, nneighbor
character(len=1024) :: iline

if (verbosity.ge.2) then
    write(stderr,'(A)') "read_smoothing_neighbors says: starting"
endif

! File has already been read once and memory has been allocated to smoothing%intarray
! The first two fields are: ifault nneighbors; calculate pointer to location of neighbors array
do i = 1,smoothing%nrecords
    if (i.eq.1) then
        smoothing%intarray(i,3) = 1
    else
        smoothing%intarray(i,3) = smoothing%intarray(i-1,3) + smoothing%intarray(i-1,2)
    endif
enddo

! Allocate memory for neighbors array
if (.not.allocated(smoothing_neighbors)) then
    nentries = smoothing%intarray(smoothing%nrecords,3) + smoothing%intarray(smoothing%nrecords,2)
    allocate(smoothing_neighbors(nentries))
endif

! Re-open the smoothing file to read the neighbors
open(unit=25,file=smoothing%file,status='old')
do i = 1,smoothing%nrecords
    read(25,'(A)') iline
    nneighbor = smoothing%intarray(i,2)
    ineighbor = smoothing%intarray(i,3)
    read(iline,*) j,j,(smoothing_neighbors(ineighbor+j-1),j=1,nneighbor)
enddo
close(25)

if (verbosity.ge.2) then
    write(stderr,'(A)') "read_smoothing_neighbors says: finished"
endif
if (verbosity.ge.3) then
    write(stderr,'(A)') '       fault  nneighbors    neighbor'
    do i = 1,smoothing%nrecords
        write(stderr,'(10I12)') (smoothing%intarray(i,j),j=1,2), &
            (smoothing_neighbors(smoothing%intarray(i,3)+j-1),j=1,smoothing%intarray(i,2))
    enddo
endif
if (verbosity.ge.2) then
    write(stderr,*)
endif

return
end subroutine read_smoothing_neighbors

!--------------------------------------------------------------------------------------------------!

subroutine calc_greens_functions()
use io_module, only: stderr, verbosity
use variable_module, only: inversion_mode, displacement, los, prestress, &
                           gf_type, gf_disp, gf_stress, gf_los
use gf_module, only: calc_gf_disp_okada_rect, calc_gf_stress_okada_rect, calc_gf_los_okada_rect, &
                     calc_gf_disp_okada_pt,   calc_gf_stress_okada_pt,   calc_gf_los_okada_pt, &
                     calc_gf_disp_tri,        calc_gf_stress_tri,        calc_gf_los_tri
implicit none

if (verbosity.ge.1) then
    write(stderr,'(A)') 'calc_greens_functions says: starting'
endif

! Displacement Green's functions
if (displacement%file.ne.'none') then

    ! Displacement Green's functions need to be calculated
    if (gf_disp%file.eq.'none') then
        if (gf_type.eq.'okada_rect') then
            call calc_gf_disp_okada_rect()
        elseif (gf_type.eq.'okada_pt') then
            call calc_gf_disp_okada_pt()
        elseif (gf_type.eq.'triangle') then
            call calc_gf_disp_tri()
        else
            call print_usage('!! Error: no option to calculate Greens functions called '// &
                             trim(gf_type))
        endif
    endif

endif

! Stress Green's functions
if (prestress%file.ne.'none'.or.inversion_mode.eq.'anneal-psc') then
    ! Stress Green's functions need o be calculated
    if (gf_stress%file.eq.'none') then
        if (gf_type.eq.'okada_rect') then
            call calc_gf_stress_okada_rect()
        elseif (gf_type.eq.'okada_pt') then
            call calc_gf_stress_okada_pt()
        elseif (gf_type.eq.'triangle') then
            call calc_gf_stress_tri()
        else
            call print_usage('!! Error: no option to calculate Greens functions called '// &
                             trim(gf_type))
        endif
    endif
endif

! LOS displacement Green's functions
if (los%file.ne.'none') then
    ! LOS displacement Green's functions need to be calculated
    if (gf_los%file.eq.'none') then
        if (gf_type.eq.'okada_rect') then
            call calc_gf_los_okada_rect()
        elseif (gf_type.eq.'okada_pt') then
            call calc_gf_los_okada_pt()
        elseif (gf_type.eq.'triangle') then
            call calc_gf_los_tri()
        else
            call print_usage('!! Error: no option to calculate Greens functions called '// &
                              trim(gf_type))
        endif
    endif
endif

if (verbosity.ge.1) then
    write(stderr,'(A)') 'calc_greens_functions says: finished'
    write(stderr,*)
endif

return
end subroutine calc_greens_functions

!--------------------------------------------------------------------------------------------------!

subroutine run_inversion()
use io_module, only: stderr, verbosity
use variable_module, only: inversion_mode
use lsqr_module, only: invert_lsqr
use anneal_module, only: invert_anneal, invert_anneal_pseudocoupling
implicit none

if (verbosity.ge.1) then
    write(stderr,'(A)') 'run_inversion says: starting'
endif

if (inversion_mode.eq.'lsqr') then
    call invert_lsqr()
elseif (inversion_mode.eq.'anneal') then
    call invert_anneal()
elseif (inversion_mode.eq.'anneal-psc') then
    call invert_anneal_pseudocoupling()
else
    call print_usage('!! Error: no inversion mode named '//trim(inversion_mode))
endif

if (verbosity.ge.1) then
    write(stderr,'(A)') 'run_inversion says: finished'
    write(stderr,*)
endif

return
end subroutine run_inversion

!--------------------------------------------------------------------------------------------------!

subroutine free_memory()
! Deallocate arrays

use io_module, only: stderr, verbosity
use variable_module, only: displacement, prestress, los, fault, &
                           gf_disp, gf_stress, gf_los, &
                           smoothing, smoothing_neighbors, rake_constraint, slip_constraint, &
                           halfspace
implicit none

if (verbosity.ge.1) then
    write(stderr,'(A)') 'free_memory says: starting'
endif

if (allocated(displacement%array)) then
    deallocate(displacement%array)
endif
if (allocated(prestress%array)) then
    deallocate(prestress%array)
endif
if (allocated(los%array)) then
    deallocate(los%array)
endif
if (allocated(fault%array)) then
    deallocate(fault%array)
endif
if (allocated(gf_disp%array)) then
    deallocate(gf_disp%array)
endif
if (allocated(gf_stress%array)) then
    deallocate(gf_stress%array)
endif
if (allocated(gf_los%array)) then
    deallocate(gf_los%array)
endif
if (allocated(smoothing%intarray)) then
    deallocate(smoothing%intarray)
endif
if (allocated(smoothing_neighbors)) then
    deallocate(smoothing_neighbors)
endif
if (allocated(rake_constraint%array)) then
    deallocate(rake_constraint%array)
endif
if (allocated(slip_constraint%array)) then
    deallocate(slip_constraint%array)
endif
if (allocated(halfspace%array)) then
    deallocate(halfspace%array)
endif

if (verbosity.ge.1) then
    write(stderr,'(A)') 'free_memory says: finished'
endif

return
end subroutine free_memory

!--------------------------------------------------------------------------------------------------!

subroutine write_solution()
use io_module, only: stdout, stderr, verbosity
use variable_module, only: output_file, inversion_mode, fault, fault_slip, rake_constraint, &
                           disp_misfit_file, los_misfit_file
use anneal_module, only: disp_misfit_l2norm, los_misfit_l2norm
implicit none
! Local variables
integer :: i, ounit
double precision :: slip_mag, tmp_slip_array(fault%nrecords,2)

if (verbosity.ge.1) then
    write(stderr,'(A)') 'write_solution says: starting'
endif

! Print RMS misfit if specified
if (disp_misfit_file.ne.'none') then
    if (verbosity.ge.1) then
        write(stderr,'(A)') 'write_solution says: writing displacement RMS misfit to '// &
                            trim(disp_misfit_file)
    endif

    write(0,*) 'write_solution: opening misfit file'
    open(unit=81,file=disp_misfit_file,status='unknown')

    ! If rake is constrained, make an array of the correct size to use with misfit function
    if (inversion_mode.eq.'lsqr'.and.rake_constraint%file.ne.'none' &
                                                           .and.rake_constraint%nfields.eq.1) then
        write(0,*) 'write_solution: writing misfit for fixed rake'
        do i = 1,fault%nrecords
            tmp_slip_array(i,1) = fault_slip(i,1) ! Green's functions already calculated for this rake
            tmp_slip_array(i,2) = 0.0d0
        enddo
        write(81,*) disp_misfit_l2norm(tmp_slip_array)/dsqrt(dble(fault%nrecords))

    ! Otherwise, just use the misfit function directly
    else
        write(0,*) 'write_solution: writing misfit for free rake'
        write(81,*) disp_misfit_l2norm(fault_slip)/dsqrt(dble(fault%nrecords))
    endif

    write(0,*) 'write_solution: closing misfit file'
    close(81)
endif

! Line-of-sight RMS misfit
if (los_misfit_file.ne.'none') then
    if (verbosity.ge.1) then
        write(stderr,'(A)') 'write_solution says: writing LOS RMS misfit to '//trim(los_misfit_file)
    endif

    write(0,*) 'write_solution: opening misfit file'
    open(unit=81,file=los_misfit_file,status='unknown')

    ! If rake is constrained, make an array of the correct size to use with misfit function
    if (inversion_mode.eq.'lsqr'.and.rake_constraint%file.ne.'none' &
                                                           .and.rake_constraint%nfields.eq.1) then
        do i = 1,fault%nrecords
            tmp_slip_array(i,1) = fault_slip(i,1) ! Green's functions already calculated for this rake
            tmp_slip_array(i,2) = 0.0d0
        enddo
        write(81,*) los_misfit_l2norm(tmp_slip_array)/dsqrt(dble(fault%nrecords))

    ! Otherwise, just use the misfit function directly
    else
        write(81,*) los_misfit_l2norm(fault_slip)/dsqrt(dble(fault%nrecords))
    endif

    write(0,*) 'write_solution: closing misfit file'
    close(81)
endif

! Print fault slip solution
if (verbosity.ge.1) then
    write(stderr,'(A)') 'write_solution says: writing slip solution to '//trim(output_file)
endif
if (output_file.eq.'stdout') then
    ounit = stdout
else
    ounit = 99
    open (unit=ounit,file=output_file,status='unknown')
endif

do i = 1,fault%nrecords
    slip_mag = dsqrt(fault_slip(i,1)*fault_slip(i,1)+fault_slip(i,2)*fault_slip(i,2))

    if (inversion_mode.eq.'lsqr') then
        if (rake_constraint%file.eq.'none'.or.rake_constraint%nfields.eq.2) then
            if (slip_mag.lt.1.0d3) then
                write(ounit,5011) fault_slip(i,1), fault_slip(i,2)
            else
                write(ounit,5001) fault_slip(i,1), fault_slip(i,2)
            endif
        else
            slip_mag = dabs(fault_slip(i,1))
            if (slip_mag.lt.1.0d3) then
                write(ounit,5012) fault_slip(i,1)
            else
                write(ounit,5002) fault_slip(i,1)
            endif
        endif

    elseif (inversion_mode.eq.'anneal') then
        if (slip_mag.lt.1.0d3) then
            write(ounit,5011) fault_slip(i,1), fault_slip(i,2)
        else
            write(ounit,5001) fault_slip(i,1), fault_slip(i,2)
        endif

    elseif (inversion_mode.eq.'anneal-psc') then
        if (slip_mag.lt.1.0d3) then
            write(ounit,5011) fault_slip(i,1), fault_slip(i,2)
        else
            write(ounit,5001) fault_slip(i,1), fault_slip(i,2)
        endif

    else
        call print_usage('!! Error: frankly, I do not know how you got this far using an '//&
                         'inversion mode that does not seem to exist...')
    endif
enddo
5011 format(2F14.3)
5001 format(1P2E14.6)
5012 format(1F14.3)
5002 format(1P1E14.6)

if (allocated(fault_slip)) then
    deallocate(fault_slip)
endif

if (output_file.ne.'stdout') then
    close(ounit)
endif

if (verbosity.ge.1) then
    write(stderr,'(A)') 'write_solution says: finished'
endif

return
end subroutine write_solution
