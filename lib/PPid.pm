package PPid;
use base 'Exporter';
our @EXPORT_OK = qw/create_pid_file/;

use strict;
use warnings;
use Fcntl;
use Fcntl ':mode';

use lib '/usr/lib/zoner/perl-utils';
use ZonerLog;

sub proc_is_running {
	my ($pid) = @_;

	my $proc_name = $0;

	my $proc_pid_file = "/proc/$pid/cmdline";
	open PROC_CMD, '<', $proc_pid_file
	    or return 0;
	my $cmdline_content = <PROC_CMD>;
	close PROC_CMD;

	return 0 if (not defined $cmdline_content);

	chomp $cmdline_content;

	return 1
		if $cmdline_content =~ m!^.*perl.*$proc_name.*$!;

	return 0;
}

sub create_pid_file_impl {
    my ($pid_file) = @_;

    clog ($sev_log1, "PID: Openning pid file ($pid_file)");
    my $pid_ok = sysopen PID_FILE_HANDLE, $pid_file, O_EXCL | O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW;
    if ( $pid_ok ) {
        print PID_FILE_HANDLE $$;
        close PID_FILE_HANDLE;
        return 1;
    }

    # check if its empty
    open my $fh, '<', $pid_file or return 0;

    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat $fh
        or return 0;

    # is regular file?
    if ( !S_ISREG ($mode) ) {
        clog ($sev_log1, "PID: $pid_file is not regular file!");
        return 2;
    }

    my $pid = <$fh>;
    # file is empty
    if (not defined $pid) {
        close $fh;
	unlink $pid_file;
        return 0;
    }
    # file is not empty
    chomp $pid;

    my $now = time ();
    my $diff = $now - $ctime;
    if ( $diff >= 10 ) {
	my $process_runing = proc_is_running ($pid);
	if ( $process_runing ) {
		close $fh;
		return 2;
	}
      # process not running, then delete pidfile and dont grap lock;
      truncate $fh, 0;
      close $fh;
      unlink $pid_file;
      return 0;
    }

    return 2;
}

sub create_pid_file {
    my ($pid_file) = @_;

    my $ret = 0;
    clog ($sev_log1, "PID: Try to catch pid lock ($pid_file)");
    for (my $p = 0; $p < 5; ++$p) {
    	$ret = create_pid_file_impl ($pid_file);
	return 0 if $ret == 2;
	return 1 if $ret;
    }

    return $ret;
}

1;
