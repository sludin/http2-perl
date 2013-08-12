#!perl -T
use 5.008;
use strict;
use warnings FATAL => 'all';
use Test::More;

use HTTP2::Draft::Compress;

plan tests => 2;

sub int_encoding_ok
{
  my $test = shift;

  my $bits            = $test->[0];
  my $bytes_ref       = [ @{$test->[1]} ]; # decode_int consumes the bytes
                                           # passed to it.  Copy so the
                                           # tests are not destroyed.
  my $expected_result = $test->[2];

  my $n = HTTP2::Draft::Compress::decode_int( $bytes_ref, $bits );

  if ( $n == $expected_result ) {
    pass( "Expected result decoded" );
  }
  else {
    fail( "Expected $expected_result, got $n" );
  }
}

sub int_decoding_ok
{
  my $test = shift;

  my $bits            = $test->[0];
  my $expected_output = $test->[1];
  my $int_to_encode   = $test->[2];

  my $bytes = HTTP2::Draft::Compress::encode_int( $int_to_encode, $bits );


  if ( @$bytes != @$expected_output ) {
    fail ( Dumper( $expected_output ) . Dumper( $bytes ) );
  }

  for my $i ( 0 .. scalar( @$bytes ) - 1 ) {

    if ( $bytes->[$i] != $expected_output->[$i] ) {
      fail( "Decoding error" );
      return;
    }
  }

  pass( "Expected result encoded" );
}

my @tests = (
             [ 5, [ 0x1F, 0x9A, 0x0A ], 1337 ],
            );

for my $test ( @tests ) {
  int_encoding_ok( $test );
}

for my $test ( @tests ) {
  int_decoding_ok( $test );
}

__END__

5 1F 9A 0A
1337
