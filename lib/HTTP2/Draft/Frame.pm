
package HTTP2::Draft::Frame;

use strict;
use warnings;

use Exporter qw( import );

use Data::Dumper;

use HTTP2::Draft;
use HTTP2::Draft::Log qw( $log );


use Carp;

use Exporter qw( import );

use Data::Dumper;



our $VERSION = $HTTP2::Draft::VERSION;

######
# Frame construction methods
# From the Wire: ( reading )
#   1) 8 byte header is read from the socket
#   2) This is sent to unpack which creates an 'empty' frame of the correct type
#   3) If the frame has data, read the data and then call the data method
#      of the frame
# From Scratch: ( writing )
#   1) Call the constructor with the relevant frame header information.
#      If the infotmation is not available ( like length, flags, etc )...
#




use constant {
 DATA             => 0,
 HEADERS          => 1,
 RST_STREAM       => 3,
 SETTINGS         => 4,
 PUSH_PROMISE     => 5,
 PING             => 6,
 GOAWAY           => 7,
 WINDOW_UPDATE    => 9,
 MAGIC            => 98,
};



our %types =
(
 &DATA             => 'DATA',
 &RST_STREAM       => 'RST_STREAM',
 &SETTINGS         => 'SETTINGS',
 &PUSH_PROMISE     => 'PUSH_PROMISE',
 &PING             => 'PING',
 &GOAWAY           => 'GOAWAY',
 &HEADERS          => 'HEADERS',
 &WINDOW_UPDATE    => 'WINDOW_UPDATE',
 &MAGIC            => 'MAGIC',
);

use constant {
  SETTINGS_MAX_CONCURRENT_STREAMS => 4,
  SETTINGS_INITIAL_WINDOW_SIZE    => 7,
  SETTINGS_FLOW_CONTORL_OPTIONS   => 10
};

use constant {
  NO_ERROR           => 0,
  PROTOCOL_ERROR     => 1,
  INTERNAL_ERROR     => 2,
  FLOW_CONTORL_ERROR => 3,
  STREAM_CLOSED      => 5,
  FRAME_TOO_LARGE    => 6,
  REFUSED_STREAM     => 7,
  CANCEL             => 8,
  COMPRESSION_ERROR  => 9
};

@HTTP2::Draft::Frame::EXPORT_OK   = qw ( DATA RST_STREAM SETTINGS PUSH_PROMISE PING
                                         GOAWAY HEADERS WINDOW_UPDATE MAGIC
                                         SETTINGS_MAX_CONCURRENT_STREAMS
                                         SETTINGS_INITIAL_WINDOW_SIZE
                                         SETTINGS_FLOW_CONTORL_OPTIONS
                                         NO_ERROR
                                         PROTOCOL_ERROR
                                         INTERNAL_ERROR
                                         FLOW_CONTORL_ERROR
                                         STREAM_CLOSED
                                         FRAME_TOO_LARGE
                                         REFUSED_STREAM
                                         CANCEL
                                         COMPRESSION_ERROR
                                    );

%HTTP2::Draft::Frame::EXPORT_TAGS = (  frames =>
                                     [ qw( DATA RST_STREAM SETTINGS PUSH_PROMISE PING
                                           GOAWAY HEADERS WINDOW_UPDATE MAGIC ) ],
                                     settings =>
                                     [ qw ( SETTINGS_MAX_CONCURRENT_STREAMS
                                            SETTINGS_INITIAL_WINDOW_SIZE
                                            SETTINGS_FLOW_CONTORL_OPTIONS ) ],
                                     errors =>
                                     [ qw ( NO_ERROR
                                            PROTOCOL_ERROR
                                            INTERNAL_ERROR
                                            FLOW_CONTORL_ERROR
                                            STREAM_CLOSED
                                            FRAME_TOO_LARGE
                                            REFUSED_STREAM
                                            CANCEL
                                            COMPRESSION_ERROR ) ]
                                  );

my $COMMON_HEADER_LENGTH = 8;

sub new
{
  my $class = shift;
  my $type  = shift;

  my $self = _new_no_init( $type );

  confess "type = $type" if ! $self;

  return undef if ! $self->_init( @_ );

  return $self;
}

# Constructor directly called by unpack to avoid _init overrides
sub _new_no_init
{
  my $type = shift;
  my $self = {};

  if ( ! exists $types{$type} )
  {
    HTTP2::Draft::error( "Unknown frame type: $type" );
    return undef;
  }

  bless $self, "HTTP2::Draft::Frame::$types{$type}";
  $self->{type} = $type;

  return $self;
}

sub _init
{
  my $self = shift;

  my %params = @_;

  # $self->{type} is set in _new_no_init
  $self->{streamid} = $params{streamid} || 0;
  $self->{flags}    = $params{flags};
  $self->{length}   = exists $params{length} ? $params{length} : -1;

  return 1;
}

sub pack
{
  my $self = shift;

  my $wire = pack( "nCCN", $self->{length}, $self->{type},
                   $self->{flags}, ($self->{streamid} & 0x7FFFFFF) );

  return $wire;
}


sub unpack
{
  my $head = shift;

  if ( length( $head ) != $COMMON_HEADER_LENGTH ) {
    HTTP2::Draft::error( "new_frame_from_wire: exptected $COMMON_HEADER_LENGTH byte, received " . length( $head ) );
    return undef;
  }

  #print "---\n";
  #HTTP2::Draft::hex_print( $head );
  #print "---\n";

  my ( $length, $type, $flags, $streamid ) = unpack( "nCCN", $head );

  $streamid &= 0x7FFFFFFF;

  my $frame = HTTP2::Draft::Frame->new( $type,
                                        streamid => $streamid,
                                        flags    => $flags,
                                        length   => $length );

  if ( ! $frame ) {
    HTTP2::Draft::error( "Frame construction failed" );
  }

  if ( $frame->{length} == -1 ) {
    $log->error( "*** length is -1:" );
    $log->error( Data::Dumper::Dumper( $frame ) );
  }

  return $frame;
}

sub dump
{
  my $self = shift;
  my $dumper = Data::Dumper->new( [ $self ] );
  $dumper->Sortkeys( sub { my $hash = shift; 
			   return [ grep { $_ ne "data" && $_ ne "uncompressed" && $_ ne "wire" } keys %$hash ]; } );
  print $dumper->Dump();
}

############################################
#
# Data
#

package HTTP2::Draft::Frame::DATA;

our @ISA = ( 'HTTP2::Draft::Frame' );

sub _init
{
  my $self = shift;

  $self->SUPER::_init( @_ );

  return 1;
}

sub data
{
  my $self = shift;
  my $data = shift;

  my $len = length( $data );

  if ( $self->{length} != -1 ) {
    if ( $self->{length} != $len ) {
      HTTP2::Draft::error( "Length mismatch in DataFrame::Data.  Expected $self->{length} got $len" );
      return undef;
    }
  }
  else {
    $self->{length} = $len;
  }

  $self->{data} = $data;

  return $len;
}

sub pack
{
  my $self = shift;
  my $wire = $self->SUPER::pack() . $self->{data};
  $self->{wire} = $wire;
  return $self->{wire};
}




package HTTP2::Draft::Frame::RST_STREAM;

@HTTP2::Draft::Frame::RST_STREAM::ISA = ( 'HTTP2::Draft::Frame' );

sub _init
{
  my $self = shift;
  $self->SUPER::_init( @_ );

  return 1;
}

sub data
{
  my $self = shift;
  my $data = shift;

  $self->{data} = shift;

  if ( length( $data ) != 8 ) {
    die "Unexpected RST_STREAM length: " . length( $data );
  }

  my ( $last_good_streamid, $status_code ) = unpack( "NN", $data );
  $last_good_streamid &= 0x7FFFFFFF;

  $self->{last_good_streamid} = $last_good_streamid;
  $self->{status_code} = $status_code;

  return 1;
}

sub pack
{
  die "RST_STREAM::pack not implemented";
#  my $self = shift;
#  my $wire = $self->SUPER::pack() . $self->{data};
#  $self->{wire} = $wire;
#  return $self->{wire};

}

package HTTP2::Draft::Frame::SETTINGS;

@HTTP2::Draft::Frame::SETTINGS::ISA = ( 'HTTP2::Draft::Frame' );


sub _init
{
  my $self = shift;
  my %params = @_;

  $self->SUPER::_init( type => 4, flags => 0, length => $params{length} );

  $self->{settings} = $params{settings};

  return 1;
}

sub data
{
  my $self = shift;
  my $data = shift;

  $self->{data} = shift;

  my $num = $self->{length} / 8;

  if ( $self->{length} % 8 != 0 ) {
    die "Bad length in SETTINGS frame: $self->{length}";
  }

  my $pos = 0;

  my %settings;

  for ( 1 .. $num ) {
    my ( $id, $value ) = unpack( "NN", substr( $data, $pos ) );
    $pos += 8;

    # TODO: I am not sure if all of the masking is really appropriate.  It forces things
    #       to be within spec, but it does not assert it.  This should be cleaned up
    #       and replaced with checks and potentially PROTOCOL_ERRORs
    $id &= 0x00FFFFFF;

    $settings{$id} = $value;
  }

  $self->{settings} = \%settings;

  return 1;
}

sub pack
{
  my $self = shift;

  my $wire;

  for my $id ( keys %{$self->{settings}} ) {
    $wire .= pack( "N", $id );
    $wire .= pack( "N", $self->{settings}->{$id} );
  }

  # need to set the length before the call to $self->SUPER::pack();
  $self->{length} = length( $wire );
  my $frame_header = $self->SUPER::pack();

  $self->{wire} = $frame_header . $wire;

  return $self->{wire};
}

package HTTP2::Draft::Frame::PING;

use Data::Dumper;



@HTTP2::Draft::Frame::PING::ISA = ( 'HTTP2::Draft::Frame' );

#our @ISA = ( 'HTTP2::Draft::Frame' );


sub _init
{
  my $self = shift;

  my %params = @_;

  my $flags = $params{pong} ? 0x2 : 0x0;
  $self->{data} = $params{data};

  $self->SUPER::_init( streamid => 0, type => HTTP2::Draft::Frame::PING, length => length( $self->{data} ), flags => $flags );


  return 1;
}

#sub data
#{
#  my $self = shift;

#  $self->{data} = shift;

#  my ( $id ) = unpack( "N", $self->{data} );

#  $self->{streamid} = $id;

#  return 1;
#}

sub pack
{
  my $self = shift;

  my $wire = $self->SUPER::pack() . $self->{data};

  $self->{wire} = $wire;
  return $self->{wire};
}


package HTTP2::Draft::Frame::GOAWAY;

our @ISA = ( 'HTTP2::Draft::Frame' );

sub _init
{
  my $self = shift;
  my %params = @_;

  $self->SUPER::_init( type => HTTP2::Draft::Frame::GOAWAY, flags => 0, length => 8 );

  $self->{last_streamid} = $params{last_streamid};
  $self->{error_code}    = $params{error_code} || 0;

  return 1;
}

sub data
{
  my $self = shift;
  my $data = shift;

  my ($last_stream_id,$error_code) = unpack( "NN", $data );
  $self->{data} = substr( $data, 4 );

  $self->{error_status} = $error_code;
  $self->{last_streamid} = $last_stream_id;

}

sub pack
{
  my $self = shift;

  my $wire = pack( "NN", $self->{last_streamid} & 0x7FFFFFFF, $self->{error_code} );

  my $frame_header = $self->SUPER::pack();

  $wire = $frame_header . $wire;

  $self->{wire} = $wire;
  return $self->{wire};
}



package HTTP2::Draft::Frame::HEADERS;

our @ISA = ( 'HTTP2::Draft::Frame' );

sub _init
{
  my $self = shift;
  my %params = @_;

  $self->SUPER::_init( type => 1, flags => $params{flags}, streamid => $params{streamid}, length => $params{length} );

  $self->{priority}     = $params{priority} || undef;
  $self->{http_headers} = $params{http_headers};
  $self->{direction}    = $params{direction};

#  $self->dump();

  return 1;
}

sub data
{
  my $self = shift;
  my $block = shift;
  my $inflator = shift;

#  confess( "HEADERS::data called" );
  $self->{length} = 0;

  if ( $self->{flags} & 0x8 ) {
    $self->{priority} = unpack( "N", $block );
    $self->{priority} &= 0x7FFFFFFF;
    $block = substr( $block, 4 );
    $self->{length} += 4;
  }

#  HTTP2::Draft::hex_print( $block );

  my $headers = $inflator->inflate( $block );
#  print Data::Dumper::Dumper( $headers );

  $self->{http_headers} = $headers;

  $self->{data} = $block;
  $self->{length} += length( $block );
}

sub pack
{
  my $self = shift;
  my $priority = "";

  $self->{length} = length( $self->{data} );

  # Priority is optional.  If it is being sent set the proper flag
  # and add the four bytes.
  if ( defined $self->{priority} ) {
    $priority = pack( "N", $self->{priority} & 0x7FFFFFFF );
    $self->{flags} |= 0x8;
    $self->{length} += 4;
  }

  my $frame_header = $self->SUPER::pack();

  my $wire = $frame_header . $priority . $self->{data};

#  $self->dump();

  $self->{wire} = $wire;

  #HTTP2::Draft::hex_print( $wire );
#  HTTP2::Draft::hex_print( $wire );

  return $self->{wire};
}


package HTTP2::Draft::Frame::WINDOW_UPDATE;

@HTTP2::Draft::Frame::WINDOW_UPDATE::ISA = ( 'HTTP2::Draft::Frame' );

my $DATA_LENGTH = 8;

# TODO: If a sender receives a WINDOW_UPDATE that causes the its window size to exceed this limit (2^31-1),
#       it must send RST_STREAM with status code FLOW_CONTROL_ERROR to terminate the stream.

sub _init
{
  my $self = shift;
  my %params = @_;

  $self->SUPER::_init( type => 9, flags => 0, length => 4 );

  $self->{streamid} = $params{streamid};
  $self->{delta}    = $params{delta};

  return 1;
}

sub data
{
  my $self = shift;
  my $data = shift;

  #HTTP2::Draft::hex_print( $data );

#  my $len = length( $data );
#  if ( $len != $DATA_LENGTH ) {
#    HTTP2::Draft::error( "Unexpected WINDOW_UPDATE length.  Expect $DATA_LENGTH.  Received $len" );
#    return undef;
#  }

  my ( $delta ) = unpack( "N", $data );
  $delta    &= 0x7FFFFFFF;

  $self->{delta}    = $delta;

  return 1;
}

sub pack
{
  my $self = shift;

  my $wire = pack( "N", $self->{delta} & 0x7FFFFFFF);

  $self->{length} = 4;

  my $frame_header = $self->SUPER::pack();

  $wire = $frame_header . $wire;

  $self->{wire} = $wire;
  return $self->{wire};
}




1;
