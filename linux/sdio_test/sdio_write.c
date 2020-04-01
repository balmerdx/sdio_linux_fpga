#include <stdint.h>
#include <stdio.h>
#include <fcntl.h> 
#include <termios.h>
#include <unistd.h>
#include <errno.h>

const char* device_name = "/dev/balmerSDIO0";

#include "time_utils.h"

int main(void)
{
   	int fd;
	
	printf("SDIO Port Write\n");

	fd = open(device_name,O_RDWR);
	if(fd == -1)						/* Error Checking */
		printf("  Error! in Opening %s  \n", device_name);
	else
		printf("  %s Opened Successfully \n", device_name);

	static char write_buffer[4096];
	int  bytes_write = 0;
	int i = 0;
	for(i=0;i<sizeof(write_buffer); i++)
	{
		if(i&1)
			write_buffer[i] = i>>8;
		else
			write_buffer[i] = i;
	}

	//msleep(100);

	uint64_t start_usec = TimeUsec();
	bytes_write = write(fd, write_buffer, sizeof(write_buffer));
	uint64_t end_usec = TimeUsec();
	printf("Delta tume %i usec\n", (int)(end_usec-start_usec));
	printf("Bytes write=%d\n", bytes_write);
	close(fd);

	return 0;
}


