!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief container for various plainwaves related things
!> \par History
!>      10.2002 created [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
MODULE pw_env_types
  USE cube_utils,                      ONLY: cube_info_type,&
                                             destroy_cube_info
  USE f77_blas
  USE gaussian_gridlevels,             ONLY: destroy_gaussian_gridlevel,&
                                             gridlevel_info_type
  USE input_section_types,             ONLY: section_vals_release
  USE pw_poisson_types,                ONLY: pw_poisson_release,&
                                             pw_poisson_type
  USE pw_pool_types,                   ONLY: pw_pool_p_type,&
                                             pw_pool_release,&
                                             pw_pool_type,&
                                             pw_pools_dealloc,&
                                             pw_pools_flush_cache
  USE realspace_grid_types,            ONLY: realspace_grid_desc_p_type,&
                                             realspace_grid_desc_type,&
                                             rs_grid_release_descriptor
#include "cp_common_uses.h"

  IMPLICIT NONE
  PRIVATE

  LOGICAL, PRIVATE, PARAMETER :: debug_this_module=.TRUE.
  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'pw_env_types'

  PUBLIC :: pw_env_type
  PUBLIC :: pw_env_retain, pw_env_release, pw_env_get, pw_env_flush_cache
!***

! *****************************************************************************
!> \brief contained for different pw related things
!> \param pw_pools pools for multigrids
!> \param rs_descs descriptors for the realspace grids
!> \param xc_pw_pool the pool used for xc calculation on grid (might be the
!>        same as the finest, or finer still).
!> \param gridlevel_info gaussian gridlevel info
!> \param cube_info info on cube and max sphere size for multigrids
!> \param aux_bas which multigrid is the auxiliar basis
!> 
!>      readonly attributes
!> \param auxbas_pw_pool a pool that allocates grids in the auxiliary basis
!> \param auxbas_rs_desc real space grid in the auxiliary basis, be careful
!>        in parallel nsmax is choosen with multigrid in mind!
!> \note
!>      be careful in parallel nsmax for the rs_grids is choosen with
!>      multigrid in mind! (well not as of this writing but...)
!> \par History
!>      10.2002 created [fawzi]
!>      04.2003 added rs grid pools [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
  TYPE pw_env_type
     INTEGER :: ref_count
     TYPE(pw_pool_p_type), DIMENSION(:), POINTER :: pw_pools
     TYPE(pw_pool_type), POINTER :: xc_pw_pool
     TYPE(realspace_grid_desc_p_type), DIMENSION(:), POINTER :: rs_descs
     TYPE(gridlevel_info_type), POINTER :: gridlevel_info
     TYPE(cube_info_type), DIMENSION(:), POINTER :: cube_info
     INTEGER :: auxbas_grid
     TYPE(pw_poisson_type), POINTER :: poisson_env
  END TYPE pw_env_type

CONTAINS

! *****************************************************************************
!> \brief returns the various attributes of the pw env
!> \param pw_env the einvironment you want info about
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!>      For the other see the attributes of pw_env_type
!> \par History
!>      10.2002 created [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
SUBROUTINE pw_env_get(pw_env, pw_pools, cube_info, gridlevel_info,&
     auxbas_pw_pool,auxbas_grid,rs_descs,auxbas_rs_desc,&
     xc_pw_pool, poisson_env,error)
    TYPE(pw_env_type), POINTER               :: pw_env
    TYPE(pw_pool_p_type), DIMENSION(:), &
      OPTIONAL, POINTER                      :: pw_pools
    TYPE(cube_info_type), DIMENSION(:), &
      OPTIONAL, POINTER                      :: cube_info
    TYPE(gridlevel_info_type), OPTIONAL, &
      POINTER                                :: gridlevel_info
    TYPE(pw_pool_type), OPTIONAL, POINTER    :: auxbas_pw_pool
    INTEGER, INTENT(out), OPTIONAL           :: auxbas_grid
    TYPE(realspace_grid_desc_p_type), &
      DIMENSION(:), OPTIONAL, POINTER        :: rs_descs
    TYPE(realspace_grid_desc_type), &
      OPTIONAL, POINTER                      :: auxbas_rs_desc
    TYPE(pw_pool_type), OPTIONAL, POINTER    :: xc_pw_pool
    TYPE(pw_poisson_type), OPTIONAL, POINTER :: poisson_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'pw_env_get', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: failure

  failure=.FALSE.

  CPPrecondition(ASSOCIATED(pw_env),cp_failure_level,routineP,error,failure)
  CPPrecondition(pw_env%ref_count>0,cp_failure_level,routineP,error,failure)
  IF (.NOT. failure) THEN
     IF (PRESENT(pw_pools)) pw_pools => pw_env%pw_pools
     IF (PRESENT(rs_descs)) rs_descs => pw_env%rs_descs
     IF (PRESENT(cube_info)) cube_info => pw_env%cube_info
     IF (PRESENT(gridlevel_info)) gridlevel_info => pw_env%gridlevel_info
     IF (PRESENT(auxbas_pw_pool)) THEN
        auxbas_pw_pool => pw_env%pw_pools(pw_env%auxbas_grid)%pool
     END IF
     IF (PRESENT(auxbas_rs_desc)) THEN
        auxbas_rs_desc => pw_env%rs_descs(pw_env%auxbas_grid)%rs_desc
     END IF
     IF (PRESENT(auxbas_grid)) auxbas_grid = pw_env%auxbas_grid
     IF (PRESENT(xc_pw_pool)) xc_pw_pool => pw_env%xc_pw_pool
     IF (PRESENT(poisson_env)) poisson_env => pw_env%poisson_env
  END IF
END SUBROUTINE pw_env_get

! *****************************************************************************
!> \brief retains the pw_env (see doc/ReferenceCounting.html)
!> \param pw_env the pw_env to retain
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!> \par History
!>      10.2002 created [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
SUBROUTINE pw_env_retain(pw_env,error)
    TYPE(pw_env_type), POINTER               :: pw_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'pw_env_retain', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: failure

  failure=.FALSE.

  CPPrecondition(ASSOCIATED(pw_env),cp_failure_level,routineP,error,failure)
  IF (.NOT. failure) THEN
     CPPrecondition(pw_env%ref_count>0,cp_failure_level,routineP,error,failure)
     pw_env%ref_count=pw_env%ref_count+1
  END IF
END SUBROUTINE pw_env_retain

! *****************************************************************************
!> \brief releases the given pw_env (see doc/ReferenceCounting.html)
!> \param pw_env the pw_env to release
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!> \par History
!>      10.2002 created [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
SUBROUTINE pw_env_release(pw_env, kg, error)
    TYPE(pw_env_type), POINTER               :: pw_env
    LOGICAL, OPTIONAL                        :: kg
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'pw_env_release', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, igrid_level, stat
    LOGICAL                                  :: failure, my_kg

  failure=.FALSE.
  my_kg = .FALSE.
  IF(PRESENT(kg)) my_kg = kg
  IF (ASSOCIATED(pw_env)) THEN
     CPPrecondition(pw_env%ref_count>0,cp_failure_level,routineP,error,failure)
     pw_env%ref_count=pw_env%ref_count-1
     IF (pw_env%ref_count<1) THEN
        CALL pw_poisson_release(pw_env%poisson_env, error=error)
        CALL pw_pools_dealloc(pw_env%pw_pools,error=error)
        IF (ASSOCIATED(pw_env%gridlevel_info)) THEN
           IF(my_kg) THEN
             DEALLOCATE (pw_env%gridlevel_info%cutoff,STAT=stat)
             CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
             CALL section_vals_release(pw_env%gridlevel_info%print_section,error=error)
             DEALLOCATE (pw_env%gridlevel_info%count,STAT=stat)
             CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
           ELSE
             CALL destroy_gaussian_gridlevel(pw_env%gridlevel_info, error=error)
           END IF
           DEALLOCATE(pw_env%gridlevel_info,stat=stat)
           CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
        END IF
        IF (ASSOCIATED(pw_env%cube_info)) THEN
           DO igrid_level=1,SIZE(pw_env%cube_info)
              CALL destroy_cube_info(pw_env%cube_info(igrid_level))
           END DO
           DEALLOCATE(pw_env%cube_info,stat=stat)
           CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
        END IF
        CALL pw_pool_release(pw_env%xc_pw_pool,error=error)
        IF (ASSOCIATED(pw_env%rs_descs)) THEN
          DO i=1, SIZE(pw_env%rs_descs)
            CALL rs_grid_release_descriptor(pw_env%rs_descs(i)%rs_desc, error=error)
          END DO
          DEALLOCATE(pw_env%rs_descs, stat=stat)
          CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
        END IF
        DEALLOCATE(pw_env, stat=stat)
        CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
     END IF
  END IF
  NULLIFY(pw_env)
END SUBROUTINE pw_env_release

! *****************************************************************************
!> \brief flushes the cached pws
!> \param pw_env the pw_env to be flushed
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!> \par History
!>      11.2002 created [fawzi]
!> \author Fawzi Mohamed
! *****************************************************************************
SUBROUTINE pw_env_flush_cache(pw_env,error)
    TYPE(pw_env_type), POINTER               :: pw_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'pw_env_flush_cache', &
      routineP = moduleN//':'//routineN

    LOGICAL                                  :: failure

  failure=.FALSE.

  CPPrecondition(ASSOCIATED(pw_env),cp_failure_level,routineP,error,failure)
  IF (.NOT. failure) THEN
     IF (ASSOCIATED(pw_env%pw_pools)) THEN
        CALL pw_pools_flush_cache(pw_env%pw_pools,error=error)
     END IF
  END IF
END SUBROUTINE pw_env_flush_cache

END MODULE pw_env_types
