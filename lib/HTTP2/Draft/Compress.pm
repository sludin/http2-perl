package HTTP2::Draft::Compress;

use 5.008;
use strict;
use warnings FATAL => 'all';

use Carp;


use Data::Dumper;

use HTTP2::Draft::HeaderIndex;



=head1 NAME

HTTP2::Draft::Compress

=head1 VERSION

Version 0.03

=cut

our $VERSION = '0.03';



my $debug_compression = 0;


sub debug
{
  if ( $debug_compression ) {
    print @_, "\n";
  }
}


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

  if ( exists $params{request} && $params{request} == 1 )
  {
    $self->{index} = HTTP2::Draft::HeaderIndex->new( request => 1 );
  }
  elsif ( exists $params{response} && $params{response} == 1 )
  {
    $self->{index} = HTTP2::Draft::HeaderIndex->new( response => 1 );
  }

  $self->{reference} = {};

}




# print pack "C*", HTTP2::Draft::Compress::pack_len_string( "foo" );

sub encode_len_string
{
  my $string = shift;

  return encode_int(length( $string ),0), unpack( "C*", $string );
}


sub encode_int
{
  my $int  = shift;
  my $bits = shift;
  my @ret;
  my $max = (2 ** $bits) - 1;


  my $I = $int;
  my $Q;
  my $R;

  if ( $I <= $max )
  {
    push @ret, $I;
  }
  else
  {
    push @ret, $max if $max;
    $I -= $max;
    $Q = 1;

    while ( $Q > 0 )
    {
      $R = $I % 128;
      $Q = int($I / 128);

      push @ret, $R | ($Q > 0 ? 0x80 : 0x00 );

      $I = $Q;

    }

  }

  return @ret;
}



sub deflate
{
  my $self    = shift;
  my $headers = shift;

  #print Dumper( $headers );

  my $ws;

  my @hblock;

  for my $name ( keys %$headers )
  {
    my @tmp;

    my $value = $headers->{$name};

    debug( "Deflate: Encoding $name: $value\n" );

    my $nvkey = "$name:$value";
    $ws->{$nvkey} = { name => $name, value => $value, indexed => 1 };

    if ( (my $entry = $self->{index}->find_nv( $name, $value )) )
    {
      debug( "Deflate: Found full pair in table: index = $entry->[0]\n" );

      if ( ! exists $self->{reference}->{$nvkey} )
      {
        debug( "Deflate: Not found in reference set.  Adding to transmitted headers" );

        # TODO: this needs integer ecoding.  For testing as long as we stay under 127 we shoudl be OK
        push @tmp, ($entry->[0]) | 0x80;
      }
    }
    else
    {
      # need to do a literal representation
      # let's only do incremental indexed for now ( 0x40 )
      debug( "Deflate: Did not find full pair in table.  Doing a literal representation" );

      my $i = $self->{index}->find_n( $name );

      if ( $i != -1 )
      {
        debug( "Deflate: Found header name.  Including header name index: index = $i" );

        my @t = encode_int( $i + 1, 5 );
        $t[0] |= 0x40;

        push @tmp, @t;
      }
      else
      {
        debug( "Deflate: New header name.  Encoding header name as string" );

        push @tmp, 0x40;
        push @tmp, encode_len_string( $name );
      }

      debug( "Deflate: Adding value to header block\n" );

      push @tmp, encode_len_string( $value );

      my $nvkey = "$name:$value";
#      $ws->{$nvkey} = { name => $name, value => $value, indexed => 1 };

      $self->{index}->store_nv( $name, $value );

      #      if ( ! exists $self->{reference}->{$nvkey} ) {
      #	$self->{reference}->{$nvkey} = { indexed => 1,
      #					 key => $name,
      #					 value => $value };
      #      }
    }

 #   print Dumper( \@hblock );

    debug( "Deflate: Adding:" );
    debug( "Deflate: " );
    HTTP2::Draft::hex_print( pack "C*", @tmp ) if $debug_compression;;

    push @hblock, @tmp;
  }



  for my $nvkey ( keys %{$self->{reference}} )
  {
    if ( ! exists $ws->{$nvkey} &&
         $self->{reference}->{$nvkey}->{indexed} ) {
      my $entry = $self->{index}->find_nv($self->{reference}->{$nvkey}->{name},
                                          $self->{reference}->{$nvkey}->{value} );

      debug( "Deflate: $nvkey in reference set and not in working set.  Adding to header block.\n" );

#      print Dumper( $entry );
      # TODO: pack ints over 128
      push @hblock, ($entry->[0]) | 0x80;
    }
  }

  #print Dumper( $self->{reference} );
  #print Dumper( $ws );

  for my $nvkey ( keys %$ws )
  {
    $self->{reference} = $ws;
  }

#  print Dumper( $self->{reference} );

  #HTTP2::Draft::hex_print( pack "C*", @hblock ) if $debug_compression;

  
  return pack "C*", @hblock;

}


sub extract_string
{
  my $bytes_ref = shift;

  my $len = decode_int( $bytes_ref, 7 );
  my $string = pack( "c*", @{$bytes_ref}[0 .. ($len)-1] );

  # Consume the bytes
  splice( @$bytes_ref, 0, $len );

  return $string;
}


sub extract_nv
{
  my $bytes_ref = shift;

  my $name = extract_string( $bytes_ref );
  my $value = extract_string( $bytes_ref );

  return ( $name, $value );
}

sub decode_int
{
  my $bytes_ref = shift;
  my $bits = shift;

  my $max = (2 ** $bits) - 1;

  my $I = shift @$bytes_ref;

  # If the first byte is less that $max then that is the decoded int
  if ( $I < $max )
  {
    return $I;
  }
  else
  {
     my $n = 0;

     my $byte;
     while ( ($byte = shift @$bytes_ref) & 0x80  )
     {
       $I += ($byte & 0x7F) * (128 ** $n);
       $n++;
     }

     $I += $byte * (128 ** $n);
   }

  return $I;
}

sub get_token
{
  my $bytes_ref = shift;

  return if ( @$bytes_ref == 0 );

  my $op = shift @$bytes_ref;

  my $token = {
               op => 0,
               index         => undef,
               name_index    => undef,
               name_literal  => undef,
               value_literal => undef
              };

  $token->{op} = $op;



  if ( ($op & 0x80) == 0x80 )
  {
    debug( "Literal index\n" );

    # put the 7 bit index start back on the array
    unshift @$bytes_ref, $op &= 0x7F;

    my $I = decode_int( $bytes_ref, 7 );

    $token->{index} = $I;
  }
  elsif ( ($op & 0xE0) == 0x60 )
  {
    die "Should not be here yet";
  }
  elsif ( ($op & 0xE0) == 0x40 )
  {
    debug( "Literal Header with Incremental Indexing" );

    if ( $op == 0x40 ) {
      debug( "  Full literal name and value" );

      my ( $name, $value ) = extract_nv( $bytes_ref );



      $token->{name_literal} = $name;
      $token->{value_literal} = $value;
    }
    else {
      debug( "  Indexed Header, literal value" );

      unshift @$bytes_ref, $op & 0x1F;

      # Subtracting one from the wired int
      my $I = decode_int( $bytes_ref, 5 ) - 1;

      my $value = extract_string( $bytes_ref );



      $token->{name_index} = $I;
      $token->{value_literal} = $value;
    }
  }
  elsif ( ($op & 0xC0) == 0x00 )
  {
    debug( "Literal Header with Substitution Indexing\n" );

    push @$bytes_ref, $op;

    my $index = decode_int( $bytes_ref, 6 ) - 1;
    my $substituted_index = decode_int( $bytes_ref, 8 );
    my $value = extract_string( $bytes_ref );
  }
  else
  {
    die( "Unrecognized instruction: %02x\n", $op );
  }

  return $token;
}

sub inflate
{
  my $self    = shift;
  my $block   = shift;
  my $headers = {};

  my @bytes = unpack( "C*", $block );

  my $ws;


  while( my $token = get_token( \@bytes ) )
  {
    my $op = $token->{op};

    if ( ($op & 0x80) == 0x80 ) {

      my $index = $token->{index};

      my $entry = $self->{index}->find_i($index);

      debug( "Literal index: $index" );

      if ( ! $entry ) {
        die "Entry $index not found in index";
      }

      my $name  = $entry->[1];
      my $value = $entry->[2];

      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };
    }
    elsif ( ($op & 0xE0) == 0x60 ) {
      die "Not implemented.  Yet";
    }
    elsif ( ($op & 0xE0) == 0x40 ) {
      debug( "Literal Header with Incremental Indexing\n" );

      my $name;
      my $value;

      if ( $op == 0x40 ) {
        debug( "  Full literal name:value\n" );

        $name = $token->{name_literal};
        $value = $token->{value_literal};
      }
      else {
        my $index = $token->{name_index};

        my $entry = $self->{index}->find_i( $index );

        $name = $entry->[1];
        $value = $token->{value_literal};
      }

      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };

      $self->{index}->store_nv( $name, $value );
    }
    elsif ( ($op & 0xC0) == 0x00 )  {
      debug( "Literal Header with Substitution Indexing\n" );

      my $index;
      my $substituted_index;
      my $n;
      my $name;
      my $value;


      $index = $token->{index};
      $substituted_index = $token->{substituted_index};

      my $entry = $self->{index}->find_i( $index );

      $name = $entry->[1];

      $value = $token->{value_literal};


      $self->{index}->store_nvi( $name, $value, $substituted_index );



      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };


    }
    else {
      die ( "Unrecognized instruction: %02x\n", $op );
    }
  }

  for my $nvkey ( keys %$ws )
  {
    my ( $n, $v ) = $nvkey =~ /^(:?[^:]+):(.*)/;

    if ( exists $self->{reference}->{$n} &&
         $self->{reference}->{$n}->{indexed} )
    {
      delete $self->{reference}->{$n};
    }
    else
    {
      $self->{reference}->{$n} = $ws->{$nvkey};
    }
  }

  for my $n ( keys %{$self->{reference}} )
  {
    my $v = $self->{reference}->{$n}->{value};

    $headers->{$n} = $v;
  }

  return $headers;
}



=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use HTTP2::Draft::Compress;

    my $foo = HTTP2::Draft::Compress->new();
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

    perldoc HTTP2::Draft::Compress


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

1; # End of HTTP2::Draft::Compress
