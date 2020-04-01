#include <stdio.h>
#include <fcntl.h> 
#include <termios.h>
#include <unistd.h> 
#include <errno.h>

#include "time_utils.h"

const char* device_name = "/dev/balmerSDIO0";

int main(void)
{
   	int fd;/*File Descriptor*/
	
	printf("SDIO Port Read\n");

	fd = open(device_name,O_RDWR);
	if(fd == -1)
		printf("  Error! in Opening %s\n", device_name);
	else
		printf("  %s Opened Successfully\n", device_name);



	static uint8_t read_buffer[4096];
	int  bytes_read = 0;
	int i = 0;

	//msleep(100);
	uint64_t start_usec = TimeUsec();
	bytes_read = read(fd, read_buffer, sizeof(read_buffer));
	uint64_t end_usec = TimeUsec();
	printf("  Delta tume %i usec\n", (int)(end_usec-start_usec));
	printf("  Bytes received %d\n", bytes_read);

	//for(i=0;i<bytes_read;i++)
	//    printf("%x,", (int)read_buffer[i]);

	printf("\n");
	close(fd);

	return 0;
}


