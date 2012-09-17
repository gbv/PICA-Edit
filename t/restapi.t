use strict;
use warnings;
use v5.10;
use Test::More skip_all => 'not implemented yet';
use Plack::Testi;
use HTTP::Request::Common;

use App::Picaedit;

my $pe = App::Picaedit->new;

my $app = sub { };

test_psgi $app => sub {
	my $cb = shift;
	my $res = $cb->(GET '/edit/1');
};

done_testing;
