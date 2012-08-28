use strict;
use warnings;
use Test::More;

use PICA::Record;
use Try::Tiny;
use PICA::Edit::Request;

my ($e,$pica,$x,$result);

$e = PICA::Edit::Request->new;
isa_ok($e,'PICA::Edit::Request');
ok( !$e->error, 'empty edit' );

$e = PICA::Edit::Request->new( id => 'abc:foo' );
ok( $e->error('id'), "malformed id" );
ok( $e->error, 'malformed edit' );

$e = PICA::Edit::Request->new( id => 'abc:ppn:123' );
ok( !$e->error, 'edit with record id' );

$pica = PICA::Record->new('003@ $01234');
$x = { };
try { $e->perform_strict($pica) } catch { $x = $_ };
ok( $x->{id}, "record not found" );

$pica = PICA::Record->new('003@ $0123');
$result = try { $e->perform_strict($pica) };
is( "$result", "$pica", "performed empty edit" );

# ...

done_testing;

