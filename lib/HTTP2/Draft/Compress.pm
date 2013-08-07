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


sub extract_string2
{
  my $bytes_ref = shift;

  my $len = decode_int2( $bytes_ref, 7 );
  my $string = pack( "c*", @{$bytes_ref}[0 .. ($len)-1] );

  # Consume the bytes
  splice( @$bytes_ref, 0, $len );

  return $string;
}


sub extract_nv2
{
  my $bytes_ref = shift;

  my $name = extract_string2( $bytes_ref );
  my $value = extract_string2( $bytes_ref );

  return ( $name, $value );
}

sub decode_int2
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

    my $I = decode_int2( $bytes_ref, 7 );

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

      my ( $name, $value ) = extract_nv2( $bytes_ref );



      $token->{name_literal} = $name;
      $token->{value_literal} = $value;
    }
    else {
      debug( "  Indexed Header, literal value" );

      unshift @$bytes_ref, $op & 0x1F;

      # Subtracting one from the wired int
      my $I = decode_int2( $bytes_ref, 5 ) - 1;

      my $value = extract_string2( $bytes_ref );



      $token->{name_index} = $I;
      $token->{value_literal} = $value;
    }
  }
  elsif ( ($op & 0xC0) == 0x00 )
  {
    debug( "Literal Header with Substitution Indexing\n" );

    push @$bytes_ref, $op;

    my $index = decode_int2( $bytes_ref, 6 ) - 1;
    my $substituted_index = decode_int2( $bytes_ref, 8 );
    my $value = extract_string2( $bytes_ref );
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



1;
