package ZDnssec;
use base 'Exporter';
our @EXPORT_OK = qw/sign_zone get_keys/;

use strict;
use warnings;
use File::Temp;
use File::Copy qw/move cp/;

use FLock;
use AutoRel;
use MasterToolsUtils qw/build_zonedir_path/;

use lib '/usr/lib/zoner/perl-utils';
use ZonerLog;

sub sign_zone {
	my ($env, $zone) = @_;
	my $zone_name = $zone->{'zone_name'};

	eval {

		my $zone_path = build_zonedir_path ($zone_name);

		my $cur_dir = "$env->{zones_dir}/$zone_path";

		clog ($sev_log1, "signing zone: ($zone_name) in $cur_dir directory.");
		if ( ! chdir ($cur_dir) ) {
			die "sign: Directory $cur_dir not exists!";
		}

		if ( (! -e $zone_name) || (! -s $zone_name) ) {
			die "sign: File $zone_name in $cur_dir doesn't exist or is empty!";
		}

		clog ($sev_log2, "flock: Gaining file lock for zone $zone_name...");
		my $lock = FLock->new ($zone_name, 'signd');
		clog ($sev_log2, "flock: Locked.");

		my ($ksks, $zsks) = get_keys ($zone_name);
		$zone->{ksks} = $ksks;
		$zone->{zsks} = $zsks;

		clog ($sev_log1, "sign: including keys to zone.");
		my $afh = include_keys ($zone);

		my $return_code = 0;
		call_dnssec_signzone ($env, $zone, $afh, \$return_code);
		clog ($sev_log1, "dnssec-signzone: ($zone_name) finished with return code: $return_code.");

		clog ($sev_log2, "flock: Unleash file lock.");
		$lock->drop_lock ();
		clog ($sev_log2, "flock: Unlocked.");

		return 1;
	} or do {
		my $err = $@;
		return if ( ! $err );

		# Destructor of FLock object silently destroy lock if exception raised.
		if ( $err =~ /^get_lock/ ) {
			clog ($sev_error, "flock: I can't get lock! Zone ($zone_name) is not signed!");
			clog ($sev_log2, "flock: Unleash file lock.");
			clog ($sev_log2, "flock: Done.");
			return;
		}

		if ( $err =~ /^drop_lock/ ) {
			clog ($sev_warning, "Drop of lock failed!");
			return;
		}

		if ( $err =~ /^signzone/ ) {
			# zapsat do odlozenych zon s atributem sign
			return;
		}

		chomp $err;
		clog ($sev_warning, "exception raised: $err");
	};
}

# dat to ZDnssec::Utils
sub get_keys {
	my ($zone_name) = @_;

	my $exists_file = sub {

		my ($path) = @_;
		my @ar = ();

		if ( (-e "$path-active.key") && (-e "$path-active.private") ) {
			push (@ar, "$path-active");
		} else {
			return ();
		}
		
		if ( (-e "$path-passive.key") && (-e "$path-passive.private") ) {
			push (@ar, "$path-passive");
		} else {
			# nothing right now
		}

		if ( (-e "$path-second-active.key") && (-e "$path-second-active.private") ) {
			push (@ar, "$path-second-active.key");
		} else {
			# nothing right now
		}

		return \@ar;
	};

	my $ksks = $exists_file->("keys/ksks/$zone_name") or die "keys: I can't found active KSK for ($zone_name)!";
	my $zsks = $exists_file->("keys/zsks/$zone_name") or die "keys: I can't found active ZSK for ($zone_name)!";

	return ($ksks, $zsks);
}

sub call_dnssec_signzone {
        my ($env, $zone, $afh, $ret_code) = @_;
        my ($zone_name, $ksks, $zsks, $rrsig_val) = unpack_zone ($zone);
	
		my $fd_no = fileno ($afh->get ());
		my $pid = $$;
		my $zone_file = "/proc/$pid/fd/$fd_no";

        my $cmd = build_dnssec_signzone_cmd ($zone, $zone_file);

		harden_call_sub ();

        my $ok = open (my $ch, "$cmd 2>&1|");
        if ( ! defined $ok ) {
			clog ($sev_error, "dnssec_signzone: ($zone_name) can't run command: ($cmd). ($!)");
			die "signzone";
        }

        my $out;
        while ( my $line = <$ch> ) {
                # skip warning line
                if ( $line =~ /^dnssec-signzone:\s(fatal|error):/ ) {
					$out = $line;
                } elsif ( ! $out ) {
					$out = $line;
                }
        }
        chomp $out;

        close $ch;

        my $retc = ($? >> 8);

        if ( defined $ret_code ) {
			$$ret_code = $retc;
        }

        if ($retc != 0) {
			clog ($sev_error, "dnssec_signzone: ($zone_name) ($out) ($retc)" );
			die "signzone";
        }

		my $res = chown $env->{duid}, $env->{ngid}, "$zone_name.signed";
		if (!$res) {
			clog ($sev_warning, "sigzone: Cannot change privileges on $zone_name.signed file to: $env->{duid}:$env->{ngid}. Reason: $!");
		}

        return 1;
}

# not yet secured
sub call_dnssec_keygen {
	my ($zone, $key_type, $ret_code) = @_;
	my $zone_name = $zone->{'zone_name'};

	my $cmd = build_dnssec_keygen_cmd ($zone, $key_type);

	harden_call_sub ();

	my $ok = open (my $ch, "$cmd 2>&1|");
	if ( ! defined $ok ) {
		clog ($sev_error, "dnssec_keygen: ($zone_name) can't run command: ($cmd).");
		die "keygen";
	}

	my $out;
	while ( my $line = <$ch> ) {
			# skip warning line
			if ( $line =~ /^dnssec-keygen:\s(fatal|error):/ ) {
				$out = $line;
			} elsif ( ! $out ) {
				$out = $line;
			}
	}
	chomp $out;

	close $ch;

	my $retc = ($? >> 8);

	if ( defined $ret_code ) {
		$$ret_code = $retc;
	}

	if ($retc != 0) {
		clog ($sev_error, "dnssec-keygen: ($zone_name) ($out) ($retc)" );
		die "keygen\n";
	}

	return $out; 
}


sub harden_call_sub {
	delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
	$ENV{'PATH'} = '/usr/sbin/:/usr/bin';
	umask 0037;
}

sub include_keys {
	my ($zone, $tmp_dir) = @_;
	my ($zone_name, $ksks, $zsks, $rrsig_val) = unpack_zone ($zone);

	$tmp_dir = '/proc/self/cwd' if (!defined $tmp_dir);
	# nasty code when i used getcwd. Never more!
	# $tmp_dir = getcwd () if ( ! defined $tmp_dir);
	# # untaint value... i know. It's nasty little hack :(.
	# ($tmp_dir) = $tmp_dir =~ /(.^)/;

	my $insert_line = "\n;%s\n\$INCLUDE \"%s\"\n";

	my $tmp = File::Temp->new ( UNLINK => 1, DIR => $tmp_dir );
	my $tmp_name = $tmp->filename ();
	if ( ! File::Temp::unlink0 ($tmp, $tmp_name) ) {
		clog ($sev_warning, "inc: Secure deletion of $tmp_name file failed!");
	}

	cp ($zone_name, $tmp) or die "copy: $!";

	foreach my $key (@$ksks) {
		my $line = sprintf ($insert_line, 'KSK key', "$key.key");
		syswrite ($tmp, $line) or die "include_keys: $!";
	}
	foreach my $key (@$zsks) {
		my $line = sprintf ($insert_line, 'ZSK key', "$key.key");
		syswrite ($tmp, $line) or die "include_keys: $!";
	}

	$tmp->flush ();

	return AutoRel->new ($tmp);
}

sub rssig_val_cal {
	my $now = shift @_ || time ();

	my $month_seconds = 3600 * 24 * 30;
	my $rrsig_expiration = ($month_seconds * 12);
	my $rrsig_validity = $now + $rrsig_expiration;

	return $rrsig_validity;
}

sub build_dnssec_keygen_cmd {
	my ($zone, $key_type, $bits) = @_;
	my $zone_name = $zone->{'zone_name'};

	my $cmd = "dnssec-keygen  -r/dev/urandom -q -3 -f KSK -a NSEC3RSASHA1 ";
	
	if ( $key_type =~ /^ksk$/ )  {
		$bits = 4096 if ( ! defined $bits );
		$cmd .= " -f KSK ";
	} elsif ( $key_type =~ /^zsk$/ ) {
		$bits = 2048 if ( ! defined $bits );
	}

	$cmd .= " -b $bits -n ZOME $zone ";

	return $cmd;
}

sub build_dnssec_signzone_cmd {
        my ($zone, $input_file) = @_;

        my ($zone_name, $ksks, $zsks, $rrsig_val) = unpack_zone ($zone);

		# result to tmp file
		my $cmd = "dnssec-signzone -p -N keep -o $zone_name -f $zone_name.signed";

        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime ($rrsig_val);
        $mon += 1;
        $year += 1900;

        my $rrsig_date = sprintf ("%d%.2d%.2d%.2d%.2d%.2d", $year, $mon, $mday, $hour, $min, $sec);
        $cmd .= " -e $rrsig_date ";

        foreach my $ksk (@$ksks) {
			$cmd .= " -k $ksk.key ";
        }

		$cmd .= " $input_file " if defined $input_file || " $zone_name ";

        foreach my $zsk (@$zsks) {
			$cmd .= " $zsk.key ";
        }

        return $cmd;
}

sub unpack_zone ($)  {
	my ($zone) = @_;

	return ($zone->{'zone_name'}, $zone->{'ksks'}, $zone->{'zsks'}, $zone->{'rrsig_val'});
}

1;
