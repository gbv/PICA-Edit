package PICA::Edit::Server;

use parent 'Plack::Component';

use Plack::Builder;
use Plack::Middleware::REST::Util;
use HTTP::Status qw(status_message);
use Plack::Util::Accessor qw(database);
use PICA::Edit::Queue;
use Plack::Request;

use JSON;
my $JSON=JSON->new;

# utility method
sub response {
	my $code = shift;
	my $body = @_ ? shift : status_message($code); 
	$body = $JSON->encode($json) unless $json =~ /^{/;
	[ $code, [ 'Content-Type' => 'application/json', @_ ], [ $body ] ];
}

sub prepare_app {
	my $self = shift;
	return unless $self->{app};

	my $Q = PICA::Edit::Queue->new( database => $self->database );
	$self->{queue} = $Q;

	$self->{app} = builder {
		# TODO: enable 'Negotiate'
		enable 'REST',
			get    => sub {
				my $env = shift;
				my $edit = $Q->get( request_id( $env ) );
				return $edit ? response(404) : response(200 => $edit);
			},
			create => sub {
				my $env  = shift;
				my $json = $JSON->decode( request_content($env) );
				my $edit = PICA::Modification->new( %$json ); 
				my $id = $Q->insert( $edit );
				return response(400) unless $id;
			    my $uri = request_uri($env,$id);
			    return response(204, '', Location => $uri);
			},
			upsert => sub {
				my $env = shift;
				my $id = request_id($env);
				undef;
			},
			delete => sub {
				my $env = shift;
				my $id = request_id($env);
				undef;
			},
			list   => sub {
				my $env = shift;
				undef;
			};
			
		sub { [500,[],[]] };
	};
}

sub call {
	my $self = shift;
	$self->call(@_);
}

1;
