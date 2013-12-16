#!/usr/bin/perl

#my $user = $ARGV[0];

my $uid = $ARGV[0];
my $gid = $ARGV[1];
my $name = $ARGV[2];

if(!($uid =~ /^[0-9]+$/) || !($gid =~ /^[0-9]+$/) || !defined($name))
{
    print "NOT USER\n";
}
else
{
    print "IS USER\n";
}

print "\n\n\n";
if(!($uid =~ /^[0-9]+$/) || !($gid =~ /^[0-9]+$/) || !defined($name))
{
    print "$uid is not uid\n";
    print "$gid is not gid\n";
    print "$name is not name\n";
}
else
{
    print "$uid is uid\n";
    print "$gid is gid\n";
    print "$name is name\n";
}

#sub IsNetworkUser($)
#{
#    my $user = $_[0];
#    if(!defined($user))
#    {
#        return 0;
#    }
#    system "adquery user $user > /dev/null 2>&1";
#    return !$?;
#}

#if (!IsNetworkUser($user))
#{
#    print "$user is not network user. \n";
#}
#else
#{
#    print "$user is network user. \n";
#}
#

#foreach my $user (glob("/Users/*"))
#{
#    if (-f $user)
#    {
#        next;
#    }
#    print $user,"\n";
#
#}
#
#$TRUE = 1;
#$FALSE = 0;
#
#print "This should print 'true': ";
#$TRUE ? print "true\n" : print "false\n";
#
#print "This should print 'false': ";
#$FALSE ? print "true\n" : print "false\n";
#
##$TRUE ? chown(50, 50, "/Users/test") : 2 ;
#
#my $yn=0;
#
#$yn?chown(50, 50, "/Users/test")
#   :chown(100, 100, "/Users/test");
