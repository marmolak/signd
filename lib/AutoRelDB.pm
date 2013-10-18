package AutoRelDB;
use strict;
use warnings;

sub new {
	my ($class, $fd) = @_;
	my $this = { db_fd => $fd };
	bless $this, $class;
	return $this;
}

sub get {
	my ($this) = @_;
	return $this->{db_fd};
}

sub close {
	my ($this) = @_;
	$this->{db_fd}->disconnect() if ($this->{db_fd});
}

sub DESTROY {
	my ($this) = @_;
	$this->close ();
}

1;
