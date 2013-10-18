package SigndMain;
use base 'Exporter';
our @EXPORT_OK = qw/main/;

use strict;
use warnings;

use Data::Dumper;
use POSIX ":sys_wait_h";
use Thread::Semaphore;
use English;

use lib '/usr/lib/zoner/perl-utils';
use ZonerLog;

use ZDnssec qw/sign_zone/;
use SigndConn qw/signd_conn get_requests flush_requests get_max_id/;
use SigndConf;

my %children;

my $tasks_done = 0;
my $start_count = 0;

# global semaphores
my $s = Thread::Semaphore->new (4);
my $boss_lock = Thread::Semaphore->new (0);

sub get_env {
	my $debug = 0;

	# explicit taint
	my $taint_impl = sub {
		my ($val) = @_;

		return sub {
			my ($val3) = @_;
			return $val3;
		} unless $debug;

		local $ENV{PATH} = '/bin/';
		my $taint = `/bin/true &> /dev/null`;

		return sub {
			my ($val2) = @_;
			return $val2 unless $debug;
			return unless defined $val2;
			return  $taint . $val2;
		}
	};
	my $taint = $taint_impl->();

	my $user = &$taint ($SigndConf::user);
	my $nsd_user = &$taint ($SigndConf::nsd_user);
	my $signd_db_pass = &$taint ($SigndConf::signd_db_pass);
	my $tmp_dir = &$taint ($SigndConf::tmp_dir);
	my $zones_dir = &$taint ($SigndConf::zones_dir);

	my ($dlogin, $dpass, $duid, $dgid) = getpwnam ($user) or die "I can't found $user user! ($!)";
	my ($nlogin, $npass, $nuid, $ngid) = getpwnam ($nsd_user) or die "I can't found $nsd_user user! ($!)";

	my %env = (
	'nuid' => $nuid,
	'duid' => $duid,
	'ngid' => $ngid,
	'dgid' => $dgid,
	'zones_dir' => $zones_dir,
	'tmp_dir' => $tmp_dir,
	'user' => $user,
	'nsd-user' => $nsd_user,
	);

	return \%env;
}

sub main {

	my $env = get_env ();
	if ( $EUID != $env->{duid} ) {
		die "signd: not running under dns-data user!";
	}
	umask 0037;

	my $db_conn = signd_conn ('localhost', 'f1234160d518742f758915091e1bca85');

	my $max_id = get_max_id ($db_conn);

	if ( ! $max_id ) {
		clog ($sev_log1, "boss: Nothing to do. Exiting.");
		$db_conn->rollback ();
		$db_conn->disconnect ();
		return 0;
	}

	my ($requests, $rs_count) = get_requests ($db_conn);
	$start_count = $rs_count;

	local $SIG{CHLD} = \&sig_chld_handler;
	local $SIG{KILL} = \&sig_kill_handler;

	for ( ; $rs_count > 0; --$rs_count) {
		# wait for lock
		$s->down ();


		my $row = $requests->fetchrow_arrayref ();

		if ( ! defined $row ) {
			clog ($sev_error, "fetch_row: Strange error. I can't get row.");
			next;
		}

		my $zone_name = $row->[0];
		my $rrsig_val = time ();

		my %zone = (
				'zone_name'     => $zone_name,
				'zsks'			=> [],
				'ksks'			=> [],
				'rrsig_val'     => $rrsig_val,
		);

		my $pid = fork ();
		$children{$pid} = 1;

		if ( $pid > 0 ) {
			# parent

		} elsif ( $pid == 0 ) {
			# child
			clog ($sev_log1, "child: children started.");
			# cleanup mess
			undef %children;
			undef $boss_lock;
			undef $s;
			undef $db_conn;
			$requests->finish ();
			undef $requests;

			child_work ($env, \%zone);

			exit (0);

		} elsif ( ($pid == -1) && ($rs_count == $start_count) ) {

			die "fork failed on start!";

		} elsif ( ($pid == -1) && ($rs_count != $start_count) ) {
			clog ($sev_error, "fork failed in loop!");
			next;
		}
	}

	$requests->finish ();

	# wait for childrens if we have tasks to do
	clog ($sev_log1, "boss: lock boss process and wait for childrens.");
	$boss_lock->down ();
	clog ($sev_log1, "boss: unlocked.");

	foreach my $pid (keys %children) {
		clog ($sev_log2, "Wait for children $pid.");
		next if (waitpid ($pid, 0) < 0);

		delete $children{$pid};
		my $retc = ($? >> 8);
		clog ($sev_log1, "children ($pid) exited with return code: $retc");
	}

	clog ($sev_log1, "boss on exit: flushing requests.");
	flush_requests ($db_conn, $max_id);
	$db_conn->commit ();
	$db_conn->disconnect ();
	return 0;
}

# bude prijimat rovnou data o klicich z databaze
sub child_work {
	my ($env, $zone) = @_;

	sign_zone ($env, $zone);
	return;
}

sub sig_chld_handler {

	local ($!, $?);
	# wait for all signals
	while ( (my $pid = waitpid (-1, WNOHANG)) > 0 ) {
		next unless defined $children{$pid};
		next if $children{$pid} == 0;

		my $retc = ($? >> 8);
		clog ($sev_log1, "sig_handler: children ($pid) exited with return code: $retc");
		++$tasks_done;
		delete $children{$pid};

		if ( (!%children) && ($tasks_done == $start_count) ) {
			clog ($sev_log1, "Waking boss process.");
			$boss_lock->up ();
		} else {
			$s->up ();
		}
	}
}

sub sig_kill_handler {
	clog ($sev_log1, "SIGKILL received. Aborting process.");
	$tasks_done = $start_count;
	$boss_lock->up ();
}

1;
