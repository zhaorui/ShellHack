Compress Tool and Skills
========================

Zip
---
 * Biggest advantage:  avaliable on all operating system
 * Downside:           does not offer the best level of compression, tar.gz and tar.bz2 is the best.
 * Usage:
    #Conpress a directory with zip
    zip -r archive.zip directory
    #Extract a zip archive
    unzip archive.zip

TAR
---
Its probably the Linux/UNIX version of zip - quick and dirty, only consumes very little time and CPU to compress.
 * Usage:
    #Compress a directory
    tar -cvf archive dirctory
    #Extract a tar archive
    tar -xvf archive.tar [-C spcific directory]

TAR.GZ
------
my weapon of choice for most compression.
Usage:
    #Compress
    tar -zcvf archive.tar.gz directory
    #Extract
    tar -zxvf archive.tar.gz

TAR.BZ2
-------
This format has the best level of compression among all of the fomats mentioned above.
But this comes at a cost - in time and in CPU.
    #Compress
    tar -jcvf archive.tar.bz2 directory
    #Extract
    tar -jxvf archive.tar.bz2

