#!/usr/bin/perl -w

my $H=0;
my $M=0;
my $S=-6;
my $MILS=0;

sub fixtime($)
{
    my ($HMS, $ms) = split /,/, $_[0];
    my ($hour, $min, $sec) = split /:/, $HMS;
    my $t1 = (($H*60+$M)*60+$S)*1000+$MILS;
    my $t2 = (($hour*60+$min)*60+$sec)*1000+$ms;
    my $result = $t2 + $t1;
    if ($result < 0){
        print "time pont isn't exist!!\n";
        $result = 0;
    }
    $ms = $result%1000;
    $sec = ($result/1000)%60;
    $min = ($result/1000/60)%60;
    $hour = int($result/1000/60/60);
    
    $_[0] = "$hour:$min:$sec,$ms";
}

my $srt="/tmp/test.srt";
my $newsrt="/tmp/newtest.srt";

if (! open SRT, "$srt"){
    die "Not found the srt file";
}

if (! open NEWSRT, ">$newsrt"){
    die "could not create $srt";
}

while (<SRT>){
    if (/\r\n$/){
        #fixing the MS line-ending issue
        s/\r\n$/\n/;
    }
    print NEWSRT "$_";
    if (/^\d+$/){
       my $timeline = <SRT>;
       my ($from, $to) = split /-->/, $timeline;
       fixtime($from);
       fixtime($to);
       print NEWSRT "$from --> $to\n";
    }
}
