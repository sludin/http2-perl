package HTTP2::Draft::FrameStream;

use 5.008;
use strict;
use warnings FATAL => 'all';

use base qw( IO::Async::SSLStream );
use HTTP2::Draft::Frame qw( :frames :settings :errors );


=head1 NAME

HTTP2::Draft::FrameStream - Frame stream class based on IO::Async::SSLStreams

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';


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
#  print "read_frame\n";

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



=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use HTTP2::Draft::FramerStream;

    my $foo = HTTP2::Draft::FrameStream->new();
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

    perldoc HTTP2::Draft::FramerStream


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

1; # End of HTTP2::Draft::FramerStream
