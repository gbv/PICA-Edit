package PICA::Edit::Request;
#ABSTRACT: Modification request of an identified PICA+ record

use 5.010;

use Carp;
use Try::Tiny;
use PICA::Record;
use LWP::Simple ();

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
        $self->{dbkey} = lc($2) if defined $2;
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

=method retrieve_and_perform ( unAPI => $url )

Retrieve the record via unAPI. This method actually modifies the edit request,
so you should only call it once.  On success the PICA+ record before and after
modification is stored as L<PICA::Record> in the edit request. On failure, the
error is added to the edit.

=cut

sub retrieve_and_perform {
    my ($self, %args) = @_;
    return $self if $self->error;

    # TODO: move this to other code to separate retrieve and before/after (?) 

    try { 
        my $url = $args{unAPI} . '?format=pp&id=' . $self->{id};
        $self->{before} = PICA::Record->new( LWP::Simple::get( $url ) ); 
    } catch {
        $self->error( id => 'failed to retrieve record' ); 
    };

    if ( $self->{before} ) {
        try {
            $self->{after} = $self->perform_strict( $self->{before} );
        } catch {
            while (my ($k,$v) = each %$_) {
                $self->error( $k => $v );
            }
        };
    }
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

=method status

Returns the current status of this edit request, which is: -1 for edit requests
with error, 0 for normal, wellformed edit request, 1 for performed edits, 2 for
empty, performed edits.

=cut

sub status {
    my $self = shift;
    return -1 if $self->error;
    return 0 unless $self->{before} and $self->{after};
    return 2 if $self->{before}->string eq $self->{after}->string;
    return 1;
}

1;
