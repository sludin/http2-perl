#!perl -T
use 5.008;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 13;

BEGIN {
    use_ok( 'HTTP2::Draft' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Client' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Compress' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Connection' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Frame' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::HeaderIndex' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Log' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Server' ) || print "Bail out!\n";
    use_ok( 'HTTP2::Draft::Stream' ) || print "Bail out!\n";
    use_ok( 'IO::Async::HTTP2::Framer' ) || print "Bail out!\n";
    use_ok( 'IO::Async::HTTP2::FramerStream' ) || print "Bail out!\n";
    use_ok( 'IO::Async::SPDY::Framer' ) || print "Bail out!\n";
    use_ok( 'IO::Async::SPDY::Server' ) || print "Bail out!\n";
}

diag( "Testing HTTP2::Draft $HTTP2::Draft::VERSION, Perl $], $^X" );
