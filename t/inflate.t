#!perl -T
use 5.008;
use strict;
use warnings FATAL => 'all';
use Test::More;

use HTTP2::Draft::Compress;

plan tests => 4;

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
  my $compress = shift;
  my $test = shift;

  my $block = $test->[0];
  my $headers = $test->[1];


#  diag(  Dumper( $headers ) );

  my $h = $compress->inflate( $block );

  if ( compare_hash( $headers, $h ) ) {
    pass( "Headers match" );
  }
  else {
    fail( "Headers do not match" );
  }

}




my @tests = (
             [
               "84440B2F696E6465782E68746D6C430E3132372E302E302E313A38343433814D514D6F7A696C6C612F352E3020284D6163696E746F73683B20496E74656C204D6163204F5320582031302E383B2072763A32352E3029204765636B6F2F32303133303830342046697265666F782F32352E30463F746578742F68746D6C2C6170706C69636174696F6E2F7868746D6C2B786D6C2C6170706C69636174696F6E2F786D6C3B713D302E392C2A2F2A3B713D302E38490E656E2D55532C656E3B713D302E35",
               {
                 'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20130804 Firefox/25.0',
                 'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                 ':scheme' => 'https',
                 'accept-language' => 'en-US,en;q=0.5',
                 ':host' => '127.0.0.1:8443',
                 ':method' => 'GET',
                 ':path' => '/index.html'
               }
             ],
             [
               "27260E2F6373732F7374796C652E6373732A2912746578742F6373732C2A2F2A3B713D302E314F2168747470733A2F2F3132372E302E302E313A383434332F696E6465782E68746D6C",
               {
                 'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20130804 Firefox/25.0',
                 'accept' => 'text/css,*/*;q=0.1',
                 'accept-language' => 'en-US,en;q=0.5',
                 ':method' => 'GET',
                 ':scheme' => 'https',
                 ':host' => '127.0.0.1:8443',
                 ':path' => '/css/style.css',
                 'referer' => 'https://127.0.0.1:8443/index.html'
               },
             ],
             [
               "2726152F7363726970742F6A6176617363726970742E6A732A29032A2F2A",
               {
                 'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20130804 Firefox/25.0',
                 'accept' => '*/*',
                 'accept-language' => 'en-US,en;q=0.5',
                 ':method' => 'GET',
                 ':scheme' => 'https',
                 ':host' => '127.0.0.1:8443',
                 ':path' => '/script/javascript.js',
                 'referer' => 'https://127.0.0.1:8443/index.html'
               },
             ],
             [
               "2726192F696D616765732D7374617469632F7370616365722E6769662A2921696D6167652F706E672C696D6167652F2A3B713D302E382C2A2F2A3B713D302E35",
               {
                 'user-agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:25.0) Gecko/20130804 Firefox/25.0',
                 'accept' => 'image/png,image/*;q=0.8,*/*;q=0.5',
                 'accept-language' => 'en-US,en;q=0.5',
                 ':method' => 'GET',
                 ':scheme' => 'https',
                 ':host' => '127.0.0.1:8443',
                 ':path' => '/images-static/spacer.gif',
                 'referer' => 'https://127.0.0.1:8443/index.html'
               },
             ],
           );


my $compress = HTTP2::Draft::Compress->new( request => 1 );

for my $test ( @tests ) {
  $test->[0] = pack( "C*", map { hex($_) } unpack( "(a2)*", $test->[0] ) );
  inflate_ok( $compress, $test );
}




