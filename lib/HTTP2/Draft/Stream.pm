package HTTP2::Draft::Stream;
use Readonly;

use Exporter qw( import );
use HTTP2::Draft;
use HTTP2::Draft::Log qw( $log );

our $VERSION = $HTTP2::Draft::VERSION;

sub new
{
  my $class = shift;
  my $self = {};
  bless $self, $class;
  $self->_init( @_ );
  return $self;
}


Readonly $STATE_IDLE               => 0;
Readonly $STATE_RESERVED_LOCAL     => 1;
Readonly $STATE_RESERVED_REMOTE    => 2;
Readonly $STATE_OPEN               => 3;
Readonly $STATE_HALF_CLOSED_REMOTE => 4;
Readonly $STATE_HALF_CLOSED_LOCAL  => 5;
Readonly $STATE_CLOSED             => 6;

my %state_names = {
                   $STATE_IDLE               => 'STATE_IDLE',
                   $STATE_RESERVED_LOCAL     => 'STATE_RESERVED_LOCAL',
                   $STATE_RESERVED_REMOTE    => 'STATE_RESERVED_REMOTE',
                   $STATE_OPEN               => 'STATE_OPEN',
                   $STATE_HALF_CLOSED_REMOTE => 'STATE_HALF_CLOSED_REMOTE',
                   $STATE_HALF_CLOSED_LOCAL  => 'STATE_HALF_CLOSED_LOCAL',
                   $STATE_CLOSED             => 'STATE_CLOSED'
                  };



our %EXPORT_TAGS = ( states => [ qw ( $STATE_IDLE
                                      $STATE_RESERVED_LOCAL
                                      $STATE_RESERVED_REMOTE
                                      $STATE_OPEN
                                      $STATE_HALF_CLOSED_REMOTE
                                      $STATE_HALF_CLOSED_LOCAL
                                      $STATE_CLOSED ) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{states} } );


sub _init
{
  my $self      = shift;

  my %params = @_;

  $self->{conn}         = $params{conn};

# TODO: this assume all of the headers have been read
  $self->{streamid} = $params{streamid};
  $self->{http_headers} = $params{http_headers};

  $self->{window}        = $params{window};
  $self->{max_window}    = $params{window};
  $self->{state}         = $STATE_IDLE;
  $self->{bytes_written} = 0;
  $self->{buffer}        = "";
  $self->{header_state}  = 0;

}

sub state
{
  my $self = shift;
  my $state = shift;

  if ( $state ) {
    $log->debug( "stream_id ($self->{streamid}): Changing state from $self->{state} to $state" );
    $self->{state} = $state;
  }

  return $self->{state};
}



    #                       +--------+
    #                 PP    |        |    PP
    #              ,--------|  idle  |--------.
    #             /         |        |         \
    #            v          +--------+          v
    #     +----------+          |           +----------+
    #     |          |          | H         |          |
    # ,---| reserved |          |           | reserved |---.
    # |   | (local)  |          v           | (remote) |   |
    # |   +----------+      +--------+      +----------+   |
    # |      |          ES  |        |  ES          |      |
    # |      | H    ,-------|  open  |-------.      | H    |
    # |      |     /        |        |        \     |      |
    # |      v    v         +--------+         v    v      |
    # |   +----------+          |           +----------+   |
    # |   |   half   |          |           |   half   |   |
    # |   |  closed  |          | R         |  closed  |   |
    # |   | (remote) |          |           | (local)  |   |
    # |   +----------+          |           +----------+   |
    # |        |                v                 |        |
    # |        |  ES / R    +--------+  ES / R    |        |
    # |        `----------->|        |<-----------'        |
    # |  R                  | closed |                  R  |
    # `-------------------->|        |<--------------------'
    #                       +--------+


1;
