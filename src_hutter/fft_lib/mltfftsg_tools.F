!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
MODULE mltfftsg_tools

#if defined(__SGL) || defined(__FFTSGL)
  INTEGER, PARAMETER :: dbl = KIND(0.0)
#else
  INTEGER, PARAMETER :: dbl = SELECTED_REAL_KIND ( 14, 200 )
#endif

  PRIVATE
  PUBLIC :: matmov, zgetmo, get_cache_size, scaled

CONTAINS
  
! *****************************************************************************
  SUBROUTINE matmov ( n, m, a, lda, b, ldb )
    INTEGER                                  :: n, m, lda
    COMPLEX(dbl)                             :: a( lda, * )
    INTEGER                                  :: ldb
    COMPLEX(dbl)                             :: b( ldb, * )

    b ( 1:n , 1:m ) = a ( 1:n, 1:m )
  END SUBROUTINE matmov
  
! *****************************************************************************
  SUBROUTINE zgetmo ( a, lda, m, n, b, ldb )
    INTEGER                                  :: lda, m, n
    COMPLEX(dbl)                             :: a( lda, n )
    INTEGER                                  :: ldb
    COMPLEX(dbl)                             :: b( ldb, m )

    b ( 1:n, 1:m ) = TRANSPOSE ( a ( 1:m, 1:n ) )
  END SUBROUTINE zgetmo
  
! *****************************************************************************
  SUBROUTINE scaled ( n, sc, a )
    IMPLICIT NONE
    INTEGER  :: n
    COMPLEX(dbl) :: a ( n )
    REAL(dbl) :: sc

#if defined(__SGL) || defined(__FFTSGL)
    CALL sscal(n,sc,a,1)
#else
    CALL dscal(n,sc,a,1)
#endif

  END SUBROUTINE scaled
  
! *****************************************************************************
  FUNCTION get_cache_size ( )

    IMPLICIT NONE
    INTEGER :: get_cache_size

#if defined ( __T3E )
    get_cache_size = 1024*8
#elif defined ( __SX5 ) || defined ( __T90 )
    get_cache_size = 1024*128
#elif defined ( __ALPHA )
    get_cache_size = 1024*8
#elif defined ( __SGI )
    get_cache_size = 1024*4
#elif defined ( __POWER2 )
    get_cache_size = 1024*10
#elif defined ( __HP )
    get_cache_size = 1024*64
#else
    get_cache_size = 1024*2
#endif
    
  END FUNCTION get_cache_size

END MODULE mltfftsg_tools
