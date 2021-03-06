!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief module that contains the algorithms to perform an itrative
!>         diagonalization by the block-Davidson approach
!>         P. Blaha, et al J. Comp. Physics, 229, (2010), 453-460
!>         \Iterative diagonalization in augmented plane wave based 
!>              methods in electronic structure calculations\
!> \par History
!>      05.2011 created [MI]
!> \author MI
! *****************************************************************************
MODULE qs_block_davidson_types

  USE cp_fm_struct,                    ONLY: cp_fm_struct_create,&
                                             cp_fm_struct_release,&
                                             cp_fm_struct_type
  USE cp_fm_types,                     ONLY: cp_fm_create,&
                                             cp_fm_release,&
                                             cp_fm_type
  USE input_section_types,             ONLY: section_vals_type,&
                                             section_vals_val_get
  USE kinds,                           ONLY: dp
  USE qs_mo_types,                     ONLY: get_mo_set,&
                                             mo_set_type
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE
  PRIVATE
  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_block_davidson_types'

  PUBLIC :: block_davidson_allocate, block_davidson_release, block_davidson_env_create, davidson_type

  TYPE davidson_type
     INTEGER :: max_iter, prec_type,solver_type,niter_new_prec, first_prec
     REAL(KIND = dp) :: conv_percent, energy_gap, eps_iter
     REAL(KIND = dp),  DIMENSION(:), POINTER :: evals
     TYPE(cp_fm_type), POINTER :: H_block_mat, H_block_vec,&
                                  matrix_z, S_block_mat, W_block_mat
  END TYPE davidson_type

CONTAINS

! *****************************************************************************

  SUBROUTINE block_davidson_env_create(bdav_env,nspins,scf_section,error)

    TYPE(davidson_type), DIMENSION(:), &
      POINTER                                :: bdav_env
    INTEGER, INTENT(IN)                      :: nspins
    TYPE(section_vals_type), POINTER         :: scf_section
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'block_davidson_env_create', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ispin, stat
    LOGICAL                                  :: failure

    failure=.FALSE.

    CPPrecondition(.NOT.ASSOCIATED(bdav_env),cp_failure_level,routineP,error,failure)
    IF(.NOT. failure) THEN
      ALLOCATE(bdav_env(nspins), stat=stat)
      CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)
      IF (.NOT.failure) THEN
        DO ispin = 1,nspins
          NULLIFY(bdav_env(ispin)%H_block_mat)
          NULLIFY(bdav_env(ispin)%H_block_vec)
          NULLIFY(bdav_env(ispin)%S_block_mat)
          NULLIFY(bdav_env(ispin)%W_block_mat)
          NULLIFY(bdav_env(ispin)%evals)
          NULLIFY(bdav_env(ispin)%matrix_z)

          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%PRECONDITIONER",&
             i_val=bdav_env(ispin)%prec_type,error=error)
          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%PRECOND_SOLVER",&
             i_val=bdav_env(ispin)%solver_type,error=error)
          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%ENERGY_GAP",&
             r_val=bdav_env(ispin)%energy_gap,error=error)
          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%NEW_PREC_EACH",&
             i_val=bdav_env(ispin)%niter_new_prec,error=error)
          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%MAX_ITER",&
             i_val=bdav_env(ispin)%max_iter,error=error)
          CALL section_vals_val_get(scf_section,"DIAGONALIZATION%EPS_ITER",&
             r_val=bdav_env(ispin)%eps_iter,error=error)
         CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%FIRST_PREC",&
             i_val=bdav_env(ispin)%first_prec,error=error)
         CALL section_vals_val_get(scf_section,"DIAGONALIZATION%DAVIDSON%CONV_MOS_PERCENT",&
             r_val=bdav_env(ispin)%conv_percent,error=error)

        END DO 
      END IF
    END IF

  END SUBROUTINE block_davidson_env_create

  SUBROUTINE block_davidson_allocate(bdav_env,mo_set,error)

    TYPE(davidson_type)                      :: bdav_env
    TYPE(mo_set_type), POINTER               :: mo_set
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'block_davidson_allocate', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, nao, nmo, nmox2, stat
    LOGICAL                                  :: failure
    TYPE(cp_fm_struct_type), POINTER         :: fm_struct_tmp
    TYPE(cp_fm_type), POINTER                :: mo_coeff

    failure = .FALSE.
    CALL timeset(routineN,handle)
    NULLIFY(fm_struct_tmp, mo_coeff)


    CALL get_mo_set(mo_set=mo_set, mo_coeff=mo_coeff,nao=nao,nmo=nmo)

    nmox2 = 2*nmo
!    write(*,*) nmo, nmox2
!    stop 'alloc' 
    CALL cp_fm_struct_create(fm_struct_tmp, nrow_global=nmox2, ncol_global=nmox2,&
                             para_env=mo_coeff%matrix_struct%para_env, &
                             context=mo_coeff%matrix_struct%context,error=error)
    CALL cp_fm_create(bdav_env%H_block_mat,fm_struct_tmp,name="H_dav",error=error)
    CALL cp_fm_create(bdav_env%S_block_mat,fm_struct_tmp,name="S_dav",error=error)
    CALL cp_fm_create(bdav_env%H_block_vec,fm_struct_tmp,name="C_dav",error=error)
    CALL cp_fm_create(bdav_env%W_block_mat,fm_struct_tmp,name="W_dav",error=error)
    CALL cp_fm_struct_release(fm_struct_tmp,error=error)

    ALLOCATE(bdav_env%evals(nmox2),STAT=stat)
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)

    CALL cp_fm_struct_create(fm_struct_tmp, nrow_global=nao, ncol_global=nmo,&
                             para_env=mo_coeff%matrix_struct%para_env, &
                             context=mo_coeff%matrix_struct%context,error=error)
    CALL cp_fm_create(bdav_env%matrix_z,fm_struct_tmp,name="Z_mat",error=error)
    CALL cp_fm_struct_release(fm_struct_tmp,error=error)

    CALL timestop(handle)

  END SUBROUTINE block_davidson_allocate

  SUBROUTINE block_davidson_release(bdav_env,error)

    TYPE(davidson_type), DIMENSION(:), &
      POINTER                                :: bdav_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'block_davidson_release', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ispin, nspins, stat
    LOGICAL                                  :: failure

    failure = .FALSE.

    IF(ASSOCIATED(bdav_env)) THEN

      nspins = SIZE(bdav_env)
      DO ispin = 1,nspins


        CALL cp_fm_release(bdav_env(ispin)%matrix_z,error=error)
        CALL cp_fm_release(bdav_env(ispin)%H_block_mat,error=error)
        CALL cp_fm_release(bdav_env(ispin)%S_block_mat,error=error)
        CALL cp_fm_release(bdav_env(ispin)%W_block_mat,error=error)
        CALL cp_fm_release(bdav_env(ispin)%H_block_vec,error=error)
        DEALLOCATE(bdav_env(ispin)%evals,STAT=stat)
        CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)

      END DO 
      DEALLOCATE(bdav_env,STAT=stat)
      CPPostconditionNoFail(stat==0,cp_warning_level,routineP,error)

    END IF

  END SUBROUTINE block_davidson_release

END MODULE  qs_block_davidson_types
