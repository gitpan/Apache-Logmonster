# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#
# $Id: Utility.t,v 1.4 2004/11/26 18:09:22 matt Exp $
#

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..18\n"; }
END {print "not ok 1\n" unless $loaded;}
use lib "lib";
use Apache::Logmonster::Utility;
$loaded = 1;
print "ok 1 - Apache::Logmonster::Utility\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $utility = Apache::Logmonster::Utility->new();
$utility ? print "ok 2 - new utility\n" : print "not ok 2\n";

$r = $utility->yes_or_no("test", 5);
$r ? print "ok 3 - yes_or_no\n" : print "not ok 3 (yes_or_no)\n";

$r = $utility->file_check_readable("/etc/hosts", 1);
$r ? print "ok 4 - file_check_readable\n" : print "not ok 4 (file_check_readable)\n";

$r = $utility->file_check_writable("/tmp/test.pid");
$r ? print "ok 5 - file_check_writable\n" : print "not ok 5 (file_check_writable)\n";

if ( $r ) {
	$r = $utility->file_write("/tmp/test.pid", "junk");
	$r ? print "ok 6 - file_write\n" : print "not ok 6 (file_write)\n";

	($r) = $utility->file_read("/tmp/test.pid");
	$r ? print "ok 7 - file_read\n" : print "not ok 7 (file_read)\n";

	$r = $utility->file_append("/tmp/test.pid", ["more junk"]);
	$r ? print "ok 8 - file_append\n" : print "not ok 8 (file_append)\n";

	$r = $utility->file_delete("/tmp/test.pid");
	$r ? print "ok 9 - file_delete\n" : print "not ok 9 (file_delete)\n";
}

$r = $utility->check_pidfile("/tmp/test.pid");
-e $r ? print "ok 10 - check_pidfile\n" : print "not ok 10 (check_pidfile)\n";

$r = $utility->file_delete($r);
$r ? print "ok 11 - file_delete\n" : print "not ok 11 (file_delete)\n";

$r = $utility->is_process_running("init");
$r ? print "ok 12 - is_process_running\n" : print "not ok 12 (is_process_running)\n";

my $rm = $utility->find_the_bin("rm");
-x $rm ? print "ok 13 - find_the_bin\n" : print "not ok 13 (find_the_bin)\n";

$r = $utility->chdir_source_dir("/tmp");
$r ? print "ok 14 - chdir_source_dir\n" : print "not ok 14 (chdir_source_dir)\n";

(@list) = $utility->get_the_date();
$list[0] ? print "ok 15 - get_the_date\n" : print "not ok 15 (get_the_date)\n";

$r = $utility->syscmd("test");
! $r ? print "not ok 16 - syscmd\n" : print "ok 16 - syscmd\n";

my @list = $utility->get_dir_files("/etc");
-e $list[0] ? print "ok 17 - get_dir_files\n" : print "not ok 17 (get_dir_files)\n";

$r = $utility->drives_get_mounted();
$r ? print "ok 18 - drives_get_mounted\n" : print "not ok 18 (drives_get_mounted)\n";


