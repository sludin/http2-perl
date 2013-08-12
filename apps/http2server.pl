use strict;
use warnings;
use lib '../lib';

use Data::Dumper;

use HTTP2::Draft::Server;
use HTTP::Date;

use HTTP2::Draft::Log qw( $log );

$SIG{PIPE} = sub { print "Caught sigpipe\n"; exit(1) };

$ENV{IO_ASYNC_DEBUG} = 1;

my %content_types =
(
 html => "text/html",
 htm  => "text/html",
 txt  => "text/plain",
 gif  => "image/gif",
 jpg  => "image/jpeg",
 jpeg => "image/jpeg",
 css  => "text/css",
 js   => "text/javascript",
 '_none' => "text/html"
);


my %params = (
	      SSL_cert_file     => 'servercert.pem',
	      SSL_key_file      => 'serverkey.pem',
	      SSL_cipher_list   => 'RC4-MD5',  # to help ssldump

	      on_request        => \&on_request,

	      root              => "/Users/sludin/Documents/projects/gallery/html",
	      port              => 8443,
	      host              => "127.0.0.1"
);


my $server = HTTP2::Draft::Server->new( %params );

HTTP2::Draft::Log::init( "DEBUG" );

$server->start();




sub on_request
{
  my $request = shift;
  my $stream = shift;

  my $uri = $request->uri()->path();
  my ($path,$filename) = $uri =~ /(.*\/)(.*)$/;
  $filename ||= "index.html";
  my $query = $request->uri()->query();
  my ($ext) = $filename =~ /\.([^\.]*)$/;
  $ext ||= "_none";

  my $fullpath = $server->{root} . "$path$filename";

  my $content;
  my $code = 0;
  my $msg = "";
  my $content_type;

  my $headers = {};

  if ( open( my $fh, "<", $fullpath ) ) {
    while( <$fh> ) {
      $content .= $_;
    }
    close( $fh );


    $headers->{'content-type'} = exists $content_types{$ext} ? $content_types{$ext} : "text/plain";
#    $headers->{'cache-control'} = "max-age=300";
    $headers->{'cache-control'} = "no-store";
    $headers->{'last-modified'} = time2str( (stat $fullpath)[9] );

    $code = 200;
    $msg = "OK";


  }
  else {
    $content = "<html><head></head><body>$fullpath Not found</body></html>";
    $code = 404;
    $msg = "Not Found";
    $headers->{'content-type'} = "text/html";
#    $headers->{'cache-control'} = "max-age=300";
    $headers->{'cache-control'} = "no-store";
    $headers->{'last-modified'} = time2str( time );
  }



  my $resp_headers = new HTTP::Headers( %$headers );

  my $response = HTTP::Response->new( $code, $msg, $resp_headers, $content );

  $server->response( $response, $stream );

#  exit(0);
}

