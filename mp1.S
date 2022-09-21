
# mp1.S - missile-command version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct missile,
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64

	#video location bounds for crosshairs and missiles
	LOWER_X_BOUND = 0
	LOWER_Y_BOUND = 0
	UPPER_X_BOUND = 79
	UPPER_Y_BOUND = 24

	#labels for calculating video memory offset 
	ROW_OFFSET = 2
	COL_OFFSET = 160
	SHIFT16 = 16

	INIT_BASE_ALIVE = 0x00010101
	INIT_X_CROSS = 40
	INIT_Y_CROSS = 12
	ARG_OFFSET = 4
	RETURN_NEG_1 = -1

	#character to draw for crosshair - '+'
	CROSSHAIR_CHAR = 43

	#space character for blank areas	
	SPACE = 32

	#bitmasks for first,second, and third bases to extract alive/dead states
	FIRST_BITMASK = 0x000000FF
	SECOND_BITMASK = 0x0000FF00
	THIRD_BITMASK = 0x00FF0000

	#size to malloc for adding a missile struct to list
	STRUCT_SIZE = 33

	#24 * 80 * 2 = 3840
	BASE_Y_OFFSET = 3840 


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
	pushl %ebp
	movl %esp, %ebp

	pushl %eax 					
	pushl %ecx 					
	pushl %edx 					
	pushl %edi					
	pushl %esi
	pushl %ebx 					
	call update_missiles			#save registers call update_missiles and restore registers
	popl %ebx
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %eax

	pushl %eax
	pushl %ebx
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	call mp1_redraw_bases			#save registers call mp1_redraw_bases and restore registers
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax

	pushl %eax
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebx
	call mp1_update_crosshairs		#save registers call mp1_update_crosshairs and restore registers
	popl %ebx
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %eax

	leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
	movl 8(%esp), %ecx			#ecx gets arg then check if <0 and if so then out of bounds
	cmpl $0, %ecx
	jl NOT_IN_BOUNDS
	cmpl $4, %ecx
	jg NOT_IN_BOUNDS			#check if ecx is > 0 and if so then out of bounds
	jmp *jump_table(,%ecx,4)
	jmp END
	NOT_IN_BOUNDS:
	movl $RETURN_NEG_1, %ecx
	END:
		ret
	
	jump_table:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------
#
# This function is responsible for processing each missile in mp1_missile_list.
# Processing steps include updating the missile position, drawing the missile, drawing explosion characters, and removing the missile
# Inputs: None
# Outputs: eax - returns 0 if status of game not changed, else >0
# Registers: ebx - holds ptr to head of mp1_missile_list,
#			 eax - holds missile bounds and video memory location to draw char to
#			 edx - holds X and Y destinations
#			 esi - decrements exploded value

update_missiles:
	pushl %ebp
	movl %esp, %ebp

	movl mp1_missile_list, %ebx
	
	#begins traversal of and processing of a missile
	TRAVERSE_LIST:
	cmpl $0, %ebx					#checks if current missile is null and if so then done and jump to END_OF_LIST
	je END_OF_LIST

	movl X(%ebx), %eax				#get row offset value into eax
	shrl $SHIFT16, %eax
	imull $ROW_OFFSET, %eax
	movl Y(%ebx), %ecx				#get col offset value into ecx
	shrl $SHIFT16, %ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax					#add to get total video memory byte offset into eax
	movb $SPACE, %cl				#replace current position with space character
	pushl %edx
	call mp1_poke
	popl %edx

	cmpl $0, EXPLODED(%ebx)
	jne EXPLODING

	UPDATE_POSITION:
	#check if updated X position will be in bounds, otherwise remove
	movl VX(%ebx), %eax
	addl X(%ebx), %eax
	shrl $SHIFT16, %eax
	cmpl $LOWER_X_BOUND, %eax
	jl REMOVE_MISSILE
	cmpl $UPPER_X_BOUND, %eax
	jg REMOVE_MISSILE 

	#check if updated Y position will be in bounds, otherwise remove
	movl VY(%ebx), %eax
	addl Y(%ebx), %eax
	shrl $SHIFT16, %eax
	cmpl $LOWER_Y_BOUND, %eax
	jl REMOVE_MISSILE
	cmpl $UPPER_Y_BOUND, %eax
	jg REMOVE_MISSILE

	#update X and Y positions since they will be in bounds
	movl VX(%ebx), %eax
	addl %eax, X(%ebx)
	movl VY(%ebx), %eax
	addl %eax, Y(%ebx)

	#check if X destination is reached. If so, check if Y destination reached, otherwise draw a missile
	CHECK_X_DEST:
	movl X(%ebx), %eax
	shrl $SHIFT16, %eax
	movl DEST_X(%ebx), %edx
	cmpl %eax, %edx
	jne DRAW_MISSILE

	#check if Y destination reached. If so, draw explosion, otherwise draw a missile
	CHECK_Y_DEST:
	movl Y(%ebx), %eax
	shrl $SHIFT16, %eax
	movl DEST_Y(%ebx), %edx
	cmpl %eax, %edx
	je EXPLODING

	#missile not exploding nor reached destination so draw a missile
	DRAW_MISSILE:
	movl X(%ebx), %eax			#get row offset value into eax
	shrl $SHIFT16, %eax
	imull $ROW_OFFSET, %eax
	movl Y(%ebx), %ecx			#get col offset value into ecx
	shrl $SHIFT16, %ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax				#add to get total video memory byte offset into eax
	movb C(%ebx), %cl			#replace current position with missile character
	pushl %edx
	call mp1_poke
	popl %edx

	#done with processing a missile so go to next missile and restart list traversal checks
	NEXT_MISSILE:
	movl NEXT(%ebx), %ebx
	jmp TRAVERSE_LIST

	#missile is exploding so draw explosion character and call missile_explode
	EXPLODING:
	movl X(%ebx), %eax				#get row offset value into eax
	shrl $SHIFT16, %eax
	imull $ROW_OFFSET, %eax
	movl Y(%ebx), %ecx				#get col offset value into ecx
	shrl $SHIFT16, %ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax					#add to get total video memory byte offset into eax
	movb $EXPLOSION, %cl			#replace current position with space character
	pushl %edx
	call mp1_poke
	popl %edx
	pushl %ebx
	call missile_explode
	popl %ebx

	#check the return value from missile_explode to see if game status has changed 
	CHECK_STATUS:
	cmpl $0, %eax
	je DEC_EXPLODE

	#missile is exploding so we need to decrement the explosion variable for current missile and check if done exploding, otherwise go to next missile
	DEC_EXPLODE:
	movl EXPLODED(%ebx), %esi
	decl %esi
	movl %esi, EXPLODED(%ebx)
	cmpl $0, EXPLODED(%ebx)
	je DONE_EXPLODING
	jmp NEXT_MISSILE

	DONE_EXPLODING:
	movl X(%ebx), %eax			#get row offset value into eax
	shrl $SHIFT16, %eax
	imull $ROW_OFFSET, %eax
	movl Y(%ebx), %ecx			#get col offset value into ecx
	shrl $SHIFT16, %ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax				#add to get total video memory byte offset into eax
	movb $SPACE, %cl			#replace current position with space character
	pushl %edx
	call mp1_poke
	popl %edx

	#subroutine to call missile remove function 
	REMOVE_MISSILE:

	pushl %eax					#callee-save registers before removing missile from linked list
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebx
	call mp1_missile_remove
	popl %ebx
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %eax


	END_OF_LIST:
	leave
	ret

# Function header: int mp1 ioctl startgame (unsigned long ignore)
# This function starts the game and initializes all needed variables
# Inputs: unsigned long ignore - meaningless and should be ignored
# Outputs: None
# Registers: None

mp1_ioctl_startgame:
	movl $0x00, mp1_score
	movl $0x00, mp1_missile_list
	movl $INIT_BASE_ALIVE, base_alive		#set base_alive with 3 bytes of alive
	movl $INIT_X_CROSS, crosshairs_x		#set x crosshair coordinate to 40
	movl $INIT_Y_CROSS, crosshairs_y		#set y crosshair coordinate to 12

		ret

# Function header: int mp1 ioctl addmissile (struct missile* user missile);
# This function adds a new missile to the game and updates the linked list accordingly 
# Inputs: struct missile* user missile - missile to be added to the game 
# Outputs: returns -1 for if add missile's memory allocations fails or 0 if success
# Registers: eax- holds return value for if copy failed(-1) or succeeded(0)

mp1_ioctl_addmissile:
	pushl %ebp								#push base pointer and move stack pointer
	movl %esp, %ebp
	pushl %ebx								#save missile ptr
	movl 8(%ebp), %edi						#edi contains the pointer to the missile struct

	pushl $STRUCT_SIZE						#malloc size of the missile struct (33)
	call mp1_malloc							#update esp to account for malloc
	addl $4, %esp							
	movl %eax, %ebx
	cmpl $0, %ebx
	je FAILED

	pushl $STRUCT_SIZE
	pushl %edi
	pushl %ebx
	call mp1_copy_from_user
	addl $12, %esp							#update stack ptr to account for 3 arguments pushed onto stack from mp1_copy_from_user
	cmpl $0, %eax
	jne FAILED

	movl mp1_missile_list, %eax				#update linked list with new missile
	movl %eax, NEXT(%ebx)
	movl %ebx, mp1_missile_list

	movl $0, %eax
	jmp DONE_ADDING

	FAILED:									#malloc failed so free the memory and return -1 into eax
	pushl %eax
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebx
	call mp1_free
	popl %ebx
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %eax
	movl $RETURN_NEG_1, %eax
	addl $4, %esp

	DONE_ADDING:
	popl %ebx
	leave
		ret

# int mp1 ioctl movexhairs (unsigned long xhair delta packed);
# This function adds a new missile to the game and updates the linked list accordingly 
# Inputs: unsigned long xhair delta packed - 32-bit integer containing two signed 16-bit integers packed into its low and high words.
# 											 low 16 bits represent x displacement to move crosshair
#											 high 16 bits represent y displacement to move crosshair
# Outputs: returns 0 - represents success that crosshair is within bounds at all times
# Registers: eax- holds return value(0)

mp1_ioctl_movexhairs:
	#replace old crosshair position with a space
	movl crosshairs_x, %eax			#get row offset value into eax
	imull $ROW_OFFSET, %eax
	movl crosshairs_y, %ecx			#get col offset value into ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax					#add to get total video memory byte offset into eax
	movb $SPACE, %cl				#replace current position with null character
	pushl %edx
	call mp1_poke
	popl %edx

	#process location argument
	movl ARG_OFFSET(%esp), %eax		#get arg value from stack
	shll $SHIFT16, %eax				#logical shift left to get low 16 bits into upper 16, fill lower 16 with 0s
	sarl $SHIFT16, %eax				#arithmetic shift right the high bits to get into low, sign extend to the left
	movl ARG_OFFSET(%esp), %ecx
	sarl $SHIFT16, %ecx

	#update X and Y crosshair positions
	addl %eax, crosshairs_x			
	addl %ecx, crosshairs_y			

	#keeps X crosshair between the bounds of 0-79 inclusive and Y crosshair between the bounds of 0-24 inclusive
	CHECK_CROSSHAIR_BOUNDS:
	cmpl $LOWER_X_BOUND, crosshairs_x
	jl MIN_X_BOUNDS
	cmpl $UPPER_X_BOUND, crosshairs_x
	jg MAX_X_BOUNDS
	cmpl $LOWER_Y_BOUND, crosshairs_y
	jl MIN_Y_BOUNDS
	cmpl $UPPER_Y_BOUND, crosshairs_y
	jg MAX_Y_BOUNDS

	jmp WITHIN_BOUNDS

	MIN_X_BOUNDS:
	movl $LOWER_X_BOUND, crosshairs_x
	jmp CHECK_CROSSHAIR_BOUNDS

	MAX_X_BOUNDS:
	movl $UPPER_X_BOUND, crosshairs_x
	jmp CHECK_CROSSHAIR_BOUNDS

	MIN_Y_BOUNDS:
	movl $LOWER_Y_BOUND, crosshairs_y
	jmp CHECK_CROSSHAIR_BOUNDS

	MAX_Y_BOUNDS:
	movl $UPPER_Y_BOUND, crosshairs_y
	jmp CHECK_CROSSHAIR_BOUNDS

	#after setting crosshairs to be within bounds, update crosshair to new position
	WITHIN_BOUNDS:
	movl crosshairs_x, %eax		#get row offset value into eax
	imull $ROW_OFFSET, %eax
	movl crosshairs_y, %ecx		#get col offset value into ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax				#add to get total video memory byte offset into eax

	movb $CROSSHAIR_CHAR, %cl	#replace current position with null character
	pushl %edx
	call mp1_poke
	popl %edx
	movl $0, %eax				#crosshair is within bounds so return 0
		ret

mp1_ioctl_getstatus:
		ret

# int mp1 ioctl endgame (unsigned long ignore);
# This function frees the whole linked list and ends the game
# Inputs: unsigned long ignore - The parameter passed in arg is meaningless and should be ignored
# Outputs: None
# Registers: ecx - holds tmp ptr to missile_list
mp1_ioctl_endgame:
	pushl %ebp
	movl %esp, %ebp
	movl mp1_missile_list, %ecx			#ecx contains the head ptr to missile list

	END_GAME_LOOP:
	cmpl $0, %ecx						#check if the list is empty and if so jump to done
	je GAME_DONE
	movl NEXT(%ecx), %ecx
	pushl %eax							#save all registers before freeing missile
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %ebx
	pushl mp1_missile_list
	call mp1_free						#delete head missile
	popl mp1_missile_list
	popl %ebx
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %eax
	movl %ecx, mp1_missile_list 		#head now points to next missile in the list
	cmpl $0, mp1_missile_list
	jne END_GAME_LOOP

	GAME_DONE:
		leave
		ret

# This function draws a dead or alive base for each of the three bases based on the status of the base.
# Each base uses a bitmask in order to extract the dead/alive status
# Inputs: None
# Outputs: None
# Registers: edx - holds alive or dead base pic , eax - holds video memory offset to draw char to, edi - holds bounds to draw bases
mp1_redraw_bases:
	pushl %ebp
	movl %esp, %ebp
	
	#checking first base to see if dead or alive then jump to PRINT_FIRST with dead or alive pic
	FIRST:
	movl $FIRST_BITMASK, %esi			#bit mask to get first byte for base 1
	andl base_alive, %esi
	leal base_pic, %edx
	movl $18, %edi						#edi holds bounds 18-22 for x coordinates of first base
	cmpl $0, %esi
	jg PRINT_FIRST
	leal dead_base_pic, %edx

	#print all characters for the first base
	PRINT_FIRST:
	movl %edi, %eax
	imull $2, %eax
	addl $BASE_Y_OFFSET, %eax			#eax holds video memory offset 24 * 160 = 3840
	movb (%edx), %cl
	pushl %edx
	call mp1_poke
	popl %edx
	incl %edi
	incl %edx
	cmpl $23, %edi
	jl PRINT_FIRST

	#checking second base to see if dead or alive then jump to PRINT_SECOND with dead or alive pic
	SECOND:
	movl $SECOND_BITMASK, %esi			#bit mask to get second byte for base 2
	andl base_alive, %esi
	leal base_pic, %edx
	movl $38, %edi						#edi holds bounds 38-42 for x coorinates of second base
	cmpl $0, %esi
	jg PRINT_SECOND
	leal dead_base_pic, %edx

	#print all characters for the second base
	PRINT_SECOND:
	movl %edi, %eax
	imull $2, %eax
	addl $BASE_Y_OFFSET, %eax
	movb (%edx), %cl
	pushl %edx
	call mp1_poke
	popl %edx
	incl %edi
	incl %edx
	cmpl $43, %edi
	jl PRINT_SECOND

	#checking third base to see if dead or alive then jump to PRINT_THIRD with dead or alive pic
	THIRD:
	movl $THIRD_BITMASK, %esi			#bit mask to get third byte for base 3
	andl base_alive, %esi
	leal base_pic, %edx
	movl $58, %edi
	cmpl $0, %esi
	jg PRINT_THIRD
	leal dead_base_pic, %edx

	#print all characters for the third base
	PRINT_THIRD:
	movl %edi, %eax
	imull $2, %eax
	addl $BASE_Y_OFFSET, %eax
	movb (%edx), %cl
	pushl %edx
	call mp1_poke
	popl %edx
	incl %edi
	incl %edx
	cmpl $63, %edi
	jl PRINT_THIRD

	leave
	ret

# This function is reponsible for updating the crosshair with the crosshair character at new position
# Inputs: None
# Outputs: None
# Registers: eax - holds video memory offset to draw character at
mp1_update_crosshairs:
	pushl %ebp								#save base pointer and update stack pointer
	movl %esp, %ebp

	movl crosshairs_x, %eax					#get row offset value into eax
	imull $ROW_OFFSET, %eax
	movl crosshairs_y, %ecx					#get col offset value into ecx
	imull $COL_OFFSET, %ecx
	addl %ecx, %eax							#add to get total video memory byte offset into eax
	pushl %eax
	movb $CROSSHAIR_CHAR, %cl				#update crosshair with "+" character
	pushl %edx
	call mp1_poke
	popl %edx


	leave
		ret
		
# mp1_missile_remove(struct missile* user_missile)
# The purpose of this function is to remove a missile from the linked list and free the memory
# Inputs: user_missile - holds the missile to remove 
# Outputs: None
# Registers: ebx - holds the missile to remove 
mp1_missile_remove:
	pushl %ebp								# save base pointer and stack pointer
	movl %esp, %ebp

	movl mp1_missile_list, %eax
	cmpl %eax, %ebx							# check if head is the ptr to remove
	je REMOVE_HEAD

	FIND_MISSILE:
	cmpl $0, %eax
	je END_OF_LIST
	movl NEXT(%eax), %edi					#edi holds next missile
	cmpl %edi, %ebx							#check if edi is the missile to remove and remove it
	je REMOVE
	movl %edi, %eax							#eax holds current missile in the list
	jmp FIND_MISSILE

	REMOVE:
	movl NEXT(%edi), %ebx					#ebx now points to the missile after the one that we need to remove
	movl %ebx, NEXT(%eax)
	pushl %eax								#save registers
	pushl %ecx
	pushl %edx
	pushl %esi
	pushl %ebx
	pushl %edi
	call mp1_free
	popl %edi
	popl %ebx
	popl %esi								# restore registers
	popl %edx
	popl %ecx
	popl %eax
	jmp DONE


	REMOVE_HEAD:
	movl NEXT(%ebx), %edi					#edi holds head->next
	movl %edi, mp1_missile_list 			#head is now set to head->next
	movl mp1_missile_list, %ebx				#update ebx with pointer to start of new list

	pushl %ebx								#save registers
	pushl %ecx
	pushl %edx
	pushl %edi
	pushl %esi
	pushl %eax
	call mp1_free
	popl %eax								# restore registers
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %ebx

	DONE:
	leave
		ret

	
