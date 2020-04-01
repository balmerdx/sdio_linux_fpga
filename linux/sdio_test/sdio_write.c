#include <stdint.h>
#include <stdio.h>
#include <fcntl.h> 
#include <termios.h>
#include <unistd.h>
#include <errno.h>
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

uint64_t TimeUsec()
{
	struct timespec ts;
	timespec_get(&ts, TIME_UTC);
    return ts.tv_sec*(uint64_t)1000000+ts.tv_nsec/1000;
}

int main(void)
{
   	int fd;
	
	printf("\n +----------------------------------+");
	printf("\n |         SDIO Port Read           |");
	printf("\n +----------------------------------+");

	fd = open(device_name,O_RDWR);
	if(fd == -1)						/* Error Checking */
		printf("\n  Error! in Opening %s  ", device_name);
	else
		printf("\n  %s Opened Successfully ", device_name);

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

	printf("\n  Before write addr=%x\n", (unsigned int)write_buffer);
	//msleep(100);

	uint64_t start_usec = TimeUsec();
	bytes_write = write(fd, write_buffer, sizeof(write_buffer));
	uint64_t end_usec = TimeUsec();
	printf("\n  Delta tume %i usec\n", (int)(end_usec-start_usec));
		
	printf("\n\n  Bytes write=%d", bytes_write);
	printf("\n\n  ");
	close(fd);

	return 0;
}


