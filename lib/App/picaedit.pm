package App::picaedit;
#ABSTRACT: picaedit core application

use strict;
use warnings;
use v5.10;

use base 'App::Command'; # at least 0.00_1

use Carp;
use Try::Tiny;
use Scalar::Util qw(reftype blessed);
use Log::Contextual qw(:log :dlog with_logger);
use PICA::Edit::Request;
use PICA::Edit::Queue;

use LWP::Simple ();

use File::Slurp;
use IO::Interactive qw(is_interactive);

use JSON;
our $JSON = JSON->new->utf8(1)->pretty(1);

sub init {
    my $self = shift;

    $self->{queue} ||= PICA::Edit::Queue->new( 
        database => $self->{database},
    );
}

sub edit_from_input {
    my $self = shift;

	# check whether edit has been provided from configuration

    my $edit;
	
	if ( $self->{edit} ) {
		$edit = PICA::Edit::Request->new( $self->{edit} );
	} elsif( grep { exists $self->{$_} } qw(id iln epn del add) )  {
		$edit = PICA::Edit::Request->new(
    	    map { $_ => $self->{$_} } qw(id iln epn del add)
	    );
	} elsif( !is_interactive() ) { # from STDIN
		$edit = read_file( \*STDIN );
		log_trace { "edit from STDIN: $edit" };
		$edit = PICA::Edit::Request->new( $edit );
	}

	return $edit;
}

sub edit_error {
    my ($self, $msg, $edit) = @_;

    my %errors = %{$edit->{errors}};
    join "\n", map { "$msg $_: ".$errors{$_} } keys %errors;
}

# helper method
sub iterate_edits {
    my $self     = shift;
    my $callback = shift;

    log_error { "expect edit_id as argument" } unless @_;

    foreach (@_) {
        unless (/^\d+$/) {
            log_warn { "invalid edit_id: $_" };
            next;
        }
        my $edit = $self->{queue}->select( { edit_id => $_ } );
        if ($edit) {
            $_ = $edit;
            $callback->();
        } else {
            log_warn { "edit request not found: $_" };
            next;
        }
    }
}

sub iterate_performed_edits {
    my $self     = shift;
    my $callback = shift;

    $self->iterate_edits( sub {
        my $edit = $self->retrieve_and_perform_edit( $_ );

        if ($edit->error) {
            log_error { $self->edit_error( "" => $edit ); };
        } else {
            $_ = $edit;
            $callback->();
        }
    } => @_ );
}

=head1 COMMAND METHODS

=head2 command_request

Request a new edit.

=cut

sub command_request {
    my $self = shift;
    my $queue = $self->{queue};

    my $edit = $self->edit_from_input(@_);
    Dlog_trace { $_ } $edit;

    $self->retrieve_and_perform_edit( $edit );

    if ($edit->error) {
        log_error { $self->edit_error( "malformed edit" => $edit ) };
    } else {
        my $edit_id = $queue->insert( $edit );
		if ($edit_id) {
			log_info { "New edit request accepted: $edit_id" } 
		} else {
			log_error { "Failed to insert edit request" };
		}
    }
}

=head2 command_preview

Looks up an edit requests's edit, applies the edit and shows the result.

=cut

sub command_preview {
    my $self = shift;

    $self->iterate_performed_edits( sub {
		# TODO: do something more useful
        say $_->{after};
    } => @_ );
}

=head2 command_check

Check edits and mark as done on success, unless already processed.

=cut

sub command_check { 
    my $self = shift;

    $self->iterate_edits( sub {
		my ($status,$edit_id) = ($_->{status},$_->{edit_id});

		if ($status != 0) {
			log_info { "edit $edit_id is already status: $status" };
			return;
		}

        my $edit = $self->retrieve_and_perform_edit( $_ );
        if ($edit->error) {
            log_error { $self->edit_error( "" => $edit ); };
		} elsif ($edit->{before}->string ne $edit->{after}->string) {
			$self->{queue}->update( { status => 0 }, { edit_id => $edit_id } );
			log_info { "edit $edit_id has not been performed yet" };
		} else {
			$self->{queue}->update( { status => 1 }, { edit_id => $edit_id } );
			log_info { "edit $edit_id is now done" }
		}
    } => @_ );
}

sub command_reject {
    my $self    = shift;

    $self->iterate_edits( sub {
        ...
    } => @_ );
}


sub command_remove {
    my $self = shift;

    log_error { "expect edit_id as argument" } unless @_;

    foreach (@_) {
        unless (/^\d+$/) {
            log_warn { "invalid edit_id: $_" };
            next;
        }

        my $s = $self->{queue}->remove( { edit_id => $_ } );
#        say "S:$s\n";
#        if (!$queue->remove( { edit_id => $_ } )) {
#            say "not found";
#        }
    }
    # TODO: log successful removal
}

sub command_list {
    my $self   = shift;

    my $status = @_ ? shift : $self->{status};
    $status = do { given ($status) {
        when ('pending') { 0; };
        when ('rejected') { -1; };
        when ('failed') { -2; };
        when ('done') { 1; };
        default { '' };
    } };
    
    my $where = { };
    $where->{status} = $status if $status =~ /^(-1|0|1|2)$/;

    foreach (qw(iln epn creator id del add)) {
        $where->{$_} = $self->{$_} if $self->{$_};
    }

    my $limit = undef;
    $limit = $self->{limit} if ($self->{limit} || '') =~ /^\d+$/;

    my @list = $self->{queue}->select( $where, { limit => $limit } );
    say $JSON->encode(\@list); # TODO: other output format
}

=method retrieve_and_perform_edit ( $edit )

Retrieve the record via unAPI. This method actually modifies the edit request,
so you should only call it once.  On success the PICA+ record before and after
modification is stored as L<PICA::Record> in the edit request. On failure, the
error is added to the edit.

=cut

sub retrieve_and_perform_edit {
    my ($self, $edit) = @_;

	unless (blessed $edit) {
		bless $edit, 'PICA::Edit::Request';
		$edit->check;
	}
    Dlog_trace { "as_edit $_" } $edit;
    
    return $edit if $edit->error;

    my $unapi = $self->{unapi} || croak "Missing unapi configuration";
    my ($before,$after);

    unless ($edit->{id} && $edit->{ppn}) {
        $edit->error( id => "missing record id/ppn" );
        return $edit;
    }

    try { 
        my $url = $unapi . '?format=pp&id=' . $edit->{id};
		log_trace { $url };
        $before = PICA::Record->new( LWP::Simple::get( $url ) ); 
    } catch {
        $edit->error( id => 'failed to retrieve record' ); # modifies edit
    };

    if ( $before ) {
        try {
            $after = $edit->perform_strict( $before );
        } catch {
            while (my ($k,$v) = each %$_) {
                $edit->error( $k => $v ); # modifes edit
            }
        };
    }

    $edit->{before} = $before;
    $edit->{after}  = $after;

    return $edit;
}

1;

=head1 SYNOPSIS

    # run as command line script
    my $picaedit = App::picaedit->new;
    $picaedit->parse_options(@ARGV);
    $picaedit->execute;

    # directly execute
    App::picaedit->new( %config )->execute( @args );

=head1 DESCRIPTION

App::picaedit is the core of the L<picaedit> command line client. You can also
create your own frontend using this package. Eventually App::picaedit delegates
commands to an instance of L<PICA::Edit::Queue>.

=head1 SEE ALSO


=cut