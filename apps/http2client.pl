use strict;
use warnings;
use lib '../lib';


use HTTP2::Draft::Client;

use Data::Dumper;

use URI;

use HTTP2::Draft::Log qw( $log );

use Getopt::Long qw( :config no_ignore_case );

use HTTP::Request;

use HTML::TokeParser;


my $level = 0;

my $options;

our $VERSION = "0.02";
my $APP = "http2client";
my $nrequests = 0;

GetOptions(
           "ciphers=s"   => \$options->{ciphers},
           "compressed"  => \$options->{compressed},
           "data|d=s"    => \$options->{data},
           "header|H=s"  => \@{$options->{header_list}},
           "head|I"      => \$options->{head},
           "help|h"      => \$options->{help},
           "include|i"   => \$options->{include},
           "verbose|v+"   => \$options->{verbose},
           "version|V"   => \$options->{version},
           "get-assets|a" => \$options->{assets},
           "flowcontrol|f=i"       => \$options->{flowcontrol},
           "n"           => \$options->{discard}
          );

if ( $options->{version} ) {
  print "$APP $VERSION\n";
  exit(0);
}

if ( $options->{help} ) {
  print <<EOT;
Usage: $APP [options] URL
Options:
  -version -V   Print the version and exit
  -help    -h   Print this help and exit
  -data    -d   Send a POST request with the indciated data
  -header  -H   Add a header in Name: Value form
  -head    -I   Perform a HEAD request
  -ciphers      Indicate the cipher list to use
  -include -i   Include the response headers in the output
  -verbose -v   More data
  -assets  -a   Download assets from a base HTML page
  -flowcontrol -f Set the flow control window.  0 disables.
  -compressed   Request that the object are gzipped
  -n            Discard output
EOT
  exit(0);
}

for ( @{$options->{header_list}} ) {
  if ( /^\s*([^:]+)\s*:\s*(.*)$/ ) {
    $options->{headers}->{lc($1)} = $2;
  }
  else {
    $log->logdie( "Invalid hader pattern: $_" );
  }
}

my $dest = shift;

if ( $dest !~ /^https?:\/\// ) {
  $dest = "http://" . $dest;
}

my $uri = URI->new_abs( $dest, 'http' );

my $request = create_request( $uri, $options->{data}, $options->{compressed} );

my $port = 443;
my $host = $uri->authority();

if ( $uri->authority() =~ /:/ ) {
  ($host,$port) = $uri->authority() =~ /^(.*):(\d+)$/;
}


if ( $options->{verbose} == 1 ) {
  HTTP2::Draft::Log::init( "INFO" );
}
elsif ( $options->{verbose} >= 2 ) {
  HTTP2::Draft::Log::init( "DEBUG" );
}
else {
  HTTP2::Draft::Log::init( "ERROR" );
}

my %connect_args = (
		    on_response       => \&on_response,
		    on_http2_connect  => \&on_connect,
		    hostname          => $request->header( 'host' ),
		    host              => $host,
		    port              => $port,
);
if ( defined $options->{ciphers} ) {
  $connect_args{SSL_cipher_list} = $options->{ciphers};
}
if ( defined $options->{flowcontrol} ) {
  $connect_args{flow_control} = $options->{flowcontrol};
  print "Flow control = $options->{flowcontrol}\n";
}

my $client = HTTP2::Draft::Client->new( %connect_args );
$client->connect();




##########################################

sub create_request
{
  my $uri        = shift;
  my $content    = shift;
  my $compressed = shift;

  my $request = HTTP::Request->new();
  $request->method( 'GET' );
  $request->uri( $uri );

  my $port = 443;
  my $host = $uri->authority();

  if ( $uri->authority() =~ /:/ ) {
    ($host,$port) = $uri->authority() =~ /^(.*):(\d+)$/;
  }

  # TODO - the options use probably should not happen in this function
  $request->header(
                   'user-agent' => delete $options->{headers}->{'user-agent'} || "$APP-$VERSION",
                   'accept'     => delete $options->{headers}->{'accept'} || "*/*",
                   'host'       => delete $options->{headers}->{host} || $host
                  );

  if ( defined( $content ) && length( $content ) > 0 ) {
    $request->content( $content );
    $request->method( 'POST' );
  }

  if ( $compressed ) {
    $request->headers( 'accept-encoding' => "gzip" );
  }

  return $request;
}

sub request
{
  my $client = shift;
  my $request = shift;
  my $stream = shift;

  $nrequests++;
  $client->request( $request, $stream );
}



sub on_connect
{
  my ($client, $stream ) = @_;

  my $conn = $stream->{conn};

#  print $client, "\n";
#  print $stream, "\n";
#  print $conn, "\n";

  request( $client, $request, $stream );
#  $client->request( $request, $stream );
}

sub on_response
{
  my ($client, $stream, $streamid, $response ) = @_;


  if ( $options->{include} ) {
    print HTTP2::Draft::http_version(), " ", $response->code(), "\n";
    print $response->headers()->as_string();
    print "\n";
  }

  if ( ! $options->{discard} ) {
    print $response->content();
  }

  if ( $level == 0 && $options->{assets} ) {
    # read the html
    my $ct = $response->header( "content-type" );
    if ( $ct eq "text/html" ) {
      my $content = $response->content();
      my $p = HTML::TokeParser->new( \$content );
      my @urls;

      my $base = $uri;

      while( my $token = $p->get_token ) {
        if ( $token->[0] eq "S" ) {
          if ( $token->[1] eq "img" ) {
            push @urls, $token->[2]->{src};
          }
          elsif ( $token->[1] eq "script" ) {
            push @urls, $token->[2]->{src};
          }
          elsif ( $token->[1] eq "link" ) {
            push @urls, $token->[2]->{href};
          }
          elsif ( $token->[1] eq "base" ) {
            if ( exists $token->[2]->{href} ) {
              $base = URI->new( $token->[2]->{href} );
            }
          }
        }
      }

      @urls = grep { defined $_ } @urls;

#      print ( "Found ", scalar( @urls ), " resources to fetch:\n" );

      my @objects = grep { $_ = URI->new_abs( $_, $base ) } @urls;

      my $max = 10;
      for ( @objects ) {
        print Dumper( $_ );
        my $request = create_request( $_, undef, 0 );
        request( $client, $request, $stream );
        last if ! --$max;
      }

    }
  }

  $nrequests--;

#  $client->close( $stream );
  #print join("\n", map { s|/|::|g; s|\.pm$||; $_ } keys %INC);

  if ( $nrequests == 0 ) {
    exit(0);
  }

}


__END__






