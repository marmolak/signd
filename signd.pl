#!/usr/bin/perl -T
use strict;
use warnings;

use lib '/usr/lib/zoner/perl-utils';
use ZonerLog;

use lib './lib/';
use PPid qw/create_pid_file/;

use SigndMain;

my $pid_lock = 0;

set_log_file ('/var/log/signd/signd.log');
set_log_severity (20);

my $pid_file_loc = '/var/run/signd/signd.pid';
my $ret = 30;

eval
{
    local $SIG{INT} = sub { die "intk\n" };
    $pid_lock = create_pid_file ($pid_file_loc);
    unless ($pid_lock)
    {
		clog ($sev_error, "Process running. Check pid file: $pid_file_loc");
		$ret = 30;
    } else {

    	my $start = time ();
    	$ret = SigndMain::main ();
		my $end = time ();
		my $diff = $end - $start;
		clog ($sev_log1, "Runtime: $diff secs.");
    }

    return 1;
} or do {
	my $err = $@;
	if ($err) {

		# break from keyboard
		if ($err =~ /^intk/ && $pid_lock) {
			clog ($sev_log1, "PID: unlinking pidfile");
			truncate $pid_file_loc, 0;
			unlink $pid_file_loc;
			exit ($ret);
		}

		if ($err) {
			chomp $err;
			clog ($sev_log1, "died with exception: $err");
		}
	}
};

if ($pid_lock)
{
    clog ($sev_log1, "PID: unlinking pidfile");
    truncate $pid_file_loc, 0;
    unlink $pid_file_loc;
}

exit ($ret);
