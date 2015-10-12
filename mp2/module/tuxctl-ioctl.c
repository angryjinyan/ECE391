/* tuxctl-ioctl.c
 *
 * Driver (skeleton) for the mp2 tuxcontrollers for ECE391 at UIUC.
 *
 * Mark Murphy 2006
 * Andrew Ofisher 2007
 * Steve Lumetta 12-13 Sep 2009
 * Puskar Naha 2013
 */

#include <asm/current.h>
#include <asm/uaccess.h>

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/file.h>
#include <linux/miscdevice.h>
#include <linux/kdev_t.h>
#include <linux/tty.h>
#include <linux/spinlock.h>

#include "tuxctl-ld.h"
#include "tuxctl-ioctl.h"
#include "mtcp.h"

#define debug(str, ...) \
	printk(KERN_DEBUG "%s: " str, __FUNCTION__, ## __VA_ARGS__)




/*************************global variables*********************************/
static unsigned int ack_or_not;
struct tux_buttons
{
	spinlock_t buttons_lock;
	unsigned long buttons;
};
static unsigned int busy = 0;
static struct tux_buttons button_status;
static unsigned long led_status;
const static unsigned char seven_segment_information [16] = {0xE7, 0x06, 0xCB, 0x8F, 0x2E, 0xAD, 
	0xED, 0x86, 0xEF, 0xAF, 0xEE, 0x6D, 0xE1, 0x4F, 0xE9, 0xE8};
unsigned a, b, c;



/************************loacl function declaration************************/

int tuxctl_ioctl_tux_init(struct tty_struct* tty);
int tuxctl_ioctl_tux_buttons(struct tty_struct* tty, unsigned long arg);
int tuxctl_ioctl_tux_set_led (struct tty_struct* tty, unsigned long arg);
int tuxctl_ioctl_tux_led_request(struct tty_struct* tty);
int tuxctl_ioctl_tux_read_led (struct tty_struct* tty, unsigned long arg);
int tuxtl_handle_get_button(unsigned b, unsigned c);
/************************ Protocol Implementation *************************/

/* tuxctl_handle_packet()
 * IMPORTANT : Read the header for tuxctl_ldisc_data_callback() in 
 * tuxctl-ld.c. It calls this function, so all warnings there apply 
 * here as well.
 */
void tuxctl_handle_packet (struct tty_struct* tty, unsigned char* packet)
{
	if(busy)
		return;

    a = packet[0]; /* Avoid printk() sign extending the 8-bit */
    b = packet[1]; /* values when printing them. */
    c = packet[2];

    //printk("packet : %x %x %x\n", a, b, c);
    switch(a)
    {
     	case MTCP_ACK:
     		ack_or_not = 1;
     		return;
     	case MTCP_BIOC_EVENT:
     		busy = 1;
     		tuxtl_handle_get_button(b, c);
     		busy = 0;
     		return;
     	case MTCP_RESET:
     		tuxctl_ioctl_tux_init(tty);	
     		if(!ack_or_not)
 				return ;			
		 	tuxctl_ioctl_tux_set_led(tty, led_status);	
			return; 
		 default:
		 	return;
     }
}

/******** IMPORTANT NOTE: READ THIS BEFORE IMPLEMENTING THE IOCTLS ************
 *                                                                            *
 * The ioctls should not spend any time waiting for responses to the commands *
 * they send to the controller. The data is sent over the serial line at      *
 * 9600 BAUD. At this rate, a byte takes approximately 1 millisecond to       *
 * transmit; this means that there will be about 9 milliseconds between       *
 * the time you request that the low-level serial driver send the             *
 * 6-byte SET_LEDS packet and the time the 3-byte ACK packet finishes         *
 * arriving. This is far too long a time for a system call to take. The       *
 * ioctls should return immediately with success if their parameters are      *
 * valid.                                                                     *
 *                                                                            *
 ******************************************************************************/
int 
tuxctl_ioctl (struct tty_struct* tty, struct file* file, 
	      unsigned cmd, unsigned long arg)
{
    switch (cmd) 
    {
		case TUX_INIT:
			return  tuxctl_ioctl_tux_init(tty);
		case TUX_BUTTONS:
			return  tuxctl_ioctl_tux_buttons(tty, arg);
		case TUX_SET_LED:
			return  tuxctl_ioctl_tux_set_led (tty, arg);
		case TUX_LED_ACK:
			return 0;
		case TUX_LED_REQUEST:
			return 0;
		case TUX_READ_LED:
			return 0;
		default:
	    	return -EINVAL;
    }
}

/*********************implementation of local functions*************************/

/*
 *tuxctl_ioctl_tuxinit
 *DESCRIPTION: Initialize the TUX Controller
 *Input: tty - a pointer to a tty_struct type argument, used for tuxctl_ldisc_put
 *Output: None
 *Return Value: Always 0 (success)
 *Side Effects: Same as description
 */
 int tuxctl_ioctl_tux_init(struct tty_struct* tty)
 {
 	unsigned char write_value[2];

 	ack_or_not = 0;
 	
 	//Enable Button interrupt-on-change.
 	write_value[0] = MTCP_BIOC_ON;
 	//Put the LED display into user-mode.
 	write_value[1] = MTCP_LED_USR;

 	tuxctl_ldisc_put(tty, &write_value[0], 1);
 	//usleep(1000);
 	tuxctl_ldisc_put(tty, &write_value[1], 1);

 	//initialize led_status and buttons
 	led_status = 0;
 	button_status.buttons = 0xFF;
 	button_status.buttons_lock = SPIN_LOCK_UNLOCKED;

 	return 0;
 }

/*
 *tuxctl_ioctl_set_led
 *DESCRIPTION: Display the data specified by arg to LED on TUX Controller
 *Input: tty - a pointer to a tty_struct type argument, used for tuxctl_ldisc_put
 *       arg - The argument is a 32-bit integer of the following form: 
 *			   The low 16-bits specify a number whose hexadecimal value is to be 
 *			   displayed on the 7-segment displays. The low 4 bits of the third byte 
 *			   specifies which LED’s should be turned on. The low 4 bits of the 
 *			   The low 4 bits of the highest byte (bits 27:24) specify whether the 
 *			   corresponding decimal points should be turned on. 
 *Output: None
 *Return Value: Always 0 (success)
 *Side Effects: Same as description
 */
 int tuxctl_ioctl_tux_set_led (struct tty_struct* tty, unsigned long arg)
 {
 	unsigned char display_value[4];
 	unsigned char leds_on;
 	unsigned char dp;
 	unsigned int  i;		//general index
 	unsigned long bitmask; 
 	unsigned char buffer_to_send[6];
 	if(!ack_or_not)
 		return -1;
 	
 	ack_or_not = 0;
 	//extract information from arg
 	bitmask = 0x000F;
 	for(i = 0; i < 4; ++i, bitmask <<= 4)
 	{
 		display_value[i] = (bitmask & arg) >> (4*i);
 	}

 	leds_on = (arg & (0x0F << 16)) >> 16;
 	dp = (arg & (0x0F << 24)) >> 24;

 	//Put the LED display into user-mode.
 	buffer_to_send[0] = MTCP_LED_USR;
 	tuxctl_ldisc_put(tty, &buffer_to_send[0], 1);

 	//put data into buffer_to_send
 	//opcode
 	buffer_to_send[0] = MTCP_LED_SET;
 	buffer_to_send[1] = 0x0F;

 	bitmask = 0x01;
 	for(i = 0; i < 4; ++i, bitmask <<= 1)
 	{
 		if(leds_on & bitmask)
 		{
 			display_value[i] = seven_segment_information[display_value[i]];
 			if(dp & bitmask)
 				display_value[i] |= 0x10;
 			buffer_to_send[2 + i] = display_value[i];
 			
 		}
 		else
 		{
 			buffer_to_send[2 + i] = 0x0;
 		}
 	}
 	//save the current led_status
 	led_status = arg;


 	//send the buffer to TUX Controller
 	tuxctl_ldisc_put(tty, buffer_to_send, 6);

	return 0;
 }


/*
 *tuxctl_ioctl_tux_buttons
 *DESCRIPTION: put the status of button to arg
 *INPUT: tty - a pointer to a tty_struct type argument, used for tuxctl_ldisc_put
 		 arg - where to put the status of button
 *OUPUT: None
 *Return Value: 0 if success
 *Side Effects: None
 */
int tuxctl_ioctl_tux_buttons(struct tty_struct* tty, unsigned long arg)
{
	unsigned long flags;
	unsigned long *buttons_ptr;
	int ret;
	buttons_ptr = &(button_status.buttons);

	

	//check lock
	spin_lock_irqsave(&(button_status.buttons_lock), flags);

	//copy to user space
	ret = copy_to_user((void *)arg, (void *)buttons_ptr, sizeof(long));

	//unlock
	spin_unlock_irqrestore(&(button_status.buttons_lock), flags);

	if (ret > 0)
		return -EFAULT;
	else
		return 0;
	

}
/*
 *tuxtl_handle_get_button
 *DESCRIPTION: the function get the status of button and save in buttons
 *INPUT: b - have the value of XXXXCBAS (X stands for not use)
 *		 c - have the value of XXXXRDLU
 *OUPUT: None
 *Return Value: Always 0 (success)
 *Side Effects: change the lowest byte of global variable button to RLDUCBAS
 */
int tuxtl_handle_get_button(unsigned b, unsigned c)
{
	unsigned long flags;
	unsigned int status_of_L;
	unsigned int status_of_D;

	b = ~b;
	c = ~c;

	status_of_L = (c & 0x02) >> 1;
	status_of_D = (c & 0x04) >> 2;

	//check lock
	spin_lock_irqsave(&(button_status.buttons_lock), flags);

	//take the last four bits of b and c and put them into buttons
	//reassign the value of L and D
	button_status.buttons = ~((((b & 0x0F) | ((c & 0x0F) << 4)) & 0x9F) 
				| (status_of_D << 5) | (status_of_L << 6));
	//unlock
	spin_unlock_irqrestore(&(button_status.buttons_lock), flags);

	
	return 0;
}
