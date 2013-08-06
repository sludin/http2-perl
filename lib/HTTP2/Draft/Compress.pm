package HTTP2::Draft::Compress;

use Carp;

use strict;
use warnings;

use Data::Dumper;

use HTTP2::Draft::HeaderIndex;

our $VERSION = $HTTP2::Draft::VERSION;

my $debug_compression = 0;


sub debug
{
  if ( $debug_compression ) {
    print @_;
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

sub decode_int
{
  my $bytes = shift;
  my $pos = shift;
  my $bits = shift;

#print Dumper( $bytes );

  my $i = $pos;

  my $max = (2 ** $bits) - 1;

#print $max, "\n";

  my $I;

  my $n = 0;

  if ( $bytes->[$i] < $max )
  {
    return wantarray ? ($bytes->[$i], 1) : $bytes->[$i];;
  }
  else
  {
    $I = $bytes->[$i] if $max;
    # print "byte: ", $bytes->[$i], "\n";

    for ( ; ;  )
    {
      $i++;
      # print "byte: ", $bytes->[$i], "\n";
      if ( $bytes->[$i] & 0x80 )
      {
        $I += ($bytes->[$i] & 0x7F) * (128 ** $n);
      }
      else
      {
        $I += $bytes->[$i] * (128 ** $n);
        last;
      }
      $n++;
    }
  }

#print "I = $I\n";

  return wantarray ? ($I, ($i - $pos) + 1) : $I;
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
        debug( "Deflate: Not found in reference set.  Adding to transmitted headers\n" );

        # TODO: this needs integer ecoding.  For testing as long as we stay under 127 we shoudl be OK
        push @tmp, ($entry->[0]) | 0x80;
      }
    }
    else
    {
      # need to do a literal representation
      # let's only do incremental indexed for now ( 0x40 )
      debug( "Deflate: Did not find full pair in table.  Doing a literal representation\n" );

      my $i = $self->{index}->find_n( $name );

      if ( $i != -1 )
      {
        debug( "Deflate: Found header name.  Including header name index: index = $i\n" );

        my @t = encode_int( $i + 1, 5 );
        $t[0] |= 0x40;

        push @tmp, @t;
      }
      else
      {
        debug( "Deflate: New header name.  Encoding header name as string\n" );

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

    #debug( "Deflate: Adding:\n" );
    #debug( "Deflate: " );
    #HTTP2::Draft::hex_print( pack "C*", @tmp ) if $debug_compression;;

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
  my $block = shift;
  my $pos = shift;
  my $i = $pos;

  my $len = $block->[$pos];
  $i++;


  my $string = pack( "c*", @{$block}[$i .. ($i + $len)-1] );

  $i += $len;

  return ( $string, $i - $pos );
}


sub extract_nv
{
  my $block = shift;
  my $pos = shift;
  my $i = $pos;

  my $nlen = $block->[$pos];
  $i++;

  my $name = pack( "c*", @{$block}[$i .. $i + $nlen] );
  $i += $nlen;
  my $vlen = $block->[$i];
  my $value = pack( "c*", @{$block}[$i .. $i + $vlen] );
  $i += $vlen;

  return ( $name, $value, $i - $pos );
}

sub inflate
{
  my $self   = shift;
  my $block = shift;
  my $headers = {};

  my $ws;

  HTTP2::Draft::hex_print( $block, 1 );

  my @b = unpack( "C*", $block );


  for ( my $i = 0; $i < scalar(@b); $i++ )
  {

    #printf ( "Instruction: %02x\n", $b[$i] );

    #printf ( "%02X\n", $b[$i] & 0xE0 );

    debug( "opcode: " . sprintf( "%02X", $b[$i] ) . "\n" );

    my ( $name, $value, $length );
    if ( ($b[$i] & 0x80) == 0x80 )
    {

      $b[$i] &= 0x7F;


      my ($I, $n) = decode_int( \@b, $i, 7 );
#      $I--;

      $i += ($n-1);

      debug( "Literal index: $I\n" );

      my $entry = $self->{index}->find_i($I);

      if ( ! $entry )
      {
        die "Entry $I not found in index";
      }

      $name = $entry->[1];
      $value = $entry->[2];

      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };

    }
    elsif ( ($b[$i] & 0xE0) == 0x60 )
    {
      $i++;
      die "Should not be here yet";

      ( $name, $value, $length ) = extract_nv( \@b, $i );
      $i += $length;
    }
    elsif ( ($b[$i] & 0xE0) == 0x40 )
    {
      debug( "Literal Header with Incremental Indexing\n" );

      if ( $b[$i] == 0x40 )
      {
        debug( "Full literal name:value\n" );
        $i++;
        ( $name, $value, $length ) = extract_nv( \@b, $i );
        $i += $length;
      }
      else
      {
        $b[$i] &= 0x1F;

        my ( $I, $n ) = decode_int( \@b, $i, 5 );
        $I--;

        debug( "Indexed header: index = $I\n" );

        my $entry = $self->{index}->find_i( $I );

        $name = $entry->[1];

        $i += $n;
        ($value, $length) = extract_string( \@b, $i );
        $i += $length;

        $i--;
      }

      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };

      $self->{index}->store_nv( $name, $value );

    }
    elsif ( ($b[$i] & 0xC0) == 0x00 )
    {
      debug( "Literal Header with Substitution Indexing\n" );
#      $i++;

#      die "Should not be here yet";

      my $index;
      my $substituted_index;
      my $n;


      ( $index, $n ) = decode_int(\@b, $i, 6 );
      $index--;
      $i += $n;

      my $entry = $self->{index}->find_i( $index );
      ( $substituted_index, $n ) = decode_int( \@b, $i, 8 );
      $i += $n;

#print "I = $I\n";
#print Dumper( $entry );

      my $name = $entry->[1];

      ($value,$length) = extract_string( \@b, $i );
#print length( $value ), " ", $length, "\n";
#text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8

print "length = $length\n";

      $i += $length;

      $self->{index}->store_nvi( $name, $value, $substituted_index );



      my $nvkey = "$name:$value";
      $ws->{$nvkey} = { indexed => 1,
                        value   => $value,
                        name    => $name };


#      print $nvkey, "\n";

#      printf( "%02X\n", $b[$i] );

      $i--; # TODO: Stupid.  Decrement because I increment in the for loop.  Stupid.

#print "name = $name, $value = $value\n";

#      $i += $length;

    }
    else
    {
      printf ( "Unrecognized instruction: %02x\n", $b[$i] );
    }

#    print "$name: $value\n";

  }

#print Dumper( $ws );
#print Dumper( $self->{reference} );

  for my $nvkey ( keys %$ws )
  {
    my ( $n, $v ) = $nvkey =~ /^(:?[^:]+):(.*)/;

#    if ( exists $self->{reference}->{$n} &&
#         $self->{reference}->{$n}->{indexed} )
#    {
#      delete $self->{reference}->{$n};
#    }
#    else
#    {
      $self->{reference}->{$n} = $ws->{$nvkey};
#    }
  }

  for my $n ( keys %{$self->{reference}} )
  {
    my $v = $self->{reference}->{$n}->{value};

#    print "$n: $v\n ";

#    my ( $n, $v ) = $nvkey =~ /^(:?[^:]+):(.*)/;
    $headers->{$n} = $v;
#        print "$nvkey name = $n, value = $v\n";
  }


#print Dumper( $headers );

  return $headers;
  #  print "\n";


}



1;
