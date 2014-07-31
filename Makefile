#Makefile Template for Play Ground of Code

CC= gcc
CXX= g++
CFLAGS= 
CXXFLAGS= 
LDFLAGS= 

#Add the target binary here
Progs= 

all: $(Progs)

#Add the target object file here, for instace
#test.o: test.c

clean:
    rm -rf *.o $(Progs)
