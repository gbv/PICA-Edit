use Test::More;
use Test::Exception;
use strict;

use PICA::Modification;
use PICA::Modification::Queue;
use PICA::Modification::TestQueue;

use File::Temp qw(tempfile);
use DBI;

eval {
    require DBD::SQLite;
    DBD::SQLite->import();
};
plan skip_all => "Skipping tests in lack of DBD::SQLite" if $@;

## test database configuration

#dies_ok { PICA::Modification::Queue->new( database => { } ) 'database required';

my $dbfile;
(undef,$dbfile) = tempfile();
my $dsn = "dbi:SQLite:dbname=$dbfile";
my $dbh = DBI->connect($dsn,"","") 
    or plan skip_all => "Skipping tests in lack of DBD::SQLite";

new_ok 'PICA::Modification::Queue' => [ 'DB', database => $dbh ];

my $q = new_ok 'PICA::Modification::Queue' => [ 'DB', database => { dsn => $dsn } ];
test_queue $q, 'PICA::Modification::Queue::DB';

done_testing;
