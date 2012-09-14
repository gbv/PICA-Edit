package PICA::Edit::Queue;

use strict;
use warnings;
use v5.10;

use Carp;
use PICA::Edit::Queue::DB;
use PICA::Edit::Queue::REST;
use PICA::Edit::Queue::Hash;

sub new {
    my ($class,%config) = @_;

	if ($config{api}) {
		return PICA::Edit::Queue::REST->new( %config );
	} elsif ($config{database}) {
		return PICA::Edit::Queue::DB->new( %config );
	} else {
		return PICA::Edit::Queue::Hash->new;
	}
}

1;
