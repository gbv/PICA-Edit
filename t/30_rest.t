use strict;
use warnings;
use Test::More;

use App::Picaedit;
use PICA::Edit::Server;

use File::Temp qw(tempfile);
use DBI;

eval {
    require DBD::SQLite;
    DBD::SQLite->import();
};
plan skip_all => "Skipping tests in lack of DBD::SQLite" if $@;

my $dbfile;
(undef,$dbfile) = tempfile();
my $dsn = "dbi:SQLite:dbname=$dbfile";

my $server = PICA::Edit::Server->new(
	database => $dsn
);

## test_psgi $server

#my $app = App::Picaedit->new(
#	rest => 
#);

ok(1);

done_testing;
