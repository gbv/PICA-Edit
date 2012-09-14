use Test::More;
use Test::Exception;
use strict;

use PICA::Modification;
use PICA::Edit::Queue;
use PICA::Edit::Queue::Test;

use File::Temp qw(tempfile);
use DBI;

eval {
    require DBD::SQLite;
    DBD::SQLite->import();
};
plan skip_all => "Skipping tests in lack of DBD::SQLite" if $@;

## test database configuration

#dies_ok { PICA::Edit::Queue->new( database => { } ) 'database required';

my $dbfile;
(undef,$dbfile) = tempfile();
my $dsn = "dbi:SQLite:dbname=$dbfile";
my $dbh = DBI->connect($dsn,"","") 
    or plan skip_all => "Skipping tests in lack of DBD::SQLite";

my $q = PICA::Edit::Queue->new( database => $dbh );
isa_ok($q,'PICA::Edit::Queue::DB');


$q = PICA::Edit::Queue->new( database => { dsn => $dsn } );
isa_ok($q,'PICA::Edit::Queue::DB');

test_queue( $q );

done_testing;
