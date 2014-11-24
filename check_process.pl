#!/usr/bin/perl
#Author Aries
#Testing processes
###
use strict;
use warnings;

use Net::SNMP;

## ============================================================

my $BK_OK = 0;
my $BK_WARNING = 1;
my $BK_CRITICAL = 2;
my $BK_UNKOWN = 3;

## ============================================================

my $host_name = "";
my $community = "public";
my $warning = 20;
my $critical = 25;
my $proc_name = "";

while (defined(my $arg = shift)) {
    if ($arg eq "-c") {
        $critical = shift;
        next;
    }elsif ($arg eq "-w") {
        $warning = shift;
        next;
    }elsif ($arg eq "-C") {
        $community = shift;
        next;
    }elsif ($arg eq "-H") {
        $host_name = shift;
        next;
    }elsif ($arg eq "-h") {
        &print_help();
        exit $BK_CRITICAL;
    }elsif ($arg eq "-p") {
        $proc_name = shift;
        next;
    }else {
        next;
    }
}

if ($host_name eq "") {
    print "Host missed!";
    exit $BK_UNKOWN;
}

if ($proc_name eq "") {
    print "Proc missed!";
    exit $BK_UNKOWN;
}

## ==============================================================

my $oid_runtime = ".1.3.6.1.2.1.25.4.2.1.2";

my ($session, $error) = Net::SNMP->session(-hostname => $host_name, -community => $community, -version => 2);
if (!defined($session)) {
    print("UNKNOWN: SNMP Session : $error\n");
    exit $BK_UNKOWN;
}

my $result = $session->get_table(Baseoid => $oid_runtime);
if (!defined($result)) {
    my $temp=$session->error;
    $temp =~ s/'//g;
    printf("UNKNOWN: %s.\n", $temp);
    $session->close;
    exit $BK_UNKOWN;
}

## ==============================================================

my $count_proc = 0;
foreach my $key (keys %$result) {
    $count_proc++ if ($result->{$key} eq "$proc_name");
}

$session->close;

## ==============================================================

if ($critical > $warning) {
    if ($count_proc > $critical) {
        print "Critical: Count of process $proc_name is $count_proc\n";
        exit $BK_CRITICAL;
    }elsif ($count_proc >= $warning) {
        print "Warning: Count of process $proc_name is $count_proc\n";
        exit $BK_WARNING;
    }else {
        print "OK: Count of process $proc_name is $count_proc\n";
        exit $BK_OK;
    }
}else {
    # C <= W
    if ($count_proc < $critical) {
        print "Critical: Count of process $proc_name is $count_proc\n";
        exit $BK_CRITICAL;
    }elsif ($count_proc < $warning) {
        print "Warning: Count of process $proc_name is $count_proc\n";
        exit $BK_WARNING;
    }else {
        print "OK: Count of process $proc_name is $count_proc\n";
        exit $BK_OK;
    }
}

## ==============================================================

sub print_help {
    print "usage: check_process.pl -H [hostname or ip] -C [snmp community] -w [warning counts] -c [CRITICAL counts] -p [process name]\n";
}
