package FLock;
use strict;
use warnings;
use Fcntl;
use Fcntl ':mode';
use Time::HiRes;

use base 'Exporter';
our @EXPORT_OK = qw/new/;

sub new {
	my ($class, $zone_name, $prog_name) = @_;

	my $this = {
		zone_name => $zone_name,
		prog_name => $prog_name,
		pid => $$,
		retry => 5,
		locked => 0,
	};
	bless $this, $class;

	$this->get_lock ();

	return $this;
}

sub get_lock_impl {
	my ($this) = @_;
	my ($zone_name, $prog_name, $pid) = $this->unpack_args ();

	my $lock_file = "$zone_name.lock";

    my $lock = sysopen (LOCK_HANDLE, $lock_file, O_EXCL | O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW);
    if ( $lock ) {
        print LOCK_HANDLE "$prog_name $pid\n";
        close LOCK_HANDLE;

		$this->{locked} = 1;
    }
}

sub get_lock {
	my ($this) = @_;

	return $this->{locked} if ( $this->{locked} );

	for ( ; $this->{retry} > 0; --$this->{retry} ) {
		$this->get_lock_impl ();
		last if ($this->{locked} == 1);
		Time::HiRes::sleep (0.5);
	}

	die "get_lock" unless $this->{locked};
}

sub drop_lock {
	my ($this) = @_;
	my ($zone_name, $prog_name, $pid) = $this->unpack_args ();

	die "drop_lock" if ( $this->{locked} == 0 );

	my $lock_file = "$zone_name.lock";
	open (my $lock_fp, '<', $lock_file);

	if ( !$lock_fp ) {
		die "drop_lock";
	}

	my $line = <$lock_fp>;
	close $lock_fp;

	die "drop_lock" if ( ! defined $line );
	
	# we are owner of lock?
	die "drop_lock" if ( !($line =~ /^${prog_name}\s${pid}$/) );

	unlink $lock_file;

	$this->{locked} = 0;

	return 1;
}

sub DESTROY {
	my ($this) = @_;

	return if ( !$this->{locked} );
	# don't raise exception!
	eval {
		$this->drop_lock ();
		return 1;
	};
}
 
sub unpack_args {
	my ($this) = @_;

	return ( $this->{zone_name}, $this->{prog_name}, $this->{pid} );
}

1;
