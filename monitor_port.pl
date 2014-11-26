#!/usr/bin/env perl

 ($sec,$min,$hour,$mday,$mon,$year) = (localtime)[0..5];
 ($sec,$min,$hour,$mday,$mon,$year) = (
    sprintf("%02d", $sec),
    sprintf("%02d", $min),
    sprintf("%02d", $hour),
    sprintf("%02d", $mday),
    sprintf("%02d", $mon + 1),
    $year + 1900
);

$date="$year-$mon-$mday $hour:$min:$sec";



open (FH,"/opt/aimcpro/monitor/port.list") || die;
while (defined($port_tn=<FH>)) {
        ($host_ip,$mod_n,$port_t,$port_n)=split(/\t/,$port_tn);
	chomp $host_ip;
	chomp $mod_n;
	chomp $port_t;
	chomp $port_n;
	ch_result();
	}


sub ch_result {

    open LOG,">>/opt/aimcpro/monitor/port_status.log";
    select LOG;

    if($port_t eq 'tcp'){
       `/usr/bin/nc -z -w2 $host_ip $port_n`;
       $flag = `echo $?`;
    }else{
       `/usr/bin/nc -u -z -w2 $host_ip $port_n`;
       $flag = `echo $?`;
    }


    if($flag != 0){
        print "$date $host_ip $mod_n $port_t $port_n is closed!\n";
                
    }
    close(LOG);
}
   
