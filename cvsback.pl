#!/usr/bin/env perl
use strict;
use Log::Log4perl qw(:easy);
use File::Basename;
use POSIX qw(strftime);
use Digest::MD5;
use IO::File;
use File::Find;
use threads;
use Thread::Queue;
use File::Rsync;
use Mail::Sender;


my 	$srcFile=shift @ARGV;
my 	($logger,$file_md5,$currentTime,$logFile,$Msg,$Subject);			
my 	$thread_max=10;
my 	$remotehost='rsynclansgg@10.20.xx.xx::backup';
   	$currentTime=strftime("%Y%m%d%H%M", localtime(time));
	$logFile="$currentTime.log";		   

#define mail subject
$Subject = "gitback notify";

#md5 by currentTime
my 	$ctx = Digest::MD5->new;
	$ctx->add($currentTime);
my 	$currentTimeMD5 = $ctx->hexdigest;

#define logger config
my $log_logger = get_logger();
$log_logger->level($INFO);   

# Appenders  
my $file_appender = Log::Log4perl::Appender->new(  
					"Log::Dispatch::File",
					filename => "$logFile",  
					mode     => "append",
					);
my $stdout_appender =  Log::Log4perl::Appender->new(
                        		"Log::Log4perl::Appender::Screen",
                        		name	=> "screenlog",
                        		stderr    => 1
					);
$log_logger->add_appender($file_appender);  
$log_logger->add_appender($stdout_appender);
  
# Layouts  
my $layout =  Log::Log4perl::Layout::PatternLayout->new(  
                  "%d %p > %F{1}:%L %M -- %m%n"
                  );                    

$file_appender->layout($layout);
$stdout_appender->layout($layout);

#Sender
my $send_user='xx@.com';
#passwd for Sender
my $send_user_pw='xxx';
#smtp address
my $smtp_server='smtp.xxx.com';
#address
my @address=qw(xx@.com yy@.com);

#create file queue
my $fileSplitQueue = Thread::Queue->new();
my $fileAesQueue = Thread::Queue->new();

main();

sub main {
	Usage() unless (defined($srcFile) );
	$log_logger->info("Begin:$currentTime");
	my $srcFilePath = file_md5sum($srcFile);
	splitFile($srcFile);
	find(\&findSplitFile,$srcFilePath);	
	SplitQueueThread();
	find(\&findAesFile,$srcFilePath);
	fileAesQueueThread();	
	checklog($logFile);
	for my $addr (@address){
		sendMail($addr);
	}

	$currentTime=strftime("%Y%m%d%H%M", localtime(time));
	$log_logger->info("End:$currentTime");
}

#md5sum
sub file_md5sum {
		my $file = shift;
		my $file_md5sum = `md5sum $file`;
		my $md5sum_command = ` echo $? `;
		my ($fileName,$filePath) = fileparse($file);
		if ($md5sum_command != 0) {
				my $file_md5 = "system command maybe exec fail, command result code is $md5sum_command";
				my $log = "srcfile:$file  file_md5sum:$file_md5sum";
				   $Msg = "srcfile:$file  file_md5sum:$file_md5\n";
				$log_logger->warn($log); 

		} else {
				my ($file_md5) = split(/ /, $file_md5sum);
				my $log = "srcfile:$file file_md5sum:$file_md5";
			       	   $Msg = "srcfile:$file file_md5sum:$file_md5\n";		
				   $log_logger->info($log); 		
		}		
		return $filePath;
}

#split file
sub splitFile {
	 my $srcFile = shift;
	 my ($fileName,$filePath) = fileparse($srcFile);
	 my $split_command =`split -b 5G $srcFile -d -a 3 $srcFile.`;
	    $split_command = `echo $? `;
	if ($split_command == 0 ){
			my $splitFileCode = 'success';
			$log_logger->info(" srcFile:$srcFile  desc:$splitFileCode splitFileResult:$split_command"); 

	}else{
			my $splitFileCode = 'fail';
			$log_logger->warn(" srcFile:$srcFile  desc:$splitFileCode splitFileResult:$split_command"); 
		}
}

sub findSplitFile {
		if ( $_ =~ /$srcFile\.\d{3}$/) {
			$fileSplitQueue->enqueue($File::Find::name);
			$log_logger->info("fileSplitQueue enqueue : $File::Find::name"); 
		}
}

sub SplitQueueThread {
	while ( $fileSplitQueue->pending() ){	
		if (scalar threads->list() < $thread_max) {		
		my $readQueue = $fileSplitQueue->dequeue();
		$log_logger->info("fileSplitQueue dequeue : $readQueue ");     	
		threads->create(\&encryptAES,$readQueue); 
		
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

sub encryptAES {
		my $file = shift;
		my $cmd_result = `openssl enc -aes-128-cbc -a -salt -in $file  -out $file.$currentTime.aes -pass pass:$currentTimeMD5`;
		my $flag = `echo $?`; 
		if ($flag == 0){
			$log_logger->info("encryptAES file:$file encrypt success");
		}else{
			$log_logger->warn("encryptAES file:$file encrypt fail"); 
		}		
}

sub findAesFile {
		if ( $_ =~ /$srcFile\.\d{3}\.$currentTime\.aes$/) {
			$fileAesQueue->enqueue($File::Find::name);
			$log_logger->info("fileAesQueue enqueue:$File::Find::name"); 
	}
}

sub fileAesQueueThread {
	while ($fileAesQueue->pending()){
			if (scalar threads->list() < $thread_max) {	
			my $readQueue = $fileAesQueue->dequeue(); 
			$log_logger->info("fileAesQueue dequeue : $readQueue  ");       
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
 
$obj->exec( { src => "$file", dest => $remotehost } ) or warn ($log_logger->warn("rsync: $file to $remotehost fail!" ));
my $rval = $obj->status;
if ($rval == 0 ) {
	$log_logger->info("rsync: $file to $remotehost Success!\n");
}
	#print $obj->out;
}

sub checklog {
	my $logFile=shift;
	my $read_fh  = IO::File->new( $logFile, 'r' ) or warn "open file fail $!"; 	
	while (<$read_fh>) {
		if (/fail/) {
			$Msg = "$Msg$_";
			}
		}
		$Msg = "message :\nCurrentTime is  $currentTime\n$Msg";
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

