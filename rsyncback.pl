#!/usr/bin/env perl
use strict;
use threads;
use Thread::Queue;
use File::Rsync;
use threads::shared;
use File::Find;
use File::Basename;
use POSIX qw(strftime);
use Log::Log4perl qw(:easy);
use Mail::Sender;

my ($logger,$Msg,$Subject,$filename);

my %splitFileMd5 = (); 
   share(%splitFileMd5);
my %remoteFileMd5 = (); 
   share(%remoteFileMd5);
 
##### src file #######
my $srcFile = shift @ARGV;
my ($fileName,$filePath) = fileparse($srcFile);

######### remote host rsync config ##################
my $remotehost = 'lansgg@192.168.85.129::gitbackup';
my $remotehostdir='/opt/gitbackup/';

######## max threads count##############
my $thread_max = 10;
########## current time #############
my $currentTime = strftime("%Y%m%d%H%M", localtime(time));
########## log file ##############
my $logFile = "$currentTime.log";

my $splitFileQueue = Thread::Queue->new();
my $remotefileQueue = Thread::Queue->new();
my $remotefilemd5Queue = Thread::Queue->new();

############## define smtp ######################
#Sender
my $send_user='18601337852@wo.cn';
#passwd for Sender
my $send_user_pw='123qwe';
#smtp address
my $smtp_server='smtp.wo.cn';
#define mail subject
$Subject = "back notify";
#address
my @address=qw(18601337852@wo.cn);
#################################################

################### define log conf #########################
my $log_logger = get_logger();
   $log_logger->level($INFO); 
   
my $file_appender = Log::Log4perl::Appender->new(  
					"Log::Dispatch::File",
					filename => "$logFile",  
					mode     => "append",
					);
					
   $log_logger->add_appender($file_appender); 
#my $layout =  Log::Log4perl::Layout::PatternLayout->new(  
#                  "%d %p > %F{1}:%L %M -- %m%n"
#                  );                    
my $layout =  Log::Log4perl::Layout::PatternLayout->new(  
                  "%d %p > %F{1} %M -- %m%n"
                  );  

$file_appender->layout($layout);
 
###################################################
main();

sub main {
	$log_logger->info("Begin:$currentTime");
	srcFileMd5($srcFile);
	splitFile($srcFile);
	find(\&findSplitFile,$filePath);
	splitFileMd5Thread();
	rsyncThread();
	remoteFile_md5sumThread();
	
	for my $splitFileMd5key ( keys %splitFileMd5) {
 	 unless ( exists $remoteFileMd5{$splitFileMd5key} ) {
			$log_logger->warn("compare:remoteFileMd5keyNoexists  splitFileMd5:$splitFileMd5key"); 
 	 }
  	if ( $splitFileMd5{$splitFileMd5key} eq $remoteFileMd5{$splitFileMd5key} ) {
  			$log_logger->info("compare: splitFileMd5:$splitFileMd5key($splitFileMd5{$splitFileMd5key}) vs remoteFileMd5:$splitFileMd5key($remoteFileMd5{$splitFileMd5key})"); 	
  	} 
  	else {
  			$log_logger->warn("compare:fail splitFileMd5:$splitFileMd5key($splitFileMd5{$splitFileMd5key}) vs remoteFileMd5:$splitFileMd5key($remoteFileMd5{$splitFileMd5key})"); 
 	 	}
	}	 
	checklog($logFile);
	for my $addr (@address){
		sendMail($addr);
	}	
}
	
sub findSplitFile {
		if ( $_ =~ /$fileName\.\d{3}$/) {
			$log_logger->info("splitFileQueue enqueue : $_"); 
			$splitFileQueue->enqueue($_);
			$log_logger->info("remotefileQueue enqueue : $_"); 			
			$remotefileQueue->enqueue($_);
			$log_logger->info("remotefilemd5Queue enqueue : $_"); 			
#			$remotefilemd5Queue->enqueue($File::Find::name);
			$remotefilemd5Queue->enqueue($_);
		}
}

sub splitFileMd5Thread {
	while($splitFileQueue->pending()) {
		my $Queue = $splitFileQueue->dequeue();
		splitFileMd5($Queue);
	}
}

sub srcFileMd5 {
	my $file=shift;
	my $md5_command=`md5sum $file`;
	my $flag=`echo $?`;
	if ($flag == 0) {
		my ($file_md5,$filename) = split(/\s+/,$md5_command);
		my $log = "srcfile:$file  file_md5sum:$file_md5";
     	   $Msg = "srcfile:$file  file_md5sum:$file_md5\n";
		   print "filename is $filename , md5 is $file_md5\n";	
		   $log_logger->info($log);
	}else {
		my $file_md5 = "system command maybe exec fail, command result code is $md5_command";
		my $log = "srcfile:$file  file_md5sum:$file_md5";
		   $Msg = "srcfile:$file  file_md5sum:$file_md5\n";
		   $log_logger->warn($log);					
	}
}

sub splitFileMd5 {
	my $file=shift;
	my $md5_command=`md5sum $filePath$file`;
	my $flag=`echo $?`;
	if ($flag == 0) {
		my ($file_md5,$filename) = split(/\s+/,$md5_command);
		my $log = "file:$file  file_md5sum:$file_md5";
		   print "filename is $filename , md5 is $file_md5\n";
		   $splitFileMd5{$file}=$file_md5;
	       $log_logger->info($log);
		
	}
}

sub splitFile {
		 my $srcFile = shift;
		 my $split_command =`split -b 20M $srcFile -d -a 3 $srcFile.`;
		    $split_command = `echo $? `;
		if ($split_command == 0 ){
				my $splitFileCode = 'success';
				$log_logger->info(" srcFile:$srcFile  desc:$splitFileCode splitFileResult:$split_command"); 
	
		}else{
				my $splitFileCode = 'fail';
				$log_logger->warn(" srcFile:$srcFile  desc:$splitFileCode splitFileResult:$split_command"); 
			}
}

sub rsyncThread {
	while ( $remotefileQueue->pending() ){	
		if (scalar threads->list() < $thread_max) {		
			my $readQueue = $remotefileQueue->dequeue();
			print "remotefileQueue dequeue : $readQueue\n";
			$log_logger->info("remotefileQueue dequeue : $readQueue "); 
			threads->create(\&rsync,$readQueue);
	}
	foreach my $thread (threads->list(threads::all)){			
				if ($thread->is_joinable()){
					$thread->join();			
			}	
		}
	}
	foreach my $thread ( threads->list(threads::all) ) {
		$thread->join();
	}	 
	
}

sub remoteFile_md5sumThread {
	while ( $remotefilemd5Queue->pending() ){	
		if (scalar threads->list() < $thread_max) {		
			my $readQueue = $remotefilemd5Queue->dequeue();
			print "remotefileQueue dequeue : $readQueue\n";
			$log_logger->info("remotefileQueue dequeue : $readQueue "); 
			threads->create(\&remoteFile_md5sum,$readQueue);
	}
	foreach my $thread (threads->list(threads::all)){			
				if ($thread->is_joinable()){
					$thread->join();			
			}	
		}
	}
	foreach my $thread ( threads->list(threads::all) ) {
		$thread->join();
	}	 
	
}

sub remoteFile_md5sum {
		my $file=shift;
		my $filePath = shift;
		my ($file_md5,$filename);	
		my @ancresult=`ansible all -m shell -a "md5sum $remotehostdir$file"`;
		my $flag = `echo $?`;
		if ($flag == 0 ) {
				my ($file_md5,$filename)=split(/\s+/,$ancresult[1]);
				my $log = "file:$filename file_md5sum:$file_md5";
				   $remoteFileMd5{$file} = $file_md5;	
			       $log_logger->info($log); 				
		}else{
				my $file_md5sum = " ansible command exec fail, command code : @ancresult";
				my $log = "file:$file file_md5sum:$file_md5sum";
				   $log_logger->warn($log);			
				
		}
}	

sub rsync {
		my $file = shift;
		my $obj = File::Rsync->new(
		{
		archive    => 1,
		compress => 1,
		checksum => 1,
		recursive => 1,
		owner => 1,
		devices => 1,
		group => 1,
		perms => 1,
		times => 1,
	    verbose => 1,
		timeout => 300,
		progress => 1,
		stats => 1,
		links => 1,
	   'hard-links' => 1,
	   'ignore-times' => 1,
	   'password-file' => './rsync.pass',
		}
);
 
$obj->exec( { src => "$filePath$file", dest => $remotehost } ) or warn ($log_logger->warn("rsync: $file to $remotehost fail!" ));
my $rval = $obj->status;
if ($rval == 0 ) {
	$log_logger->info("rsync: $file to $remotehost Success!\n");
	}
#	print $obj->out;
}

sub checklog {
	my $logFile=shift;
	my $read_fh  = IO::File->new( $logFile, 'r' ) or warn  ($log_logger->warn("checklog: open file  $logFile fail!" ));
	while (<$read_fh>) {
		if (/fail/) {
			$Msg = "$Msg$_";
			}
		}
		$Msg = "message :\nCurrentTime:$currentTime\n$Msg";
		$log_logger->info($Msg);		
	}
	
sub sendMail {
	my $CONTACTEMAIL = shift;
 	my $sender = new Mail::Sender{
	   ctype => 'text/plain; charset=utf-8',
	   encoding => 'utf-8',    
 	}; 
#die "Error in mailing : $Mail::Sender::Error\n" unless ref $sender;

if ($sender->MailMsg({
   	smtp => $smtp_server ,
   	from => $send_user,
   	to => $CONTACTEMAIL,
   	subject => $Subject,
   	msg => $Msg,
   	auth => 'LOGIN', 
   	authid => $send_user,
   	authpwd => $send_user_pw,
   	charset=>'utf-8'
 	}) < 0) {
   	warn "$Mail::Sender::Error\n";
   	return 1;
 	}else{
	$sender->Close();
	#print "$send_user to $CONTACTEMAIL smtp Success Subject : $Subject\n";
	return 0;
	}
}

sub Usage {
    print <<"END";
    perl cvsback.pl filename
END
   exit 2;
}

	