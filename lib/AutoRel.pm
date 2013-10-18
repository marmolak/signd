package AutoRel;
use strict;
use warnings;

sub new {
	my ($class, $fd) = @_;
	my $this = { fd => $fd };
	bless $this, $class;
	return $this;
}

sub get {
	my ($this) = @_;
	return $this->{fd};
}

sub close {
	my ($this) = @_;
	close $this->{fd} if ($this->{fd});
}

sub DESTROY {
	my ($this) = @_;
	$this->close ();
}

1;
