use strict;
use warnings;
use lib "../lib";
use HTTP2::Draft::Compress;

use Data::Dumper;

my @bytes = map { hex($_) } @ARGV;

my $block = pack "C*", @bytes;

my $compress = HTTP2::Draft::Compress->new( request => 1 );
$compress->inflate( $block );








__END__
84 44 0c 2f 73 69 6d 70 6c 65 2e 68 74 6d 6c 43 0e 31 32 37 2e 30 2e 30 2e 31 3a 38 34 34 33 81 4d 51 4d 6f 7a 69 6c 6c 61 2f 35 2e 30 20 28 4d 61 63 69 6e 74 6f 73 68 3b 20 49 6e 74 65 6c 20 4d 61 63 20 4f 53 20 58 20 31 30 2e 38 3b 20 72 76 3a 32 35 2e 30 29 20 47 65 63 6b 6f 2f 32 30 31 33 30 38 30 34 20 46 69 72 65 66 6f 78 2f 32 35 2e 30 46 3f 74 65 78 74 2f 68 74 6d 6c 2c 61 70 70 6c 69 63 61 74 69 6f 6e 2f 78 68 74 6d 6c 2b 78 6d 6c 2c 61 70 70 6c 69 63 61 74 69 6f 6e 2f 78 6d 6c 3b 71 3d 30 2e 39 2c 2a 2f 2a 3b 71 3d 30 2e 38 49 0e 65 6e 2d 55 53 2c 65 6e 3b 71 3d 30 2e 35
