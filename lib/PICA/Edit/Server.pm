package PICA::Edit::Server;
#ABSTRACT: PICA edit request server as PSGI application

use strict;
use warnings;
use v5.10;

use parent qw(Plack::Component);

use Plack::Request;
use Plack::Response;
use App::picaedit;

sub prepare_app {
	my $self = shift;
	use Data::Dumper;
	
	my $backend = App::picaedit->new(
		# TODO: ...
		config => $self->{config}
	);
	$backend->prepare;

	# TODO: change logger for PSGI

	$self->{picaedit} = $backend;
}

sub call {
	my $self = shift;
	my $req  = Plack::Request->new(shift);

	my $path   = $req->path;
	my $method = $req->method;

	my $backend = $self->{picaedit};

	my $res = Plack::Response->new(404,[],['{"error":"Not found"}']);

	$res->headers( { 'Content-Type' => 'application/json; charset=utf-8' } );

	# TODO: log errors to $var
	
#	if ( $path =~ qr{^/(\d+)\.pp} ) {
#	} els
	if ( $path =~ qr{^/(\d+)\.pp} ) {
		my $edit_id = $1;
		if ($method eq 'GET') {
			my $body = $backend->execute('preview', $edit_id );
			#$backend->{result};
			
			$res->headers( { 'Content-Type' => 'text/plain' } );
			$res->body( $body ) if $body;

		} elsif ($method eq 'DELETE') {
			# TODO: access control
			...
			# TODO: on error
#			$backend->{queue}remove('check', $edit_id );
		}
	} else {
		
		# TODO: limit, status, sort_by, page etc.

		my $out = $backend->execute('list'); 
		$res->body( $out );
	}

	return $res->finalize;
}

1;

=head1 SYNOPSIS

    use PICA::Edit::Server;
	
	my $app = PICA::Edit::Server->new(
		database
		config => 'your_config_file'
	);

	$app;

=cut
