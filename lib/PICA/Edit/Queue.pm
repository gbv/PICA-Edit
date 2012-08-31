package PICA::Edit::Queue;
#ABSTRACT: Manages a list of PICA edit requests

use strict;
use warnings;
use v5.12;

use Carp;
use DBI;
use Scalar::Util qw(blessed);
use Log::Contextual qw(:log :dlog);

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

=method new( database => $database )

Create a new Queue. See L</database> for configuration.

=cut

sub new {
    my ($class,%config) = @_;

    my $self = bless { }, $class;
	$self->database( $config{database} );

    $self;
}

=method database( [ $dbh | { %config } | %config ] )

Get or set a database connection either as L<DBI> handle (config value C<dbh>)
or with C<dsn>, C<username>, and C<password>. One can also set the C<table>. 

=cut

sub database {
	my $self = shift;
	return $self->{db} unless @_;

	## first set database
	
	my $db = (blessed $_[0] and $_[0]->isa('DBI::db')) 
		   ? { dbh => @_ }
		   : ( ref $_[0] ? $_[0] : { @_ } );

	if ($db->{dbh}) { 
		$self->{db} = $db->{dbh};
	} elsif ($db->{dsn}) {
		$self->{db} = DBI->connect($db->{dsn}, $db->{username}, $db->{password});
		croak "failed to connect to database: ".$DBI::errstr unless $self->{db};
	} else {
		croak "missing database configuration";
	}

	$self->{table} = $db->{table} || 'changes';

	log_trace { "Connected to database" };


	## then initialize database
	my $table = $self->{db}->quote_identifier($self->{table});

    # FIXME: only tested in SQLite. See L<SQL::Translator> for other DBMS
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

    $self->{db}->do( $sql );

	return $self->{db};
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
	$data{status}  = $attr{status} // 0;
	$data{message} = $attr{message} // "";

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});
    my $sql   = "INSERT INTO $table (" 
              . join(',', map { $db->quote_identifier($_) } keys %data)
              . ") VALUES ("
              . join(',', map { "?" } values %data)
              . ")";
    my @bind  = values %data;

    $db->do( $sql, undef, @bind );
	$db->last_insert_id(undef,undef, $self->{table}, 'edit_id');
}

=method remove( { edit_id => $edit_id } )

Entirely remove an edit requests. Returns the number of removed requests.

=cut

sub remove {
    my ($self, $where) = @_;
	my $edit_id = $where->{edit_id};

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});
    my $sql   = "DELETE FROM $table WHERE "
              . $db->quote_identifier('edit_id')
              . "=?";

    my $num = 1*$self->_dbdo( $sql, undef, $edit_id );
	log_warn { 'edit request not found to remove' } unless $num;
	return $num;
}

sub _dbdo {
	my $self = shift;
	my $sql  = shift;
	my $attr = shift;
	my @bind = @_;

    my $db   = $self->{db};

	log_trace { "SQL '$sql': ".join(',',@bind) };

	my $r = $db->do( $sql, $attr, @bind );
	log_error { $DBI::errstr; } unless $r;

	return $r;
}

=method select( { key => $value ... } [ , { limit => $limit } ] )

Retrieve one or multiple edit requests.

=cut

sub select {
    my ($self, $where, $opts) = @_;

    $opts ||= { };
    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});

    my $limit = $opts->{limit} || (wantarray ? 0 : 1);

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

=method update( { status => $status [, message => $message ] }, { edit_id => $edit_id})

Reject (status/message), 

=cut

sub update {
    my ($self, $data, $where) = @_;

	croak "missing where clause in update" unless %$where;
	croak "missing data in update" unless %$data;

    my $db    = $self->{db};
    my $table = $db->quote_identifier($self->{table});

    my @bind_params;
	($where, @bind_params) = $self->_where_clause( $where );

	Dlog_trace { "UPDATE $_" } @_;

	my $values = join ',', map { $db->quote_identifier($_) .'=?' } keys %$data;

    my $sql = "UPDATE $table SET $values"
		. ', '.$db->quote_identifier('updated').'=CURRENT_TIMESTAMP'
		. " $where";
    @bind_params = (values %$data, @bind_params);

    my $num = $self->_dbdo( $sql, undef, @bind_params );
	log_warn { 'edit request not found to update' } unless $num;
	return ($num ? 1*$num : $num);
}

=method reject( $edit_id, { message => $message } )

Reject an edit request, optional with a message.

=cut

sub reject {
	...
}

1;

=head1 LOGGING

PICA::Edit::Queue uses L<Log::Contextual> for logging. No default package
logger is set so you E<must> set a logger in order to use this module.

=cut
