package IO::Async::HTTP2::FramerStream;


use strict;
use warnings;
use base qw( IO::Async::SSLStream );
use HTTP2::Draft::Frame qw( :frames :settings :errors );


our $VERSION = '0.01';


sub write_frame
{
  my $self = shift;
  my $frame = shift;

  # HTTP2::Draft::hex_print( $frame->{wire} );

  # TODO: do some checks


  $self->write( $frame->{wire} );
}

sub read_frame
{
  my $self   = shift;
  my $buffer = shift;
  print "read_frame\n";

  # TODO: Do something about this magic number 8
  if ( length( $buffer ) < 8 ) {
    # we do not have a full frame header yet
    return undef;
  }

#HTTP2::Draft::hex_print( $buffer );

  my $data = substr( $buffer, 0, 8 );

  my $wire = $data;

  my $frame = HTTP2::Draft::Frame::unpack( $data );

  # we need more data from the socket to get a full frame
  # this would be a GREAT place to check for too large frames
  if ( $frame->{length} + 8 > length( $buffer ) ) {
    return undef;
  }

  $data = substr( $buffer, 8, $frame->{length} );
  $wire .= $data;

#  HTTP2::Draft::hex_print( $wire );


  # TDOD: I do not like the special casing.
  if ( $frame->{type} == HEADERS ) {
    my $direction = $self->{conn}->{role} eq "server" ? "request" : "response";
    my $inflator  = $self->{conn}->{compressor}->{$direction};
    $frame->data( $data, $inflator );
  }
  else {
    $frame->data( $data );
  }

  $frame->{size} = $frame->{length} + 8;

  return $frame;
}



1;
