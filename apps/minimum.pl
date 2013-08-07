use strict;
use warnings;

use Perl::MinimumVersion;

my $filename = shift;

my $object = Perl::MinimumVersion->new( $filename ) || die $!;

print $filename, ": ", $object->minimum_version, "\n";
