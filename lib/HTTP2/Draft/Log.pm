package HTTP2::Draft::Log;

use Log::Log4perl;
use Exporter;

our $VERSION = $HTTP2::Draft::VERSION;

our ( $log );

our @EXPORT_OK = qw( $log );
our @ISA = qw( Exporter );

my $pattern = "%d (%r) %F{1} %L> %m %n";
$pattern = "(%r) %F{1} %L> %m %n";

Log::Log4perl->init(\ <<"EOT");
      log4perl.category.General = INFO, Screen
      log4perl.appender.Screen  = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.layout = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern = $pattern
EOT

sub init
{
  my $log_level = shift;

Log::Log4perl->init(\ <<"EOT");
      log4perl.category.General = $log_level, Screen
      log4perl.appender.Screen  = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.layout = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern = $pattern
EOT

  $log = Log::Log4perl::get_logger( 'General' );

}


sub BEGIN
{
  $log = Log::Log4perl::get_logger( 'General' );
}



1;
