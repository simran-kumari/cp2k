!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Gets the next data block, single/double precision real/complex
!> \param[in,out] iterator   the iterator
!> \param[out] row           row of the data block
!> \param[out] column        column of the data block
!> \param[out] block         pointer to the data block
!> \param[out] transposed    whether the block data is transposed
!> \param[out] block_number  (optional) block number
!> \param[out] row_size      (optional) logical row size of block
!> \param[out] col_size      (optional) logical column size of block
! *****************************************************************************
  SUBROUTINE iterator_next_1d_block_s (iterator, row, column, block,&
       transposed, block_number, row_size, col_size, row_offset, col_offset)
    TYPE(dbcsr_iterator), INTENT(INOUT)      :: iterator
    INTEGER, INTENT(OUT)                     :: row, column
    REAL(kind=real_4), DIMENSION(:), POINTER :: block
    LOGICAL, INTENT(OUT)                     :: transposed
    INTEGER, INTENT(OUT), OPTIONAL           :: block_number
    INTEGER, INTENT(OUT), OPTIONAL           :: row_size, col_size,&
         row_offset, col_offset

    CHARACTER(len=*), PARAMETER :: routineN = 'iterator_next_1d_block_s', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: blk_p, bp, csize, ithread, &
                                                nze, rsize, pos
    REAL(kind=real_4), DIMENSION(:), POINTER :: rbp

!   ---------------------------------------------------------------------------
! If we're pointing to a valid block, return that block.


    IF (iterator%pos .LE. iterator%nblks&
         .AND. iterator%pos .NE. 0) THEN
       row = iterator%row
       column = iterator%col_i(iterator%pos)
       IF (iterator%transpose) CALL swap (row, column)
       blk_p = iterator%blk_p(iterator%pos)
       transposed = blk_p .LT. 0
       bp = ABS (blk_p)
       rsize = iterator%row_size
       csize = iterator%cbs(column)
       nze = rsize * csize
       IF (PRESENT (row_size)) row_size = rsize
       IF (PRESENT (col_size)) col_size = csize
       IF (PRESENT (row_offset)) row_offset = iterator%row_offset
       IF (PRESENT (col_offset)) col_offset = iterator%coff(column)
       CALL dbcsr_get_data (iterator%data_area, block,&
            lb=bp, ub=bp+nze-1)
       IF (PRESENT (block_number)) block_number = iterator%pos
       ! Move to the next non-deleted position.
       CALL iterator_advance (iterator)
       CALL update_row_info (iterator)
    ELSE
       row = 0
       column = 0
       NULLIFY (block)
       IF (PRESENT (block_number)) block_number = 0
    ENDIF
  END SUBROUTINE iterator_next_1d_block_s



! *****************************************************************************
!> \brief Gets the next data block, single/double precision real/complex
!> \param[in,out] iterator   the iterator
!> \param[out] row           row of the data block
!> \param[out] column        column of the data block
!> \param[out] block         pointer to the data block
!> \param[out] transposed    whether the block data is transposed
!> \param[out] block_number  (optional) block number
!> \param[out] row_size      (optional) logical row size of block
!> \param[out] col_size      (optional) logical column size of block
! *****************************************************************************
  SUBROUTINE iterator_next_2d_block_s (iterator, row, column,&
       block, transposed,&
       block_number, row_size, col_size, row_offset, col_offset)
    TYPE(dbcsr_iterator), INTENT(INOUT)      :: iterator
    INTEGER, INTENT(OUT)                     :: row, column
    REAL(kind=real_4), DIMENSION(:, :), &
      POINTER                                :: block
    LOGICAL, INTENT(OUT)                     :: transposed
    INTEGER, INTENT(OUT), OPTIONAL           :: block_number
    INTEGER, INTENT(OUT), OPTIONAL           :: row_size, col_size, row_offset, col_offset

    CHARACTER(len=*), PARAMETER :: routineN = 'iterator_next_2d_block_s', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: blk_p, bp, csize, ithread, &
                                                nze, rsize, pos,&
                                                block_row_size, block_col_size
    REAL(kind=real_4), DIMENSION(:), POINTER           :: lin_blk_p
    INTEGER                                  :: error_handle
    TYPE(dbcsr_error_type)                   :: error

!   ---------------------------------------------------------------------------
! If we're pointing to a valid block, return that block.

    IF (careful_mod) CALL dbcsr_error_set (routineN, error_handle, error)
    IF (iterator%pos .LE. iterator%nblks&
         .AND. iterator%pos .NE. 0) THEN
       row = iterator%row
       column = iterator%col_i(iterator%pos)
       IF (iterator%transpose) CALL swap (row, column)
       blk_p = iterator%blk_p(iterator%pos)
       transposed = blk_p .LT. 0
       bp = ABS (blk_p)
       rsize = iterator%row_size
       csize = iterator%cbs(column)
       block_row_size = rsize
       block_col_size = csize
       IF (PRESENT (row_size)) row_size = rsize
       IF (PRESENT (col_size)) col_size = csize
       IF (PRESENT (row_offset)) row_offset = iterator%row_offset
       IF (PRESENT (col_offset)) col_offset = iterator%coff(column)
       nze = rsize * csize
       IF (dbcsr_buffers_2d_needed) THEN
          CALL dbcsr_buffers_flush (iterator%buffer_2d, error=error)
          CALL resize_buffers (iterator, error=error)
          CALL dbcsr_buffers_set_pointer_2d (block, row, column,&
               block_row_size, block_col_size,&
               transposed, blk_p, iterator%buffer_2d, .FALSE., error=error)
          IF (iterator%read_only) &
               CALL dbcsr_buffers_mark_dirty (iterator%buffer_2d,&
               dirty=.FALSE., error=error)
          transposed = .FALSE.
       ELSE
          IF (transposed) CALL swap (rsize, csize)
          CALL dbcsr_get_data (iterator%data_area, lin_blk_p,&
               lb=bp, ub=bp+nze-1)
          CALL pointer_s_rank_remap2 (block, rsize, csize, lin_blk_p)
       ENDIF
       IF (PRESENT (block_number)) block_number = iterator%pos
       ! Move to the next non-deleted position.
       CALL iterator_advance (iterator)
       CALL update_row_info (iterator)
    ELSE
       row = 0
       column = 0
       NULLIFY (block)
       IF (PRESENT (block_number)) block_number = 0
    ENDIF
    IF (careful_mod) CALL dbcsr_error_stop (error_handle, error)
  END SUBROUTINE iterator_next_2d_block_s
