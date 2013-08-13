package HTTP2::Draft::Connection;

use 5.008;
use strict;
use warnings FATAL => 'all';

use HTTP2::Draft;
use HTTP2::Draft::Frame qw( :frames :settings :errors );
use HTTP2::Draft::Stream;
use HTTP2::Draft::Log qw ( $log );
use HTTP2::Draft::Compress;

use Carp qw( cluck );

=head1 NAME

HTTP2::Draft::Connection - The great new HTTP2::Draft::Connection!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.03';



sub new
{
  my $class = shift;
  my $self = {};
  bless $self, $class;
  $self->_init( @_ );
  return $self;
}

sub _init
{
  my $self    = shift;
  my $framer  = shift;
  my $role    = shift;

  die ( "Role not set in Connection->new" ) if ! $role;

  # TODO: harcoding the role feels awkward.  Should this happen
  #      in subclasses or something else less fragile to typos?
  $self->{role}             = $role;
  $self->{framer}           = $framer;
  $self->{streams}          = {};
  $self->{settings}         = undef;
  $self->{max_client_frame} = 0;
  $self->{max_server_frame} = 0;
  $self->{flow_control_state} = 1;

  # TODO: this direction harcoding of the compressor
  #       feels awkward.
  $self->{compressor}->{request}  = HTTP2::Draft::Compress->new( request => 1 );
  $self->{compressor}->{response} = HTTP2::Draft::Compress->new( response => 1 );
  $self->{compressor}->{response_test} = HTTP2::Draft::Compress->new( response => 1 );

  # TODO: shoudl this be part of settings?
  $self->{default_window} = 1024 * 64;

  # TODO: Connection states need vriable that self describe
  $self->{state} = 0;

  # TODO: how shold this be initialized?
  $self->{window} = $self->{default_window};
}

sub get_stream
{
  my $self     = shift;
  my $stream_id = shift;

  return $self->{streams}->{$stream_id} ? $self->{streams}->{$stream_id} : undef;
}


sub new_stream
{
  my $self          = shift;
  my $headers_frame = shift;
  my $stream_id     = shift;


  if ( ! $stream_id ) {
    # creating a fresh stream on the client side
    $stream_id = ($self->{max_client_frame} * 2) + 1;
    $self->{max_client_frame}++;
  }

  my $window = exists $self->{settings}->{7} ?
                      $self->{settings}->{7} :
                      $self->{default_window};

  my $stream = HTTP2::Draft::Stream->new ( 'conn'         => $self,
                                           'window'       => $window,
                                           'streamid'     => $stream_id );

  $self->{streams}->{$stream->{streamid}} = $stream;

#  if ( $headers_frame->{streamid} % 2 == 0 ) {
#    HTTP2::Draft->error( "Received an even number Stream ID from a client" );
#    return undef;
#  }

#  if ( $headers_frame->{streamid} <= $self->{max_client_frame} ) {
#    HTTP2::Draft->error( "Received an Stream ID from a client that was less than or equal to a previous" );
#    return undef;
#  }

  return $stream;
}

sub read_frame
{
  my $self = shift;
  my $buffer = shift;

  my $frame = $self->{framer}->read_frame( $buffer );


  if ( $frame ) {
#    $frame->dump();
    $log->debug( "Received frame: ",
                $HTTP2::Draft::Frame::types{$frame->{type}},
                ", streamid = $frame->{streamid}, flags = $frame->{flags}, length = $frame->{length}" );
  }

  return $frame;
}


sub write_frame
{
  my $self = shift;
  my $frame = shift;

  # TODO: This should really not happen here.  Find a better place.
  if ( $frame->{type} == HEADERS ) {
    my $direction = $frame->{direction};
    my $compressor = $self->{compressor}->{$direction};

    my $block = $compressor->deflate( $frame->{http_headers} );

    if ( ! $block ) {
      $block = "";
    }

#    HTTP2::Draft::hex_print( $block );
    
    $frame->{data}   = $block;
    $frame->{length} = length( $block );

#    my $test_key = $direction . "_test";
#    if ( exists $self->{compressor}->{$test_key} ) {
#      my $test_compressor = $self->{compressor}->{$test_key};
#      my $headers = $test_compressor->inflate( $block );
#      print Data::Dumper::Dumper( $headers );
#    }


  }

  my $data = $frame->pack();

#  HTTP2::Draft::hex_print( $data );

  $log->debug( "Sending frame: ",
              "type = ", $HTTP2::Draft::Frame::types{$frame->{type}},
              ", streamid = $frame->{streamid}, flags = $frame->{flags}, length = $frame->{length}" );

  #$frame->dump();

  $self->{framer}->write_frame( $frame );

#  print "HERE|n";
}


sub write_data
{
  my $self     = shift;
  my $streamid = shift;
  my $data     = shift || "";

  Readonly::Scalar my $MAX_FRAME_SIZE => (2**14)-1;

  my $stream = $self->{streams}->{$streamid};

  my $stream_window = $stream->{window};
  my $conn_window   = $self->{window};

  $log->debug( "write_data called for ", length($data), " bytes" );

  # TODO: There may be legitimate reason to send an empty DATA frame.
  #       For example, to set the END_STREAM flag.  Not relevant for
  #       this implementation at this time
  #       Perhaps in that case they shoudl call write_frame directly
  if ( length($data) == 0 && length($stream->{buffer}) == 0 ) {
    return;
  }

  my $done = 0;
  while( ! $done ) {
    $log->debug( "Stream state (", $stream->{streamid}, ") ",
                "conn window = ", $self->{window}, " ",
                "window = ", $stream->{window}, " ",
                "buffer bytes = ", length( $stream->{buffer} ), " ",
                "addition bytes = ", length( $data ) );

    # Set the window to the smaller of the stream or conn window
    my $w = $conn_window < $stream_window ? $conn_window : $stream_window;

    # TODO: Magic number
    # Limit the payload to the maximum frame size allowed by the spec
    $w = $w > $MAX_FRAME_SIZE ? $MAX_FRAME_SIZE : $w;

#    print "conn_window = $conn_window\n";
#    print "stream_window = $stream_window\n";
#    print "w = $w\n";

    if ( $w > 0 )
    {
      # There is window space available

      # Go and append to the stream's buffer.  This make the logic
      # below simpler, but obviously is not necessarily efficient
      $stream->{buffer} .= $data;
      $data = $stream->{buffer};

      my $len = length( $data );
      my $to_send = $len;

      if ( $len > $w )
      {
        # If the available bytes to send is larger than the available window
        # split the data and save the deferred portion in the stream buffer
        $to_send = $w;
        my $deferred_data = substr( $data, $w );
        $data = substr( $data, 0, $w );
        $stream->{buffer} = $deferred_data;
      }
      else
      {
        # otherwise empty the stream buffer;
        $stream->{buffer} = "";
        $done = 1;
      }

      # If the stream buffer is empty then set the fin flag
      # TODO: This is a model that assumes all of the data is available now
      #       and there will not be mulitple calls to write the data
      # TODO: This is called END_STREAM in HTTP/2.0
      my $fin = length( $stream->{buffer} ) ? 0 : 1;

#      $fin = 1;
#      $stream->{buffer} = "";
      
      $log->debug( "Stream $stream->{streamid}: fin = $fin" );

      my $frame = HTTP2::Draft::Frame->new( DATA,
                                            streamid => $streamid,
                                            flags    => $fin );
      $frame->data( $data );
      $data = "";

      if ( $fin )
      {
        # TODO: This state should probably already be HALF_CLOSED_REMOTE
        #       and should be transitioning to CLOSED
        # TODO: should this be up a level?  i.e. in Client.pm or Server.pm?
        # TODO: we took the data from teh client/server, now we need to notify them
        #       that it is all sent.
        if ( $stream->state() == $HTTP2::Draft::Stream::STATE_HALF_CLOSED_REMOTE )
        {
          $stream->state( $HTTP2::Draft::Stream::STATE_CLOSED );
        }
        else
        {
          $stream->state( $HTTP2::Draft::Stream::STATE_HALF_CLOSED_LOCAL );
        }

      }


      $stream->{window} -= $to_send;
      $self->{window}   -= $to_send;


      $self->write_frame( $frame );

      # For partial sends that exhaust the available window, a window update will 
      # trigger the next call to write_data.
      # For partial sends that are due to the max frame size being reached, an explicit
      # timer is set.
    }
    else
    {
      # There is no window space available.  Append to the buffer and move on.
      $stream->{buffer} .= $data;
      $done = 1;
    }
  }
}


sub handle_window_update
{
  my $self = shift;
  my $frame = shift;

  my $error;


  $error = "Not a WINDOW_UPDATE frame" if $frame->{type} != WINDOW_UPDATE;
  $error = "No streamid set"           if ! exists $frame->{streamid};
  $error = "Unknown streamid: $frame->{streamid}"          if ! exists $self->{streams}->{$frame->{streamid}} && $frame->{streamid} > 0;

  if ( $error ) {
    HTTP2::Draft->error( $error );
    $log->warn( $error );
    return undef;
  }


  if ( $self->{flow_control_state} == 0x0 ) {
    $log->warn( "Received WINDOW_UPDATE when flow control was requested diabled" );
    return 1;
  }

  if ( $frame->{streamid} == 0 ) {
    # Connection window update
    $log->info( "Increasing window of connection by $frame->{delta}. Was $self->{window}, is ", $self->{window} + $frame->{delta}, "." );
    $self->{window} += $frame->{delta};

    for ( keys %{$self->{streams}} ) {
      my $stream = $self->{streams}->{$_};
      if ( $stream->{buffer} ) {
        # TODO: check stream state as well?
        $self->write_data( $stream->{streamid} );
      }
    }
  }
  else {
    # Stream window update
    my $stream = $self->{streams}->{$frame->{streamid}};
    $log->info( "Increasing window of stream $stream->{streamid} by ",
                "$frame->{delta}. Was $stream->{window}, is ",
                $stream->{window} + $frame->{delta}, "." );
    $stream->{window} += $frame->{delta};
    $self->write_data( $stream->{streamid} ) if $stream->{buffer};
  }

  return 1;
}

sub handle_settings_frame
{
  my $self  = shift;
  my $frame = shift;

  my $msg = "";

  for my $id ( keys %{$frame->{settings}} )
  {
    my $value = $frame->{settings}->{$id};

    $self->{settings}->{$id} = $value;

    # TODO: replace magic number with constant
    if ( $id == SETTINGS_INITIAL_WINDOW_SIZE )
    {
      $self->{window} = $value;

      for my $streamid ( keys %{$self->{streams}} )
      {
        my $stream = $self->{streams}->{$streamid};
        # TODO: stream state checks

        if ( $stream->{max_window} != $value )
        {
          my $diff = $value - $stream->{max_window};
          $stream->{max_window} = $value;
          if ( $diff > 0 )
          {
            # made bigger
            $stream->{window} += $value;
            # TODO: I believe we might need to send data at this tiem
            #       but the below code does not do it correctly in any way
            $self->write_data( $streamid );
          }
          else
          {
            # made smaller
            $stream->{window} -= $value;
          }
        }
      }
    }
    elsif ( $id == SETTINGS_MAX_CONCURRENT_STREAMS ) {
      # TODO: handle an update to max streams count
      my $self->{max_streams} = $value;

    }
    elsif ( $id == SETTINGS_FLOW_CONTORL_OPTIONS ) {
      # TODO: handle an update to flow control options

      if ( ($value & 0x1) == 0x1 ) {
        $log->info( "Turning off flow control\n" );
        $self->{flow_control_state} = 0;
      }
    }
    else 
    {
      $log->logdie( "Unknown setting received: $id" );
      # TODO: Protocol Error
    }


    $msg .= "$id: $value, ";



  }
  $msg =~ s/, $//;

  $log->info( "Updating settings: $msg" );

  return 1;
}

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use HTTP2::Draft::Connection;

    my $foo = HTTP2::Draft::Connection->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut


=head1 AUTHOR

Stephen Ludin, C<< <sludin at ludin.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-http2-draft at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTTP2-Draft>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HTTP2::Draft::Connection


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=HTTP2-Draft>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/HTTP2-Draft>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/HTTP2-Draft>

=item * Search CPAN

L<http://search.cpan.org/dist/HTTP2-Draft/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Stephen Ludin.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of HTTP2::Draft::Connection
