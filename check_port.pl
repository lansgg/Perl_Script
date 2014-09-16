#!/usr/bin/env perl
#############################
#FILENAME: check_port.pl
#FUNCTION: check host opened port
############################
use strict;
use warnings;
use Getopt::Std;
use vars qw($opt_H $opt_p $opt_t $opt_h);
getopts('H:p:t:h');
my($hostname,$port,$type,$output,$back,$help);
my %re;
$re{ok} = 0;
$re{crit} = 2;
my $flag;


&main();

sub main {
    get_args();
    check_result();
    warning();
}

sub check_result {
    if($type eq 'tcp'){
       `/usr/bin/nc -z -w2 $hostname $port`;
       $flag = `echo $?`;
    }else{
       `/usr/bin/nc -u -z -w2 $hostname $port`;
       $flag = `echo $?`;
    }
    if($flag == 0){
       $output = "OK: $hostname $type port $port is opened!";
       $back = $re{ok};
    }else{
       $output = "check $hostname $type port $port failed!";
       $back = $re{crit};
    }
}
sub warning {
    print "$output\n";
    exit $back;
}
sub get_args {
    $hostname = $opt_H if $opt_H;
    $port = $opt_p if $opt_p;
    $type = $opt_t if $opt_t;
    &Usage() if(!defined($hostname) || !defined($port) || !defined($type));
}

sub Usage {
    print <<"END";
    ./check_port.pl -H <hostname> -p <port> -t <protocol type[tcp|udp]> -h <help>
END
   exit 2;
}
##################### END #########################
