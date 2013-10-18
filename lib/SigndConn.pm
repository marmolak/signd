package SigndConn;

use strict;
use warnings;
use DBI;

use DBUtils qw/connect_impl/;

use lib '/usr/lib/zoner/perl-utils';
use ZonerLog;

use base 'Exporter';
our @EXPORT_OK = qw/signd_conn get_requests flush_requests get_max_id add_request/;

sub signd_conn ($$) {
	my ($host, $passwd) = @_;

	return connect_impl ($host, 'signd', $passwd);
}

sub get_requests ($) {
	my ($db_conn) = @_;

	$db_conn->ping ();

	my $query = "SELECT DISTINCT `zone_name` FROM `requests` ORDER BY `id`";
	my $prepared = $db_conn->prepare ($query);
	$prepared->execute () or die "db: query ($query) failed with error $prepared->errstr";

	my $rows_count = $prepared->rows ();

	return ($prepared, $rows_count);
}

sub get_max_id ($) {
	my ($db_conn) = @_;

	$db_conn->ping ();

	my $query = "SELECT MAX(id) FROM `requests`";
	my $prepared = $db_conn->prepare ($query);
	$prepared->execute () or die "db: query ($query) failed with error $prepared->errstr";

	my $row = $prepared->fetchrow_arrayref ();
	my $max_id = $row->[0];

	$prepared->finish ();
	return $max_id;
}

sub flush_requests ($$) {
	my ($db_conn, $max_id) = @_;

	$db_conn->ping ();

	my $query = "DELETE FROM `requests` WHERE `id` <= ?";
	my $prepared = $db_conn->prepare ($query);
	$prepared->execute ($max_id) or die "db: query ($query) failed with error $prepared->errstr";
	$prepared->finish ();
}

sub add_request ($$) {
	my ($db_conn, $zone_name) = @_;

	$db_conn->ping ();

	my $query = "INSERT INTO `requests` (`zone_name`) VALUES ('?')";
	my $prepared = $db_conn->prepare_cached ($query, { dbi_dummy => __FILE__.__LINE__ } );
	$prepared->execute ($zone_name) or die "db: query ($query) failed with error $prepared->errstr";
	$prepared->finish ();
}

1;
