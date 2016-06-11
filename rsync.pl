#!/usr/bin/env perl
 
use strict;
use threads;
use Thread::Queue;
use File::Find;
use File::Rsync;
use POSIX qw(strftime);
 
#本地主机文件目录
my $srcFilePath='/root/test/';
#使用队列，将要备份的文件逐一插入队列
my $fileQueue = Thread::Queue->new();
#远端主机备份目录
my $remotedir='lansgg@192.168.137.129::lansggtest';
#最大线程数
my $thread_max = 5;
my $backupTime = strftime("%Y%m%d%H%M%S",localtime(time));
print "begin : $backupTime\n";
 
#检索要备份目录下的所有文件，. 除外。 linux中 . 代表当前目录
sub findAllFile {
        unless ( $_ eq '.'){
        print "corrent file : $File::Find::name \n";
        $fileQueue->enqueue($_);
        }
}
 
find(\&findAllFile,$srcFilePath);
 
#使用rsync进行传输
sub rsync {
    my $file = shift;
    print "rsync -- $file \n";
    my $obj = File::Rsync->new(
    {
    archive    => 1,
    compress => 1,
    checksum => 1,
    recursive => 1,
    times => 1,
#    verbose => 1,
    timeout => 300,
    progress => 1,
    stats => 1,
    'ignore-times' => 1,
    'password-file' => './rsync.pass',
    }
);
 
$obj->exec( { src => "$srcFilePath$file", dest => $remotedir } ) or warn "rsync Failed ! \n";
 
#print $obj->out;
 
}
#检查队列中未传输的文件
while ($fileQueue->pending()){
    while (scalar(threads->list()) < $thread_max ){
#        my $readQueue = $fileQueue->dequeue();        #此做调试使用，查看当前传输的文件
#        print "current file Queue is $readQueue \n";
#生成线程
        threads->create(\&rsync,$readQueue);
 
#查看当前线程总数
        my $thread_count = threads->list();
#        print "thread_count is $thread_count\n"; 
    }
#确定当前线程是否作业完成，进行回收
    foreach my $thread (threads->list(threads::all)){
        if ($thread->is_joinable()){
                $thread->join();
            }
        }
}
 
#join掉剩下的线程（因为在while中的队列为空时，可能还有线程在执行，但是此时程序将退出while循环，所以这里需要额外程序join掉剩下的线程）
 
foreach my $thread ( threads->list(threads::all) ) {
    $thread->join();
    }
 
 
$backupTime = strftime("%Y%m%d%H%M%S",localtime(time));
print "end : $backupTime\n";
