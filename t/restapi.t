use strict;
use warnings;
use v5.10;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

use App::Picaedit;

my $pe = App::Picaedit->new;
my $app = sub { };

test_psgi $app => sub {
	my $cb = shift;
	my $res = $cb->(GET '/edit/1');
};

done_testing;


# Wraps PICA::Edit::Queue as Plack::App::REST::Storage
package PICA::Edit::Queue::Storage;

use parent 'PICA::Edit::Queue';

sub create {
	my ($self, $edit) = @_;
	my $id = $self->insert($edit); # may croak
	return $id;
}

sub read {
	my ($self, $id) = @_;
	$self->select( { edit_id => $id } );
}

sub update {
	return undef;
	# TODO: wrap super::update
}

sub list {
	#...;
	# use $self->select( ... );
}


