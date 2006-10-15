#!/usr/bin/perl
use strict;
use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "lib";

BEGIN { 
    use_ok( 'Apache::Logmonster' );
    use_ok( 'Apache::Logmonster::Perl' );
    use_ok( 'Apache::Logmonster::Utility' );
}
require_ok( 'Apache::Logmonster' );
require_ok( 'Apache::Logmonster::Perl' );
require_ok( 'Apache::Logmonster::Utility' );

# let the testing begin

# basic OO mechanism

my $utility = Apache::Logmonster::Utility->new;
my $conf = $utility->parse_config( file=>"logmonster.conf",debug=>0 );
ok ($conf, 'logmonster conf object');

## new
my $logmonster = Apache::Logmonster->new($conf,0);
ok ($logmonster, 'new logmonster object');


# override logdir from logmonster.conf
$conf->{'logbase'} = "t/trash";
$conf->{'logdir'} = "t/trash";
$conf->{'tmpdir'} = "t/trash";

# set conf for subroutines
$logmonster->{'conf'} = $conf;
my $original_working_directory = cwd;

my $log_fh;

## check_config
    ok( $logmonster->check_config(), 'check_config');


## get_log_dir
    $logmonster->{'conf'}->{'rotation_interval'} = "hour";
    ok( my $logdir = $logmonster->get_log_dir(), 'get_log_dir hour');
    #print "     logdir: $logdir\n";

    $logmonster->{'conf'}->{'rotation_interval'} = "day";
    ok( $logdir = $logmonster->get_log_dir(), 'get_log_dir day');
    #print "     logdir: $logdir\n";

    $logmonster->{'conf'}->{'rotation_interval'} = "month";
    ok( $logdir = $logmonster->get_log_dir(), 'get_log_dir month');
    #print "     logdir: $logdir\n";

## report_open
    $log_fh = $logmonster->report_open("Logmonster",0);
    ok( $log_fh, 'report_open');
    $logmonster->{'report'} = $log_fh;

# report_hits: set up a dummy hits file
    ## report_open
        my $hits_fh = $logmonster->report_open("HitsPerVhost",0);
        ok( $hits_fh, 'report_open');

        # dump sample data into the file
        print $hits_fh "mail-toaster.org:49300\nexample.com:13\n";

    ## report_close
        $logmonster->report_close($hits_fh);


## report_hits
    if ( -e "/tmp/HitsPerVhost.txt" ) {
        ok( $logmonster->report_hits("/tmp"), 'report_hits');
        unlink "/tmp/HitsPerVhost.txt";
    } 
    else {
        ok( $logmonster->report_hits(), 'report_hits');
    };


## get_domains_list
    if ( ! -d "t/trash/Includes" ) {
        system("/bin/mkdir -p t/trash/Includes");
        open my $EX_CONF, ">", "t/trash/Includes/example.com";
        print $EX_CONF '\n
<VirtualHost *:80>
  ServerAdmin webmaster@example.com
  DocumentRoot /Users/Shared/Sites/mail.example.com
  ServerName www.example.com
  ServerAlias *.example.com example.com
</VirtualHost>\n';
        close $EX_CONF;
    };

    $logmonster->{'conf'}->{'vhost'} = "t/trash/Includes";

    my $domains =  $logmonster->get_domains_list();
    ok( $domains, 'get_domains_list');


## get_vhosts_from_file
    ok( $logmonster->get_vhosts_from_file(
        "t/trash/Includes",
    ), 'get_vhosts_from_file');


## compress_log_file
#    ok( $logmonster->compress_log_file(
#        "matt.cadillac.net", 
#        "/var/log/apache/2006/09/29/access.log",
#    ), 'compress_log_file');


## consolidate_logfile
#    ok( $logmonster->consolidate_logfile(
#        "matt.cadillac.net", 
#        "/var/log/apache/2006/09/29/access.log.gz",
#        "t/trash/matt.cadillac.net-access.log.gz",
#    ), 'consolidate_logfile');


## fetch_log_files
#    $conf->{'logbase'} = "/var/log/apache";
#    ok( $logmonster->fetch_log_files(), 'fetch_log_files');
    

    $logmonster->{'debug'} = 0;
    $logmonster->{'clean'} = 0;

## turn_domains_into_sort_key
    ok ( $logmonster->turn_domains_into_sort_key( $domains,
    ), 'turn_domains_into_sort_key');



## split_logs_to_vhosts
#    ok ( $logmonster->split_logs_to_vhosts($domains), 'split_logs_to_vhosts');


## check_stats_dir
    if ( ! -d "t/trash/doms" ) {
        system("/bin/mkdir -p t/trash/doms");
    };

    ok( $logmonster->check_stats_dir($domains), 'check_stats_dir');


## sort_vhost_logs
#    ok ( $logmonster->sort_vhost_logs(), 'sort_vhost_logs');



## feed_the_machine
#    ok( $logmonster->feed_the_machine($domains), 'feed_the_machine');


## check_awstats_file


## install_default_awstats_conf


## report_close
    ok( $logmonster->report_close($log_fh, 0), 'report_close');

