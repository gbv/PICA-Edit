package PICA::Edit::Request;
#ABSTRACT: Modification request of an identified PICA+ record

use 5.010;
use strict;
use warnings;

use Carp;
use PICA::Record;

=head1 DESCRIPTION

An edit is change request of an identified PICA+ record. The request may be
malformed and invalid. It consists of the following optional attributes:

=over 4

=item id

The fully qualified record identifier (C<PREFIX:ppn:PPN>).

=item iln

The ILN of level 1 record to modify.

=item epn

The EPN of the level 2 record to modify.

=item del

A comma-separated list of PICA+ field to be removed.

=item add

A stringified PICA+ record with fields to be added.

=back

=cut

sub trim { 
    my $s = shift // ''; 
    $s =~ s/^\s+|\s+$//g; $s; 
}

=method new ( %attributes )

Creates a new edit request from attributes. An edit request, once created,
should not be modified. On creation, all attributes are checked for
wellformedness and normalized. On error the constructor does not carp but
it collects a list of error messages, each connected to the attribute that
an error originates from.

=cut

sub new {
    my ($class, %args) = @_;

    my $self = bless {

        # attributes
        id    => trim( $args{id}  // '' ),
        iln   => trim( $args{iln} // '' ),
        epn   => trim( $args{epn} // '' ),
        del   => trim( $args{del} // '' ),
        add   => trim( $args{add} // '' ),

        # mapping from malformed attributes (id,iln,epn,del,add) to messages
        errors => { },
    }, $class;

    # check and normalize attributes

    if ($self->{id} =~ /^(([a-z]([a-z0-9-]?[a-z0-9]))*:ppn:(\d+[0-9Xx]))?$/) {
        $self->{ppn}   = uc($4) if defined $4;
        $self->{dbkey} = uc($5) if defined $5;
    } else {
        $self->error( id => "malformed record identifier" );
    }

    $self->error( iln => "malformed ILN" ) unless $self->{iln} =~ /^\d*$/;

    $self->error( epn => "malformed EPN" ) unless $self->{epn} =~ /^\d*$/;

    if ($self->{add}) {
        my $pica = eval { PICA::Record->new( $self->{add} ) };
        if ($pica) {
            $pica->sort;
	    	$self->{add} = "$pica";
        } else {
            $self->error( add => "malformed fields to add" );
        }
    }

    $self->{del} = [ 
        sort grep { $_ !~ /^\s*$/ } split(/\s*,\s*/, $self->{del}) 
    ];

    $self->error( del => "malformed fields to remove" )
        if grep { $_ !~  qr{^[012]\d\d[A-Z@](/\d\d)?$} } @{ $self->{del} };

    return $self;
}

=method perform ( $pica )

Perform the edit request on a PICA+ record and return the result. Returns
undef if the edit request is malformed. 

Only edits at level 0 and level 1 are supported by now.

=cut

sub perform {
    my ($self, $pica) = @_;

    return if $self->error or !$pica or !$pica->isa('PICA::Record');

    my $iln = $self->{iln};
    my $epn = $self->{epn};
    my $tags = [ split ',', $self->{del} ];

    my $add = PICA::Record->new( $self->{add} || '' );

    # new PICA record with all level0 fields but the ones to remove
    my @level0 = grep /^0/, @$tags;
    my @level1 = grep /^1/, @$tags;
    my @level2 = grep /^2/, @$tags;

    # Level 0
    my $result = $pica->main;
    $result->remove( @level0 ) if @level0;
    $result->append( $add->main );    

    # Level 1
    foreach my $h ( $pica->holdings ) {
        if (@level1 and (!$iln or $h->iln eq $iln)) {
            $h->remove( map { $_ =~ qr{/} ? $_ : "$_/.." } @level1 );
        } 
        $result->append( $h->fields );

        # TODO: level2 noch nicht nicht unterstützt
    }

    $result->sort;

    return $result;
}


=method perform_strict

Perform the edit request on a PICA+ record and return the result. Croaks with a
hash of error message on a malformed request, if no record id or neither add
nor del were provided as attributes, or if record id/iln/epn do not match the
original record. 

=cut

sub perform_strict {
    my ($self, $pica) = @_;

    return if $self->error;

    croak( { id => "record not found" } ) unless $pica;
    croak( { id => "missing record ID" } ) unless $self->{id};
    croak( { id => "PPN does not match" } ) unless $self->{ppn} eq $pica->ppn;

    unless( $self->{add} or $self->{del} ) {
        croak {
            add => "please provide some changes",
            del => "please provide some changes",
        };
    }

    # TODO: check for disallowed fields to add/remove

    my ($iln,$epn) = ($self->{iln}, $self->{epn});

    croak( { iln => "ILN missing" } ) 
        if $epn ne '' and $iln eq ''; # TODO: get ILN from record

    if ( $iln ) {
        my $holding = $pica->holdings( $iln );
        croak { iln => "ILN not found in this record" } unless $holding;
        
        my @items = $holding->items;
    }

    return $self->perform( $pica );
}

=method error( $attribute => $message )

Gets or sets an error message connected to an attribute.

=cut

sub error {
    my $self = shift;

    return (scalar %{$self->{errors}}) unless @_;
    
    my $attribute = shift;
    return $self->{errors}->{$attribute} unless @_;

    my $message = shift;
    $self->{errors}->{$attribute} = $message;

    return $message;
}

1;

__END__

# Checks whether the edit could be performed
sub validate_edit {
    my $self  = shift;
#    my $unapi = shift or croak 'Missing unAPI configuration';

    my $pica;
    if ($self->{record} !~ /^test/) {
        $pica = LWP::Simple::get( "$unapi?id=".$self->{record}."&format=pp" );
        $pica = eval { PICA::Record->new( $pica ); };
        if (!$pica) {
            $self->{malformed}->{record} //= "not found";
            croak "Failed to get PICA+ record";
        }

        # predict outcome
        $self->{predict} = { deltag => { }, add => { } };
        if ($self->{deltags}) {
            foreach my $tag ( @{ $self->{del} } ) {
                my $status = -1;
                given($tag) {
                    when(/^0/) { # exact tag
                        my @fields = $pica->field($tag);
                        $status = scalar @fields; 
                    };
                    when(/^1/) { 
                        my $t = $tag =~ qr{/} ? $tag : "$tag/..";
                        if ($holding) {
                            my @f = $holding->field($t);
                            $status = scalar @f;
                        }
                    };
                    when(/^2/) {
                        my $t = $tag =~ qr{/} ? $tag : "$tag/..";
                        if ($item) {
                            my @f = $item->field($t);
                            $status = scalar @f;
                        }
                    };
                }
                $self->{predict}->{deltag}->{$tag} = $status;
            }
        }

        if ($self->{addfields}) {
            foreach my $f ( PICA::Record->new( $self->{addfields} )->fields ) {
                # TODO: testen, ob Feld schon so vorhanden, dann löschen
                $self->{predict}->{add}->{"$f"} = "0"
            }
        }

        $self->{modrec} = "".edit_record($self, $pica);
    }

    return 1;
}


# create a minimal record for editing
sub get_record {
    my ($self,$from) = @_;

    my $pica = shift;

    my $n = PICA::Record->new;
    $n->ppn( $pica->ppn );

    return $n;
}


# Creates an new edit with partly normalized (but not validated) values
# TODO: remove
sub new_edit {
    my $self = { }; #bless { }, shift;
    my %args = @_;

    if ( my @mal = malformed_edit($self) ) {
        $self->{malformed} = { map { $_ => "invalid" } @mal },
        $self->{error}     = "invalid edit";
    }

    return $self;
}


1;
