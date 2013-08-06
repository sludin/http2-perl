package HTTP2::Draft::HeaderIndex;

use Storable qw( dclone );

use strict;
use warnings;

use Data::Dumper;


our $VERSION = $HTTP2::Draft::VERSION;

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







1;
