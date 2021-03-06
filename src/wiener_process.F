!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Handling of the Wiener process currently employed in turn of the
!>      Langevin dynamics.
!> \par History
!>      none
!> \author Matthias Krack (05.07.2005)
! *****************************************************************************
MODULE wiener_process

  USE atomic_kind_list_types,          ONLY: atomic_kind_list_type
  USE cp_para_types,                   ONLY: cp_para_env_type
  USE cp_subsys_types,                 ONLY: cp_subsys_get,&
                                             cp_subsys_type
  USE distribution_1d_types,           ONLY: distribution_1d_type,&
                                             init_local_particle_set
  USE f77_blas
  USE force_env_types,                 ONLY: force_env_get,&
                                             force_env_type
  USE input_constants,                 ONLY: langevin_ensemble
  USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                             section_vals_type
  USE kinds,                           ONLY: dp
  USE md_environment_types,            ONLY: get_md_env,&
                                             md_environment_type
  USE metadynamics_types,              ONLY: meta_env_type
  USE parallel_rng_types,              ONLY: GAUSSIAN,&
                                             create_rng_stream,&
                                             next_rng_seed
  USE particle_list_types,             ONLY: particle_list_type
  USE simpar_types,                    ONLY: simpar_type
  USE string_utilities,                ONLY: compress
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  ! Global parameters in this module
  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'wiener_process'

  ! Public subroutines
  PUBLIC :: create_wiener_process, create_wiener_process_cv

CONTAINS

! *****************************************************************************
!> \brief Create a Wiener process for Langevin dynamics and initialize an
!>      independent random number generator for each atom in all force
!>      environment and all the subsystems/fragments therein.
!> \par History
!>      Creation (06.07.2005,MK)
! *****************************************************************************
  SUBROUTINE create_wiener_process(md_env,error)

    TYPE(md_environment_type), POINTER       :: md_env
    TYPE(cp_error_type), INTENT(INOUT)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'create_wiener_process', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=40)                        :: name
    INTEGER :: iparticle, iparticle_kind, iparticle_local, nparticle, &
      nparticle_kind, nparticle_local, stat
    LOGICAL                                  :: failure
    REAL(KIND=dp), ALLOCATABLE, &
      DIMENSION(:, :, :)                     :: seed
    REAL(KIND=dp), DIMENSION(3, 2)           :: initial_seed
    TYPE(atomic_kind_list_type), POINTER     :: atomic_kinds
    TYPE(cp_para_env_type), POINTER          :: para_env
    TYPE(cp_subsys_type), POINTER            :: subsys
    TYPE(distribution_1d_type), POINTER      :: local_particles
    TYPE(force_env_type), POINTER            :: force_env
    TYPE(particle_list_type), POINTER        :: particles
    TYPE(section_vals_type), POINTER         :: force_env_section, &
                                                subsys_section, work_section
    TYPE(simpar_type), POINTER               :: simpar

    failure = .FALSE.
    NULLIFY(work_section,force_env)
    CPPrecondition (ASSOCIATED(md_env),cp_failure_level,routineP,error,failure)

    CALL get_md_env(md_env=md_env, force_env=force_env, para_env=para_env,&
         simpar=simpar, error=error)

    IF (simpar%ensemble == langevin_ensemble) THEN

       ! Load initial seed (not needed for a restart)

       initial_seed = next_rng_seed(error=error)

       CALL force_env_get(force_env,force_env_section=force_env_section,&
            subsys=subsys,error=error)

       subsys_section => section_vals_get_subs_vals(force_env_section,"SUBSYS",error=error)

       CALL cp_subsys_get(subsys=subsys,atomic_kinds=atomic_kinds,local_particles=local_particles,&
            particles=particles,error=error)

       nparticle_kind = atomic_kinds%n_els
       nparticle = particles%n_els

       ! Allocate the (local) data structures for the Wiener process

       ALLOCATE(local_particles%local_particle_set(nparticle_kind),STAT=stat)
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

       DO iparticle_kind=1,nparticle_kind
          nparticle_local = local_particles%n_el(iparticle_kind)
          ALLOCATE (local_particles%local_particle_set(iparticle_kind)%rng(nparticle_local),STAT=stat)
          CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
          DO iparticle_local=1,nparticle_local
             NULLIFY (local_particles%local_particle_set(iparticle_kind)%rng(iparticle_local)%stream)
          END DO
       END DO

       ! Each process generates all seeds. The seed generation should be
       ! quite fast and in this way a broadcast is avoided.

       ALLOCATE (seed(3,2,nparticle),STAT=stat)
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

       seed(:,:,1) = initial_seed
       DO iparticle=2,nparticle
          seed(:,:,iparticle) = next_rng_seed(seed(:,:,iparticle-1),error=error)
       END DO

       ! Update initial seed

       initial_seed = next_rng_seed(seed(:,:,nparticle),error=error)

       ! Create a random number stream (Wiener process) for each particle

       DO iparticle_kind=1,nparticle_kind
          nparticle_local = local_particles%n_el(iparticle_kind)
          DO iparticle_local=1,nparticle_local
             iparticle = local_particles%list(iparticle_kind)%array(iparticle_local)
             WRITE (UNIT=name,FMT="(A,I8)") "Wiener process for particle",iparticle
             CALL compress(name)
             CALL create_rng_stream(rng_stream=local_particles%local_particle_set(iparticle_kind)%&
                  &rng(iparticle_local)%stream,name=name,distribution_type=GAUSSIAN,&
                  extended_precision=.TRUE., seed=seed(:,:,iparticle),error=error)
          END DO
       END DO

       DEALLOCATE (seed,STAT=stat)
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

       ! Possibly restart Wiener process
       NULLIFY (work_section)
       work_section => section_vals_get_subs_vals(section_vals=subsys_section,&
            subsection_name="RNG_INIT", error=error)
       CALL init_local_particle_set(distribution_1d=local_particles,&
            nparticle_kind=nparticle_kind, &
            work_section=work_section,error=error)
    END IF

  END SUBROUTINE create_wiener_process

! *****************************************************************************
!> \brief Create a Wiener process for Langevin dynamics used for
!>        metadynamics and initialize an
!>        independent random number generator for each COLVAR.
!> \author Fabio Sterpone
!> \date   01.2009
!>      
! *****************************************************************************
  SUBROUTINE create_wiener_process_cv(meta_env,error)

    TYPE(meta_env_type), POINTER             :: meta_env
    TYPE(cp_error_type), INTENT(INOUT)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'create_wiener_process_cv', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=40)                        :: name
    INTEGER                                  :: i_c, stat
    LOGICAL                                  :: failure
    REAL(KIND=dp), ALLOCATABLE, &
      DIMENSION(:, :, :)                     :: seed
    REAL(KIND=dp), DIMENSION(3, 2)           :: initial_seed

    failure=.FALSE.
    IF (.NOT.ASSOCIATED(meta_env)) RETURN
 
    initial_seed = next_rng_seed(error=error)
 
    DO i_c=1,meta_env%n_colvar
       NULLIFY (meta_env%rng(i_c)%stream)
    END DO

    ! Each process generates all seeds. The seed generation should be
    ! quite fast and in this way a broadcast is avoided.

    ALLOCATE (seed(3,2,meta_env%n_colvar),STAT=stat)
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

    seed(:,:,1) = initial_seed
    DO i_c=2,meta_env%n_colvar
       seed(:,:,i_c) = next_rng_seed(seed(:,:,i_c-1),error=error)
    END DO
    
    ! Update initial seed
    initial_seed = next_rng_seed(seed(:,:,meta_env%n_colvar),error=error)
    
    ! Create a random number stream (Wiener process) for each particle
    DO i_c=1,meta_env%n_colvar
       WRITE (UNIT=name,FMT="(A,I8)") "Wiener process for COLVAR",i_c
       CALL compress(name)
       CALL create_rng_stream(rng_stream=meta_env%rng(i_c)%stream,name=name,distribution_type=GAUSSIAN,&
            extended_precision=.TRUE., seed=seed(:,:,i_c),error=error)
    END DO
    DEALLOCATE (seed,STAT=stat)
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

  END SUBROUTINE create_wiener_process_cv

END MODULE wiener_process
