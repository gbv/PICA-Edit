use Test::More;
use Test::Exception;
use strict;

use PICA::Modification;
use PICA::Edit::Queue;

use File::Temp qw(tempfile);
use DBI;

eval {
    require DBD::SQLite;
    DBD::SQLite->import();
};
plan skip_all => "Skipping tests in lack of DBD::SQLite" if $@;

## test database configuration

dies_ok { PICA::Edit::Queue->new( database => undef ) } 'database required';

my $dbfile;
(undef,$dbfile) = tempfile();
my $dsn = "dbi:SQLite:dbname=$dbfile";
my $dbh = DBI->connect($dsn,"","") 
    or plan skip_all => "Skipping tests in lack of DBD::SQLite";

my $q = PICA::Edit::Queue->new( database => $dbh );
isa_ok($q,'PICA::Edit::Queue');

my $q = PICA::Edit::Queue->new( database => { dsn => $dsn } );
isa_ok($q,'PICA::Edit::Queue');

###

is($q->count,0,'empty queue');

sub picaedit { PICA::Modification->new( id => "foo:ppn:789" ) };

my $e1 = picaedit;
#print Dumper($e1)."\n";

my $id = $q->insert( $e1 );
ok( $id, "inserted edit" );
is( $q->count, 1, 'count = 1' );

my $e2;
($e2) = $q->select( { edit_id => $id } );
$e2   = $q->select( { edit_id => $id } );
ok( $e2, "selected edit" );

#use Data::Dumper;
#print Dumper($e2)."\n";
#print( $e2->{created} );

done_testing;
