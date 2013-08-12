package HTTP2::Draft::Framer;

use 5.008;
use strict;
use warnings FATAL => 'all';

use HTTP2::Draft::FrameStream;

use HTTP2::Draft::Frame qw ( :frames :settings :errors );

use strict;
use warnings;
use IO::Async::SSL;
use Data::Dumper;

use HTTP2::Draft;
use HTTP2::Draft::Log qw( $log );


=head1 NAME

HTTP2::Draft::Framer - Framer based on IO::Async

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


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
    my $framer = HTTP2::Draft::FrameStream->new( handle => $handle );

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

    HTTP2::Draft::hex_print( $$buffref );
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
    my $framer = HTTP2::Draft::FrameStream->new( handle => $handle );

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




=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use HTTP2::Draft::Framer;

    my $foo = HTTP2::Draft::Framer->new();
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

    perldoc HTTP2::Draft::Framer


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

1; # End of HTTP::Draft::Framer
