#!perl -T
use 5.008;
use strict;
use warnings FATAL => 'all';
use Test::More;

use HTTP2::Draft::Compress;

plan tests => 1;

sub compare_lists
{
  my $list_a = shift;
  my $list_b = shift;

  my $n = scalar( @$list_a ) - 1;

  for my $i ( 0 .. $n ) {
    if ( $list_a->[$i] != $list_b->[$i] ) {
      return 0;
    }
  }

  return 1;
}

sub test_string_encode_ok
{
  my $test = shift;

  my $encoded_string = [ @{$test->[0]} ];
  my $string = $test->[1];

  my $extracted_string = HTTP2::Draft::Compress::extract_string( $encoded_string );



  if ( $string eq $extracted_string ) {
    pass( "OK" );
  }
  else {
    fail( "Got $extracted_string, expected $string" );
  }
}



my @tests = ( [
               [ 0x15, 0x2f, 0x73, 0x63, 0x72, 0x69, 0x70, 0x74,
                 0x2f, 0x6a, 0x61, 0x76, 0x61, 0x73, 0x63, 0x72,
                 0x69, 0x70, 0x74, 0x2e, 0x6a, 0x73 ],
               "/script/javascript.js",
              ],
            );


for my $test ( @tests ) {
  test_string_encode_ok( $test );
}

__END__


15 2f 73 63 72 69 70 74 2f 6a  61 76 61 73 63 72 69 70 74 2e 6a 73




0000 27 ''' 26 '&' 15     2f '/' 
0004 73 's' 63 'c' 72 'r' 69 'i' 
0008 70 'p' 74 't' 2f '/' 6a 'j' 
000C 61 'a' 76 'v' 61 'a' 73 's' 
0010 63 'c' 72 'r' 69 'i' 70 'p' 
0014 74 't' 2e '.' 6a 'j' 73 's' 
0018 2a '*' 29 ')' 03     2a '*' 
001C 2f '/' 2a '*' 
