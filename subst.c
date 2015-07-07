//subst <file> <old> <new>
#define _POSIX_C_SOURCE 200809L
#define BUFFER_LEN 4096
#define MAX_LINE   1024
#define FILE_MODE   (S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

int main(int argc, char **argv)
{
    int fd, newfd;
    const char* file = argv[1];
    char* old = (char*)malloc(strlen(argv[2])+1);
    char* new = (char*)malloc(strlen(argv[3])+1);
    int newfile_len = strlen(file)+strlen(".in");
    char* newfile = (char *)malloc(newfile_len+1);
    snprintf(newfile, newfile_len+1, "%s.in", file);

    FILE *fp = fopen(file, "r+");
    if(!fp){
        perror("fopen failed");
        exit(1);
    }

    if ((newfd = open(newfile, O_CREAT|O_EXCL|O_APPEND, FILE_MODE)) < 0){
        perror("open newfile failed");
        exit(1);
    }

    char* line = NULL;
    size_t line_len = 0;
    while (getline(&line, &line_len, fp) != -1){
        printf("get the line: %s", line);
        if (line[line_len-1] == '\n'){
            
        }
        if ( line_len == strlen(old) && strncmp(line, old, line_len) == 0){
            write(newfd, new, strlen(new));
            if(line)
        }
        else
            write(newfd, line, strlen(line));
    }

    free(line);
    close(fd);
    close(newfd);

    char cmd[MAX_LINE];
    //snprintf(cmd, MAX_LINE, "mv %s %s", file, newfile);
    //system(cmd);
    free(newfile);
    return 0;
}
