/*									tab:8
 *
 * photo.c - photo display functions
 *
 * "Copyright (c) 2011 by Steven S. Lumetta."
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice and the following
 * two paragraphs appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE AUTHOR OR THE UNIVERSITY OF ILLINOIS BE LIABLE TO 
 * ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL 
 * DAMAGES ARISING OUT  OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, 
 * EVEN IF THE AUTHOR AND/OR THE UNIVERSITY OF ILLINOIS HAS BEEN ADVISED 
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE AUTHOR AND THE UNIVERSITY OF ILLINOIS SPECIFICALLY DISCLAIM ANY 
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE 
 * PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND NEITHER THE AUTHOR NOR
 * THE UNIVERSITY OF ILLINOIS HAS ANY OBLIGATION TO PROVIDE MAINTENANCE, 
 * SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Author:	    Steve Lumetta
 * Version:	    3
 * Creation Date:   Fri Sep  9 21:44:10 2011
 * Filename:	    photo.c
 * History:
 *	SL	1	Fri Sep  9 21:44:10 2011
 *		First written (based on mazegame code).
 *	SL	2	Sun Sep 11 14:57:59 2011
 *		Completed initial implementation of functions.
 *	SL	3	Wed Sep 14 21:49:44 2011
 *		Cleaned up code for distribution.
 */


#include <string.h>

#include "assert.h"
#include "modex.h"
#include "photo.h"
#include "photo_headers.h"
#include "world.h"


/* types local to this file (declared in types.h) */

/* 
 * A room photo.  Note that you must write the code that selects the
 * optimized palette colors and fills in the pixel data using them as 
 * well as the code that sets up the VGA to make use of these colors.
 * Pixel data are stored as one-byte values starting from the upper
 * left and traversing the top row before returning to the left of
 * the second row, and so forth.  No padding should be used.
 */
struct photo_t {
    photo_header_t hdr;			/* defines height and width */
    uint8_t        palette[192][3];     /* optimized palette colors */
    uint8_t*       img;                 /* pixel data               */
};

/* 
 * An object image.  The code for managing these images has been given
 * to you.  The data are simply loaded from a file, where they have 
 * been stored as 2:2:2-bit RGB values (one byte each), including 
 * transparent pixels (value OBJ_CLR_TRANSP).  As with the room photos, 
 * pixel data are stored as one-byte values starting from the upper 
 * left and traversing the top row before returning to the left of the 
 * second row, and so forth.  No padding is used.
 */
struct image_t {
    photo_header_t hdr;			/* defines height and width */
    uint8_t*       img;                 /* pixel data               */
};



/* file-scope variables */

/* 
 * The room currently shown on the screen.  This value is not known to 
 * the mode X code, but is needed when filling buffers in callbacks from 
 * that code (fill_horiz_buffer/fill_vert_buffer).  The value is set 
 * by calling prep_room.
 */
static const room_t* cur_room = NULL; 

/*the basic structure for octree nodes*/
struct octree_node {
		uint16_t	idx_by_RGB;
		uint16_t	idx_in_level_2;
		unsigned long int	red_sum;
		unsigned long int	green_sum;
		unsigned long int 	blue_sum;
		unsigned int pixel_number;
		uint16_t	palette_idx;
};
	
	
/* 
 * fill_horiz_buffer
 *   DESCRIPTION: Given the (x,y) map pixel coordinate of the leftmost 
 *                pixel of a line to be drawn on the screen, this routine 
 *                produces an image of the line.  Each pixel on the line
 *                is represented as a single byte in the image.
 *
 *                Note that this routine draws both the room photo and
 *                the objects in the room.
 *
 *   INPUTS: (x,y) -- leftmost pixel of line to be drawn 
 *   OUTPUTS: buf -- buffer holding image data for the line
 *   RETURN VALUE: none
 *   SIDE EFFECTS: none
 */
void
fill_horiz_buffer (int x, int y, unsigned char buf[SCROLL_X_DIM])
{
    int            idx;   /* loop index over pixels in the line          */ 
    object_t*      obj;   /* loop index over objects in the current room */
    int            imgx;  /* loop index over pixels in object image      */ 
    int            yoff;  /* y offset into object image                  */ 
    uint8_t        pixel; /* pixel from object image                     */
    const photo_t* view;  /* room photo                                  */
    int32_t        obj_x; /* object x position                           */
    int32_t        obj_y; /* object y position                           */
    const image_t* img;   /* object image                                */

    /* Get pointer to current photo of current room. */
    view = room_photo (cur_room);

    /* Loop over pixels in line. */
    for (idx = 0; idx < SCROLL_X_DIM; idx++) {
        buf[idx] = (0 <= x + idx && view->hdr.width > x + idx ?
		    view->img[view->hdr.width * y + x + idx] : 0);
    }

    /* Loop over objects in the current room. */
    for (obj = room_contents_iterate (cur_room); NULL != obj;
    	 obj = obj_next (obj)) {
	obj_x = obj_get_x (obj);
	obj_y = obj_get_y (obj);
	img = obj_image (obj);

        /* Is object outside of the line we're drawing? */
	if (y < obj_y || y >= obj_y + img->hdr.height ||
	    x + SCROLL_X_DIM <= obj_x || x >= obj_x + img->hdr.width) {
	    continue;
	}

	/* The y offset of drawing is fixed. */
	yoff = (y - obj_y) * img->hdr.width;

	/* 
	 * The x offsets depend on whether the object starts to the left
	 * or to the right of the starting point for the line being drawn.
	 */
	if (x <= obj_x) {
	    idx = obj_x - x;
	    imgx = 0;
	} else {
	    idx = 0;
	    imgx = x - obj_x;
	}

	/* Copy the object's pixel data. */
	for (; SCROLL_X_DIM > idx && img->hdr.width > imgx; idx++, imgx++) {
	    pixel = img->img[yoff + imgx];

	    /* Don't copy transparent pixels. */
	    if (OBJ_CLR_TRANSP != pixel) {
		buf[idx] = pixel;
	    }
	}
    }
}


/* 
 * fill_vert_buffer
 *   DESCRIPTION: Given the (x,y) map pixel coordinate of the top pixel of 
 *                a vertical line to be drawn on the screen, this routine 
 *                produces an image of the line.  Each pixel on the line
 *                is represented as a single byte in the image.
 *
 *                Note that this routine draws both the room photo and
 *                the objects in the room.
 *
 *   INPUTS: (x,y) -- top pixel of line to be drawn 
 *   OUTPUTS: buf -- buffer holding image data for the line
 *   RETURN VALUE: none
 *   SIDE EFFECTS: none
 */
void
fill_vert_buffer (int x, int y, unsigned char buf[SCROLL_Y_DIM])
{
    int            idx;   /* loop index over pixels in the line          */ 
    object_t*      obj;   /* loop index over objects in the current room */
    int            imgy;  /* loop index over pixels in object image      */ 
    int            xoff;  /* x offset into object image                  */ 
    uint8_t        pixel; /* pixel from object image                     */
    const photo_t* view;  /* room photo                                  */
    int32_t        obj_x; /* object x position                           */
    int32_t        obj_y; /* object y position                           */
    const image_t* img;   /* object image                                */

    /* Get pointer to current photo of current room. */
    view = room_photo (cur_room);

    /* Loop over pixels in line. */
    for (idx = 0; idx < SCROLL_Y_DIM; idx++) {
        buf[idx] = (0 <= y + idx && view->hdr.height > y + idx ?
		    view->img[view->hdr.width * (y + idx) + x] : 0);
    }

    /* Loop over objects in the current room. */
    for (obj = room_contents_iterate (cur_room); NULL != obj;
    	 obj = obj_next (obj)) {
	obj_x = obj_get_x (obj);
	obj_y = obj_get_y (obj);
	img = obj_image (obj);

        /* Is object outside of the line we're drawing? */
	if (x < obj_x || x >= obj_x + img->hdr.width ||
	    y + SCROLL_Y_DIM <= obj_y || y >= obj_y + img->hdr.height) {
	    continue;
	}

	/* The x offset of drawing is fixed. */
	xoff = x - obj_x;

	/* 
	 * The y offsets depend on whether the object starts below or 
	 * above the starting point for the line being drawn.
	 */
	if (y <= obj_y) {
	    idx = obj_y - y;
	    imgy = 0;
	} else {
	    idx = 0;
	    imgy = y - obj_y;
	}

	/* Copy the object's pixel data. */
	for (; SCROLL_Y_DIM > idx && img->hdr.height > imgy; idx++, imgy++) {
	    pixel = img->img[xoff + img->hdr.width * imgy];

	    /* Don't copy transparent pixels. */
	    if (OBJ_CLR_TRANSP != pixel) {
		buf[idx] = pixel;
	    }
	}
    }
}


/* 
 * image_height
 *   DESCRIPTION: Get height of object image in pixels.
 *   INPUTS: im -- object image pointer
 *   OUTPUTS: none
 *   RETURN VALUE: height of object image im in pixels
 *   SIDE EFFECTS: none
 */
uint32_t 
image_height (const image_t* im)
{
    return im->hdr.height;
}


/* 
 * image_width
 *   DESCRIPTION: Get width of object image in pixels.
 *   INPUTS: im -- object image pointer
 *   OUTPUTS: none
 *   RETURN VALUE: width of object image im in pixels
 *   SIDE EFFECTS: none
 */
uint32_t 
image_width (const image_t* im)
{
    return im->hdr.width;
}

/* 
 * photo_height
 *   DESCRIPTION: Get height of room photo in pixels.
 *   INPUTS: p -- room photo pointer
 *   OUTPUTS: none
 *   RETURN VALUE: height of room photo p in pixels
 *   SIDE EFFECTS: none
 */
uint32_t 
photo_height (const photo_t* p)
{
    return p->hdr.height;
}


/* 
 * photo_width
 *   DESCRIPTION: Get width of room photo in pixels.
 *   INPUTS: p -- room photo pointer
 *   OUTPUTS: none
 *   RETURN VALUE: width of room photo p in pixels
 *   SIDE EFFECTS: none
 */
uint32_t 
photo_width (const photo_t* p)
{
    return p->hdr.width;
}


/* 
 * prep_room
 *   DESCRIPTION: Prepare a new room for display.  You might want to set
 *                up the VGA palette registers according to the color
 *                palette that you chose for this room.
 *   INPUTS: r -- pointer to the new room
 *   OUTPUTS: none
 *   RETURN VALUE: none
 *   SIDE EFFECTS: changes recorded cur_room for this file
 */
void
prep_room (const room_t* r)
{
    /* Record the current room. */
	photo_t *p = room_photo(r);
	fill_my_palette(p->palette);
    cur_room = r;
}


/* 
 * read_obj_image
 *   DESCRIPTION: Read size and pixel data in 2:2:2 RGB format from a
 *                photo file and create an image structure from it.
 *   INPUTS: fname -- file name for input
 *   OUTPUTS: none
 *   RETURN VALUE: pointer to newly allocated photo on success, or NULL
 *                 on failure
 *   SIDE EFFECTS: dynamically allocates memory for the image
 */
image_t*
read_obj_image (const char* fname)
{
    FILE*    in;		/* input file               */
    image_t* img = NULL;	/* image structure          */
    uint16_t x;			/* index over image columns */
    uint16_t y;			/* index over image rows    */
    uint8_t  pixel;		/* one pixel from the file  */

    /* 
     * Open the file, allocate the structure, read the header, do some
     * sanity checks on it, and allocate space to hold the image pixels.
     * If anything fails, clean up as necessary and return NULL.
     */
    if (NULL == (in = fopen (fname, "r+b")) ||
	NULL == (img = malloc (sizeof (*img))) ||
	NULL != (img->img = NULL) || /* false clause for initialization */
	1 != fread (&img->hdr, sizeof (img->hdr), 1, in) ||
	MAX_OBJECT_WIDTH < img->hdr.width ||
	MAX_OBJECT_HEIGHT < img->hdr.height ||
	NULL == (img->img = malloc 
		 (img->hdr.width * img->hdr.height * sizeof (img->img[0])))) {
	if (NULL != img) {
	    if (NULL != img->img) {
	        free (img->img);
	    }
	    free (img);
	}
	if (NULL != in) {
	    (void)fclose (in);
	}
	return NULL;
    }

    /* 
     * Loop over rows from bottom to top.  Note that the file is stored
     * in this order, whereas in memory we store the data in the reverse
     * order (top to bottom).
     */
    for (y = img->hdr.height; y-- > 0; ) {

	/* Loop over columns from left to right. */
	for (x = 0; img->hdr.width > x; x++) {

	    /* 
	     * Try to read one 8-bit pixel.  On failure, clean up and 
	     * return NULL.
	     */
	    if (1 != fread (&pixel, sizeof (pixel), 1, in)) {
		free (img->img);
		free (img);
	        (void)fclose (in);
		return NULL;
	    }

	    /* Store the pixel in the image data. */
	    img->img[img->hdr.width * y + x] = pixel;
	}
    }

    /* All done.  Return success. */
    (void)fclose (in);
    return img;
}


/* 
 * read_photo
 *   DESCRIPTION: Read size and pixel data in 5:6:5 RGB format from a
 *                photo file and create a photo structure from it.
 *                Code provided simply maps to 2:2:2 RGB.  You must
 *                replace this code with palette color selection, and
 *                must map the image pixels into the palette colors that
 *                you have defined.
 *   INPUTS: fname -- file name for input
 *   OUTPUTS: none
 *   RETURN VALUE: pointer to newly allocated photo on success, or NULL
 *                 on failure
 *   SIDE EFFECTS: dynamically allocates memory for the photo
 */
photo_t*
read_photo (const char* fname)
{
    FILE*    in;	/* input file               */
    photo_t* p = NULL;	/* photo structure          */
    uint16_t x;		/* index over image columns */
    uint16_t y;		/* index over image rows    */
    uint16_t pixel;	/* one pixel from the file  */
	uint32_t image_size;

    /* 
     * Open the file, allocate the structure, read the header, do some
     * sanity checks on it, and allocate space to hold the photo pixels.
     * If anything fails, clean up as necessary and return NULL.
     */
    if (NULL == (in = fopen (fname, "r+b")) ||
	NULL == (p = malloc (sizeof (*p))) ||
	NULL != (p->img = NULL) || /* false clause for initialization */
	1 != fread (&p->hdr, sizeof (p->hdr), 1, in) ||
	MAX_PHOTO_WIDTH < p->hdr.width ||
	MAX_PHOTO_HEIGHT < p->hdr.height ||
	NULL == (p->img = malloc 
		 (p->hdr.width * p->hdr.height * sizeof (p->img[0])))) {
	if (NULL != p) {
	    if (NULL != p->img) {
	        free (p->img);
	    }
	    free (p);
	}
	if (NULL != in) {
	    (void)fclose (in);
	}
	return NULL;
    }
	/*declare variables for the following codes*/
	image_size = p->hdr.width * p->hdr.height;
	struct octree_node level_2[OCTREE_LEVEL2_NODES_NUM];	//the 4th level of octree, has 8^4 nodes
	struct octree_node level_4[OCTREE_LEVEL4_NODES_NUM];	//the 4th level of octree, has 8^4 nodes
	/*have the same order of original level_4, keeps the position of the first 128 nodes in sorted level_4,
	* all the other places are -1*/
	int	new_position_of_level_4[OCTREE_LEVEL4_NODES_NUM];
	uint32_t	i;		//general index for looping
	uint32_t		red_average;	//used to caluate the average for red
	uint32_t		green_average;	//used to caluate the average for green	
	uint32_t		blue_average;	//used to caluate the average for blue
	uint16_t	pixels_array[image_size];	//recorded the photo pixels
	/*initialize some variables*/
	
	//intialize level_4 and new_position_of_level_4
	for(i = 0; i < OCTREE_LEVEL4_NODES_NUM; ++i)
	{
		level_4[i].idx_by_RGB = i;
		level_4[i].idx_in_level_2 = 100;
		level_4[i].red_sum = level_4[i].green_sum = level_4[i].blue_sum = 0;
		level_4[i].pixel_number = 0;
		level_4[i].palette_idx = -1;
		new_position_of_level_4[i] = -1;
	}
	
	//intialize level_2
	for(i = 0; i < OCTREE_LEVEL2_NODES_NUM; ++i)
	{
		level_2[i].idx_by_RGB = i;
		level_2[i].idx_in_level_2 = 100;
		level_2[i].red_sum = level_2[i].green_sum = level_2[i].blue_sum = 0;
		level_2[i].pixel_number = 0;
		level_2[i].palette_idx = -1;
		
	}
	
	/*first loop over file: map all the pixels into leverl4 array 
	 *and record the number of pixels in each node, also records their sum of RGB
	 *this loop also put the file into the pixels array*/
	
	/* 
     * Loop over rows from bottom to top.  Note that the file is stored
     * in this order, whereas in memory we store the data in the reverse
     * order (top to bottom).
     */
    for (y = p->hdr.height; y-- > 0; ) 
	{
		/* Loop over columns from left to right. */
		for (x = 0; p->hdr.width > x; x++) 
		{
	    /* 
	     * Try to read one 16-bit pixel.  On failure, clean up and 
	     * return NULL.
	     */
			if (1 != fread (&pixel, sizeof (pixel), 1, in)) 
			{
				free (p->img);
				free (p);
				(void)fclose (in);
				return NULL;
			}
			
		//put the pixel in pixels_array
		pixels_array[p->hdr.width * y + x] = pixel;
		
		//find the corrosponding level 4 node
		i = map_to_octree (pixel, 4);
		++level_4[i].pixel_number;
		level_4[i].idx_in_level_2 = map_to_octree(pixel, 2);
		level_4[i].red_sum += (pixel >> 11) & 0x001F;
		level_4[i].green_sum += (pixel >> 5) & 0x003F;
		level_4[i].blue_sum += pixel & 0x001F;
		level_4[i].idx_by_RGB = i;
		}
    }
	
    /* no need for the file anymore */
    (void)fclose (in);
	
	
	/*qsort the level 4 array to get the first 128 nodes, the reulst will be descending order*/
	qsort(level_4, OCTREE_LEVEL4_NODES_NUM, sizeof(struct octree_node), level_4_qsort_compare);
	
	
	/*for level 4 nodes, calculate the average color for first 128 nodes 
	 *and put the corrosponding value in palette and the palette index 
	 *and put their new position index to an array representing the old array*/
	unsigned int pixel_num;
	for(i = 0; i < OCTREE_LEVEL4_NODES_USED_NUM; ++i)
	{
		pixel_num = level_4[i].pixel_number;
		if(pixel_num)
		{
			red_average = level_4[i].red_sum / pixel_num;
			green_average = level_4[i].green_sum / pixel_num;
			blue_average = level_4[i].blue_sum / pixel_num;
		}
		else
		{
			red_average = green_average = blue_average = 0;
		}
		p->palette[i][0] = (uint8_t) (red_average & 0x1F) << 1;
		p->palette[i][1] = (uint8_t) (green_average & 0x3F);
		p->palette[i][2] = (uint8_t) (blue_average & 0x1F) << 1;
		level_4[i].palette_idx = PALETTE_USED + i;
		new_position_of_level_4[level_4[i].idx_by_RGB] = i;
	}
	
	uint16_t 	level_2_idx;
	/*goes through the rest of the level_4 and put it in level_2 
	 *and put their new position index to an array representing the old array*/
	for(i = OCTREE_LEVEL4_NODES_USED_NUM; i < OCTREE_LEVEL4_NODES_NUM; ++i)
	{
		level_2_idx = level_4[i].idx_in_level_2;
		if(level_2_idx < 64)
		{
			level_2[level_2_idx].red_sum += level_4[i].red_sum;
			level_2[level_2_idx].green_sum += level_4[i].green_sum;
			level_2[level_2_idx].blue_sum += level_4[i].blue_sum;
			level_2[level_2_idx].pixel_number += level_4[i].pixel_number;
		}
		new_position_of_level_4[level_4[i].idx_by_RGB] = i;
	}
		
	/*for level 2 nodes, calculate the average color for each node 
     *and put the corrosponding value in palette and the palette index */
	 for(i = 0; i < OCTREE_LEVEL2_NODES_NUM; ++i)
	{
		pixel_num = level_2[i].pixel_number;
		if(pixel_num)
		{
			red_average = level_2[i].red_sum / pixel_num;
			green_average = level_2[i].green_sum / pixel_num;
			blue_average = level_2[i].blue_sum / pixel_num;
		}
		else
		{
			red_average = green_average = blue_average = 0;
		}
		p->palette[i+OCTREE_LEVEL4_NODES_USED_NUM][0] = (uint8_t) (red_average & 0x1F) << 1;
		p->palette[i+OCTREE_LEVEL4_NODES_USED_NUM][1] = (uint8_t) (green_average & 0x3F);
		p->palette[i+OCTREE_LEVEL4_NODES_USED_NUM][2] = (uint8_t) (blue_average & 0x1F) << 1;
		level_2[i].palette_idx = PALETTE_USED + OCTREE_LEVEL4_NODES_USED_NUM + i;
	}

	/*goes again the nodes after first 128 in level_4, and find their palette_idx in level_2*/
	for(i = OCTREE_LEVEL4_NODES_USED_NUM; i < OCTREE_LEVEL4_NODES_NUM; ++i)
	{
		if(level_4[i].idx_in_level_2 < 64)
		{
			level_4[i].palette_idx = level_2[level_4[i].idx_in_level_2].palette_idx; 
		}		
	}
	
	/*loop over the pixels_array, and put the right value in image*/
	for(i = 0; i < image_size; ++i)
	 {
			p->img[i] = level_4[new_position_of_level_4[map_to_octree(pixels_array[i], 4)]].palette_idx;
	 }
	
    return p;
}


/*
 *map_to_octree
 *Description: helper function that convert the 16 bit RGB value to map to level 2 or level 4 nodes
 *				only takes the first x bits from each R,G,B and get them togeter
 *Input: pixel: the 16 bit pixel (5:6:5)  of RGB
 *		 level_number: 2 or 4, indicate which level of octree does the pixel map to
 *Output: None
 *Return Value: the position in array_2 or array_4, for array_2, it only occupies the last 6 bits
		  for array_4, it occupies the last 12 bits
 *Side Effects: None
 */
uint16_t map_to_octree (const uint16_t pixel, const uint8_t level_number)
{
	if(level_number != 2 && level_number != 4)
		return -1;
	uint16_t pixel_copy = pixel;
	if(level_number == 2)
	{
		return (((pixel_copy >> 14) << 4) | (((pixel_copy >> 9) & 0x3) << 2) | ((pixel_copy >> 3) & 0x3));
	}
	else
	{
		return (((pixel_copy >> 12) << 8) | (((pixel_copy >> 7) & 0x000F) << 4) | ((pixel_copy >> 1) & 0x000F));
	}	
}


/*
 *level_4_qsort_compare
 *Description: helper function that compare the number of pixels in two octree nodes
 *Input: general pointer a and b
 *Output: None
 *Return Value: > 0 if the element pointed by a goes after the element pointed by b
 *Side Effects: None
 */
int level_4_qsort_compare(const void *a, const void *b)
{
	const struct octree_node* octree_node_a = a;
	const struct octree_node* octree_node_b = b;
	return (octree_node_b->pixel_number - octree_node_a->pixel_number);
	
}
