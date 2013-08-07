package HTTP2::Draft::HeaderIndex;

use 5.008;
use strict;
use warnings FATAL => 'all';

use Storable qw( dclone );

use strict;
use warnings;

use Data::Dumper;

=head1 NAME

HTTP2::Draft::HeaderIndex - The great new HTTP2::Draft::HeaderIndex!

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';



my %request_table_nv;
my %request_table_i;
my %response_table_nv;
my %response_table_i;



my @static_request_table =
(
 [ 0,  ":scheme",             "http"  ],
 [ 1,  ":scheme",             "https" ],
 [ 2,  ":host",               ""      ],
 [ 3,  ":path",               "/"     ],
 [ 4,  ":method",             "GET"   ],
 [ 5,  "accept",              ""      ],
 [ 6,  "accept-charset",      ""      ],
 [ 7,  "accept-encoding",     ""      ],
 [ 8,  "accept-language",     ""      ],
 [ 9,  "cookie",              ""      ],
 [ 10, "if-modified-since",   ""      ],
 [ 11, "keep-alive",          ""      ],
 [ 12, "user-agent",          ""      ],
 [ 13, "proxy-connection",    ""      ],
 [ 14, "referer",             ""      ],
 [ 15, "accept-datetime",     ""      ],
 [ 16, "authorization",       ""      ],
 [ 17, "allow",               ""      ],
 [ 18, "cache-control",       ""      ],
 [ 19, "connection",          ""      ],
 [ 20, "content-length",      ""      ],
 [ 21, "content-md5",         ""      ],
 [ 22, "content-type",        ""      ],
 [ 23, "date",                ""      ],
 [ 24, "expect",              ""      ],
 [ 25, "from",                ""      ],
 [ 26, "if-match",            ""      ],
 [ 27, "if-none-match",       ""      ],
 [ 28, "if-range",            ""      ],
 [ 29, "if-unmodified-since", ""      ],
 [ 30, "max-forwards",        ""      ],
 [ 31, "pragma",              ""      ],
 [ 32, "proxy-authorization", ""      ],
 [ 33, "range",               ""      ],
 [ 34, "te,",                 ""      ],
 [ 35, "upgrade",             ""      ],
 [ 36, "via",                 ""      ],
 [ 37, "warning",             ""      ],
);

my @static_response_table =
(
 [ 0,  ":status",                     "200" ],
 [ 1,  "age",                         "",   ],
 [ 2,  "cache-control",               "",   ],
 [ 3,  "content-length",              "",   ],
 [ 4,  "content-type",                "",   ],
 [ 5,  "date",                        "",   ],
 [ 6,  "etag",                        "",   ],
 [ 7,  "expires",                     "",   ],
 [ 8,  "last-modified",               "",   ],
 [ 9,  "server",                      "",   ],
 [ 10, "set-cookie",                  "",   ],
 [ 11, "vary",                        "",   ],
 [ 12, "via",                         "",   ],
 [ 13, "access-control-allow-origin", "",   ],
 [ 14, "accept-ranges",               "",   ],
 [ 15, "allow",                       "",   ],
 [ 16, "connection",                  "",   ],
 [ 17, "content-disposition",         "",   ],
 [ 18, "content-encoding",            "",   ],
 [ 19, "content-language",            "",   ],
 [ 20, "content-location",            "",   ],
 [ 21, "content-md5",                 "",   ],
 [ 22, "content-range",               "",   ],
 [ 23, "link",                        "",   ],
 [ 24, "location",                    "",   ],
 [ 25, "p3p",                         "",   ],
 [ 26, "pragma",                      "",   ],
 [ 27, "proxy-authenticate",          "",   ],
 [ 28, "refresh",                     "",   ],
 [ 29, "retry-after",                 "",   ],
 [ 30, "strict-transport-security",   "",   ],
 [ 31, "trailer",                     "",   ],
 [ 32, "transfer-encoding",           "",   ],
 [ 33, "warning",                     "",   ],
 [ 34, "www-authenticate",            "",   ],
);

sub init_static_tables
{
  for ( @static_request_table ) {
    my $key_nv = $_->[1] . ":" . $_->[2];
    my $key_i = $_->[0];

    $request_table_nv{$key_nv} = $_;
    $request_table_i{$key_i} = $_;
  }

  for ( @static_response_table ) {
    my $key_nv = $_->[1] . ":" . $_->[2];
    my $key_i = $_->[0];

    $response_table_nv{$key_nv} = $_;
    $response_table_i{$key_i} = $_;
  }
}

init_static_tables();



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
  my $self = shift;
  my %params = @_;

  if ( exists $params{request} && $params{request} == 1 ) {
    $self->{dynamic_nv} = dclone( \%request_table_nv );
    $self->{dynamic_i} = dclone( \%request_table_i );
  }
  elsif ( exists $params{response} && $params{response} == 1 ) {
    $self->{dynamic_nv} = dclone( \%response_table_nv );
    $self->{dynamic_i} = dclone( \%response_table_i );
  }
  else {
    die "Need to indicate either request or repsonse";
  }

  $self->{reference} = {};
}

sub find_n
{
  my $self = shift;
  my ( $n ) = @_;

  for my $i ( keys %{$self->{dynamic_i}} ) {
    if ( $self->{dynamic_i}->{$i}->[1] eq $n ) {
      return $i;
    }
  }

  return -1;
}

sub find_nv
{
  my $self = shift;
  my ( $n, $v ) = @_;
  my $k = "$n:$v";

  #print "Looking up nv: $k. ";

  if ( exists $self->{dynamic_nv}->{$k} )
  {
    #print "Found: $self->{dynamic_nv}->{$k}->[0]\n";

    return $self->{dynamic_nv}->{$k};
  }

  #print "Not found\n";

  return undef;
}

sub find_i
{
  my $self = shift;
  my $i = shift;
  return $self->{dynamic_i}->{$i}
}

sub store_nv
{
  my $self = shift;
  my ( $n, $v ) = @_;

  my $key_nv = "$n:$v";

  my $i = scalar( keys %{$self->{dynamic_i}} );
  my $entry = [ $i, $n, $v ];

#  print "Storing $key_nv at index $i\n";

  $self->{dynamic_nv}->{$key_nv} = $entry;
  $self->{dynamic_i}->{$i} = $entry;
}

sub store_nvi
{
  my $self = shift;
  my ( $n, $v, $i ) = @_;

  my $key_nv = "$n:$v";

  my $entry = $self->find_i( $i );
  $entry->[1] = $n;
  $entry->[2] = $v;

#  my $entry = [ $i, $n, $v ];

#  print "Storing $key_nv at index $i\n";

  $self->{dynamic_nv}->{$key_nv} = $entry;
  $self->{dynamic_i}->{$i} = $entry;
}

sub remove
{
  my $self = shift;
  die "Unimplemented";
}






=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use HTTP2::Draft::HeaderIndex;

    my $foo = HTTP2::Draft::HeaderIndex->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1


=head1 AUTHOR

Stephen Ludin, C<< <sludin at ludin.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-http2-draft at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=HTTP2-Draft>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HTTP2::Draft::HeaderIndex


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

1; # End of HTTP2::Draft::HeaderIndex
