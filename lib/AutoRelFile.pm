package AutoRelFile;
use strict;
use warnings;

sub new {
	my ($class, $file_name) = @_;
	my $this = { file_name => $file_name, unlink_flag => 1 };
	bless $this, $class;
	return $this;
}

sub get {
	my ($this) = @_;
	return $this->{file_name};
}

sub close {
	my ($this) = @_;
	unlink $this->{file_name} if ( ($this->{file_name}) && ($this->{unlink_flag}) );
}

sub no_unlink {
	my ($this) = @_;
	$this->{unlink_flag} = 0;
}

sub DESTROY {
	my ($this) = @_;
	$this->close ();
}

1;
