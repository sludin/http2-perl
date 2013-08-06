package HTTP2::Draft;

use strict;
use warnings;

our $VERSION = '0.02';

my @errors;
my $MAX_ERRORS = 100;
my $MAX_ERROR_MSG = "Max errors reached";

sub http_version
{
  return "HTTP-draft-04/2.0";
}

sub error
{
  my $error = shift;
  if ( defined $error ) {
    if ( scalar @errors < $MAX_ERRORS ) {
      push @errors, $error;
    }
    else {
      if ( $errors[$MAX_ERRORS] ne $MAX_ERROR_MSG ) {
        push @errors, $MAX_ERROR_MSG;
      }
    }
  }

  return wantarray ? @errors : $errors[0];
}


sub hex_print
{
  my $data = shift;
  my $style = shift || "0";

  my $n = 0;

  my ( @hex ) = unpack( "(H2)*", $data );

  for ( @hex ) {
    if ( $n % 4 == 0 ) {
      printf( "\n%04X ", $n );
    }
    print "$_ ";

    if ( $style == 1 ) {
      if ( hex($_) >= 32 and hex($_) < 127 ) {
        print "\'", chr(hex($_)), "\' ";
      }
      else {
        print "    ";
      }
    }


    $n++;
  }
  print "\n";
}






1;
