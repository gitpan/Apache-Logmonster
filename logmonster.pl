#!/usr/bin/perl
use strict;
use warnings;

package Apache::Logmonster;

use vars qw($VERSION); 
$VERSION  = '3.02';

use lib "lib";

use English;
use Getopt::Long;
use Pod::Usage;
use Apache::Logmonster 3;
use Apache::Logmonster::Utility 5; 

my %command_line_options = (
    'bump:i'     => \my $bump,       # an optional time offset
    'clean!'     => \my $clean,      # ability to override conf file
    'interval:s' => \my $interval,   # hour/day/month
    'hourly'     => \my $hourly,
    'daily'      => \my $daily,
    'monthly'    => \my $monthly,
    'n'          => \my $dry_run,    # just show what we would do
    'verbose+'   => \my $verbose,    # incremental -v options
    'report'     => \my $report_mode,
);
if ( ! GetOptions (%command_line_options) ) {
    pod2usage;
};

# a generic utility object that provides many useful functions
my $utility = Apache::Logmonster::Utility->new();
my $banner  = "\n\t\t Apache Log Monster $VERSION by Matt Simerson \n\n";
my $config  = $utility->parse_config( file =>"logmonster.conf", debug=>0 );

# allow CLI to override clean option in config file
   $config->{'clean'} = $clean if defined $clean;
   $config->{'time_offset'} = $bump if defined $bump;

my $logmonster = Apache::Logmonster->new($config,$verbose);

# if this is not enabled, our report formatting will be jumbled
$OUTPUT_AUTOFLUSH++;

if ( $verbose && ! $report_mode ) {
  $verbose == 1 ? print "verbose mode (1).\n"
: $verbose == 2 ? print "very verbose mode (2).\n"
: $verbose == 3 ? print "screaming at you (3).\n"
: warn "unknown verbosity\n";
};

print $banner if $verbose;

# run a few preliminary sanity tests
$logmonster->check_config();

# CLI backwards compatability with previous versions
$interval ||= $hourly  ? "hour"
            : $daily   ? "day"
            : $monthly ? "month"
            : q{};

my %valid_intervals = ( hour => 1, day => 1, month => 1 );

if ( ! defined $valid_intervals{$interval} ) {
    pod2usage;
};

# stuff a few settings into the $logmonster object so
# Apache::Logmonster functions can access them.

my @hosts = split(/ /, $config->{'hosts'});
my $host_count = @hosts;
$logmonster->{'host_count'} = $host_count;
$logmonster->{'rotation_interval'} = $interval;
$logmonster->{'dry_run'} = $dry_run || 0;

if ($report_mode) {
    # prints out the last intervals hit count and exit, useful for SNMP
    $logmonster->report_hits();
    exit 1;
};

# open a file to log our activities to
my $REPORT = $logmonster->report_open("Logmonster", $verbose);

# store the file handle in the $logmonster object for functions
$logmonster->{'report'} = $REPORT;

$utility->_progress($banner) if $verbose;
print $REPORT $banner;

# do the work
my $domains_ref = 
$logmonster->get_domains_list     ();
$logmonster->fetch_log_files      ();
$logmonster->split_logs_to_vhosts ($domains_ref);
$logmonster->check_stats_dir      ($domains_ref);
$logmonster->sort_vhost_logs      () if !$dry_run;
$logmonster->feed_the_machine     ($domains_ref);
$logmonster->report_close         ($REPORT);

exit 1;   # happy exit status

__END__


=head1 NAME

Apache::Logmonster - log utility for merging, sorting, and processing web logs


=head1 VERSION
 
This documentation refers to Apache::Logmonster version 3.00
 

=head1 SYNOPSIS

logmonster.pl -i <interval> [-v] [-r] [-n] [-b N]

   Interval is one of:

       hour    (last hour)
       day     (yesterday)
       month   (last month)

   Optional:

      -v     verbose     - lots of status messages 
      -n     dry run     - do everything except feed the logs into the processor
      -r     report      - last periods hit counts
      -b N   back N days - use with -i day to process logs older than one day


=head1 USAGE

To see what it will do without actually doing anything

   /usr/local/sbin/logmonster -i day -v -n

From cron: 

   5 1 * * * /usr/local/sbin/logmonster -i day

From cron with a report of activity: 

   5 1 * * * /usr/local/sbin/logmonster -i day -v


=head1 DESCRIPTION

Logmonster is a tool to collect log files from one or many Apache web servers, split them based on the virtual host they were served for, sort the logs into cronological order, and finally pipe the sorted logs to the log file analyzer of choice (webalizer, http-analyze, AWstats, etc).


=head2 MOTIVATION

Log collection: I have a number of web sites that are mirrored on two or three web servers. The statistics I care about are agreggate. I want to know how much traffic a web site is getting across all the servers. To accomplish that, the logs must be collected from each server. 

Sorting: Since most log processors require the log file entries to be in chronological order, simply concatenating them, or feeding them one after another does not work. Logmonster takes care of this by sorting all the log entries for each vhost into chronological order.

Processor Agnostic: If I want to switch from one log processor to another, it should be simple and painless. Logmonster takes care of all the dirty work to make the possible. Each domain can even have its own processor.


=head2 FEATURES

=over

=item * Log Retrieval from one or mnay hosts

=item * Ouputs to webalizer, http-analyze, and AWstats.

=item * Automatic vhost configuration 

Logmonster reads your Apache config files to learn about your virtual hosts and their file system location. Logmonster also generates config files as required (ie, awstats.example.com.conf).

=item * Settings configuration for each virtualhost

Outputs stats into each virtual domains stats dir, if that directory exists. This is an easy way to enable or disable stats for a virtual host. If "stats" exists, it will be updated. Otherwise it will not. Can also creates missing stats directories if desired (see statsdir_policy in logmonster.conf).

=item * Efficient

uses Compress::Zlib to read directly from .gz files to minimizes network and disk usage. Skips processing logs for vhosts with no $statsdir. Skips sorting if you only have logs from one host.

=item * Flexible update intervals

you can run it monthly, daily, or hourly

=item * Reporting

saves an activity report and sends an email friendly report.

=item * Reliable

lots of error checking so if something goes wrong, it gives a useful error message.

=item * Apache savvy

Understands and correctly deals with server aliases

=back


=head1 INSTALLATION

=over

=item Step 1 - Download and install (it's FREE!)

http://tnpi.net/cart/index.php?crn=210&rn=385&action=show_detail

Install like nearly every perl module: 

   perl Makefile.PL
   make test
   make install 

To install the config file use "make conf" or "make newconf". newconf will overwrite any existing config file, so use it only for new installs.

=item Step 2 - Edit logmonster.conf

 vi /usr/local/etc/logmonster.conf

=item Step 3 - Edit httpd.conf

Adjust the CustomLog and ErrorLog definitions. We make two changes, appending %v (the vhost name) to the CustomLog and adding cronolog to automatically rotate the log files.

  LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %v" combined
  CustomLog "| /usr/local/sbin/cronolog /var/log/apache/%Y/%m/%d/access.log" combined
  ErrorLog "| /usr/local/sbin/cronolog /var/log/apache/%Y/%m/%d/error.log"

=item Step 4 - Test manually, then add to cron.

  crontab -u root -e
  5 1 * * * /usr/local/sbin/logmonster -i day

=item Step 5 - Read the FAQ

L<http://tnpi.net/wiki/Logmonster_FAQ>

=item Step  6 - Enjoy

Allow Logmonster to make your life easier by handling your log processing. Enjoy the daily summary emails, and then express your gratitude by making a small donation to support future development efforts.

=back


=head1 DIAGNOSTICS

Run in verbose mode (-v) to see addition status and error messages. If you want more verbosity, you can increase the verbosity by appending another -v (-v -v). If that is not enough, run with (-v -v -v) for even more verbosity. If that is not enough is, the source with you be. "Fear is the path to the dark side. Fear leads to anger. Anger leads to hate. Hate leads to suffering." Fear not, for the source is strong with you.

Also helpful when troubleshooting is the ability to skip cleanup (so logfiles do not have to be fetched anew) with the --noclean command line option.


=head1 DEPENDENCIES

Not perl builtins

  Compress::Zlib
  Date::Parse (TimeDate)
  Params::Validate

Builtins

  Carp
  Cwd
  FileHandle
  File::Basename
  File::Copy


=head1 BUGS AND LIMITATIONS

None known. Report problems to author. Patches are welcome.


=head1 AUTHOR
 
Matt Simerson  (matt@tnpi.net)
 

=head1 ACKNOWLEDGEMENTS

 Gernot Hueber - sumitted the daily userlogs feature
 Lewis Bergman - funded authoring of several features
 Raymond Dijkxhoorn - suggested not sorting the files for one log host
 Earl Ruby  - a better regexp for apache log date parsing


=head1 TODO

Add support for analog.

Add support for individual webalizer.conf file for each domain (this will likely not happen until someone submits a diff or pays me to do it as I don't use webalizer any longer).

Delete log files older than X days/month - super low priority, it's easy and low maintenance to manually delete a few months log files when I'm sure I don't need them any longer.

Do something with error logs (other than just compress)

If files to process are larger than 10MB, find a nicer way to sort them rather than reading them all into a hash. Now I create two hashes, one with data and one with dates. I sort the date hash, and using those sorted hash keys, output the data hash to a sorted file. This is necessary as wusage and http-analyze require logs to be fed in chronological order. Look at awstats logresolvemerge as a possibility.

Add config file setting for the location of awstats.pl


=head1 SEE ALSO

http://tnpi.net/wiki/Logmonster


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2003-2007, The Network People, Inc. (info@tnpi.net) All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DIS CLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
