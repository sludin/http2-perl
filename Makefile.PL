use 5.008;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'HTTP2::Draft',
    AUTHOR           => q{Stephen Ludin <sludin@ludin.org>},
    VERSION_FROM     => 'lib/HTTP2/Draft.pm',
    ABSTRACT_FROM    => 'lib/HTTP2/Draft.pm',
    LICENSE          => 'Artistic_2_0',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.008,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'HTTP2-Draft-*' },
);
