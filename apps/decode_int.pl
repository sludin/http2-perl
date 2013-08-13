use strict;
use warnings;
use lib "../lib";
use HTTP2::Draft::Compress;

use Data::Dumper;

my $bits = shift;
my @bytes = map { hex($_) } @ARGV;

my $n = HTTP2::Draft::Compress::decode_int( \@bytes, $bits  );

print $n, "\n";

__END__

5 1F 9A 0A
1337
