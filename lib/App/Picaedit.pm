package App::Picaedit;
#ABSTRACT: picaedit core application

use strict;
use warnings;
use v5.10;

use Log::Contextual qw(:log :dlog);

sub new {
	my $class = shift;
	bless {@_}, $class;
}

sub init {
    my ($self,$options) = @_;

    $self->{queue} ||= PICA::Edit::Queue->new( 
        database => $options->{database},
    );

	log_trace { "initialized App::Picaedit" };
}
1;
