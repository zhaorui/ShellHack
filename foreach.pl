#!/usr/bin/perl

foreach my $user (glob("/Users/*"))
{
    if (-f $user)
    {
        next;
    }
    print $user,"\n";

}

$TRUE = 1;
$FALSE = 0;

print "This should print 'true': ";
$TRUE ? print "true\n" : print "false\n";

print "This should print 'false': ";
$FALSE ? print "true\n" : print "false\n";

#$TRUE ? chown(50, 50, "/Users/test") : 2 ;

my $yn=0;

$yn?chown(50, 50, "/Users/test")
   :chown(100, 100, "/Users/test");
