package HTTP2::Draft::Server;

use strict;
use warnings;

use HTTP2::Draft;
use HTTP2::Draft::Connection;
use HTTP2::Draft::Frame qw( :frames :settings :errors );
use HTTP2::Draft::Log qw( $log );

use IO::Async::Loop;
use IO::Async::HTTP2::Framer;

use Data::Dumper;

use HTTP::Request;
use HTTP::Response;

our $VERSION = $HTTP2::Draft::VERSION;

sub new
{
  my $class = shift;
  my %params = @_;
  my $self = {};
  bless $self, $class;
  $self->_init( %params );
  return $self;
}

sub _init
{
  my $self = shift;
  my %params = @_;

  $self->{params} = \%params;

  $self->{on_request} = delete $params{on_request};

  if ( ! $self->{on_request} ) {
    die "Expected on_request parameter";
  }

  $self->{host} = delete $params{host} || '0.0.0.0';
  $self->{port} = delete $params{port} || 443;
  $self->{root} = delete $params{root} || './';

  $self->{SSL_Params}->{SSL_cert_file}     = delete $params{SSL_cert_file};
  $self->{SSL_Params}->{SSL_key_file}      = delete $params{SSL_key_file};
  $self->{SSL_Params}->{SSL_npn_protocols} = delete $params{SSL_npn_protocols} || [ HTTP2::Draft::http_version() ];

  for ( keys %params ) 
  {
    if ( /^SSL_/ ) {
      $self->{SSL_Params}->{$_} = delete $params{$_};
    }
  }

  if ( ! exists $self->{SSL_Params}->{SSL_cert_file} ||
       ! exists $self->{SSL_Params}->{SSL_key_file} )
  {
    die "Must set SSL_cert_file and SSL_key_file";
  }

  $self->{state} = 0;
}

sub start
{
  my $self = shift;

  my $loop = IO::Async::Loop->new;

  $self->{loop} = $loop;



  my %p = (
           %{$self->{SSL_Params}},
           on_frame_error     => \&on_frame_error,
           on_frame_read      => sub { on_frame( $self, @_ ) },
           on_http2_connect   => sub {
             my ( $stream ) = $_[0];
             $stream->{server} = $self;
             $stream->{state} = 1;
             on_session( $self, @_ );
           },
           on_ssl_error      => \&on_ssl_error,
           on_listen         => \&on_listen,
           addr              => { ip       => $self->{host},
                                  family   => "inet",
                                  port     => $self->{port},
                                  socktype => "stream" },
    );

  $loop->HTTP2_listen( %p );


  $loop->run();
}

sub on_frame_error
{
  my $stream = shift;
  my $error = shift;

  # TODO: Send GOAWAY?

  $log->error( "Frame Error detected" );

  $stream->close();
  $log->logdie( $error );

}

sub on_listen
{
  $log->info( "Listening" );
}


sub on_session
{
  my $server = shift;
  my $stream = shift;

  $server->{loop}->add( $stream );
}

sub on_ssl_error
{
  my $msg = shift;
  $log->error( "SSL Error: $msg" );
}


sub on_frame
{
  my ( $server, $framer, $frame, $eof ) = @_;

#$log->error( "on_frame" );

  if ( $eof ) {
    $log->info( "EOF Indicated" );
    return 0;
  }

  my $conn = $framer->{conn};

  if ( $conn->{state} == 2 ) {
    if ( $frame->{type} == SETTINGS ) {
      $conn->handle_settings_frame( $frame );
      my $settings = HTTP2::Draft::Frame->new( SETTINGS,
                                             settings => { 4 => 100, 7 => 1024 * 64 } );
      $conn->write_frame( $settings );

      $conn->{state} = 3;
    }
    else {
      # TODO: look up the GOAWAY error codes if there are any
      my $goaway = HTTP2::Draft::Frame->new( GOAWAY,
                                           last_stream_id => 0,
                                           error_code     => 1 );
      $conn->write_frame( $goaway );
      $log->warn( "In state $conn->{state}.  Expexted SETTINGS frame.  Got $frame->{type}" );
    }
  }
  elsif ( $conn->{state} == 3 )
  {
    if ( $frame->{type} == HEADERS )
    {
      # For HTTP, HEADERS will be first but that is not always the case by spec
      my $stream;

      if ( exists $conn->{streams}->{$frame->{streamid}} ) {
        # we are getting headers for an existing stream.
        # this means either the stream has received headers already but not an END_HEADERS
        # or it is an error.
        if ( $stream->{header_state} == 0 ) {
          # not possible.  We are getting headers for an existing stream that 
          # we have never seen before.  Bug. Die.
          $log->logdie( "Received headers for an existing stream id in header state 0" );
        }
        elsif( $stream->{header_state} == 1 ) {
          # this is the expected state.  We received a HEADERS from with out the END_HEADER
          # flag in the last frame.
          $stream = $conn->{streams}->{$frame->{streamid}};
        }
        elsif( $stream->{header_state} == 2 ) {
          # this means we are receiveing headers after the first set.  Unimplimented.  Warn
          $log->logwarn( "Receiving additional headers after the initial set.  Unimplemented" );
          return;
        }
      }
      else
      {
        $stream = $conn->new_stream( $frame );
        $stream->state( $HTTP2::Draft::Stream::STATE_OPEN );
      }


      # add the headers to the stream's headers
      for ( keys %{$frame->{http_headers}} ) {
        # TODO: there is probably a bug with this are I coudl be clobbering
        #       hedaders in a unspecified manner
        $stream->{http_headers}->{$_} = $frame->{http_headers}->{$_};
      }

      if ( ($frame->{flags} & 0x4) == 0x4 ) {
        # We received the END_HEADERS flag.  Continue

        $stream->{header_state} = 2;

        my $http_headers = $stream->{http_headers};

        $log->info( "Received a request for: ",
                    $stream->{http_headers}->{':method'}, " ",
                    $stream->{http_headers}->{':host'}, " ",
                    $stream->{http_headers}->{':path'} );

        $log->debug( "Flags: $frame->{flags}" );

        my ($filename) = $stream->{http_headers}->{':path'} =~ /\/(.*)/;

        my $request = HTTP::Request->new();

        # nowhere to put the scheme?
        $request->method( $http_headers->{':method'} );
        $request->uri( $http_headers->{':path'} );
        $request->header( 'host' => $http_headers->{':host'} );
        $request->protocol( $http_headers->{':version'} );
        $request->header( map { $_ => $http_headers->{$_} } grep { ! /^:/ } keys %$http_headers );

        if ( $frame->{flags} & 0x1 ) {

          # this is a request with no data.  Go ahead and process.
          $stream->state( $HTTP2::Draft::Stream::STATE_HALF_CLOSED_REMOTE );
          $stream->{request} = $request;
          $server->{on_request}->( $request, $stream );
        }
        else {
          # there is data still to come.  Save the request until we have it all.

          $stream->{request} = $request;
        }
      }
      else {
        $log->error( "Received a header block without the END_HEADERS flag" );
      }

    }
    elsif ( $frame->{type} == DATA )
    {
      # TODO: do something with the POST data.  Pass it to the http2server.pl perhaps?

      my $stream = $conn->{streams}->{$frame->{streamid}};

      if ( $stream->state() == $HTTP2::Draft::Stream::STATE_OPEN ) {

        # flow control is hard coded on right now for the server
        my $winup_frame = HTTP2::Draft::Frame->new( WINDOW_UPDATE,
                                                    streamid => $frame->{streamid},
                                                    delta    => $frame->{length} );
        $conn->write_frame( $winup_frame );
        $winup_frame = HTTP2::Draft::Frame->new( WINDOW_UPDATE,
                                                 streamid => 0,
                                                 delta    => $frame->{length} );
        $conn->write_frame( $winup_frame );

        my $content = $stream->{request}->content();
        $stream->{request}->content( $content . $frame->{data} );
        if ( $frame->{flags} & 0x1 ) {
          $stream->state( $HTTP2::Draft::Stream::STATE_HALF_CLOSED_REMOTE );
          $server->{on_request}->( $stream->{request}, $stream );
        }
      }
      else {
        $log->logwarn( "Received request data in an unexpected state: ", $stream->state() );
      }


    }
    elsif ( $frame->{type} == SETTINGS )
    {
      $conn->handle_settings_frame( $frame );
    }
    elsif ( $frame->{type} == PING )
    {
      my $ping = HTTP2::Draft::Frame->new( PING,
                                         streamid => $frame->{streamid} );
      $conn->write_frame( $ping );
    }
    elsif ( $frame->{type} == GOAWAY )
    {
      # TODO: We got a GOAWAY - do something!
      $log->info( "Received GOAWAY: last_good: $frame->{last_streamid}, status = $frame->{error_code}" );
    }
    elsif ( $frame->{type} == WINDOW_UPDATE )
    {
      $conn->handle_window_update( $frame );
    }
  }
  else
  {
    die "Unexpected state.  Received $conn->{state}";
  }

  return 0;
}

sub build_headers
{

}

sub response
{
  my $self     = shift;
  my $response = shift;
  my $stream   = shift;

  my $headers = {};

  my $scan = sub {
    my ( $k, $v ) = @_;
    $headers->{lc($k)} = $v;
  };

  $response->scan( $scan );

  $headers->{':status'} = $response->code(); # . " " . $response->message();
  $headers->{'content-length'} = length( $response->content() );

  my $reply  = HTTP2::Draft::Frame->new( HEADERS,
                                         streamid      => $stream->{streamid},
                                         http_headers  => $headers,
                                         direction     => "response",
                                         flags         => 0x04 # TODO: hard coded end of headers
                                       );


  $stream->{conn}->write_frame( $reply );
  $stream->{conn}->write_data( $stream->{streamid}, $response->content() );

}

1;
