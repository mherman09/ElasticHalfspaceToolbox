module anneal_module

    integer :: idum
    double precision :: temp

    ! Normal annealing variables
    double precision, allocatable :: slip_0(:), slip_new(:), slip_best(:), dslip(:), dslip_init(:)
    double precision, allocatable :: rake_0(:), rake_new(:), rake_best(:), drake(:), drake_init(:)

    ! Annealing for pseudo-coupling variables
    integer, allocatable :: isFaultLocked(:)

!--------------------------------------------------------------------------------------------------!
contains
!--------------------------------------------------------------------------------------------------!

    subroutine invert_anneal()
    use io, only: stderr, verbosity
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

    ! Free up annealing array memory
    if (allocated(slip_0)) then
        deallocate(slip_0)
    endif
    if (allocated(slip_new)) then
        deallocate(slip_new)
    endif
    if (allocated(slip_best)) then
        deallocate(slip_best)
    endif
    if (allocated(dslip)) then
        deallocate(dslip)
    endif
    if (allocated(dslip_init)) then
        deallocate(dslip_init)
    endif
    if (allocated(rake_0)) then
        deallocate(rake_0)
    endif
    if (allocated(rake_new)) then
        deallocate(rake_new)
    endif
    if (allocated(rake_best)) then
        deallocate(rake_best)
    endif
    if (allocated(drake)) then
        deallocate(drake)
    endif
    if (allocated(drake_init)) then
        deallocate(drake_init)
    endif

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
    use io, only: stderr, verbosity
    use variable_module, only: fault, slip_constraint, rake_constraint, &
                               anneal_init_mode
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
        call usage('!! Error: a slip constraint file is required for simulated annealing')
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
        call usage('!! Error: a rake constraint file is required for simulated annealing')
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
        call usage('!! Error: no annealing mode named '//trim(anneal_init_mode))
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
    use io, only: stderr, verbosity
    use variable_module, only: fault, slip_constraint, rake_constraint, stress_weight, &
                               los_weight, smoothing_constant, &
                              anneal_log_file, max_iteration, reset_iteration, &
                            temp_start, temp_minimum, cooling_factor, anneal_verbosity
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

    ! Calculate objective function of initial model
    do j = 1,nflt
        slip_ssds(j,1) = slip_0(j)*dcos(rake_0(j)*d2r)
        slip_ssds(j,2) = slip_0(j)*dsin(rake_0(j)*d2r)
    enddo
    obj_0 = disp_misfit_l2norm(slip_ssds)/dsqrt(dble(fault%nrecords)) + &
                los_weight*los_misfit_l2norm(slip_ssds)/dsqrt(dble(fault%nrecords)) + &
                stress_weight*shear_stress(slip_ssds) + &
                smoothing_constant*roughness(slip_ssds)
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

        if (mod(i,max_iteration/10).eq.0.and.anneal_verbosity.eq.1) then
            write(0,*) 'Annealing progress: ',i,' of ',max_iteration,' iterations'
        endif
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

        ! Compute objective function for new model, save if the best model
        obj_new = disp_misfit_l2norm(slip_ssds)/dsqrt(dble(fault%nrecords)) + &
                      los_weight*los_misfit_l2norm(slip_ssds)/dsqrt(dble(fault%nrecords)) + &
                      stress_weight*shear_stress(slip_ssds) + &
                      smoothing_constant*roughness(slip_ssds)
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
        endif
        if (anneal_log_file.ne.'none') then
            write(201,'(A,I8,2(4X,A,1PE12.4))') 'Iteration: ',i,'Temperature: ',temp,&
                                             'Objective: ',obj_0
            do j = 1,nflt
                write(201,'(1PE14.6,0PF10.2)') slip_0(j),rake_0(j)
            enddo
        endif

        ! Reduce temperature by cooling factor
        if (temp.le.temp_minimum) then
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

    double precision function disp_misfit_l2norm(model_array)
    !----
    ! Calculate the L2 norm of the difference vector between the displacements produced
    ! by model_array (first column is strike-slip, second column is dip-slip) and input values
    !----
    use variable_module, only: fault, displacement, gf_disp, disp_components
    implicit none
    ! I/O variables
    double precision :: model_array(fault%nrecords,2)
    ! Local variables
    integer :: i, j, nflt, ndsp
    double precision :: disp_pre(3), ss, ds, dx, dy, dz

    nflt = fault%nrecords
    ndsp = displacement%nrecords

    disp_misfit_l2norm = 0.0d0

    if (displacement%file.eq.'none'.and.displacement%flag.ne.'misfit') then
        return
    endif

    do i = 1,ndsp
        disp_pre = 0.0d0
        do j = 1,nflt
            if (disp_components.eq.'123') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds
            elseif (disp_components.eq.'12') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
            elseif (disp_components.eq.'13') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds
            elseif (disp_components.eq.'23') then
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds
            elseif (disp_components.eq.'1') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
            elseif (disp_components.eq.'2') then
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
            elseif (disp_components.eq.'3') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(1) + ss + ds
            endif
        enddo
        dx = 0.0
        dy = 0.0
        dz = 0.0
        if (disp_components.eq.'123') then
            dx = displacement%array(i,4)-disp_pre(1)
            dy = displacement%array(i,5)-disp_pre(2)
            dz = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'12') then
            dx = displacement%array(i,4)-disp_pre(1)
            dy = displacement%array(i,5)-disp_pre(2)
        elseif (disp_components.eq.'13') then
            dx = displacement%array(i,4)-disp_pre(1)
            dz = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'23') then
            dy = displacement%array(i,5)-disp_pre(2)
            dz = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'1') then
            dx = displacement%array(i,4)-disp_pre(1)
        elseif (disp_components.eq.'2') then
            dy = displacement%array(i,5)-disp_pre(2)
        elseif (disp_components.eq.'3') then
            dz = displacement%array(i,6)-disp_pre(3)
        endif
        disp_misfit_l2norm = disp_misfit_l2norm + dx*dx + dy*dy + dz*dz
    enddo

    disp_misfit_l2norm = dsqrt(disp_misfit_l2norm)

    return
    end function disp_misfit_l2norm

!--------------------------------------------------------------------------------------------------!

    double precision function disp_misfit_chi2(model_array)
    !----
    ! Calculate the chi-squared value of the difference vector between the displacements produced
    ! by model_array (first column is strike-slip, second column is dip-slip) and input values
    !----

    use variable_module, only: fault, displacement, gf_disp, disp_components, disp_cov_mat
    implicit none

    ! I/O variables
    double precision :: model_array(fault%nrecords,2)

    ! Local variables
    integer :: i, j, nflt, ndsp
    double precision :: disp_pre(3), ss, ds, ddisp(displacement%nrecords,3)
    integer :: n, nrhs, lda, ldb, lwork, info
    integer, allocatable :: ipiv(:)
    double precision, allocatable :: alocal(:,:), blocal(:,:), work(:)

    ! Initialize chi-squared value as zero
    disp_misfit_chi2 = 0.0d0

    ! Need a displacement file and the flag indicating you want misfit to calculate misfit
    if (displacement%file.eq.'none'.and.displacement%flag.ne.'misfit') then
        return
    endif

    ! A couple of shorter variables....
    nflt = fault%nrecords
    ndsp = displacement%nrecords


    do i = 1,ndsp

        ! Compute predicted displacement at each station
        ! The displacement components to compare depends on which are specified in disp_components
        disp_pre = 0.0d0

        do j = 1,nflt
            if (disp_components.eq.'123') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds

            elseif (disp_components.eq.'12') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds

            elseif (disp_components.eq.'13') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds

            elseif (disp_components.eq.'23') then
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds
                ss = gf_disp%array(i+2*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+2*ndsp,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(3) + ss + ds

            elseif (disp_components.eq.'1') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(1) = disp_pre(1) + ss + ds

            elseif (disp_components.eq.'2') then
                ss = gf_disp%array(i+1*ndsp,j     )*model_array(j,1)
                ds = gf_disp%array(i+1*ndsp,j+nflt)*model_array(j,2)
                disp_pre(2) = disp_pre(2) + ss + ds

            elseif (disp_components.eq.'3') then
                ss = gf_disp%array(i       ,j     )*model_array(j,1)
                ds = gf_disp%array(i       ,j+nflt)*model_array(j,2)
                disp_pre(3) = disp_pre(1) + ss + ds
            endif
        enddo

        ! Compute difference between observed and predicted displacements
        ddisp(i,:) = 0.0d0
        if (disp_components.eq.'123') then
            ddisp(i,1) = displacement%array(i,4)-disp_pre(1)
            ddisp(i,2) = displacement%array(i,5)-disp_pre(2)
            ddisp(i,3) = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'12') then
            ddisp(i,1) = displacement%array(i,4)-disp_pre(1)
            ddisp(i,2) = displacement%array(i,5)-disp_pre(2)
        elseif (disp_components.eq.'13') then
            ddisp(i,1) = displacement%array(i,4)-disp_pre(1)
            ddisp(i,2) = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'23') then
            ddisp(i,1) = displacement%array(i,5)-disp_pre(2)
            ddisp(i,2) = displacement%array(i,6)-disp_pre(3)
        elseif (disp_components.eq.'1') then
            ddisp(i,1) = displacement%array(i,4)-disp_pre(1)
        elseif (disp_components.eq.'2') then
            ddisp(i,1) = displacement%array(i,5)-disp_pre(2)
        elseif (disp_components.eq.'3') then
            ddisp(i,1) = displacement%array(i,6)-disp_pre(3)
        endif
    enddo

    ! Use symmetric equation solver to multiply inverse covariance matrix and difference vector
    n = len_trim(disp_components)*ndsp
    nrhs = 1
    lda = n
    ldb = n
    allocate(ipiv(n))
    allocate(alocal(len_trim(disp_components)*ndsp,len_trim(disp_components)*ndsp))
    allocate(blocal(len_trim(disp_components)*ndsp,1))
    alocal = disp_cov_mat
    j = len_trim(disp_components)
    do i = 1,j
        blocal(1+(i-1)*ndsp:ndsp+(i-1)*ndsp,1) = ddisp(1:ndsp,i)
    enddo

    ! Get optimal size of lwork array
    allocate(work(1))
    lwork = -1
#ifdef USELAPACK
    call dsysv('Lower',n,nrhs,alocal,lda,ipiv,blocal,ldb,work,lwork,info)
#endif

    ! Resize lwork array and solve equation so that blocal = inv(cov_mat)*ddisp
    lwork = int(work(1))
    deallocate(work)
    allocate(work(lwork))
#ifdef USELAPACK
    call dsysv('Lower',n,nrhs,alocal,lda,ipiv,blocal,ldb,work,lwork,info)
#endif

    if (info.gt.0) then
        write(0,*) 'disp_misfit_chi2: block diagonal matrix is singular in dsysv'
    endif

    do i = 1,ndsp
        do j = 1,len_trim(disp_components)
            disp_misfit_chi2 = disp_misfit_chi2 + ddisp(i,j)*blocal(i+(j-1)*ndsp,1)
        enddo
    enddo

    deallocate(work)
    deallocate(ipiv)
    deallocate(alocal)
    deallocate(blocal)

    return
    end function disp_misfit_chi2

!--------------------------------------------------------------------------------------------------!

    double precision function los_misfit_l2norm(model_array)
    !----
    ! Calculate the L2 norm of the difference vector between the displacements produced
    ! by model_array (first column is strike-slip, second column is dip-slip) and input values
    !----
    use variable_module, only: fault, los, gf_los
    implicit none
    ! I/O variables
    double precision :: model_array(fault%nrecords,2)
    ! Local variables
    integer :: i, j, nflt, nlos
    double precision :: los_pre, ss, ds, dlos

    nflt = fault%nrecords
    nlos = los%nrecords

    los_misfit_l2norm = 0.0d0

    if (los%file.eq.'none') then
        return
    endif

    do i = 1,nlos
        los_pre = 0.0d0
        do j = 1,nflt
            ss = gf_los%array(i       ,j     )*model_array(j,1)
            ds = gf_los%array(i       ,j+nflt)*model_array(j,2)
            los_pre = los_pre + ss + ds
        enddo
        dlos = 0.0
        dlos = los%array(i,4)-los_pre
        los_misfit_l2norm = los_misfit_l2norm + dlos*dlos
    enddo

    los_misfit_l2norm = dsqrt(los_misfit_l2norm)

    return
    end function los_misfit_l2norm

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

!--------------------------------------------------------------------------------------------------!

    double precision function roughness(model_array)
    !----
    ! Calculate the Laplacian roughness of the model based on the linking files provided
    !----
    use variable_module, only : smoothing, smoothing_constant, smoothing_neighbors, fault
    implicit none
    ! I/O variables
    double precision :: model_array(fault%nrecords,2)
    ! Local variables
    integer :: i, j, ifault, nneighbor, ineighbor, neighbor
    double precision :: ss_rough, ds_rough

    roughness = 0.0d0
    if (smoothing_constant.lt.0.0d0) then
        return
    endif

    do i = 1,smoothing%nrecords
        ifault = smoothing%intarray(i,1)
        nneighbor = smoothing%intarray(i,2)
        ineighbor = smoothing%intarray(i,3)

        ! Fault to be smoothed gets weight=nneighbor
        ss_rough = dble(nneighbor)*model_array(ifault,1)
        ds_rough = dble(nneighbor)*model_array(ifault,2)

        ! Each neighboring fault gets weight of -1
        do j = 0,nneighbor-1
            neighbor = smoothing_neighbors(ineighbor+j)
            ss_rough = ss_rough - model_array(neighbor,1)
            ds_rough = ds_rough - model_array(neighbor,2)
        enddo

        roughness = roughness + dabs(ss_rough) + dabs(ds_rough)
    enddo

    end function roughness

!--------------------------------------------------------------------------------------------------!





!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!





    subroutine invert_anneal_pseudocoupling()
    use io, only: verbosity, stderr, stdout
    use variable_module, only: fault, displacement, prestress, slip_constraint, fault_slip, &
                           anneal_log_file, max_iteration, reset_iteration, &
                                temp_start, temp_minimum, cooling_factor, prob_lock2unlock, &
                               prob_unlock2lock
    use lsqr_module, only: invert_lsqr, A, b, x, isAsaveLoaded
    implicit none
    integer :: randFaultList(fault%nrecords)
    double precision :: slip_save(fault%nrecords,2)
    double precision :: fault_slip_0(fault%nrecords,2), fault_slip_best(fault%nrecords,2)
    integer :: nlocked, nunlocked, nswitchmax
    double precision :: temp, obj_0, obj_new, obj_best, p_trans
    integer :: i, j, k, ktmp
    real, external :: ran2
    logical :: do_inversion

    if (verbosity.eq.1.or.verbosity.eq.2) then
        write(stdout,*) 'invert_anneal_pseudocoupling: starting'
    endif

    if (verbosity.ne.0) then
        verbosity = verbosity + 20
    endif

    ! Initialize solution, random number generator, and slip_constraint%array values
    call initialize_annealing_psc()

    ! To initialize an A matrix that is its largest possible size, solve with all faults unlocked
    slip_save = slip_constraint%array
    slip_constraint%array = 99999.0d0

    ! We do not want to fit displacements with lsqr_invert(), so indicate in file name
    ! However, we want to calculate misfit during annealing process, so indicate with flag
    displacement%file = 'none'
    displacement%flag = 'misfit'

    ! Even though pre-stresses are not being inverted for in this mode (YET), to find pseudo-coupling
    ! slip in lsqr_invert() we need to activate this data structure.
    if (prestress%file.eq.'none') then
        prestress%file = 'zero'
    endif
    if (.not.allocated(prestress%array)) then
        allocate(prestress%array(fault%nrecords,2))
    endif
    prestress%array = 0.0d0

    ! Speed up loading of A matrix by saving it as Asave. Indicate it has not been loaded yet.
    isAsaveLoaded = .false.

    ! Initialize fault list in order
    do i = 1,fault%nrecords
        randFaultList(i) = i
    enddo

    ! Can switch up to this many faults in every iteration
    nswitchmax = fault%nrecords/10
    if (nswitchmax.lt.1) then
        nswitchmax = 1
    endif
    ! write(0,*) 'nswitchmax',nswitchmax

    if (verbosity.eq.22) then
        write(stdout,*) 'invert_anneal_pseudocoupling: annealing preparation finished'
    endif



    ! Initialize solution array, compute initial solution, and save results
    if (.not.allocated(fault_slip)) then
        allocate(fault_slip(fault%nrecords,2))
    endif

    ! Solve for fault slip using largest possible A matrix
    call invert_lsqr()
    if (verbosity.eq.22) then
        write(stdout,*) 'invert_anneal_pseudocoupling: initialized maximum size A'
    endif


    ! I do not actually care about that solution as the first one...
    ! Set locked/unlocked to correct values and solve again
    do i = 1,fault%nrecords
        if (isFaultLocked(i).eq.1) then
            slip_constraint%array(i,:) = slip_save(i,:)
        else
            slip_constraint%array(i,:) = 99999.0d0
        endif
    enddo
    prestress%array = 0.0d0

    ! Solve for initial fault slip
    if (minval(dabs(slip_constraint%array)).gt.99998.0d0) then
        fault_slip = 0.0d0
    else
        call invert_lsqr() ! initial solution is in fault_slip array
    endif
    if (verbosity.eq.22) then
        write(stdout,*) 'invert_anneal_pseudocoupling: finished computing initial solution'
    endif


    fault_slip_0 = fault_slip ! save the initial solution
    fault_slip_best = fault_slip
    obj_0 = disp_misfit_chi2(fault_slip) ! chi-squared
    ! obj_0 = disp_misfit_l2norm(fault_slip)/dsqrt(dble(fault%nrecords)) ! RMS
    obj_best = obj_0

    ! Set starting temperature
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

    ! Write initial solution to log file
    if (anneal_log_file.ne.'none') then
        open(unit=201,file=anneal_log_file,status='unknown')
        write(201,'(A,I4,2(4X,A,1PE12.4))') 'Iteration: ',0,'Temperature: ',temp,&
                                                 'Objective: ',obj_0
        do j = 1,fault%nrecords
            write(201,'(1P2E14.6)') fault_slip(j,1),fault_slip(j,2)
        enddo
    endif

    if (verbosity.eq.22) then
        write(stdout,*) 'invert_anneal_pseudocoupling: starting search'
        write(stdout,*)
    endif

    ! Run annealing search for distribution of locked patches
    do i = 1,max_iteration

        if (verbosity.eq.21) then
            write(stdout,'(A1,A1,A,I5,A,I5)',advance='no') ' ',achar(13), &
                                                   'invert_anneal_pseudocoupling: iteration ', &
                                                   i,' of ',max_iteration
            if (i.eq.max_iteration) then
                write(stdout,*)
            endif
        endif

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: iteration ', i,' of ',max_iteration
        endif

        ! Randomize fault list by switching each entry with a random entry
        do j = 1,fault%nrecords
            k = int(ran2(idum)*fault%nrecords)+1
            if (k.lt.1) then
                k = 1
            elseif (k.gt.fault%nrecords) then
                k = fault%nrecords
            endif
            ktmp = randFaultList(k)
            randFaultList(k) = randFaultList(j)
            randFaultList(j) = ktmp
        enddo

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: finished randomizing fault list'
        endif

        ! Flip up to 10% of faults from locked->unlocked or vice versa
        nlocked = 0
        nunlocked = 0
        do j = 1,fault%nrecords

            ! For all faults...

            if (ran2(idum).lt.prob_lock2unlock.and.isFaultLocked(randFaultList(j)).eq.1) then

                ! Flip this fault! Locked -> unlocked

                if (nunlocked.lt.nswitchmax) then
                    isFaultLocked(randFaultList(j)) = 0
                endif

                ! Only count fault as flipped if it is not always unlocked
                if (dabs(slip_save(randFaultList(j),1)).lt.99998.0d0) then
                    nunlocked = nunlocked + 1
                endif

            elseif (ran2(idum).lt.prob_unlock2lock.and.isFaultLocked(randFaultList(j)).eq.0) then

                ! Flip this fault! Unlocked -> locked

                if (nlocked.lt.nswitchmax) then
                    isFaultLocked(randFaultList(j)) = 1
                endif

                ! Only count fault as flipped if it is not always unlocked
                if (dabs(slip_save(randFaultList(j),1)).lt.99998.0d0) then
                    nlocked = nlocked + 1
                endif

            endif

        enddo

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: finished flipping faults'
        endif

        if (verbosity.eq.26) then
            write(stdout,*) 'invert_anneal_pseudocoupling says: locked faults are:'
            do j = 1,fault%nrecords
                write(stderr,'(A,I6,I6)') 'Fault: ',j,isFaultLocked(j)
            enddo
        endif


        ! Slip constraints applied to locked faults
        do j = 1,fault%nrecords
            if (isFaultLocked(j).eq.0) then
                slip_constraint%array(j,1) = 99999.0d0
                slip_constraint%array(j,2) = 99999.0d0
            else
                slip_constraint%array(j,1) = slip_save(j,1)
                slip_constraint%array(j,2) = slip_save(j,2)
            endif
        enddo

        ! Pre-stresses are zero at start of calculation (THIS MAY CHANGE TO ADD RESISTIVE TRACTIONS!)
        prestress%array = 0.0d0

        ! Calculate other subfault slip
        do_inversion = .false.
        do j = 1,fault%nrecords
            if (slip_constraint%array(j,1).gt.99998.0d0) then
                do_inversion = .true.
                exit
            endif
        enddo


        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: finished setup; calling linear solver'
        endif

        if (do_inversion) then
            call invert_lsqr()
        else
            fault_slip = 0.0d0
        endif

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: linear solver finished'
        endif


        ! Calculate new objective function
        obj_new = disp_misfit_chi2(fault_slip) ! chi-squared
        ! obj_new = disp_misfit_l2norm(fault_slip)/dsqrt(dble(fault%nrecords)) ! RMS
        if (obj_new.lt.obj_best) then
            fault_slip_best = fault_slip
            obj_best = obj_new
        endif

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: new objective function: ',obj_new
        endif

        ! Compute transition probability
        !     (obj_new < obj_0) => always transition to better model
        !     (obj_new > obj_0) => transition with p = exp(-dE/T)
        p_trans = dexp((obj_0-obj_new)/temp)

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: transition probability: ', &
                            min(p_trans,1.0d0)
        endif

        ! If the transition is made because of better fit or chance,
        ! update the current model (slip_0) with the proposed model (slip_new)
        if (ran2(idum).lt.p_trans) then
            fault_slip_0 = fault_slip
            obj_0 = obj_new
            if (verbosity.eq.26) then
                write(stderr,'(A,1P1E14.6)') 'Current solution, Objective=', obj_0
                do j = 1,fault%nrecords
                    write(stderr,'(1P2E14.6)') fault_slip_0(j,:)
                enddo
            endif
            if (anneal_log_file.ne.'none') then
                write(201,'(A,I4,2(4X,A,1PE12.4))') 'Iteration: ',i,'Temperature: ',temp,&
                                                 'Objective: ',obj_0
                do j = 1,fault%nrecords
                    write(201,'(1P2E14.6)') fault_slip_0(j,1),fault_slip_0(j,2)
                enddo
            endif
        endif

        ! Reduce temperature by cooling factor
        if (temp.lt.temp_minimum) then
            temp = temp_minimum
        else
            temp = temp*cooling_factor
        endif

        if (mod(i,reset_iteration).eq.0) then
            temp = temp_start
        endif

        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: temperature updated to: ',temp
            write(stdout,*)
        endif


        if (verbosity.eq.22) then
            write(stdout,*) 'invert_anneal_pseudocoupling: finished iteration'
            write(stdout,*)
        endif

    enddo
    fault_slip = fault_slip_best

    verbosity = verbosity - 20

    ! Free memory from least squares module variables
    if (allocated(A)) then
        deallocate(A)
    endif
    if (allocated(b)) then
        deallocate(b)
    endif
    if (allocated(x)) then
        deallocate(x)
    endif
    if (allocated(isFaultLocked)) then
        deallocate(isFaultLocked)
    endif

    if (verbosity.eq.1.or.verbosity.eq.2) then
        write(stdout,*) 'invert_anneal_pseudocoupling: finished'
    endif

    return
    end subroutine invert_anneal_pseudocoupling

!--------------------------------------------------------------------------------------------------!

    subroutine initialize_annealing_psc()
    use io, only: stderr, stdout, verbosity
    use variable_module, only: fault, slip_constraint, anneal_init_file, anneal_init_mode
    implicit none
    ! Local variables
    integer :: i, ios
    double precision :: tmparray(1,2), odds_locked
    logical :: ex
    ! External variables
    integer, external :: timeseed
    real, external :: ran2

    if (verbosity.eq.22) then
        write(stdout,*) 'initialize_annealing_psc: starting'
    endif

    ! Initialize the random number generator
    idum = -timeseed()

    ! Make sure slip_constraint%array is defined (values for locked faults)
    if (slip_constraint%file.eq.'none') then
        call usage('!! initialize_annealing_psc: a slip constraint file is required ')
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

    ! Initialize locked faults
    if (.not.allocated(isFaultLocked)) then
        allocate(isFaultLocked(fault%nrecords))
    endif
    isFaultLocked = 0

    if (trim(anneal_init_mode).eq.'unlocked') then
        isFaultLocked = 0

    elseif (trim(anneal_init_mode).eq.'locked') then
        isFaultLocked = 1

    elseif (trim(anneal_init_mode).eq.'user') then
        if (trim(anneal_init_file).eq.'') then
            write(stderr,*) 'initialize_annealing_psc: no anneal_init_file defined'
        endif
        inquire(file=anneal_init_file,exist=ex)
        if (.not.ex) then
            write(stderr,*) 'initialize_annealing_psc: did not find anneal_init_file named ', &
                       trim(anneal_init_file)
        else
            open(unit=63,file=anneal_init_file,status='old')
            do i = 1,fault%nrecords
                read(63,*,iostat=ios,err=6301,end=6301) isFaultLocked(i)
            enddo
            6301 if (ios.ne.0) then
                write(stderr,*) 'initialize_annealing_psc: error reading anneal_init_file'
            endif
            close(63)
        endif

    elseif (anneal_init_mode(1:4).eq.'rand') then
        read(anneal_init_mode(5:8),*,iostat=ios) odds_locked
        if (ios.ne.0) then
            write(stderr,*) 'initialize_annealing_psc: could not read locked odds, setting to 0.5'
            odds_locked = 0.5d0
        endif
        do i = 1,fault%nrecords
            if (ran2(idum).lt.odds_locked) then
                isFaultLocked(i) = 1
            else
                isFaultLocked(i) = 0
            endif
        enddo

    else
        write(stderr,*) 'initialize_annealing_psc: did not recognize anneal_init_mode=', &
                        trim(anneal_init_mode)
        write(stderr,*) '                          setting anneal_init_mode to unlocked'
    endif

    if (verbosity.eq.22) then
        write(stderr,*) 'initialize_annealing_psc: finished'
    endif

    return
    end subroutine initialize_annealing_psc

end module anneal_module
