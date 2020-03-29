#include <stdio.h>
#include <fcntl.h>   /* File Control Definitions           */
#include <termios.h> /* POSIX Terminal Control Definitions */
#include <unistd.h>  /* UNIX Standard Definitions 	   */ 
#include <errno.h>   /* ERROR Number Definitions           */
#include <time.h>

const char* device_name = "/dev/balmerSDIO0";

int msleep(long msec)
{
    struct timespec ts;
    int res;

    if (msec < 0)
    {
        errno = EINVAL;
        return -1;
    }

    ts.tv_sec = msec / 1000;
    ts.tv_nsec = (msec % 1000) * 1000000;

    do {
        res = nanosleep(&ts, &ts);
    } while (res && errno == EINTR);

    return res;
}

int main(void)
{
   	int fd;/*File Descriptor*/
	
	printf("\n +----------------------------------+");
	printf("\n |         SDIO Port Read           |");
	printf("\n +----------------------------------+");

	/*------------------------------- Opening the Serial Port -------------------------------*/

	/* Change /dev/ttyUSB0 to the one corresponding to your system */

	fd = open(device_name,O_RDWR);
	if(fd == -1)						/* Error Checking */
    	   printf("\n  Error! in Opening %s  ", device_name);
	else
    	   printf("\n  %s Opened Successfully ", device_name);



	/*------------------------------- Read data from serial port -----------------------------*/
	static char read_buffer[32];   // Buffer to store the data received
	int  bytes_read = 0;    /* Number of bytes read by the read() system call */
	int i = 0;

	printf("\n  Before read addr=%x\n", (unsigned int)read_buffer);
	printf("\n  Before read addr=%x\n", (unsigned int)read_buffer);
	msleep(100);
	bytes_read = read(fd, read_buffer, 32); // Read the data
	printf("\n  After read\n");
		
	printf("\n\n  Bytes Rxed -%d", bytes_read); /* Print the number of bytes read */
	printf("\n\n  ");

	for(i=0;i<bytes_read;i++)	 //printing only the received characters
	    printf("%x",(int)read_buffer[i]);

	printf("\n +----------------------------------+\n\n\n");

	close(fd);

	return 0;
}


