MODULE COMMON_VARS
  USE SCIFOR, only:str
  implicit none
  private

  !COMMON VARIABLES
  integer,public :: Ns
  integer,public :: Nimp
  integer,public :: Nbath


  !SPARSE IMP-BATH MAP AS AN OBJECT
  type sparse_row
     integer                               :: size
     integer                               :: bath_state_min
     integer                               :: bath_state_max
     integer,dimension(:),allocatable      :: bath_state
     integer,dimension(:),allocatable      :: sector_indx
  end type sparse_row

  type sparse_map
     type(sparse_row),dimension(:),pointer :: imp_state
     integer                               :: Nimp_state
     logical                               :: status=.false.
  end type sparse_map
  public :: sparse_map
  public :: sp_init_map
  public :: sp_delete_map
  public :: sp_insert_state
  public :: sp_return_intersection
  public :: sp_print_map




  !SECTOR->FOCK MAP (contains normal and imp-bath sparse maps)
  type sector_map
     integer,dimension(:),allocatable :: map
     type(sparse_map)                 :: sp
  end type sector_map
  public :: sector_map


  !Allocate/Deallocate Sector map:
  interface map_allocate
     module procedure :: map_allocate_scalar
     module procedure :: map_allocate_vector
  end interface map_allocate
  public :: map_allocate

  interface map_deallocate
     module procedure :: map_deallocate_scalar
     module procedure :: map_deallocate_vector
  end interface map_deallocate
  public :: map_deallocate




  !AUX:
  interface add_to
     module procedure :: add_to_I
     module procedure :: add_to_D
     module procedure :: add_to_Z
  end interface add_to




contains

  subroutine map_allocate_scalar(H,N,Nsp)
    type(sector_map) :: H
    integer          :: N
    integer,optional :: Nsp
    allocate(H%map(N))
    if(present(Nsp))call sp_init_map(H%sp,Nsp)
  end subroutine map_allocate_scalar
  !
  subroutine map_allocate_vector(H,N,Nsp)
    type(sector_map),dimension(:)       :: H
    integer,dimension(size(H))          :: N
    integer,optional,dimension(size(H)) :: Nsp
    integer                             :: i
    do i=1,size(H)
       if(present(Nsp))then
          call map_allocate_scalar(H(i),N(i),Nsp(i))
       else
          call map_allocate_scalar(H(i),N(i))
       endif
    enddo
  end subroutine map_allocate_vector


  subroutine map_deallocate_scalar(H)
    type(sector_map) :: H
    if(allocated(H%map))deallocate(H%map)
    call sp_delete_map(H%sp)
  end subroutine map_deallocate_scalar
  !
  subroutine map_deallocate_vector(H)
    type(sector_map),dimension(:)       :: H
    integer                             :: i
    do i=1,size(H)
       call map_deallocate_scalar(H(i))
    enddo
  end subroutine map_deallocate_vector







  !+------------------------------------------------------------------+
  !PURPOSE:  initialize the sparse matrix list
  !+------------------------------------------------------------------+
  subroutine sp_init_map(sparse,Nstates)
    type(sparse_map),intent(inout) :: sparse
    integer                        :: Nstates
    integer                        :: i
    !
    if(sparse%status)stop "sp_init_map: already allocated can not init"
    !
    sparse%Nimp_state=Nstates
    !
    allocate(sparse%imp_state(0:Nstates-1))
    do i=0,Nstates-1
       sparse%imp_state(i)%size=0
       sparse%imp_state(i)%bath_state_min=huge(1)
       sparse%imp_state(i)%bath_state_max=0
       allocate(sparse%imp_state(i)%bath_state(0))
       allocate(sparse%imp_state(i)%sector_indx(0))
    end do
    !
    sparse%status=.true.
    !
  end subroutine sp_init_map






  !+------------------------------------------------------------------+
  !PURPOSE: delete an entire sparse matrix
  !+------------------------------------------------------------------+
  subroutine sp_delete_map(sparse)    
    type(sparse_map),intent(inout) :: sparse
    integer                        :: i
    !
    if(.not.sparse%status)return
    !
    do i=0,sparse%Nimp_state-1
       deallocate(sparse%imp_state(i)%bath_state)
       deallocate(sparse%imp_state(i)%sector_indx)
       sparse%imp_state(i)%Size  = 0
    enddo
    deallocate(sparse%imp_state)
    !
    sparse%Nimp_state=0
    sparse%status=.false.
  end subroutine sp_delete_map







  !+------------------------------------------------------------------+
  !PURPOSE: insert an element value at position (i,j) in the sparse matrix
  !+------------------------------------------------------------------+
  subroutine sp_insert_state(sparse,imp_state,bath_state,sector_indx)
    type(sparse_map),intent(inout) :: sparse
    integer,intent(in)             :: imp_state
    integer,intent(in)             :: bath_state
    integer,intent(in)             :: sector_indx
    type(sparse_row),pointer       :: row
    integer                        :: column,pos
    !
    if(imp_state < 0) stop "sp_insert_state error: imp_state < 0 "
    if(imp_state > sparse%Nimp_state-1) stop "sp_insert_state error: imp_state > map%Nimp_state 2^Nimp-1"
    row => sparse%imp_state(imp_state)
    if(any(row%bath_state == bath_state))stop "sp_insert_state error: bath_state already present for this imp_state"
    !    
    call add_to(row%bath_state,bath_state)
    call add_to(row%sector_indx,sector_indx)
    if(bath_state < row%bath_state_min)row%bath_state_min=bath_state
    if(bath_state > row%bath_state_max)row%bath_state_max=bath_state
    row%Size = row%Size + 1
    !
  end subroutine sp_insert_state



  subroutine sp_return_intersection(sparse,Iimp,Jimp,array,Narray)
    type(sparse_map)                              :: sparse
    integer,intent(in)                            :: Iimp,Jimp
    integer,intent(out),dimension(:),allocatable  :: array
    type(sparse_row),pointer                      :: rowI,rowJ
    integer                                       :: i
    integer,intent(out)                           :: Narray
    !
    if(allocated(array))deallocate(array)    
    if((Iimp<0) .OR. (Jimp<0)) stop "sp_return_intersection error: Iimp OR Jimp < 0 "
    if( (Iimp>sparse%Nimp_state-1).OR. (Jimp>sparse%Nimp_state-1)) &
         stop "sp_return_intersection error: Iimp OR Jimp > 2^Nimp-1"
    rowI => sparse%imp_state(Iimp)
    rowJ => sparse%imp_state(Jimp)
    Narray=0
    if(rowI%size < rowJ%size)then    
       do i = 1,rowI%size
          if( any(rowJ%bath_state == rowI%bath_state(i)) )then
             call add_to(array,rowI%bath_state(i))
             Narray=Narray+1
          endif
       enddo
    else
       do i = 1,rowJ%size
          if( any(rowI%bath_state == rowJ%bath_state(i)) )then
             call add_to(array,rowJ%bath_state(i))
             Narray=Narray+1
          endif
       enddo
    endif
    !
  end subroutine sp_return_intersection



  subroutine sp_print_imp_state(sparse,imp_state)
    type(sparse_map),intent(inout) :: sparse
    integer,intent(in)             :: imp_state
    type(sparse_row),pointer       :: row
    integer                        :: i
    !
    if(imp_state < 0) stop "sp_insert_state error: imp_state < 0 "
    if(imp_state > sparse%Nimp_state-1) stop "sp_insert_state error: imp_state > map%Nimp_state 2^Nimp-1"
    row => sparse%imp_state(imp_state)
    write(*,"(A10,I5)")"Imp State:",imp_state
    write(*,"(A10,I5)")"     size:",row%size
    write(*,"(A10,2I5)")"  min,max:",row%bath_state_min,row%bath_state_max
    write(*,"(A10,"//str(row%size)//"I5)")"bath state",(row%bath_state(i),i=1,row%size)
    write(*,"(A10,"//str(row%size)//"I5)")"sect indxs",(row%sector_indx(i),i=1,row%size)
    write(*,"(A1)")""
    write(*,"(A1)")""
    !
  end subroutine sp_print_imp_state


  subroutine sp_print_map(sparse)
    type(sparse_map),intent(inout) :: sparse
    integer                        :: i
    !
    do i=0,sparse%Nimp_state-1
       call sp_print_imp_state(sparse,i)
    enddo
    !
  end subroutine sp_print_map











  !##################################################################
  !##################################################################
  !              AUXILIARY COMPUTATIONAL ROUTINES
  !##################################################################
  !##################################################################
  subroutine add_to_I(vec,val)
    integer,dimension(:),allocatable,intent(inout) :: vec
    integer,intent(in)                             :: val  
    integer,dimension(:),allocatable               :: tmp
    integer                                        :: n
    !
    if (allocated(vec)) then
       n = size(vec)
       allocate(tmp(n+1))
       tmp(:n) = vec
       call move_alloc(tmp,vec)
       n = n + 1
    else
       n = 1
       allocate(vec(n))
    end if
    !
    !Put val as last entry:
    vec(n) = val
    !
    if(allocated(tmp))deallocate(tmp)
  end subroutine add_to_I

  subroutine add_to_D(vec,val)
    real(8),dimension(:),allocatable,intent(inout) :: vec
    real(8),intent(in)                             :: val  
    real(8),dimension(:),allocatable               :: tmp
    integer                                        :: n
    !
    if (allocated(vec)) then
       n = size(vec)
       allocate(tmp(n+1))
       tmp(:n) = vec
       call move_alloc(tmp,vec)
       n = n + 1
    else
       n = 1
       allocate(vec(n))
    end if
    !
    !Put val as last entry:
    vec(n) = val
    !
    if(allocated(tmp))deallocate(tmp)
  end subroutine add_to_D

  subroutine add_to_Z(vec,val)
    complex(8),dimension(:),allocatable,intent(inout) :: vec
    complex(8),intent(in)                             :: val  
    complex(8),dimension(:),allocatable               :: tmp
    integer                                           :: n
    !
    if (allocated(vec)) then
       n = size(vec)
       allocate(tmp(n+1))
       tmp(:n) = vec
       call move_alloc(tmp,vec)
       n = n + 1
    else
       n = 1
       allocate(vec(n))
    end if
    !
    !Put val as last entry:
    vec(n) = val
    !
    if(allocated(tmp))deallocate(tmp)
  end subroutine add_to_Z





END MODULE COMMON_VARS

