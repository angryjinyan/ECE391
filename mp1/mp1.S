
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
		#first save callee saved registers
		pushl	%EBX
		pushl	%ESI
		pushl	%EDI
		#use %ecx to point to each missile
		leal	mp1_missile_list, %ECX
		cmpl	$0, %ECX
		jne	update_list	

		#retrieve data for callee saved register
		popl	%EDI
		popl	%ESI
		popl	%EBX
		ret
update_list:
		#first check if it is exploded
		cmpl	$0, 28(,%ECX)
		jne	no_xy_update
		#remove it from the screen
		#position will be (80*y+x)*2
		movl	8,(%ECX), %EAX
		imull	%EAX, $80
		addl	4,(%ECX), %EAX
		imull	%EAX, $2
		movw	
		#update x and y of this missile
		addl	12(,%ECX), 4(,%ECX)
		addl	16(,%ECX), 8(,%ECX)
no_xy_update:
		#first check if it is out of screen
		cmpl	$79, 4(,%ECX)
		jg	erase_missile
		cmpl	$0, 4(,%ECX)
		jl	erase_missile
		cmpl	$24, 8(,%ECX)
		jg	erase_missile
		cmpl	$0, 8(,%ECX)
		jl	erase_missile
		jmp	second_case
erase_missile:
		
secdon_case:	
		ret
redraw_list:
		ret
redraw_crosshairs:
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
		ret


# ----------------- Functions private to this file -------------------

update_missiles:
		ret

mp1_ioctl_startgame:
		ret

mp1_ioctl_addmissile:
		ret

mp1_ioctl_movexhairs:
		ret

mp1_ioctl_getstatus:
		ret

mp1_ioctl_endgame:
		ret
