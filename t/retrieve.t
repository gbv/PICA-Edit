use strict;
use warnings;
use Test::More;

use PICA::Record;
use Try::Tiny;

use PICA::Edit::Request;

my $http = <<'PICA';
003@ $0456
047A $aFoo
PICA

no warnings 'redefine';
local *LWP::Simple::get = sub { $http; };

sub edit {
    PICA::Edit::Request->new( id => 'foo:ppn:456', del => '047A', add => '021A $abar' );
}
my $e = edit;

$e->retrieve_and_perform( unAPI => "http://example.org" );

isa_ok( $e->{before}, 'PICA::Record' );
isa_ok( $e->{after}, 'PICA::Record' );
is( $e->status, 1, 'status: 1' );

$http = undef;
$e = edit;
$e->retrieve_and_perform( unAPI => "http://example.org" );

ok( !$e->{before}, 'retrieve failed' );
ok( $e->error('id'), 'retrieve failed' );

done_testing;
