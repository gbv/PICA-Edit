package PICA::Edit::Queue::Hash;

use strict;
use warnings;
use v5.10;

sub new { 
    bless [{},0], shift; 
}

sub get {
   my ($self, $id) = @_;
   return $self->[0]->{ $id };
}

sub insert {
	my ($self, $object) = @_;
	return unless defined $object;
	my $id = ++$self->[1];
	$self->[0]->{ $id } = $object;
	return $id;
}

sub update { 
    my ($self, $id => $object) = @_;
    return unless defined $self->[0]->{ $id };
	$self->[0]->{ $id } = $object;
	return $id;
}

sub remove {
    my ($self, $id) = @_;
    return unless defined $self->[0]->{ $id };
	delete $self->[0]->{ $id }; 
	$id;
}

sub list {
	my ($self, %properties) = @_;

	my $page     = delete $properties{page};
	my $pagesize = delete $properties{pagesize};
	my $sort     = delete $properties{sort};

	my $hash = $self->[0];

	# TODO: search by specific properties
	# TODO: sort by field
	# TODO: limit (pagesize) and page
	
	[ map { $_ => $hash->{$_} } sort keys %$hash ];
}

1;
