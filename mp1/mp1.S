
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
ioctl_status:		.long 0x0	# for mp1_ioctl_getstatus

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
#make %edx a callee saved function
mp1_poke:
		pushl	%edx
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		popl	%edx
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
		#first save old base pointer and get new one
		pushl	%ebp
		movl	%esp, %ebp
		
		#save callee saved registers
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		movl	$0, %esi
		#use %ecx to point to each missile
		movl	mp1_missile_list, %ecx
		#update_list completes the first task
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		call	update_missiles
		movl	%eax, %esi
		call	redraw_cities
		call	redraw_crosshairs
		popl	%edx
		popl	%ecx
		popl	%eax
		cmpl	$0, %esi
		je		tasklet_end
		#otherwise call mp1_notify_user
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$0x08049585
		call	mp1_notify_user
		popl	%edx
		popl	%edx
		popl	%ecx
		popl	%eax
tasklet_end:
		#retrieve data for callee saved register
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

#second big subfunction
#this function redraws the three bases, handling both they are alive or dead
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
redraw_cities:
		#use %ecx to hold the left corner of the city to be drawn
		#draw the leftmost one
		movl	$18, %ecx
		#use %edx to status of each base
		movl	base_alive, %edx
		#get the last byte
		andl	$0x000000ff, %edx
		cmpl	$0, %edx
		je		draw_first_destroyed_city
		call	draw_city
		jmp		draw_second_city
draw_first_destroyed_city:
		call	draw_destroyed_city
draw_second_city:
		movl	$38, %ecx
		movl	base_alive, %edx
		#get the third byte
		andl	$0x0000ff00, %edx
		cmpl	$0, %edx
		je		draw_second_destroyed_city
		call	draw_city
		jmp		draw_third_city
draw_second_destroyed_city:
		call	draw_destroyed_city
draw_third_city:
		movl	$58, %ecx
		movl	base_alive, %edx
		#get the second byte
		andl	$0x00ff0000, %edx
		cmpl	$0, %edx
		jne		draw_third_good_city
		call	draw_destroyed_city
		ret
draw_third_good_city:
		call	draw_city
		ret

#third big subfunction
#this function redraws the crosshair
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
redraw_crosshairs:
		#this function redraws the crosshair
		#first calculate position (80*y+x)*2
		movl	crosshairs_y, %eax
		imull	$80, %eax
		addl	crosshairs_x, %eax
		addl	%eax, %eax
		#use "+" as crosshairs, whose ascii is 43 in decimal
		pushl	%ecx
		movb	$43, %cl
		call	mp1_poke
		popl	%ecx
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
		#get the value of cmd in %ecx
		movl	8(%esp), %ecx
		cmpl	$4, %ecx
		jg		mp1_ioctl_wrongcmd
		cmpl	$0, %ecx
		jl		mp1_ioctl_wrongcmd
		jmp		*core_functions(,%ecx,4)
mp1_ioctl_wrongcmd:
		movl	$-1, %ecx
		ret

core_functions:
	.long	mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame



# ----------------- Functions private to this file -------------------
update_missiles:
#this function update the whole linked list
# Inputs   : %ecx holds the pointer points to head of the list (and will points the each missile)
# Outputs  : %eax holds whether we need to call the mp1_notify_user
# Registers: Standard C calling convention
#check if %ecx contains 0, which is NULL, means that it has reached the end
		cmpl	$0, %ecx
		jne		update_missiles_continue
		movl	%esi, %eax
		ret
update_missiles_continue:
		#first remove it from the screen
		call	calculate_position
		pushl	%ecx
		movb	$32, %cl
		call	mp1_poke
		popl	%ecx
		#check if it is exploded
		cmpl	$0, EXPLODED(%ecx)
		jne		no_xy_update		
		#update x and y of this missile
		movl	VX(%ecx), %edx
		addl	%edx, X(%ecx)
		movl	VY(%ecx), %edx
		addl	%edx, Y(%ecx)
no_xy_update:
		#first check if it is out of screen
		cmpl	$0x004fffff, X(%ecx)
		jg		erase_missile
		cmpl	$0, X(%ecx)
		jl		erase_missile
		cmpl	$0x0018ffff, Y(%ecx)
		jg		erase_missile
		cmpl	$0, Y(%ecx)
		jl		erase_missile
		jmp		second_case
erase_missile:
		call	mp1_missile_remove
		jmp		this_missile_done
second_case:	
		#first check if it is exploding
		cmpl	$0, EXPLODED(%ecx)
		jne		is_exploding
		movl	X(%ecx), %edx
		shrl	$16, %edx
		cmpl	%edx, DEST_X(%ecx)
		jne		third_case
		movl	Y(%ecx), %edx
		shrl	$16, %edx
		cmpl	%edx, DEST_Y(%ecx)
		jne		third_case
is_exploding:
		#save caller saved registers
		pushl	%eax
		pushl	%edx		
		#push the argument for missile_explode
		pushl	%ecx
		call	missile_explode
		#check if this function returns non_zero value
		cmpl	$0, %esi
		jne		is_exploding_continue
		movl	%eax, %esi
is_exploding_continue:
		popl	%ecx
		popl	%edx
		popl	%eax
		#get the position of the missile in %eax
		call	calculate_position
		subl	$1, EXPLODED(%ecx)
		jz		explode_stop
		pushl	%ecx
		movb	$EXPLOSION, %cl
		jmp		draw_explosion
explode_stop:
		call	mp1_missile_remove
		pushl	%ecx
		movb	$32,%cl
draw_explosion:	
		call	mp1_poke
		popl	%ecx
		jmp		this_missile_done		 
third_case:
		#this case just redraw the missile in new position
		call	calculate_position
		pushl	%ecx
		movb	C(%ecx), %cl
		call	mp1_poke
		popl	%ecx
this_missile_done:
		#move the %ecx points to the next missile
		cmpl	$0, %ecx
		jne		update_missiles_continue_second
		movl	%esi, %eax
		ret
update_missiles_continue_second:
		movl	NEXT(%ecx), %ecx
		jmp		update_missiles   

		
		
		
#this function is called by mp1_ioctl and will intialize base_alive 
#and corss hair at the beginning of the game
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_startgame:
		#c calling convetion
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		#this function intialize only base_alive and corss_hair
		movl	$0x00010101, base_alive
		movl	$40, crosshairs_x
		movl	$12, crosshairs_y
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave     
		ret  


#this function is called by mp1_ioctl and will copy a user space missile to kernel
# Inputs   : one argument, points to the missile in user space
# Outputs  : return 0 if copy succeeds and -1 if fails
# Registers: Standard C calling convention
mp1_ioctl_addmissile:
		#c calling convetion
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		#first get the argument in %ecx
		movl	8(%ebp), %ecx
		#then allocate 33 bytes in kernel
		movl	$33, %edx
		pushl	%ecx
		pushl	%edx
		call	mp1_malloc
		popl	%edx
		popl	%ecx
		#now %eax holds the pointer to the allocated memory in kernel
		pushl	%edx
		pushl	%ecx
		pushl	%eax
		call	mp1_copy_from_user
		#check if the return value is 0
		cmpl	$0, %eax
		jne		addmissile_fail
		popl	%eax
		popl	%ecx
		popl	%edx
		#now %eax still holds the pointer to the allocated memory in kernel
		#then we make %edx->next = head, head = %edx
		movl	mp1_missile_list, %edx
		movl	%edx, NEXT(%eax)
		movl	%eax, mp1_missile_list
		#return 0
		movl	$0, %eax
		jmp		addmissile_end
addmissile_fail:
		#first pop back
		popl	%eax
		popl	%ecx
		popl	%edx
		#free memory, %eax still holds the allocated memory
		pushl	%eax
		call	mp1_free
		popl	%eax
		#return -1
		movl	$-1, %eax
addmissile_end:
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave     
		ret   
		
		
		
		


#this function is called by mp1_ioctl and will move the x hair
# Inputs   : one argument, contains the move in x in low 16 bits and move in y in high 16 bits
# Outputs  : return 0 and never fails
# Registers: Standard C calling convention
mp1_ioctl_movexhairs:
		#c calling convetion
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		#we can frist erase the original crosshair
		#first calculate position (80*y+x)*2
		movl	crosshairs_y, %eax
		imull	$80, %eax
		addl	crosshairs_x, %eax
		addl	%eax, %eax
		#use " " to replace, whose ascii is 32 in decimal
		movb	$32, %cl
		call	mp1_poke
		#then get the argument in %ecx
		movl	8(%ebp), %ecx
		cmpl	$0, %ecx
		je		movexhairs_end
		#then we want to save x in %eax and y in %ecx
		movl	%ecx, %eax
		shll	$16, %eax
		sarl	$16, %eax
		sarl	$16, %ecx
		#then add the change and check boundaries
		addl	%eax, crosshairs_x
		cmpl	$79, crosshairs_x
		jg		movexhairs_xTooBig
		cmpl	$0, crosshairs_x
		jl		movexhairs_xTooSmall
		jmp		movexhairs_checkY
movexhairs_xTooBig:
		movl	$79, crosshairs_x
		jmp		movexhairs_checkY
movexhairs_xTooSmall:
		movl	$0, crosshairs_x
movexhairs_checkY:
		addl	%ecx, crosshairs_y
		cmpl	$24, crosshairs_y
		jg		movexhairs_yTooBig
		cmpl	$0, crosshairs_y
		jl		movexhairs_yTooSmall
		jmp		movexhairs_redraw
movexhairs_yTooBig:
		movl	$24, crosshairs_y
		jmp		movexhairs_redraw
movexhairs_yTooSmall:
		movl	$0, crosshairs_y
movexhairs_redraw:
		movl	crosshairs_y, %eax
		imull	$80, %eax
		addl	crosshairs_x, %eax
		addl	%eax, %eax
		#use "+" as crosshairs, whose ascii is 43 in decimal
		movb	$43, %cl
		call	mp1_poke
movexhairs_end:
		#prepare to leave
		movl	$0, %eax
		popl	%edi
		popl	%esi
		popl	%ebx
		leave          
		ret

#this function is called by mp1_ioctl and get the status of the game
# Inputs   : one argument, points to user space that we need to move data to
# Outputs  : return 0 if copy succeeds and -1 if fails
# Registers: Standard C calling convention
mp1_ioctl_getstatus:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%esi
		pushl	%edi

		movl 	$0, ioctl_status				#initialize result value to 0
		movl	mp1_score, %edx				#copy score into the lower 16 bits
		movl	%edx, ioctl_status
		
	check_1:								
		movl	$0x000000FF, %eax			#check if first base alive and set bit 16
		andl	base_alive, %eax
		jz	check_2
		addl	$0x00010000, ioctl_status
		
	check_2:
		movl	$0x0000FF00, %eax			#check if second base alive and set bit 17
		andl	base_alive, %eax
		jz	check_3
		addl	$0x00020000, ioctl_status
		
	check_3:
		movl	$0x00FF0000, %eax			#check if third base alive and set bit 18
		andl	base_alive, %eax
		jz	over
		addl	$0x00040000, ioctl_status

	over:
		movl	8(%ebp),%ecx				#copy result to user space
		pushl	$4
		pushl	$ioctl_status
		pushl	%ecx
		call	mp1_copy_to_user
		cmpl	$0, %eax					#check if copy success
		
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		
		jz	status_out						#yes, return value is 0
		movl	$-1, %eax					#no, set return value to -1
		
	status_out:		
		popl	%edi
		popl	%esi
		leave
		ret

#this function is called by mp1_ioctl and clean the list and free all the memory
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_endgame:
		#c calling convetion
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		#the function clean up the linked list
endgame_clear_list:
		cmpl	$0, mp1_missile_list
		je		endgame_end
		#%eax = head, head = head->next, free(%eax)
		movl	mp1_missile_list, %eax
		movl	NEXT(%eax), %edx
		movl	%edx, mp1_missile_list
		pushl	%eax
		call	mp1_free
		popl	%eax
		jmp		endgame_clear_list
endgame_end:
		#prepare to leave
		movl	$1, %eax
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret


#########################################other_helper_function####################################################
#calculate_position, mp1_missile_remove, draw_city, draw_destroyed_city
#all the registers are callee saved
#this function is calculate the position on the screen 
# Inputs   : %ecx points to the missile
# Outputs  : return the offset to print to the screen
# Registers: Standard C calling convention
calculate_position:
		#c calling convetion
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		#the missile is indicated by %ecx
		#position will be (80*y+x)*2
		pushl	%edx
		movl	Y(%ecx), %edx
		shrl	$16, %edx
		movl	%edx, %eax
		imull	$80, %eax
		movl	X(%ecx), %edx
		shrl 	$16, %edx
		addl	%edx, %eax
		addl	%eax, %eax
		popl	%edx
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

#this function is used to remove the given missile 
# Inputs   : %ecx points to the missile need to be removed
# Outputs  : none
# Registers: Standard C calling convention
mp1_missile_remove:
		#remove the missile
		#use %ecx to hold the missile need to be removed
		#use %esi to trace the linked list
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		cmpl	$0, mp1_missile_list
		je		missile_remove_end
		movl	mp1_missile_list, %esi
		#check if it is the first one
		cmpl	%esi, %ecx
		je		missile_remove_firstone
		#check if %esi -> next == %ecx
search_front_missile:
		cmpl	NEXT(%esi), %ecx
		je		find_front_missile
		cmpl	$0, NEXT(%esi)
		je		missile_remove_end
		movl	NEXT(%esi), %esi
		jmp		search_front_missile
find_front_missile:
		#copy the "next" of %ecx to the "next" of %esi
		movl	NEXT(%ecx),	%edx
		movl	%edx, NEXT(%esi)
		#save caller saved registers
		pushl	%eax
		pushl	%edx
		#push the argument 
		pushl	%ecx
		call	mp1_free
		popl	%ecx
		popl	%edx
		popl	%eax
		#make %ecx points to the missile in front of the removed one
		movl	%esi, %ecx
		jmp		missile_remove_end
missile_remove_firstone:
		movl	NEXT(%ecx), %ebx
		movl	%ebx, mp1_missile_list
		#save caller saved registers
		pushl	%eax
		pushl	%edx
		#push the argument 
		pushl	%ecx
		call	mp1_free
		popl	%ecx
		popl	%edx
		popl	%eax
		movl	mp1_missile_list, %ecx
missile_remove_end:
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret
		
		
		
#this function is draw the good city on the screen 
# Inputs   : %ecx holds the leftmost corner of the city
# Outputs  : none
# Registers: Standard C calling convention
draw_city:
		#the leftcorner of city is in %ecx
		#use %esi to hold the base_pic address
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		leal	base_pic, %esi
		#first calculate 80*24(80*y), which is fixed
		movl	$24, %eax
		imull	$80, %eax
		addl	%ecx, %eax
		addl	%eax, %eax
		#draw the first char
		movb	0(%esi), %cl
		call	mp1_poke
		#draw the rest char
		#add one char to %eax each time, which is 2 bytes
		addl	$2, %eax
		movb	1(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	2(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	3(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	4(%esi), %cl
		call	mp1_poke
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret		

		
#this function is draw the dead city on the screen 
# Inputs   : %ecx holds the leftmost corner of the city
# Outputs  : none
# Registers: Standard C calling convention		
draw_destroyed_city:
		#the leftcorner of city is in %ecx
		#use %esi to hold the dead_base_pic address
		pushl	%ebp
		movl	%esp, %ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		leal	dead_base_pic, %esi
		#first calculate 80*24(80*y), which is fixed
		movl	$24, %eax
		imull	$80, %eax
		addl	%ecx, %eax
		addl	%eax, %eax
		#draw the first char
		movb	0(%esi), %cl
		call	mp1_poke
		#draw the rest char
		#add one char to %eax each time, which is 2 bytes
		addl	$2, %eax
		movb	1(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	2(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	3(%esi), %cl
		call	mp1_poke
		addl	$2, %eax
		movb	4(%esi), %cl
		call	mp1_poke
		#prepare to leave
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret	
