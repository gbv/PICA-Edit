package PICA::Edit::Queue;
#ABSTRACT: Manages a list of PICA edit requests

use 5.010;
use strict;
use Carp;
use DBI;

=head1 DESCRIPTION

The edit queue stores a list of edit requests (L<PICA::Edit::Request>). In
addition to the edit request's attributes (id,iln,epn,del,add), each request is
stored with the following attributes:

=over 4

=item edit_id

A unique identifier for this edit request, assigned by the queue.

=item created

A timestamp when the edit request was inserted into the queue.

=item creator

An optional string to identify the creator of the request.

=back

In addition the following attributes are added or modified when an edit is
updated:

=over 4

=item status

The edit requests's status which is one of 0 for unprocessed, 1 for processed
or solved, and -1 for failed or rejected.

=item updated

Timestamp when the edit request was last updated or checked.

=item message

An optional message with information about current processing

=back

The current implementation is only tested with SQLite. Much code is borrowed
from L<Dancer::Plugin::Database::Handle>. A Future version may also work with
NoSQL databases.

=cut

=method new( db => $database )

Create a new Queue. Configuration must contain a L<DBI> database handle.

=cut

sub new {
    my ($class,%config) = @_;

    my $db = $config{db};
    croak "missing database handle" unless $db and $db->isa('DBI::db');

    my $self = bless { 
        db    => $db,
        table => 'changes',
    }, $class;

    $self->init;

    $self;
}

sub init {
    my $self = shift;

    # FIXME: only tested in SQLite. See L<SQL::Translator> for other DBMS
    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});
    my $sql = <<"SQL";
create table if not exists $table (
    `id`      NOT NULL,
    `iln`,
    `epn`,
    `add`,
    `del`,
    `edit_id` INTEGER PRIMARY KEY,
    `created` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `creator`,
    `updated` DATETIME DEFAULT CURRENT_TIMESTAMP,
    `message`,
    `status`
);
SQL

    $db->do( $sql );
}

=method insert( $edit, { creator => $creator } )

Insert a L<PICA::Edit::Request>. The edit is stored with a timestamp and
creator unless it is malformed. Returns an edit identifier or success. 
 
=cut

sub insert {
    my ($self, $edit, %attr) = @_;
    croak("malformed edit") if !$edit or $edit->error;

    my %data = ( map { $_ => $edit->{$_} } qw(id iln epn add del) );
    $data{creator} = $attr{creator} || '';
    $data{del}   = join(',',@{$data{del}});

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});
    my $sql   = "INSERT INTO $table (" 
              . join(',', map { $db->quote_identifier($_) } keys %data)
              . ") VALUES ("
              . join(',', map { "?" } values %data)
              . ")";
    my @bind  = values %data;

    $db->do( $sql, undef, @bind );
}

=method remove( $edit_id )

Entirely removes an edit request.

=cut

sub remove {
    my ($self, $edit_id) = @_;

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});
    my $sql   = "DELETE FROM $table WHERE "
              . $db->quote_identifier('edit_id')
              . "=?";

    $db->do( $sql, undef, $edit_id );
}

=method select( { key => $value ... } [ , { limit => $limit } ] )

Retrieve one or multiple edit requests.

=cut

sub select {
    my ($self, $where, $opts) = @_;

    my $opts ||= { };
    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});

    my $limit = $opts->{limit} || '';
    $limit = 1 if !wantarray and !$limit;

    my $which_cols = '*';
    # $which_cols = join(',', map { $db->quote_identifier($_) } @cols);

    my @bind_params;
    ($where, @bind_params) = $self->_where_clause( $where );

    my $sql = "SELECT $which_cols FROM $table $where"
            . " ORDER BY " . $db->quote_identifier('updated');
    $sql .= " LIMIT $limit" if $limit;

    # TODO: $edit->{del} must be an array (?)

    if ($limit == 1) {
        return $db->selectrow_hashref( $sql, undef, @bind_params );
    } else {
        return @{ $db->selectall_arrayref( $sql, { Slice => {} }, @bind_params ) };
    }
}

sub _where_clause {
    my ($self, $where) = @_;

    my $db  = $self->{db};
    my $sql = join(' AND ', map { $db->quote_identifier($_)."=? " } keys %$where);
    return ('',()) unless $sql;

    return ("WHERE $sql", values %$where);
}

=method count( { $key => $value ... } )

Return the number of edit request with given properties.

=cut

sub count {
    my ($self, $where) = @_;

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});

    my @bind_params;
    ($where, @bind_params) = $self->_where_clause( $where );
    my $sql = "SELECT COUNT(*) AS C FROM $table $where";

    my ($count) = $db->selectrow_array( $sql, undef, @bind_params );
    return $count;
}

=method update( { edit_id => $edit_id} { status => $status [, message => $message ] } )

Reject (status/message), 

=cut

sub update {
    my ($self, $where, $values) = @_;

    # message, status, lastcheck (timestamp)
    
#SET updated = CURRENT_TIMESTAMP
    # create timestamp and store
    #

}

=method reject( $edit_id, { message => $message } )

Reject an edit request, optional with a message.

=cut

sub reject {
}

1;
