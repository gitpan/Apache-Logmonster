# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Perl.t,v 1.2 2005/05/02 21:05:59 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..4\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Apache::Logmonster::Perl;
$loaded = 1;
print "ok 1 - Apache::Logmonster::Perl\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):


my $perl = Apache::Logmonster::Perl->new();
$perl ? print "ok 2 - perl object\n" : print "not ok 2\n";


$r = $perl->check;
$r ? print "ok 3 - version check\n" : print "not ok 3 (version check)\n";


$r = $perl->module_load( {
		module      => "CGI",
		ports_name  => "p5-CGI",
		ports_group => "www",
		timer       => 10,
	} );
$r ? print "ok 4 - module load\n" : print "not ok 4 (module_load)\n";
