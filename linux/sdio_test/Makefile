CC=arm-linux-gnueabihf-gcc -Wall -pedantic -std=gnu11 -O3
#CC=gcc -Wall -pedantic -std=c11 -O3

read: sdio_read.c
	${CC} $< -o $@


write: sdio_write.c
	${CC} $< -o $@
