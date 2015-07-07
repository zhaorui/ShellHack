//subst <file> <old> <new>
#define _POSIX_C_SOURCE 200809L
#define BUFFER_LEN 4096

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    char buffer[4096]; // change the 4096

    const char* file = argv[1];
    const char* old = argv[2];
    const char* new = argv[3];
    int fd;
    if ((fd = open(file, O_RDWR|O_APPEND)) < 0){
        perror("open failed");
        exit(1);
    }

    //while(read(file, buffer, 4096)>0){
    //    
    //}

    write(fd, "hellworld", 9);

    close(fd);
    return 0;
}
