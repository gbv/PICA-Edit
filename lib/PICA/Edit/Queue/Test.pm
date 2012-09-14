package PICA::Edit::Queue::Test;
use strict;
use Test::More;

use PICA::Modification;
use Test::JSON::Entails;

use parent 'Exporter';
our @EXPORT = qw(test_queue);

sub test_queue {
	my $queue = shift;
	my $test = bless { queue => $queue }, __PACKAGE__;
	$test->run;
}

sub get { my $t = shift; $t->{queue}->get(@_); }
sub insert { my $t = shift; $t->{queue}->insert(@_); }
sub update { my $t = shift; $t->{queue}->update(@_); }
sub remove { my $t = shift; $t->{queue}->remove(@_); }
sub list { my $t = shift; $t->{queue}->list(@_); }

sub run {
	my $self = shift;

	my @list = $self->list();
	is_deeply \@list, [], 'empty queue';

	my $mod = PICA::Modification->new( 
		del => '012A',
		id  => 'foo:ppn:123',
	);

	my $id = $self->insert( $mod );
	ok( $id, "inserted modification" );

	my $got = $self->get($id);
	entails $got => $mod->attributes, 'get stored modification';

	@list = $self->list();
	is scalar @list, 1, 'list size 1';
	entails $list[0] => $mod->attributes, 'list contains modification';

	my $id2 = $self->remove($id);
	is $id2, $id, 'deleted modification';

	$got = $self->get($id);
	is $got, undef, 'deleted modification';
}

1;
