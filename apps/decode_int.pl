use strict;
use warnings;
use lib "../lib";
use HTTP2::Draft::Compress;

my $bits = shift;
my @bytes = map { hex($_) } @ARGV;

my $n = HTTP2::Draft::Compress::decode_int( \@bytes, 0, $bits );

print $n, "\n";

