package MasterToolsUtils;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw/build_zonedir_path/;

use Digest::MD5 qw (md5_hex);
 

sub build_zonedir_path ($) {
	my ($zone_name) = @_;

	my $hash = md5_hex ($zone_name);
	# Result: /a/b/c/zone_name
	return join ("/", split ("", substr $hash, 29, 3)) . "/" . $zone_name . "/";
}
