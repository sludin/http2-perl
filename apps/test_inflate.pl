use strict;
use warnings;
use lib "../lib";
use HTTP2::Draft::Compress;

use Data::Dumper;

sub compare_hash
{
  my $hash_a = shift;
  my $hash_b = shift;

  for my $name ( keys %$hash_a ) {
    if ( $hash_a->{$name} ne $hash_b->{$name} ) {
      return 0;
    }
  }

  for my $name ( keys %$hash_b ) {
    if ( $hash_a->{$name} ne $hash_b->{$name} ) {
      return 0;
    }
  }

  return 1;
}

sub inflate_ok
{
  my $test = shift;

  my $block = $test->[0];
  my $headers = $test->[1];

  my $compress = HTTP2::Draft::Compress->new( request => 1 );
  my $h = $compress->inflate( $block );

  if ( compare_hash( $headers, $h ) ) {
    pass( "Headers match" );
  }
  else {
    fail( "Headers do not match" );
  }

}





my $block = "84440c2f73696d706c652e68746d6c43" .
            "0e3132372e302e302e313a3834343381" .
            "4d514d6f7a696c6c612f352e3020284d" .
            "6163696e746f73683b20496e74656c20" .
            "4d6163204f5320582031302e383b2072" .
            "763a32352e3029204765636b6f2f3230" .
            "3133303830342046697265666f782f32" .
            "352e30463f746578742f68746d6c2c61" .
            "70706c69636174696f6e2f7868746d6c" .
            "2b786d6c2c6170706c69636174696f6e" .
            "2f786d6c3b713d302e392c2a2f2a3b71" .
            "3d302e38490e656e2d55532c656e3b71" .
            "3d302e35";


my $headers = {
          'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20130804 Firefox/25.0',
          'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          ':scheme' => 'https',
          'accept-language' => 'en-US,en;q=0.5',
          ':host' => '127.0.0.1:8443',
          ':method' => 'GET',
          ':path' => '/simple.html'
        };

my $b = pack( "C*", map { hex($_) } unpack( "(a2)*", $block ) );


my @tests = (
             [ $block, $b ],
             );


for my $test ( @tests ) {
  inflate_ok( $test );
}




__END__
84 44 0c 2f 73 69 6d 70 6c 65 2e 68 74 6d 6c 43 0e 31 32 37 2e 30 2e 30 2e 31 3a 38 34 34 33 81 4d 51 4d 6f 7a 69 6c 6c 61 2f 35 2e 30 20 28 4d 61 63 69 6e 74 6f 73 68 3b 20 49 6e 74 65 6c 20 4d 61 63 20 4f 53 20 58 20 31 30 2e 38 3b 20 72 76 3a 32 35 2e 30 29 20 47 65 63 6b 6f 2f 32 30 31 33 30 38 30 34 20 46 69 72 65 66 6f 78 2f 32 35 2e 30 46 3f 74 65 78 74 2f 68 74 6d 6c 2c 61 70 70 6c 69 63 61 74 69 6f 6e 2f 78 68 74 6d 6c 2b 78 6d 6c 2c 61 70 70 6c 69 63 61 74 69 6f 6e 2f 78 6d 6c 3b 71 3d 30 2e 39 2c 2a 2f 2a 3b 71 3d 30 2e 38 49 0e 65 6e 2d 55 53 2c 65 6e 3b 71 3d 30 2e 35
