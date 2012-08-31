package PICA::Edit;
#ABSTRACT: Queued modification requests to PICA+ databases

use 5.012;
use strict;
use warnings;

use PICA::Edit::Request;
use PICA::Edit::Queue;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(editrequest);

sub editrequest { PICA::Edit::Request->new(@_) }

1;

=head1 SEE ALSO

L<PICA::Edit::Request>, L<PICA::Edit::Queue>, L<App::picaedit>, L<picaedit>.

=cut
