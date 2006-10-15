#!/usr/bin/perl

use strict;
use inc::Module::Install;

name               'Apache-Logmonster';
abstract_from      'lib/Apache/Logmonster.pm';
author_from        'lib/Apache/Logmonster.pm';
version_from       'lib/Apache/Logmonster.pm';
license            'bsd';
perl_version       '5.005';

# modules required at run time
requires           'Compress::Zlib' => '0';
requires           'Date::Parse'    => '2.0'; 

auto_include_deps ( );
auto_install      ( -do_once => 1,  );
#WriteMakefile     ( PL_FILES => {}, );
WriteAll();

print "\n", '-'x78, "\n\n";

exit;
