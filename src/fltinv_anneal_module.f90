module anneal_module
    ! Control options
    character(len=8) :: anneal_init_mode          ! zero, mean, uniform, random
    character(len=256) :: anneal_log_file         ! file logging annealing progress
    integer :: max_iteration                      ! maximum number of steps
    integer :: reset_iteration                    ! step to reset current solution to best, temp to temp_start
    double precision :: temp_start                ! >0: mult by initial obj value; <0: use absolute value
    double precision :: temp_minimum              ! >0: mult by initial obj value; <0: use absolute value
    double precision :: cooling_factor            ! every iteration, temp->temp*cooling_factor

    integer :: idum
    double precision :: temp
    double precision, allocatable :: slip_0(:), slip_new(:), slip_best(:), dslip(:), dslip_init(:)
    double precision, allocatable :: rake_0(:), rake_new(:), rake_best(:), drake(:), drake_init(:)

!--------------------------------------------------------------------------------------------------!
contains
!--------------------------------------------------------------------------------------------------!

    subroutine invert_anneal()
    use io_module, only: stderr, verbosity
    use variable_module, only: fault_slip, fault
    implicit none
    ! Local variables
    integer :: i
    double precision, parameter :: pi = datan(1.0d0)*4.0d0, d2r = pi/180.0d0

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'invert_anneal says: starting'
    endif

    call initialize_annealing()

    call run_annealing_search()

    if (.not.allocated(fault_slip)) then
        allocate(fault_slip(fault%nrecords,2))
    endif
    do i = 1,fault%nrecords
        fault_slip(i,1) = slip_best(i)*dcos(rake_best(i)*d2r)
        fault_slip(i,2) = slip_best(i)*dsin(rake_best(i)*d2r)
    enddo

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'invert_anneal says: finished'
        write(stderr,*)
    endif

    return
    end subroutine invert_anneal

!--------------------------------------------------------------------------------------------------!

    subroutine initialize_annealing()
    use io_module, only: stderr, verbosity
    use variable_module, only: fault, slip_constraint, rake_constraint
    implicit none
    ! Local variables
    integer :: i
    double precision :: tmparray(1,2)
    ! External variables
    integer, external :: timeseed
    real, external :: ran2

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'initialize_annealing says: starting'
    endif

    ! Make sure slip_constraint%array is defined (bounds for slip magnitude values)
    if (slip_constraint%file.eq.'none') then
        call print_usage('!! Error: a slip constraint file is required for simulated annealing')
    else
        if (slip_constraint%nrecords.eq.1) then
            tmparray = slip_constraint%array
            deallocate(slip_constraint%array)
            allocate(slip_constraint%array(fault%nrecords,2))
            do i = 1,fault%nrecords
                slip_constraint%array(i,1) = tmparray(1,1)
                slip_constraint%array(i,2) = tmparray(1,2)
            enddo
        endif
    endif

    ! Make sure rake_constraint%array is defined (bounds for rake angle values)
    if (rake_constraint%file.eq.'none') then
        call print_usage('!! Error: a rake constraint file is required for simulated annealing')
    else
        if (rake_constraint%nrecords.eq.1) then
            tmparray = rake_constraint%array
            deallocate(rake_constraint%array)
            allocate(rake_constraint%array(fault%nrecords,2))
            do i = 1,fault%nrecords
                rake_constraint%array(i,1) = tmparray(1,1)
                rake_constraint%array(i,2) = tmparray(1,2)
            enddo
        endif
    endif

    ! Initialize the random number generator
    idum = -timeseed()

    ! Allocate memory to the fault slip and rake arrays
    allocate(slip_0(fault%nrecords))
    allocate(slip_new(fault%nrecords))
    allocate(slip_best(fault%nrecords))
    allocate(dslip(fault%nrecords))
    allocate(dslip_init(fault%nrecords))
    allocate(rake_0(fault%nrecords))
    allocate(rake_new(fault%nrecords))
    allocate(rake_best(fault%nrecords))
    allocate(drake(fault%nrecords))
    allocate(drake_init(fault%nrecords))

    ! Initialize the fault slip solution
    if (anneal_init_mode.eq.'zero') then
        slip_0 = 0.0d0
        rake_0 = 0.0d0
    elseif (anneal_init_mode.eq.'mean') then
        do i = 1,fault%nrecords
            slip_0(i) = 0.5d0*(slip_constraint%array(i,2)-slip_constraint%array(i,1)) + &
                                 slip_constraint%array(i,1)
            rake_0(i) = 0.5d0*(rake_constraint%array(i,2)-rake_constraint%array(i,1)) + &
                                 rake_constraint%array(i,1)
        enddo
    elseif (anneal_init_mode.eq.'rand'.or.anneal_init_mode.eq.'random') then
        do i = 1,fault%nrecords
            slip_0(i) = ran2(idum)*(slip_constraint%array(i,2)-slip_constraint%array(i,1)) + &
                                 slip_constraint%array(i,1)
            rake_0(i) = ran2(idum)*(rake_constraint%array(i,2)-rake_constraint%array(i,1)) + &
                                 rake_constraint%array(i,1)
        enddo
    ! elseif (anneal_init_mode.eq.'uniform') then
    !     ! same slip on all faults
    else
        call print_usage('!! Error: no annealing mode named '//trim(anneal_init_mode))
    endif

    ! Set the first model to be the best model initially
    slip_best = slip_0
    rake_best = rake_0

    ! Initialize step sizes for slip magnitude and rake angle
    do i = 1,fault%nrecords
        dslip(i) = (slip_constraint%array(i,2)-slip_constraint%array(i,1))/20.0d0
        drake(i) = (rake_constraint%array(i,2)-rake_constraint%array(i,1))/12.0d0
    enddo
    dslip_init = dslip
    drake_init = drake

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'initialize_annealing says: finished'
        write(stderr,*)
    endif

    return
    end subroutine initialize_annealing

!--------------------------------------------------------------------------------------------------!

    subroutine run_annealing_search()
    use io_module, only: stderr, verbosity
    use variable_module, only: fault, slip_constraint, rake_constraint
    implicit none
    ! Local variables
    integer :: i, j, nflt, last_obj_best
    double precision :: temp, obj_0, obj_new, obj_best, p_trans, slip_ssds(fault%nrecords,2)
    double precision, parameter :: pi=datan(1.0d0)*4.0d0, d2r=pi/180.0d0
    real, external :: ran2

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'run_annealing_search says: starting'
    endif

    nflt = fault%nrecords

    ! Calculate misfit of initial model
    do j = 1,nflt
        slip_ssds(j,1) = slip_0(j)*dcos(rake_0(j)*d2r)
        slip_ssds(j,2) = slip_0(j)*dsin(rake_0(j)*d2r)
    enddo
    obj_0 = misfit(slip_ssds) + shear_stress(slip_ssds)
    obj_best = obj_0
    last_obj_best = 0

    ! Initialize starting temperature
    if (temp_start.lt.0.0d0) then
        temp_start = -temp_start
        temp = temp_start
    else
        temp = temp_start*obj_0
        temp_start = temp
    endif

    ! Set minimum temperature
    if (temp_minimum.lt.0.0d0) then
        temp_minimum = -temp_minimum
    else
        temp_minimum = temp_minimum*obj_0
    endif

    if (anneal_log_file.ne.'none') then
        open(unit=201,file=anneal_log_file,status='unknown')
        write(201,'(A,I4,2(4X,A,1PE12.4))') 'Iteration: ',0,'Temperature: ',temp,&
                                                 'Objective: ',obj_0
        do j = 1,nflt
            write(201,'(1PE14.6,0PF10.2)') slip_0(j),rake_0(j)
        enddo
    endif

    ! Run simulated annealing search
    do i = 1,max_iteration

        ! Propose a new model (slip_new) that is a neighbor of the current model (slip_0)
        do j = 1,nflt
            slip_new(j) = slip_0(j) + (ran2(idum)-0.5d0)*dslip(j)
            rake_new(j) = rake_0(j) + (ran2(idum)-0.5d0)*drake(j)

            ! Prevent new slip magnitude from going outside bounds
            if (slip_new(j).lt.slip_constraint%array(j,1)) then
                slip_new(j) = slip_constraint%array(j,1)
            elseif (slip_new(j).gt.slip_constraint%array(j,2)) then
                slip_new(j) = slip_constraint%array(j,2)
            endif

            ! Prevent new rake angle from going outside bounds
            if (rake_new(j).lt.rake_constraint%array(j,1)) then
                rake_new(j) = rake_constraint%array(j,1)
            elseif (rake_new(j).gt.rake_constraint%array(j,2)) then
                rake_new(j) = rake_constraint%array(j,2)
            endif

            ! Prepare format for computing misfit
            slip_ssds(j,1) = slip_new(j)*dcos(rake_new(j)*d2r)
            slip_ssds(j,2) = slip_new(j)*dsin(rake_new(j)*d2r)
        enddo

        ! Compute misfit for new model, save if the best model
        obj_new = misfit(slip_ssds) + shear_stress(slip_ssds)
        ! write(0,*) 'misfit:',misfit(slip_ssds),' shear_stress:',shear_stress(slip_ssds)
        if (obj_new.lt.obj_best) then
            slip_best = slip_new
            rake_best = rake_new
            obj_best = obj_new
            last_obj_best = i
        endif

        ! Compute transition probability
        !     (obj_new < obj_0) => always transition to better model
        !     (obj_new > obj_0) => transition with p = exp(-dE/T)
        p_trans = dexp((obj_0-obj_new)/temp)

        ! If the transition is made because of better fit or chance,
        ! update the current model (slip_0) with the proposed model (slip_new)
        if (ran2(idum).lt.p_trans) then
            slip_0 = slip_new
            rake_0 = rake_new
            obj_0 = obj_new
            if (anneal_log_file.ne.'none') then
                write(201,'(A,I4,2(4X,A,1PE12.4))') 'Iteration: ',i,'Temperature: ',temp,&
                                                 'Objective: ',obj_0
                do j = 1,nflt
                    write(201,'(1PE14.6,0PF10.2)') slip_0(j),rake_0(j)
                enddo
            endif
        endif

        ! Reduce temperature by cooling factor
        if (temp.lt.temp_minimum) then
            temp = temp_minimum
        else
            temp = temp*cooling_factor
        endif

        ! if (i-last_obj_best.gt.100) then
        !     ! write(0,*) 'reducing neighbor window size to:'
        !     do j = 1,nflt
        !         dslip(j) = dslip(j)*0.95d0
        !         drake(j) = drake(j)*0.95d0
        !         ! write(0,*) j,dslip(j),drake(j)
        !     enddo
        ! endif
        if (mod(i,reset_iteration).eq.0) then
            temp = temp_start
            slip_0 = slip_best
            rake_0 = rake_best
            obj_0 = obj_best
            dslip = dslip_init
            drake = drake_init
        endif
    enddo

    if (anneal_log_file.ne.'none') then
        write(201,'(A,1P1E14.6)') 'Best solution; objective: ',obj_best
        do j = 1,nflt
            write(201,'(1PE14.6,0PF10.2)') slip_best(j),rake_best(j)
        enddo
    endif

    if (verbosity.ge.2) then
        write(stderr,'(A)') 'run_annealing_search says: finished'
        write(stderr,*)
    endif

    return
    end subroutine run_annealing_search

!--------------------------------------------------------------------------------------------------!

    double precision function misfit(model_array)
    !----
    ! Calculate the L2 norm of the difference vector between the displacements produced
    ! by model_array (first column is strike-slip, second column is dip-slip) and input values
    !----
    use variable_module, only: fault, displacement, gf_disp
    implicit none
    ! I/O variables
    double precision :: model_array(fault%nrecords,2)
    ! Local variables
    integer :: i, j, nflt, ndsp
    double precision :: disp_pre(3), ss, ds, dx, dy, dz

    nflt = fault%nrecords
    ndsp = displacement%nrecords

    misfit = 0.0d0

    if (displacement%file.eq.'none') then
        return
    endif

    do i = 1,ndsp
        disp_pre = 0.0d0
        do j = 1,nflt
            ss = gf_disp%array(i       ,j     )*model_array(j,1)
            ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
            disp_pre(1) = disp_pre(1) + ss + ds

            ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
            ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
            disp_pre(2) = disp_pre(2) + ss + ds

            ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
            ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
            disp_pre(3) = disp_pre(3) + ss + ds
        enddo
        dx = displacement%array(i,4)-disp_pre(1)
        dy = displacement%array(i,5)-disp_pre(2)
        dz = displacement%array(i,6)-disp_pre(3)
        misfit = misfit + dx*dx + dy*dy + dz*dz
    enddo

    misfit = dsqrt(misfit)

    return
    end function misfit

!--------------------------------------------------------------------------------------------------!

    double precision function shear_stress(model_array)
    !----
    ! Calculate the L2 norm of the shear tractions on the faults from pre-stresses and
    ! all other faults
    !----
    use variable_module, only: fault, prestress, gf_stress
    implicit none
    ! I/O variables
    double precision :: model_array(fault%nrecords,2)
    ! Local variables
    integer :: i, j, nflt
    double precision :: ss_shear, ds_shear, shear(2), dss, dds

    nflt = fault%nrecords

    shear_stress = 0.0d0

    if (prestress%file.eq.'none') then
        return
    endif

    do i = 1,nflt
        shear = 0.0d0
        do j = 1,nflt
            ss_shear = gf_stress%array(i       ,j     )*model_array(j,1)
            ds_shear = gf_stress%array(i       ,j+nflt)*model_array(j,2)
            shear(1) = shear(1) + ss_shear + ds_shear

            ss_shear = gf_stress%array(i+1*nflt,j     )*model_array(j,1)
            ds_shear = gf_stress%array(i+1*nflt,j+nflt)*model_array(j,2)
            shear(2) = shear(2) + ss_shear + ds_shear
        enddo
        dss = prestress%array(i,1)-shear(1)
        dds = prestress%array(i,2)-shear(2)
        shear_stress = shear_stress + dss*dss + dds*dds
    enddo

    shear_stress = dsqrt(shear_stress)

    return
    end function shear_stress

end module anneal_module