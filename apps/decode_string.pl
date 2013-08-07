use strict;
use warnings;
use lib "../lib";
use HTTP2::Draft::Compress;

use Data::Dumper;

my @bytes = map { hex($_) } @ARGV;

my $n = HTTP2::Draft::Compress::extract_string2( \@bytes );

print Dumper( \@bytes );

print $n, "\n";



__END__


15 2f 73 63 72 69 70 74 2f 6a  61 76 61 73 63 72 69 70 74 2e 6a 73
/script/javascript.js



0000 27 ''' 26 '&' 15     2f '/' 
0004 73 's' 63 'c' 72 'r' 69 'i' 
0008 70 'p' 74 't' 2f '/' 6a 'j' 
000C 61 'a' 76 'v' 61 'a' 73 's' 
0010 63 'c' 72 'r' 69 'i' 70 'p' 
0014 74 't' 2e '.' 6a 'j' 73 's' 
0018 2a '*' 29 ')' 03     2a '*' 
001C 2f '/' 2a '*' 
