use strict;
use warnings;
use Test::More;

use PICA::Record;
use Try::Tiny;
use PICA::Edit qw(editrequest);

my ($e,$pica,$x,$result);

$e = PICA::Edit::Request->new();
isa_ok($e,'PICA::Edit::Request');
ok( $e->error, 'empty edit' );

$e = editrequest( id => 'abc:foo' );
ok( $e->error('id'), "malformed id" );
ok( $e->error, 'malformed edit' );
is( $e->status, -1, 'status: -1' );

my $add = '021A $aHi';

$e = editrequest( id => 'abc:ppn:123', add => $add );
ok( !$e->error, 'edit with record id' );
is( $e->status, 0, 'status: 0' );

$pica = PICA::Record->new('003@ $01234');
$x = { };
try { $e->perform_strict($pica) } catch { $x = $_ };
ok( $x->{id}, "record not found" );

$pica = PICA::Record->new('003@ $0123');
$result = try { $e->perform_strict($pica); };

is( "$result", "$pica$add\n", "performed edit" );

$add = '021A $0x';
$e = editrequest("{ \"id\": \"foo:ppn:abc\", \"add\": \"$add\" }");
is( $e->{add}, $add, "parsed from JSON" );

done_testing;

