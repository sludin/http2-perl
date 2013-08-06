package IO::Async::HTTP2::Framer;

use IO::Async::HTTP2::FramerStream;

use HTTP2::Draft::Frame qw ( :frames :settings :errors );

use strict;
use warnings;
use IO::Async::SSL;
use Data::Dumper;

use HTTP2::Draft;
use HTTP2::Draft::Log qw( $log );
use IO::Async::Timer::Countdown;

our $VERSION = '0.01';

my $magic_header_hex = "505249202a20485454502f322e300d0a0d0a534d0d0a0d0a";

my $magic_header = pack( "(H2)*", unpack( "(A2)*", $magic_header_hex ) );





sub IO::Async::Loop::HTTP2_connect
{
  my $loop = shift;

  my %params = @_;

  my $on_http2_connect = delete $params{on_http2_connect};
  my $on_frame_read    = delete $params{on_frame_read};

  my $on_read = sub {
    my ( $framer, $buffref, $eof ) = @_;

    # TODO: should the Conn be passed here rather than the stream?
    if ( $eof )
    {
      $on_frame_read->( $framer, undef, $eof );
      return;
    }

    my $conn = $framer->{conn};

    my ( $frame, $length ) = $conn->read_frame( $$buffref );

    if ( $frame )
    {
      # consume the used bytes on the sockets buffer
#      print( "$frame->{size}, ", length( $$buffref ), "\n" );
      $$buffref = substr( $$buffref, $frame->{size} );
      $on_frame_read->( $framer, $frame, $eof );
    }

  };


  my $on_connected = sub {

    my ( $handle ) = @_;
    my $framer = IO::Async::HTTP2::FramerStream->new( handle => $handle );

    $log->info( "NPN: ", $framer->{write_handle}->next_proto_negotiated() );

    $framer->configure( on_read   => $on_read,
                        autoflush => 1,
                        write_all => 1 );

    my $conn = HTTP2::Draft::Connection->new( $framer, "client" );
    $framer->{conn} = $conn;


    $framer->write( $magic_header );

    $on_http2_connect->( $framer );


  };

  $params{on_connected} = $on_connected;

  $loop->SSL_connect( %params );
}

sub IO::Async::Loop::HTTP2_listen
{
  my $loop = shift;

  my %params = @_;

  my $on_http2_connect = delete $params{on_http2_connect};
  my $on_frame_read    = delete $params{on_frame_read};
  my $on_frame_error   = delete $params{on_frame_error};

  my $on_read = sub {
    my ( $framer, $buffref, $eof ) = @_;

    if ( $eof )
    {
      $on_frame_read->( $framer, undef, $eof );
      return;
    }

    my $conn = $framer->{conn};

#    HTTP2::Draft::hex_print( $$buffref );
#print Dumper( $framer );
print "Conn state == $conn->{state}\n";

    # TODO: dispel the magic 1
    # state 1: tls connection established, nothing has been read or written
    #          including settings frames and magic
    # state 2: received magic header, waiting for first SETTINGS frame
    # state 3: received SETTINGS frame, sent SETTINGS frame, ready to roll
    while( length( $$buffref ) > 8 ) {
      if ( $conn->{state} == 1 )
      {
        #       my $h = pack( "(H2)*", unpack( "(A2)*", $magic_header ) );

        my $hlen = length( $magic_header );

        #print $hlen, "\n";
        #print $$buffref, "\n";

        my $buflen = length( $$buffref );

        if ( $buflen < $hlen )
        {
          # perform a partial check of what is in the buffer
          if ( substr( $magic_header, 0, $buflen ) eq $$buffref )
          {
            return;
          }
          else
          {
            # ERROR
            $on_frame_error->( $framer, "Bad magic", $$buffref );
            return;
          }
        }
        else
        {
          if ( substr( $$buffref, 0, $hlen ) eq $magic_header )
          {
            $conn->{state} = 2;
            $$buffref = substr( $$buffref, $hlen );
            #return;
          }
        }

      }
      else
      {

        my $conn  = $framer->{conn};
        my $frame = $conn->read_frame( $$buffref );

        if ( $frame )
        {
          # consume the used bytes on the socket
          $$buffref = substr( $$buffref, $frame->{size} );
          $on_frame_read->( $framer, $frame, $eof );
        }
      }
    }

  };

  $params{on_accept} = sub {
    my ( $handle ) = @_;
    my $framer = IO::Async::HTTP2::FramerStream->new( handle => $handle );

    $log->info( "NPN: ", $framer->{write_handle}->next_proto_negotiated() );

    #         print Dumper( $framer );

    $framer->configure( on_read   => $on_read,
                        on_read_error => sub { print "READ ERROR\n" },
                        on_write_error => sub { print "WRITE ERROR\n" },
                        autoflush => 1,
                        write_all => 1 );

#    $framer->debug_printf( "EVENT on_read" );

    my $conn = HTTP2::Draft::Connection->new( $framer, "server" );
    $framer->{conn} = $conn;
    $conn->{state} = 1;


    $on_http2_connect->( $framer );
  };

  $loop->SSL_listen( %params );
}



