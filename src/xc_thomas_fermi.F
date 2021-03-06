!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Calculate the Thomas-Fermi kinetic energy functional
!> \note
!>      Order of derivatives is: LDA 0; 1; 2; 3;
!>                               LSD 0; a  b; aa bb; aaa bbb;
!> \par History
!>      JGH (26.02.2003) : OpenMP enabled
!>      fawzi (04.2004)  : adapted to the new xc interface
!> \author JGH (18.02.2002)
! *****************************************************************************
MODULE xc_thomas_fermi
  USE cp_array_r_utils,                ONLY: cp_3d_r_p_type
  USE f77_blas
  USE kinds,                           ONLY: dp
  USE timings,                         ONLY: timeset,&
                                             timestop
  USE xc_derivative_set_types,         ONLY: xc_derivative_set_type,&
                                             xc_dset_get_derivative
  USE xc_derivative_types,             ONLY: xc_derivative_get,&
                                             xc_derivative_type
  USE xc_functionals_utilities,        ONLY: set_util
  USE xc_rho_cflags_types,             ONLY: xc_rho_cflags_type
  USE xc_rho_set_types,                ONLY: xc_rho_set_get,&
                                             xc_rho_set_type
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

! *** Global parameters ***

  REAL(KIND=dp), PARAMETER :: pi = 3.14159265358979323846264338_dp
  REAL(KIND=dp), PARAMETER :: f13 = 1.0_dp/3.0_dp, &
                          f23 = 2.0_dp*f13, &
                          f43 = 4.0_dp*f13, &
                          f53 = 5.0_dp*f13

  PUBLIC :: thomas_fermi_info, thomas_fermi_lda_eval, thomas_fermi_lsd_eval

  REAL(KIND=dp) :: cf, flda, flsd
  REAL(KIND=dp) :: eps_rho

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'xc_thomas_fermi'

CONTAINS

! *****************************************************************************
  SUBROUTINE thomas_fermi_init ( cutoff )

    REAL(KIND=dp), INTENT(IN)                :: cutoff

    eps_rho = cutoff
    CALL set_util ( cutoff )

    cf = 0.3_dp*(3.0_dp*pi*pi)**f23
    flda = cf
    flsd = flda * 2.0_dp**f23

  END SUBROUTINE thomas_fermi_init

! *****************************************************************************
  SUBROUTINE thomas_fermi_info ( lsd, reference, shortform, needs, max_deriv, error)
    LOGICAL, INTENT(in)                      :: lsd
    CHARACTER(LEN=*), INTENT(OUT), OPTIONAL  :: reference, shortform
    TYPE(xc_rho_cflags_type), &
      INTENT(inout), OPTIONAL                :: needs
    INTEGER, INTENT(out), OPTIONAL           :: max_deriv
    TYPE(cp_error_type), INTENT(inout)       :: error

    IF ( PRESENT ( reference ) ) THEN
      reference = "Thomas-Fermi kinetic energy functional: see Parr and Yang"
       IF (.not.lsd) THEN
          IF (LEN_TRIM(reference)+6<LEN(reference)) THEN
             reference(LEN_TRIM(reference):LEN_TRIM(reference)+6)=' {LDA}'
          END IF
       END IF
    END IF
    IF ( PRESENT ( shortform ) ) THEN
      shortform = "Thomas-Fermi kinetic energy functional"
       IF (.not.lsd) THEN
          IF (LEN_TRIM(shortform)+6<LEN(shortform)) THEN
             shortform(LEN_TRIM(shortform):LEN_TRIM(shortform)+6)=' {LDA}'
          END IF
       END IF
    END IF
    IF (PRESENT(needs)) THEN
       IF (lsd) THEN
          needs%rho_spin=.TRUE.
          needs%rho_spin_1_3=.TRUE.
       ELSE
          needs%rho=.TRUE.
          needs%rho_1_3=.TRUE.
       END IF
    END IF
    IF (PRESENT(max_deriv)) max_deriv=3

  END SUBROUTINE thomas_fermi_info

! *****************************************************************************
  SUBROUTINE thomas_fermi_lda_eval(rho_set,deriv_set,order,error)
    TYPE(xc_rho_set_type), POINTER           :: rho_set
    TYPE(xc_derivative_set_type), POINTER    :: deriv_set
    INTEGER, INTENT(in)                      :: order
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'thomas_fermi_lda_eval', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, npoints
    INTEGER, DIMENSION(:, :), POINTER        :: bo
    LOGICAL                                  :: failure
    REAL(KIND=dp)                            :: epsilon_rho
    REAL(KIND=dp), DIMENSION(:, :, :), &
      POINTER                                :: e_0, e_rho, e_rho_rho, &
                                                e_rho_rho_rho, r13, rho
    TYPE(xc_derivative_type), POINTER        :: deriv

    CALL timeset(routineN,handle)
    failure=.FALSE.
    NULLIFY(bo)

    CPPrecondition(ASSOCIATED(rho_set),cp_failure_level,routineP,error,failure)
    CPPrecondition(rho_set%ref_count>0,cp_failure_level,routineP,error,failure)
    CPPrecondition(ASSOCIATED(deriv_set),cp_failure_level,routineP,error,failure)
    CPPrecondition(deriv_set%ref_count>0,cp_failure_level,routineP,error,failure)
    IF (.NOT. failure) THEN
       CALL xc_rho_set_get(rho_set,rho_1_3=r13,rho=rho,&
            local_bounds=bo,rho_cutoff=epsilon_rho,&
            error=error)
       npoints=(bo(2,1)-bo(1,1)+1)*(bo(2,2)-bo(1,2)+1)*(bo(2,3)-bo(1,3)+1)
       CALL thomas_fermi_init(epsilon_rho)

       IF ( order>=0 ) THEN
          deriv => xc_dset_get_derivative(deriv_set,"",&
               allocate_deriv=.TRUE., error=error)
          CALL xc_derivative_get(deriv,deriv_data=e_0,error=error)
          
          CALL thomas_fermi_lda_0 ( rho, r13, e_0,npoints,error )
       END IF
       IF ( order>=1.OR.order==-1 ) THEN
          deriv => xc_dset_get_derivative(deriv_set,"(rho)",&
               allocate_deriv=.TRUE.,error=error)
          CALL xc_derivative_get(deriv,deriv_data=e_rho,error=error)

          CALL thomas_fermi_lda_1 ( rho, r13, e_rho, npoints, error )
       END IF
       IF ( order>=2.OR.order==-2 ) THEN
          deriv => xc_dset_get_derivative(deriv_set,"(rho)(rho)",&
               allocate_deriv=.TRUE.,error=error)
          CALL xc_derivative_get(deriv,deriv_data=e_rho_rho,error=error)

          CALL thomas_fermi_lda_2 ( rho, r13, e_rho_rho, npoints, error )
       END IF
       IF ( order>=3.OR.order==-3 ) THEN
          deriv => xc_dset_get_derivative(deriv_set,"(rho)(rho)(rho)",&
               allocate_deriv=.TRUE.,error=error)
          CALL xc_derivative_get(deriv,deriv_data=e_rho_rho_rho,error=error)

          CALL thomas_fermi_lda_3 ( rho, r13, e_rho_rho_rho, npoints,&
               error)
       END IF
       IF ( order>3.OR.order<-3) THEN
          CALL cp_unimplemented_error(fromWhere=routineP, &
               message="derivatives bigger than 3 not implemented", &
               error=error, error_level=cp_failure_level)
       END IF
    END IF
    CALL timestop(handle)
  END SUBROUTINE thomas_fermi_lda_eval

! *****************************************************************************
  SUBROUTINE thomas_fermi_lsd_eval(rho_set,deriv_set,order,error)
    TYPE(xc_rho_set_type), POINTER           :: rho_set
    TYPE(xc_derivative_set_type), POINTER    :: deriv_set
    INTEGER, INTENT(in)                      :: order
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'thomas_fermi_lsd_eval', &
      routineP = moduleN//':'//routineN

    CHARACTER(len=6), DIMENSION(2) :: rho_spin_name = (/"(rhoa)","(rhob)"/)
    INTEGER                                  :: handle, i, ispin, npoints
    INTEGER, DIMENSION(:, :), POINTER        :: bo
    LOGICAL                                  :: failure
    REAL(KIND=dp)                            :: epsilon_rho
    REAL(KIND=dp), DIMENSION(:, :, :), &
      POINTER                                :: e_0, e_rho, e_rho_rho, &
                                                e_rho_rho_rho
    TYPE(cp_3d_r_p_type), DIMENSION(2)       :: rho, rho_1_3
    TYPE(xc_derivative_type), POINTER        :: deriv

    CALL timeset(routineN,handle)
    failure=.FALSE.
    NULLIFY(deriv, bo)
    DO i=1,2
       NULLIFY(rho(i)%array, rho_1_3(i)%array)
    END DO

    CPPrecondition(ASSOCIATED(rho_set),cp_failure_level,routineP,error,failure)
    CPPrecondition(rho_set%ref_count>0,cp_failure_level,routineP,error,failure)
    CPPrecondition(ASSOCIATED(deriv_set),cp_failure_level,routineP,error,failure)
    CPPrecondition(deriv_set%ref_count>0,cp_failure_level,routineP,error,failure)
    IF (.NOT. failure) THEN
 
       CALL xc_rho_set_get(rho_set,rhoa_1_3=rho_1_3(1)%array,&
            rhob_1_3=rho_1_3(2)%array,rhoa=rho(1)%array,&
            rhob=rho(2)%array,&
            rho_cutoff=epsilon_rho,&
            local_bounds=bo, error=error)
       npoints=(bo(2,1)-bo(1,1)+1)*(bo(2,2)-bo(1,2)+1)*(bo(2,3)-bo(1,3)+1)
       CALL thomas_fermi_init(epsilon_rho)

       DO ispin=1,2          
          IF ( order>=0 ) THEN
             deriv => xc_dset_get_derivative(deriv_set,"",&
                  allocate_deriv=.TRUE., error=error)
             CALL xc_derivative_get(deriv, deriv_data=e_0,error=error)

             CALL thomas_fermi_lsd_0 ( rho(ispin)%array, rho_1_3(ispin)%array,&
                  e_0, npoints, error )
          END IF
          IF ( order>=1.OR.order==-1 ) THEN
             deriv => xc_dset_get_derivative(deriv_set,rho_spin_name(ispin),&
                  allocate_deriv=.TRUE.,error=error)
             CALL xc_derivative_get(deriv,deriv_data=e_rho,error=error)

             CALL thomas_fermi_lsd_1( rho(ispin)%array, rho_1_3(ispin)%array,&
                  e_rho, npoints, error )
          END IF
          IF ( order>=2.OR.order==-2 ) THEN
             deriv => xc_dset_get_derivative(deriv_set,rho_spin_name(ispin)//&
                  rho_spin_name(ispin),allocate_deriv=.TRUE.,error=error)
             CALL xc_derivative_get(deriv,deriv_data=e_rho_rho,error=error)
             
             CALL thomas_fermi_lsd_2( rho(ispin)%array, rho_1_3(ispin)%array,&
                  e_rho_rho, npoints, error )
          END IF
          IF ( order>=3 .OR. order==-3 ) THEN
             deriv => xc_dset_get_derivative(deriv_set,rho_spin_name(ispin)//&
                  rho_spin_name(ispin)//rho_spin_name(ispin),&
                  allocate_deriv=.TRUE.,error=error)
             CALL xc_derivative_get(deriv,deriv_data=e_rho_rho_rho,error=error)

             CALL thomas_fermi_lsd_3( rho(ispin)%array, rho_1_3(ispin)%array,&
                  e_rho_rho_rho, npoints, error )
          END IF
          IF ( order>3.OR.order<-3) THEN
             CALL cp_unimplemented_error(fromWhere=routineP, &
                  message="derivatives bigger than 3 not implemented", &
                  error=error, error_level=cp_failure_level)
          END IF
       END DO
    END IF
    CALL timestop(handle)
  END SUBROUTINE thomas_fermi_lsd_eval

! *****************************************************************************
  SUBROUTINE thomas_fermi_lda_0 ( rho, r13, e_0, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rho, r13
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_0
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rho(ip) > eps_rho ) THEN

         e_0(ip) = e_0(ip) + flda*r13(ip)*r13(ip)*rho(ip)

      END IF

    END DO

  END SUBROUTINE thomas_fermi_lda_0

! *****************************************************************************
  SUBROUTINE thomas_fermi_lda_1 ( rho, r13, e_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rho, r13
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = f53 * flda

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rho(ip) > eps_rho ) THEN

         e_rho(ip) = e_rho(ip) + f * r13(ip)*r13(ip)

      END IF

    END DO

  END SUBROUTINE thomas_fermi_lda_1

! *****************************************************************************
  SUBROUTINE thomas_fermi_lda_2 ( rho, r13, e_rho_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rho, r13
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = f23 * f53 * flda

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rho(ip) > eps_rho ) THEN

         e_rho_rho(ip) = e_rho_rho(ip) + f / r13(ip)

      END IF

    END DO

  END SUBROUTINE thomas_fermi_lda_2

! *****************************************************************************
  SUBROUTINE thomas_fermi_lda_3 ( rho, r13, e_rho_rho_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rho, r13
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho_rho_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = -f13 * f23 * f53 * flda

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rho(ip) > eps_rho ) THEN

         e_rho_rho_rho(ip) = e_rho_rho_rho(ip) + f / ( r13(ip) * rho(ip) )

      END IF

    END DO

  END SUBROUTINE thomas_fermi_lda_3

! *****************************************************************************
  SUBROUTINE thomas_fermi_lsd_0 ( rhoa, r13a, e_0, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rhoa, r13a
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_0
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rhoa(ip) > eps_rho ) THEN
         e_0(ip) = e_0(ip) + flsd * r13a(ip) * r13a(ip) * rhoa(ip)
      END IF

    END DO

  END SUBROUTINE thomas_fermi_lsd_0

! *****************************************************************************
  SUBROUTINE thomas_fermi_lsd_1 ( rhoa, r13a, e_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rhoa, r13a
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = f53 * flsd

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rhoa(ip) > eps_rho ) THEN
         e_rho(ip) = e_rho(ip) + f * r13a(ip) * r13a(ip)
      END IF

    END DO

  END SUBROUTINE thomas_fermi_lsd_1

! *****************************************************************************
  SUBROUTINE thomas_fermi_lsd_2 ( rhoa, r13a, e_rho_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rhoa, r13a
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = f23 * f53 * flsd

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rhoa(ip) > eps_rho ) THEN
         e_rho_rho(ip) = e_rho_rho(ip) + f / r13a(ip)
      END IF

    END DO

  END SUBROUTINE thomas_fermi_lsd_2

! *****************************************************************************
  SUBROUTINE thomas_fermi_lsd_3 ( rhoa, r13a, e_rho_rho_rho, npoints, error )

    REAL(KIND=dp), DIMENSION(*), INTENT(IN)  :: rhoa, r13a
    REAL(KIND=dp), DIMENSION(*), &
      INTENT(INOUT)                          :: e_rho_rho_rho
    INTEGER, INTENT(in)                      :: npoints
    TYPE(cp_error_type), INTENT(inout)       :: error

    INTEGER                                  :: ip
    REAL(KIND=dp)                            :: f

    f = -f13 * f23 * f53 * flsd

!$omp parallel do private(ip)
    DO ip = 1, npoints

      IF ( rhoa(ip) > eps_rho ) THEN
         e_rho_rho_rho(ip) = e_rho_rho_rho(ip) + f / ( r13a(ip)*rhoa(ip))
      END IF

    END DO

  END SUBROUTINE thomas_fermi_lsd_3

END MODULE xc_thomas_fermi

