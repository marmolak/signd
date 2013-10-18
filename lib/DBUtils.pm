package DBUtils;

use strict;
use warnings;
use Carp;
use DBI;

use base 'Exporter';
our @EXPORT_OK = qw/connect_impl/;

sub connect_impl {
	my ($host, $user, $passwd) = @_;

	# terrible but safe code...
	my $db_conn = undef;
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		eval {
			alarm (1);
			my $conn_str = "DBI:mysql:database=$user;host=$host;";
			# because: http://search.cpan.org/dist/DBI/DBI.pm#AutoInactiveDestroy
			$db_conn = DBI->connect($conn_str, "$user", $passwd,
				{AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1, AutoCommit => 0}
			);
			alarm (0);
			return $db_conn; # for eval
		} or do {
			alarm (0);
			my $err = $@;
			return unless $err;
			die $err;
		};
		alarm (0);
		return 1; # for eval
	} or do {
		alarm (0);
		my $err = $@;
		return unless $err;
		if ( $err =~ /^alarm/ ) {
			die "DB: Connection timeout!";
		} else {
			die $err;
		}
	};

	return $db_conn;
}

1;
