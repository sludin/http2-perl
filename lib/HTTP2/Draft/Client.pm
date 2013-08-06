package HTTP2::Draft::Client;

use strict;
use warnings;

use HTTP2::Draft;
use HTTP2::Draft::Connection;
use HTTP2::Draft::Frame qw( :frames :settings :errors );
use HTTP2::Draft::Log qw( $log );

use IO::Async::Loop;
use IO::Async::HTTP2::Framer;
use IO::Async::Timer::Countdown;

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

  $self->{on_response}      = delete $params{on_response};
  $self->{on_content}       = delete $params{on_content};
  $self->{on_http2_connect} = delete $params{on_http2_connect};

  if ( exists $params{flow_control} ) {
    $self->{flow_control}     = delete $params{flow_control};
  }
  else {
    # TODO: Magic number
    $self->{flow_control} = 1024 * 64;
  }

  if ( ! $self->{on_response} ) {
    die "Expected on_response parameter";
  }

  $self->{host}     = delete $params{host};
  $self->{hostname} = delete $params{hostname} || $self->{host};
  $self->{port}     = delete $params{port}     || 443;

  $self->{max_streams} = 100;
  $self->{stream_count} = 0;

  $self->{SSL_Params}->{SSL_npn_protocols} = delete $params{SSL_npn_protocols} || [ HTTP2::Draft::http_version() ];
  $self->{SSL_Params}->{SSL_hostname}      = $self->{hostname};
  $self->{SSL_Params}->{SSL_verify_mode}   = IO::Socket::SSL::SSL_VERIFY_NONE();
  for ( keys %params )
  {
    if ( /^SSL_/ ) {
      $self->{SSL_Params}->{$_} = delete $params{$_};
    }
  }

  if ( ! exists $self->{host} )
  {
    die "Must set a host or ip address to connect to in 'host' param";
  }
}

sub connect
{
  my $self = shift;

  my $loop = IO::Async::Loop->new;

  $self->{loop} = $loop;


  my %p = (
           %{$self->{SSL_Params}},
           on_frame_read      => sub { on_frame( $self, @_ ) },
           on_http2_connect   => sub {
             my ( $framer ) = $_[0];
             $framer->{client} = $self;
             $self->{stream} = $framer;

             my $conn = $framer->{conn};

             my $window = $self->{flow_control};
             my $disable_flow_control = 0;

             if ( ! $window ) {
               $disable_flow_control = 1;
             }

#             my $settings = HTTP2::Draft::Frame->new( SETTINGS,
#                                                      settings => { 4 => 100, 7 => $window, 10 => $disable_flow_control } );

             my $settings = HTTP2::Draft::Frame->new( SETTINGS,
                                                      settings => { 4 => 100} );
             $conn->write_frame( $settings );

             # TODO: replace this with a short delay
             #       I want to give the server a chance to send settings.  Or do I?
             #       This will necesitate waiting 1 RTT which is far from ideal.
             #       Instead I should save the settings frmo the server
             #       Thus at this time the timer is doing nothing useful at all
             my $timer = IO::Async::Timer::Countdown->new (
                                                           delay => 0,
                                                           on_expire => sub {
                                                             $self->{on_http2_connect}->( $self, $framer, $conn );
                                                           },
                                                          );
             $timer->start();

             $loop->add( $framer );
             $loop->add( $timer );
           },
           on_ssl_error      => \&on_ssl_error,
           on_resolve_error  => \&on_resolve_error,
           on_connect_error  => \&on_connect_error,
           addr              => { ip       => $self->{host},
                                  family   => "inet",
                                  port     => $self->{port},
                                  socktype => "stream" },
          );

  $loop->HTTP2_connect( %p );

  $loop->run();
}

sub on_listen
{
}

sub on_ssl_error
{
  my $self = shift;
  print Dumper( $self );
  die "SSL Error\n";
}

sub on_resolve_error
{
  die "Could not resposne $_[0]"
}

sub on_connect_error
{
  die "Could not connect";
}


sub on_frame
{
  my ( $client, $stream, $frame, $eof ) = @_;

  if ( $eof ) {
    $log->info( "EOF Indicated" );
    exit(0);
  }

  my $conn = $stream->{conn};

  if ( $frame->{type} == HEADERS ) {
    my $conn = $stream->{conn};
    my $http_stream = $conn->get_stream( $frame->{streamid} );

    # TODO: this will need to be updated for PUSH
    if ( ! $http_stream ) {
      die "Streamid $frame->{streamid} not found in connection streams";
    }


    # TODO: update for multiple HEADERS frames
    $http_stream->{response_headers} = $frame->{http_headers};

  }
  elsif ( $frame->{type} == DATA ) {

    my $conn = $stream->{conn};

    # TODO: Check stream state and existance
    my $http_stream = $conn->get_stream( $frame->{streamid} );

    my $headers = $http_stream->{response_headers};

    if ( $client->{flow_control} != 0 ) {



      my $winup_frame = HTTP2::Draft::Frame->new( WINDOW_UPDATE,
                                                  streamid => $frame->{streamid},
                                                  delta    => $frame->{length} );
      $conn->write_frame( $winup_frame );
      $winup_frame = HTTP2::Draft::Frame->new( WINDOW_UPDATE,
                                               streamid => 0,
                                               delta    => $frame->{length} );
      $conn->write_frame( $winup_frame );
    }


    $stream->{data} .= $frame->{data};

    # TODO: dispell the magic 0x1;
    if ( ($frame->{flags} & 0x1) == 0x1 ) {

      my $response = HTTP::Response->new();

      my ( $code ) = $headers->{':status'}; 
      $response->code( $code );
      $response->message( "" );
      $response->content( $stream->{data} );
      $response->header( map { $_ => $headers->{$_} } grep { ! /^:/ } keys %{$headers} );

      $client->{on_response}->( $client, $stream, $frame->{streamid}, $response );

      $http_stream->state( $HTTP2::Draft::Stream::STATE_CLOSED );
    }

  }
  elsif ( $frame->{type} == SETTINGS ) {
    $conn->handle_settings_frame( $frame );

    Readonly::Scalar my $GHOST_BUG => 1;

    if ( $GHOST_BUG ) { # GHOST BUG
      my $winup_frame = HTTP2::Draft::Frame->new( WINDOW_UPDATE,
                                                  streamid => 1,
                                                  delta    => 1 );

      $conn->write_frame( $winup_frame );
    }
  }
  elsif ( $frame->{type} == RST_STREAM ) {

    my $last_streamid = $frame->{last_good_streamid};

    # $conn->close_stream( $last_streamid );

#    $frame->dump();

    die "Unimplemented";

  }
  elsif ( $frame->{type} == PING ) {
    # PING
    my $ping = HTTP2::Draft::Frame->new( PING, streamid => $frame->{streamid} );
    $conn->write_frame( $ping );
  }
  elsif ( $frame->{type} == GOAWAY ) {
    # GOAWAY
    $log->debug( "Received GOAWAY: last_good: $frame->{last_good_streamid}, status = $frame->{status}" );
  }
  elsif ( $frame->{type} == WINDOW_UPDATE ) {
    # WINDOW_UPDATE
    $conn->handle_window_update( $frame );
  }
  #elsif ( $frame->{type} == DATA ) {
    # $client->{on_content}->( $client, $stream, $frame->{streamid}, $frame->{data}, $fin );
  #}


  return 0;

}

sub request
{
  my $self    = shift;
  my $request = shift;
  my $stream  = shift;


  my $conn = $stream->{conn};

  my $http2_stream = $conn->new_stream();

  my $headers = {};
  my $scan = sub {
    my ( $k, $v ) = @_;
    $headers->{lc($k)} = $v;
  };

  $request->scan( $scan );
  delete $headers->{host};


  $headers->{':path'} = $request->uri()->path() || '/';
  $headers->{':host'} = $request->header( 'host' );
  $headers->{':method'} = $request->method();
  $headers->{':scheme'} = $request->uri()->scheme();
  $headers->{'accept-encoding'} = "gzip, deflate";

  my $fin = $request->content() ? 0 : 1;

  $headers->{'content-length'} = length( $request->content() ) if ! $fin;

  my $flags = 0x4;
  # currently hard coded end of headers
  if ( ! length( $request->content() ) ) {
    $flags |= 0x1;
  }


  my $hframe = HTTP2::Draft::Frame->new( HEADERS,
                                         http_headers => $headers,
                                         streamid     => $http2_stream->{streamid},
                                         direction    => "request",
                                         flags        => $flags );



  # TODO: headers might span mulitple frames
  # TODO: data might span multiple frames
#  $hframe->{priority} = 2**10;
  #$hframe->dump();

  $conn->write_frame( $hframe );

  $http2_stream->state( $HTTP2::Draft::Stream::STATE_OPEN );

  if ( length( $request->content() ) ) {
    $conn->write_data(  $http2_stream->{streamid}, $request->content() );
  }

  $http2_stream->state( $HTTP2::Draft::Stream::STATE_HALF_CLOSED_LOCAL );
}

sub close
{
  my $self   = shift;
  my $framer = shift;
  my $conn   = $framer->{conn};

  my $goaway = HTTP2::Draft::Frame->new( GOAWAY,
                                         last_streamid => $conn->{max_client_frame},
                                         status => 0 );



#  $->state( $HTTP2::Draft::Stream::CLOSED );

  $conn->write_frame( $goaway );
#  $framer->close();
}


1;
