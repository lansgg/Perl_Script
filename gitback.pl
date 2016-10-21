#!/usr/bin/env perl
################
#filename: gitback.pl
#version : 1.0
#author : zzq
#date : 20160705
#function: The transmission of gitlab backup files to the remote host
#########################

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

my ($logger,$Msg,$Subject,$filename,$srcFile,$fileName,$filePath,$fileSize,$backFilename);
my $fileCount;
my $filemsg;
my $message;
 
######### remote host rsync config ##################
my $remotehost = 'rsync@10.xx.x.x::gitbackup';

############# back file dir ###############
my $backFiledir = '/data/gitbackups/';

######## max threads count##############
my $thread_max = 10;

########## current time #############
my $currentTime = strftime("%Y%m%d%H%M", localtime(time));
$Msg = "$currentTime\n";

########## log file ##############
my $logFile = "gitback.log";

my $splitFileQueue = Thread::Queue->new();
my $remotefileQueue = Thread::Queue->new();

############## define smtp ######################
#Sender
my $send_user='monitor@cc.com.cn';
#passwd for Sender
#my $send_user_pw='123';
#smtp address
my $smtp_server='10.xx.xx.x';
#define mail subject
$Subject = "git-m6-$currentTime";
#address
my @address=qw(ff@cc.com.cn);

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
               
my $layout =  Log::Log4perl::Layout::PatternLayout->new(  
                  "%d %p > %F{1} %M -- %m%n"
                  );  

$file_appender->layout($layout);
###################################################
main();

sub main {
	Usage() unless ( scalar(@ARGV) == 0);
	$log_logger->info("Begin:$currentTime");
	$srcFile = backup();
	print "srcFile is $srcFile\n";
	($fileName,$filePath) = fileparse($srcFile) if (-f $srcFile);
	$fileSize=(stat $srcFile)[7];
	srcFileMd5($srcFile);
	splitFile($srcFile);
	find(\&findSplitFile,$filePath);
	$fileCount = $splitFileQueue->pending();
	$Msg = "$Msg"."FileCount: $fileCount\n"."$filemsg";
	splitFileMd5Thread();
	rsyncThread();	
 	for my $addr (@address){
		sendMail($addr);
	}

	$currentTime=strftime("%Y%m%d%H%M", localtime(time));
	$log_logger->info("End:$currentTime");
}

###################Access to the backup name for gitlab ################
sub backup {
my $result=`gitlab-rake gitlab:backup:create`;
my $flag=`echo $?`;
if ($flag == 0){
	$log_logger->info("gitlab-backup-create : success "); 			
	my @result=split(/\n/,$result);
	for my $cc (@result){
		if ($cc =~ /(?<filename>\d+_gitlab_backup.tar)/){
			$backFilename=$+{'filename'};
			$log_logger->info("gitlab-backup-filename : $backFilename"); 			
			}
		}
	}else{
	$log_logger->info("gitlab-backup-create : fail "); 			
	}
	return "$backFiledir$backFilename";
}

############# Search the file after segmentation ################
sub findSplitFile {
		if ( $_ =~ /$fileName\.\d{3}$/) {
			$log_logger->info("splitFileQueue enqueue : $_"); 
			$filemsg = "$filemsg"."$_\n";
			$splitFileQueue->enqueue($_);
			$log_logger->info("remotefileQueue enqueue : $_"); 			
			$remotefileQueue->enqueue($_);
#			$log_logger->info("print to logfile : $_");
	}

}

############## Search the MD5 file after segmentation ############
sub splitFileMd5Thread {
	while($splitFileQueue->pending()) {
		my $Queue = $splitFileQueue->dequeue();
		$log_logger->info("splitfileQueueMD5 dequeue : $Queue ");
		threads->create(\&splitFileMd5,$Queue);
		}
        foreach my $thread (threads->list(threads::all)){
                                if ($thread->is_joinable()){
                                        $thread->join();
                        }
                }
        foreach my $thread ( threads->list(threads::all) ) {
                $thread->join();
        }
	}

################## Search for the source file md5 #################
sub srcFileMd5 {
	my $file=shift;
	my $md5_command=`md5sum $file`;
	my $flag=`echo $?`;
	if ($flag == 0) {
		my ($file_md5,$filename) = split(/\s+/,$md5_command);
		my $log = "srcfile:$file filesize:$fileSize file_md5sum:$file_md5";
     	   $Msg = "$Msg"."srcfile:$file filesize:$fileSize file_md5sum:$file_md5\n";
		   $log_logger->info($log);
	}else {
		my $file_md5 = "system command maybe exec fail, command result code is $md5_command";
		my $log = "srcfile:$file filesize:$fileSize file_md5sum:$file_md5";
		   $Msg = "$Msg"."srcfile:$file filesize:$fileSize file_md5sum:$file_md5\n";
		   $log_logger->warn($log);					
	}
}

####### split File MD5 ###############
sub splitFileMd5 {
	my $file=shift;
	my $md5_command=`md5sum $filePath$file`;
	my $flag=`echo $?`;
	if ($flag == 0) {
		my ($file_md5,$filename) = split(/\s+/,$md5_command);
		my $log = "file:$file  file_md5sum:$file_md5";
	    $log_logger->info($log);
		
	}
}

################# Will be cut by the source file ################
sub splitFile {
		 my $srcFile = shift;
		 my $split_command =`split -b 50M $srcFile -d -a 3 $srcFile.`;
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
		progress => 1,
		stats => 1,
		links => 1,
	  	'hard-links' => 1,
	   	'ignore-times' => 1,
	   	'password-file' => './rsync.pass',
		}
);
 
$obj->exec( { src => "$filePath$file", dest => $remotehost } );
#or warn ($log_logger->warn("rsync: $file to $remotehost fail!" ));

my $rval = $obj->realstatus;
		if ($rval == 0 ) {
		$log_logger->info("rsync: $file to $remotehost Success!\n");
		}else{
		 my $rsyncError = sprintf ("%s", $obj->err);
		 $message = "$message"."Transfer Failed:\nfile:$file 		reason:$rsyncError";
		 $log_logger->info("rsync: $file to $remotehost fail reason:$rsyncError");
		}
}


sub sendMail {
	my $CONTACTEMAIL = shift;
 	my $sender = new Mail::Sender{
	   ctype => 'text/plain; charset=utf-8',
	   encoding => 'utf-8',    
 	} ;
	die "Error in mailing : $Mail::Sender::Error\n" unless ref $sender;
	if ($sender->MailMsg({
		smtp => $smtp_server,
		from => $send_user,
		to => $CONTACTEMAIL,
		subject => $Subject,
		msg => $Msg,
#		file => "$file",
#		auth => 'LOGIN', 
#		authid => $send_user,
#		authpwd => $send_user_pw,
		charset=>'utf-8'
		}) < 0) {
			die $log_logger->error("senermail fail -- $Mail::Sender::Error\n");	
		}
		$sender->Close();
	}
	
sub Usage {
    print <<"END";
    perl gitback.pl 
END
   exit 2;
}
