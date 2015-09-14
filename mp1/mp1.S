

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
base_alive:		.long 0x01010101	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"		# Picture of a dead base
crosshairs_x:		.long 0x0			# X-position of the crosshairs
crosshairs_y:		.long 0x0			# Y-position of the crosshairs


cur_status:		.long 0x0				# Current game status
m_prev:			.long 0x0				# previous missile pointer
m_cur:			.long 0x0				# current missile pointer
m_next:			.long 0x0				# next missile pointer
nuflag:			.long 0x0				# notify user flag
vba:			.long 0x0	

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
		pushl 	%ebp						#set up frame, save registers
		movl	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		
		
	##set up pointers and call update_missiles		
		movl	$0, m_prev					#initialize m_prev, m_cur, m_next
		movl	$0, m_next	
		movl	mp1_missile_list, %edx
		movl	%edx, m_cur				
		cmpl	$0, %edx					#check if current missile pointer is null
		jz		check_base_1				#no missile to update
		movl	(%edx), %ecx				#has missile, update m_next
		movl	%ecx, m_next
		
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		call	update_missiles
		popl	%edx
		popl	%ecx
		popl	%eax
		
		
	##checking if the three bases are alive and draw according to corresponding status 	
	check_base_1:
		movl	$0x000000FF, %eax
		andl	base_alive, %eax
		jz	base1_dead
		
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$18
		call	draw_live_base
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		jmp	check_base_2
		
	base1_dead:
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$18
		call	draw_dead_base
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax

	check_base_2:
		movl	$0x0000FF00, %eax
		andl	base_alive, %eax
		jz	base2_dead
		
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$38
		call	draw_live_base
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		jmp	check_base_3
		
	base2_dead:
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$38
		call	draw_dead_base
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax

	check_base_3:
		movl	$0x00FF0000, %eax
		andl	base_alive, %eax
		jz	base3_dead
		
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$58
		call	draw_live_base
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		jmp	check_base_over
		
	base3_dead:
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	$58
		call	draw_dead_base	
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
	
	check_base_over:
		pushl	%eax
		pushl	%ecx
		pushl	%edx
		pushl	crosshairs_x					
		pushl	crosshairs_y
		pushl	$0x2B
		call	draw_char		
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax	
		
		popl	%edi
		popl	%esi
		popl	%ebx
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
		movl	8(%esp),%ecx		
		
		addl	$-5, %ecx					#check if cmd in range
		jns		false_cmd
		addl	$5, %ecx
		js		false_cmd
		jmp		*ioctl_jumptable(,%ecx,4)

	ioctl_jumptable:
		.long	mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame
		
	false_cmd:								#if cmd out of range return -1
		movl	$-1, %eax
		ret


# ----------------- Functions private to this file -------------------
##update the status of all missiles, including explosion, location, erase
update_missiles:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		
		movl	$0, nuflag					#reset the notify user flag
		
	n_missile:
		movl	m_cur, %edx					#get the addr of current missile
		movl	EXPLODED(%edx), %eax		#check if the missile is exploding
		cmpl	$0, %eax
		ja		m_explode					#if exploding go to m_explode
	
		movl	m_cur, %edx					#get current missile screen location
		movl	X(%edx), %eax
		sarl	$16, %eax
		movl	Y(%edx), %ecx
		sarl	$16, %ecx
		addl	$-80, %eax					#check if out of screen
		jns		erase_m						#if out erase missile
		addl	$80, %eax
		js		erase_m
		addl	$-25, %ecx
		jns		erase_m
		addl	$25, %ecx
		js		erase_m
		
		
		cmpl	%eax, DEST_X(%edx)			#check if reached destination
		jnz		not_yet_dest
		cmpl	%ecx, DEST_Y(%edx)
		jnz		not_yet_dest
		jmp		m_explode					#destination reached, explode missile
		
	not_yet_dest:		
		movl	m_cur, %edx					#get old missile screen location
		movl	X(%edx), %eax
		shrl	$16, %eax
		movl	Y(%edx), %ecx
		shrl	$16, %ecx
		
		
		pushl	%eax						#erase old missile
		pushl	%ecx
		pushl	%edx
		pushl	%eax 
		pushl	%ecx
		pushl	$0x20
		call	draw_char	
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax	
	
		movl	m_cur, %edx					#save new x_y exact location
		movl	X(%edx), %eax
		addl	VX(%edx), %eax 				
		movl	%eax, X(%edx)
		movl	Y(%edx), %ecx
		addl	VY(%edx), %ecx 				
		movl	%ecx, Y(%edx)

		
		shrl	$16, %eax					#get new missile screen location
		shrl	$16, %ecx
		#movl	m_cur, %edx
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx				
		pushl	%eax
		pushl	%ecx
		movb	C(%edx),%cl
		pushl	%ecx
		call	draw_char					#draw new missile
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		jmp		go_to_next_m	
	
	erase_m:	
		movl	m_cur, %edx					#get current missile screen location
		movl	X(%edx), %eax
		sarl	$16, %eax
		movl	Y(%edx), %ecx
		sarl	$16, %ecx
		
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx		
		pushl	%eax 
		pushl	%ecx
		pushl	$0x20						
		call	draw_char					#erase the missile
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		movl	m_prev, %eax				#check if prev missile pointer is null
		cmpl	$0, %eax
		ja		has_prev					#has prev, not null jump to has_prev
		
	no_prev:
		movl	m_next,	%edx				#no prev, put m_next as new head pointer
		movl	%edx, mp1_missile_list		
		jmp		free_m						
		
	has_prev:
		movl	m_next,	%edx				#has prev, set prev->next = next
		movl	m_prev, %eax
		movl	%edx, (%eax)
		
	free_m:		
		movl	m_cur, %eax					#hold m_cur in %eax
		movl	m_next, %edx				#move m_next to m_cur
		movl	%edx, m_cur
		cmpl	$0, %edx					#check if next missile pointer is null
		jz		go_free						#is null, free current missile	
		movl	(%edx),	%ecx     			#not null, move m_next->next to m_next
		movl	%ecx, m_next				
		
	go_free:
		pushl	%eax						
		pushl	%ecx
		pushl	%edx	
		pushl	%eax						#push old m_cur on stack for mp1_free
		call	mp1_free
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		cmpl	$0, m_cur					#check if finished the list
		jz		um_over						#yes, check over
		jmp		n_missile					#no, go to next missile 
	
	m_explode:
		movl	m_cur, %edx					#get current missile screen location 
		movl	X(%edx), %eax
		sarl	$16, %eax
		movl	Y(%edx), %ecx
		sarl	$16, %ecx
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx	
		pushl	%eax 
		pushl	%ecx
		pushl	$64
		call	draw_char					#draw explosion
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx	
		pushl	m_cur
		call	missile_explode
		cmpl	$0, %eax					#check if hit a target
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		jz		no_hit						#no hit, do nothing
		movl	$1, nuflag					#hit a target, set notiy user flag to 1
		
	no_hit:
		movl	m_cur, %ecx					#decrement the exploding time
		movl	EXPLODED(%ecx), %edx		
		addl	$-1, %edx
		movl	%edx, EXPLODED(%ecx)
		cmpl	$0, %edx					#check if finished exploding
		jz	erase_m							#yes, erase the missile
		jmp	go_to_next_m					#no, keep the missile go to next missile
			
	
	go_to_next_m:
		movl	m_cur, %edx					#move m_cur to m_prev
		movl	%edx, m_prev
		movl	m_next, %edx				#move m_next to m_cur
		movl	%edx, m_cur
		cmpl	$0, %edx					#check if m_cur is null
		jz		um_over						#is null, update_missiles over
		movl	(%edx), %ecx				#not null, get next missile pointer
		movl	%ecx, m_next
		jmp		n_missile					#go to next missile
		
	um_over:
		cmpl	$0, nuflag					#check if need to notify user
		jz		get_out						#no, get out
		
		pushl	%eax						#yes, call notify user
		pushl	%ecx
		pushl	%edx
		call	mp1_notify_user
		popl	%edx
		popl	%ecx
		popl	%eax
		
	get_out:
		popl	%edi
		popl	%esi
		leave
		ret

mp1_ioctl_startgame:
		pushl	%ebp
		movl	%esp,%ebp
		pushl	%esi
		pushl	%edi

		
		
		movl	$0x00010101, base_alive		#initialize base_alive
		movl	$0, mp1_score				#initialize mp1_score
		movl	$40, crosshairs_x			#initialize crosshairs_x
		movl	$12, crosshairs_y			#initialize crosshairs_y
		
		popl	%edi
		popl	%esi
		popl	%ebx
		leave 
		ret

mp1_ioctl_addmissile:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi

		pushl	$33							#allocate memory
		call	mp1_malloc
		movl	8(%ebp),%ecx				#get user-side missle pointer
		pushl	%ecx						#push from*
		pushl 	%eax						#push to*
		call	mp1_copy_from_user			#copy missile
		cmpl	$0, %eax
		jnz		copy_fail					#go to copy_fail is copy fail
		popl	%eax
		movl	mp1_missile_list, %edx
		movl	%edx, (%eax)				#point new next to old head
		movl	%eax, mp1_missile_list		#update new head

		popl	%eax						#clean up stack
		popl	%eax						#clean up stack
		
		movl	$0, %eax					#set return value
		popl	%edi
		popl	%esi
		leave
		ret
	copy_fail:
		call	mp1_free
		popl	%eax						#clean up stack
		popl	%eax						#clean up stack
		popl	%eax						#clean up stack
		
		movl $-1, %eax
		
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret
		

mp1_ioctl_movexhairs:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi

		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx
		pushl	crosshairs_x					
		pushl	crosshairs_y
		pushl	$0x20
		call	draw_char					#erase old c-h
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		
		movl	8(%ebp),%ecx				#copy new location info to %eax
		movl	%ecx, %eax
		shll	$16, %eax					#extracting the x-location
		sarl	$16, %eax							
		addl	crosshairs_x, %eax
		sarl	$16, %ecx					#extracting the y-location
		addl	crosshairs_y, %ecx
		addl	$-80, %eax					#check if out of screen
		jns		movexhairs_out
		addl	$80, %eax
		js		movexhairs_out
		addl	$-25, %ecx
		jns		movexhairs_out
		addl	$25, %ecx
		js		movexhairs_out
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx
		pushl	%eax						
		pushl	%ecx
		pushl	$0x2B
		call	draw_char					#draw new c-h
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax


		
		movl	%eax, crosshairs_x			#update crosshairs_x
		movl	%ecx, crosshairs_y			#update crosshairs_y
		
	movexhairs_out:	
		pushl	%eax						
		pushl	%ecx
		pushl	%edx
		pushl	crosshairs_x
		pushl	crosshairs_y
		pushl	$0x2B
		call	draw_char					#redraw old c-h
		popl	%edx						#clean up stack	
		popl	%edx						#clean up stack
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax

		movl	$0, %eax					#set return value
		
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

mp1_ioctl_getstatus:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi

		movl 	$0, cur_status				#initialize result value to 0
		movl	mp1_score, %edx				#copy score into the lower 16 bits
		movl	%edx, cur_status
		
	check_1:								
		movl	$0x000000FF, %eax			#check if first base alive and set bit 16
		andl	base_alive, %eax
		jz	check_2
		addl	$0x00010000, cur_status
		
	check_2:
		movl	$0x0000FF00, %eax			#check if second base alive and set bit 17
		andl	base_alive, %eax
		jz	check_3
		addl	$0x00020000, cur_status
		
	check_3:
		movl	$0x00FF0000, %eax			#check if third base alive and set bit 18
		andl	base_alive, %eax
		jz	over
		addl	$0x00040000, cur_status

	over:
		movl	8(%ebp),%ecx				#copy result to user space
		pushl	$4
		pushl	$cur_status
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
		popl	%ebx
		leave
		ret
		

mp1_ioctl_endgame:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		
	not_over_yet:
		movl	mp1_missile_list, %eax		#check if the last missile is deleted
		cmpl	$0, %eax					#yes, done!
		jz	its_over
		movl	(%eax),	%ecx				#no, set next missile as head
		movl	%ecx, mp1_missile_list
		
		pushl	%eax						
		pushl	%ecx
		pushl	%edx
		push	%eax
		call	mp1_free
		popl	%edx						#clean up stack
		popl	%edx
		popl	%ecx
		popl	%eax
		jmp	not_over_yet
		
	its_over:
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

#################helper#######################
# void draw_char(unsigned long toprint, unsigned long y, unsigned long x);
# Print the char stored in the lower byte of toprint at location indicated 
# by x and y.
# Inputs   : unsigned long toprint, unsigned long y, unsigned long x
# Outputs  : none
# Registers: Standard C calling convention
draw_char:
		pushl 	%ebp
		movl 	%esp,%ebp
		pushl	%ebx
		pushl	%esi
		pushl	%edi

		pushl	%eax
		pushl 	%ecx
		pushl	%edx
		movl	8(%ebp),%ecx					#char to be printed
		movl	12(%ebp),%eax					#y coord
		movl	16(%ebp),%edx					#x coord
		imull	$80, %eax, %eax 				#calculate the offset in vmem
		addl	%edx, %eax
		shll	$1, %eax
		call	mp1_poke
		popl	%edx
		popl 	%ecx
		popl	%eax
		
		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

# void draw_live_base(unsigned long startloc);
# Draw a live base starting at location indicated by startloc
# Inputs   : unsigned long startloc
# Outputs  : none
# Registers: Standard C calling convention
draw_live_base:
		pushl 	%ebp
		movl 	%esp,%ebp	
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		movl	8(%ebp), %edx
		movl	$24, %eax
				
		imull	$80, %eax, %eax					#calculate the offset in vmem
		addl	%edx, %eax
		sall	$1, %eax

		
		leal	base_pic, %edx					
		movb	(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, (%edx,%eax,1)
		
		
		leal	base_pic, %edx
		movb	1(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 2(%edx,%eax,1)
		
		
		leal	base_pic, %edx
		movb	2(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 4(%edx,%eax,1)
		
		
		leal	base_pic, %edx
		movb	3(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 6(%edx,%eax,1)
		
		
		leal	base_pic, %edx
		movb	4(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 8(%edx,%eax,1)

		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret

# void draw_dead_base(unsigned long startloc);
# Draw a dead base starting at location indicated by startloc
# Inputs   : unsigned long startloc
# Outputs  : none
# Registers: Standard C calling convention
draw_dead_base:
		pushl 	%ebp
		movl 	%esp,%ebp	
		pushl	%ebx
		pushl	%esi
		pushl	%edi
		movl	8(%ebp), %edx
		movl	$24, %eax
		
		imull	$80, %eax, %eax					#calculate the offset in vmem
		addl	%edx, %eax
		sall	$1, %eax

		
		leal	dead_base_pic, %edx
		movb	1(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, (%edx,%eax,1)
		
		
		leal	dead_base_pic, %edx
		movb	(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 2(%edx,%eax,1)
		
		
		leal	dead_base_pic, %edx
		movb	2(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 4(%edx,%eax,1)
		
		
		leal	dead_base_pic, %edx
		movb	3(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 6(%edx,%eax,1)
		
		
		leal	dead_base_pic, %edx
		movb	4(%edx), %cl
		movl    vmem_base_addr(,1), %edx
		movb	%cl, 8(%edx,%eax,1)

		popl	%edi
		popl	%esi
		popl	%ebx
		leave
		ret
	
		