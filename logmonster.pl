#!/usr/bin/perl
use strict;

package Apache::Logmonster;

#use warnings;
use vars qw($VERSION);

$VERSION  = '2.77';

=head1 NAME

Apache::Logmonster

=head1 SYNOPSIS

Processor for Apache logs

=head1 DESCRIPTION

A tool to collect log files from multiple Apache web servers, split them based on the virtual host, sort the logs into cronological order, and then pipe them into a log file analyzer of your choice (webalizer, http-analyze, AWstats, etc).

=head2 FEATURES

=over

=item Log Retrieval from one or mnay hosts

=item Ouputs to webalizer, http-analyze, and AWstats.

=item Automatic configuration by reading Apache config files. Generates config files as required (ie, awstats.example.com.conf).

=item Outputs stats into each virtual domains stats dir, if that directory exists. (HINT: Easy way to enable or disable stats for a virtual host). Can create missing stats directories if desired.

=item Efficient: uses Compress::Zlib to read directly from .gz files to minimize disk use. Skips processing logs for vhosts with no $statsdir. Doesn't sort if you only have logs from one host.

=item Flexible: you can run it monthly, daily, or hourly

=item Reporting: saves an activity report and sends an email friendly report.

=item Reliable: lots of error checking so if something goes wrong, it'll give you a useful error message.

=item Understands and correctly deals with server aliases

=back

=head1 INSTALLATION

=over

=item Step 1 - Download and install (it's FREE!)

http://www.tnpi.biz/store/product_info.php?cPath=2&products_id=40

Install like every other perl module: 

 perl Makefile.PL
 make test
 make install 

To install the config file use "make conf" or "make newconf". newconf will overwrite any existing config file, so use it only for new installs.

=item Step 2 - Edit logmonster.conf

 vi /usr/local/etc/logmonster.conf

=item Step 3 - Edit httpd.conf

Adjust the CustomLog and ErrorLog definitions. We make two changes, adding %v (the vhost name) to the CustomLog and adding cronolog to automatically rotate the log files.

=over

=item LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %v" combined

=item CustomLog "| /usr/local/sbin/cronolog /var/log/apache/%Y/%m/%d/access.log" combined

=item ErrorLog "| /usr/local/sbin/cronolog /var/log/apache/%Y/%m/%d/error.log"

=back

=item Step 4 - Test manually, then add to cron.

  crontab -u root -e
  5 1 * * * /usr/local/sbin/logmonster -d

=item Step 5 - Read the FAQ

http://www.tnpi.biz/internet/www/logmonster/faq.shtml

=item Step  6 - Enjoy

Allow Logmonster to make your life easier by handling your log processing. Enjoy the daily summary emails, and then express your gratitude by making a small donation to support future development efforts.

=back


=head1 DEPENDENCIES

  Compress::Zlib
  Date::Parse (TimeDate)

=cut

#######################################################################
#      System Settings! Don't muck with anything below this line      #
#######################################################################

use vars qw/ $opt_b $opt_d $opt_h $opt_m $opt_n $opt_q $opt_r $opt_v
	$clean $countlog $awstats $webalizer $http_analyze $host_count /;
use FileHandle;
use Getopt::Std;
getopts('b:dhmnqrv');

use lib "lib";
use Apache::Logmonster::Utility 1; my $utility = Apache::Logmonster::Utility->new();

$|++;

my $header    = "\n\t\t Log Monster $VERSION by Matt Simerson \n\n";
my $debug     = 0; $debug = 1 if $opt_v;
my $quiet     = 0; $quiet = 1 if $opt_q;   # for cron use
my $conf      = $utility->parse_config( {file =>"logmonster.conf"});
check_config ( $conf );

$awstats      = $utility->find_the_bin("awstats.pl", "/usr/local/www/cgi-bin");
unless (-x $awstats) { warn "HEY, I can't find awstats! Consider editing $0 and setting the path to it in the find_the_bin call" };

$webalizer    = $utility->find_the_bin("webalizer");
$http_analyze = $utility->find_the_bin("http-analyze");

my $logdir = get_log_dir($conf->{'logbase'});

report_hits ($logdir) if ($opt_r);
check_flags ();
my $Report = report_open("Logmonster", $logdir);

print $header unless ($quiet); 
print $Report $header;

my ($domains)  = get_domain_list ($conf, $debug);
fetch_log_files      ( $conf );
split_logs_to_vhosts ( $conf, $domains);
check_stats_dir      ( $conf, $domains);
sort_vhost_logs      ( $conf->{'tmpdir'}) unless $opt_n;
feed_the_machine     ( $conf );
report_close         ( $Report, $debug);

exit 1;

##
# Subroutines
##
# ------------------------------------------------------------------------------


sub report_hits($)
{

=head1 report_hits

report_hits reads a days log file and reports the results back to standard out. The logfile contains key/value pairs like so:
	
    matt.simerson:4054
    www.tnpi.biz:15381
    www.nictool.com:895

This file is read by logmonster when called in -r (report) mode
and is expected to be called via an SNMP agent.

=cut

	my ($logdir) = @_;

	my $LogFile = "$logdir/HitsPerVhost.txt";

	print "report_hits: $LogFile \n" if $debug;

	print join(':', $utility->file_read($LogFile) );
	exit 1;
};

sub report_close($;$)
{
	my ($fh, $debug) = @_;
	close($fh);
};

sub report_open($;$)
{

=head1 report_open

In addition to emailing you a copy of the report, Logmonster leaves behind a copy in the log directory.

=cut

	my ($name, $dir) = @_;

	unless ( $dir ) { $dir = $logdir };

	unless ( -w $dir ) 
	{
		print "WARNING: Your report is stored in /tmp because $dir is not writable!\n" unless $quiet;
		$dir = "/tmp";
	};

	my $file = "$dir/$name.txt";
	my $fh   = new FileHandle;
	open($fh, ">$file") or warn "couldn't open $file for write: $!\n";
	print "\n ***  a detailed copy of this report is saved in the file $file   *** \n\n" unless $quiet;
	return $fh;
};

sub check_stats_dir($$)
{

=head1 check_stats_dir

Each domain on your web server is expected to have a "stats" dir. I name mine "stats" and locate in their DocumentRoot, owned by root so that the user doesn't delete it.  This sub first goes through the list of files in (by default) /var/log/apache/tmp/doms, which is a file with the log entries for each vhost. If the file name matches the vhost name, the contents of that log correspond to that vhost.

If the file is zero bytes, it deletes it as there is nothing to do. 

Otherwise, it gathers the vhost name from the file and checks the %domains hash to see if a directory path exists for that vhost. If no hash entry is found or the entry is not a directory, then we declare the hits unmatched and discard them.

For log files with entries, we check inside the docroot for a stats directory. If no stats directory exists, then we discard those entries as well.

=cut

	my ($conf, $domains) = @_;

	foreach my $file ( $utility->get_dir_files( $conf->{'tmpdir'} . "/doms" ) )
	{
		if ( -s $file == 0)
		{
			$utility->file_delete($file) if $clean;
			next;
		};

		use File::Basename;
		my $domain   = fileparse($file);
		my $docroot  = $domains->{$domain}->{'docroot'};
		my $statsdir = $conf->{'statsdir'};

		if ($statsdir =~ /^\// ) {  # fully qualified (starts with /)
			$statsdir = "$statsdir/$domain";
		} else {
			$statsdir = "$docroot/$statsdir";
		};

		print "check_stats_dir: checking for $domain: ($statsdir)\n" if $debug;

		unless ( $statsdir and -d $statsdir ) 
		{
			if ( $conf->{'statsdir_policy'} eq "create" ) {
				print "check_stats_dir: does not exist, creating $statsdir....";
				$utility->chdir_source_dir($statsdir);
				print "done.\n";
			} else {
				warn "WARN: stats dir does not exist for $domain! Discarding logs. ($statsdir)\n" unless $quiet;
				print $Report "WARN: stats dir does not exist for $domain! Discarding logs ($statsdir).\n";
				$utility->file_delete($file) if $clean;
			}
		}
	}
};

sub feed_the_machine($)
{

=head1 feed_the_machine

feed_the_machine takes the sorted vhost logs and feeds them into the stats processor that you chose.

=cut

	my ($vals) = @_;

	my ($cmd, $r);

	my $tmpdir    = $vals->{'tmpdir'};
	my $processor = $vals->{'processor'};

	foreach my $file ( $utility->get_dir_files("$tmpdir/doms") )
	{
		next if ( $file =~ /\.bak$/ );

		use File::Basename;
		my $domain   = fileparse($file);
		my $docroot  = $domains->{$domain}->{'docroot'};
		my $statsdir = $vals->{'statsdir'};

		if ($statsdir =~ /^\// ) {  # fully qualified (starts with /)
			$statsdir = "$statsdir/$domain";
		} else {
			$statsdir = "$docroot/$statsdir";
		};

		unless ( -d $statsdir )
		{
			print "skipping $file because $statsdir is not a directory.\n" unless $quiet;
			next;
		};

		if ( -f "$statsdir/.processor" ) {
			$processor = `head -n1 $statsdir/.processor`;
			chomp $processor;
		} else {
			$processor = $vals->{'processor'};
		};

		if ($processor eq "webalizer") 
		{
			$cmd = "$webalizer -n $domain -o $statsdir $file";
			printf "$webalizer -n %-20s -o $statsdir\n", $domain unless $quiet;
			printf $Report "$webalizer -n %-20s -o $statsdir\n", $domain;
		}
		elsif ($processor eq "http-analyze")
		{
			$cmd = "$http_analyze -S $domain -o $statsdir $file";
			printf "$http_analyze -S %-20s -o $statsdir\n", $domain unless $quiet;
			printf $Report "$http_analyze -S %-20s -o $statsdir\n", $domain;
		}
		elsif ($processor eq "awstats")
		{
			check_awstats_file($domain, $statsdir);

			$cmd = "$awstats -config=$domain -logfile=$file";
			printf "$awstats for \%-20s to $statsdir\n", $domain unless $quiet;
			printf $Report "$awstats for \%-20s to $statsdir\n", $domain;
		}
		else
		{
			print "Sorry, but $processor is not supported!\n";
			print $Report "Sorry, but $processor is not supported!\n";
		};

		unless ( $opt_n )
		{
			print "running $processor!\n" if $debug;
			print $Report "syscmd: $cmd\n" if $debug;
			$r = $utility->syscmd($cmd);
			print $Report "syscmd: error result: $r\n" if ($r != 0);
		}

		if ( -d "$docroot/$vals->{'userlogs'}" )
		{
			my $vlog = "$docroot/$vals->{'userlogs'}/$vals->{'access'}";
			($dd, $mm, $yy, $lm, $hh, $mn) = $utility->get_the_date(1.04);
			unless ( -f $vlog )
			{
				use File::Copy;
				copy($file, "$vlog-$yy-$mm-$dd");
				#copy($file, $vlog);
			}
			else {
				$utility->syscmd("cat $file >> $vlog-$yy-$mm-$dd");
				#$utility->syscmd("cat $file >> $vlog");
			};
		};

		if ( $clean ) 
		{
			$utility->file_delete($file);
		} 
		else 
		{
			print "\nDon't forget about $file\n";
			print $Report "\nDon't forget about $file\n";
		};
	};
};

sub check_awstats_file($$)
{
	my ($domain, $vstatsdir) = @_;

	my $statsdir = "/etc/awstats";
	my $conf     = "$statsdir/awstats.$domain.conf";

	unless ( -d $statsdir ) 
	{
		mkdir( $statsdir, 0755) or warn "Failed to create $statsdir: $!\n";
	};

	unless ( -f "$statsdir/awstats.conf" )
	{
		$utility->get_file("http://www.tnpi.biz/internet/www/logmonster/awstats.conf");
		move("awstats.conf", "$statsdir/awstats.conf") or warn "couldn't install $statsdir/awstats.conf: $!\n";
	}

	unless ( -f $conf )
	{
		my @lines  = 'Include "/etc/awstats/awstats.conf"';
		push @lines, "SiteDomain = $domain";
		push @lines, "DirData = $vstatsdir";
		push @lines, "HostAliases = $domain localhost 127.0.0.1";

		$utility->file_write($conf, @lines);
	}
}

sub sort_vhost_logs($)
{

=head1 sort_vhost_logs

At this point, we'll have collected the Apache logs from each web server and split them up based on which vhost they were served for. However, our stats processors (most of them) require the logs to be sorted in cronological date order. So, we open up each vhosts logs for the day, read them into a hash, sort them based on their log entry date, and then write them back out.

=cut

	my ($dir) = @_;
	my (%beastie, %sortme);

	use Date::Parse;
	use File::Copy;

	chdir( $dir );

	return if ($host_count == 1);   # sorting isn't necessary for only one host

	my $lines = 0;
	foreach my $file ( $utility->get_dir_files("$dir/doms") )
	{
		undef %beastie;    # clear the hash
		undef %sortme;

		if ( -s $file > 10000000 ) 
		{
			print "sort_vhost_logs: logfile $file is greater than 10MB\n" if ($debug);
			print $Report "sort_vhost_logs: logfile $file is greater than 10MB\n";
		};

		unless ( open LOG, $file )
		{
			warn "sort_vhost_logs: WARN: couldn't open $file: $!\n";
			next;
		};

		while (<LOG>)
		{
			chomp;
###
# Per Earl Ruby, switched from / / to /\s+/ so that naughty modules like 
# Apache::Register that insert extra spaces in the Log output won't mess
# up logmonsters parsing.
#			my @data          = split(/ /, $_);
###
#216.220.22.182 - - [16/Jun/2004:09:37:51 -0400] "GET /images/google-g.jpg HTTP/1.1" 200 539 "http://www.tnpi.biz/internet/mail/toaster/" "Mozilla/5.0 (Windows; U; Windows NT 5.0; en-US; rv:1.6) Gecko/20040113" www.thenetworkpeople.biz

			my @data          = split(/\s+/, $_); # split the log entry into fields

# From an Apache log entry, we use split and a regexp to pull out this line:
#   [16/Jun/2004:09:37:51 -0400]

			my $rawdate       = substr("$data[3] $data[4]", 1, 26);

# Then we use substr to extract the middle 26 characters and up with this:
#   16/Jun/2004:09:37:51 -0400
#
# We could also use a regexp to do this but substr is more efficient and we
# can safely expect the date format of ApacheLog to remain constant.

			my $date          = str2time($rawdate);

# then we convert that string to a numeric string that we can use for sorting.

			$beastie{$lines}  = $_;
			$sortme{$lines}   = $date;

# Finally, we put the entire line into the hash beastie (keyed with $lines, an incrementing number) and and create a second hash ($sortme) with the same key but the value is the timestamp. 

			$lines++;
		}; 
		close(LOG) || die "sort_vhost_logs: Gack, couldn't close $file: $!\n";

		move($file, "${file}.bak") or warn "sort_vhost_logs: couldn't move $file to ${file}.bak: $!\n";

# We create an array (because elements in arrays stay in order) of line numbers based on the sortme hash

		my @sorted = sort { ($sortme{$a} <=> $sortme{$b}) || 
			($sortme{$a} cmp $sortme{$b}); } ( keys(%sortme) );

		unless ( open VHOST, ">$file" )
		{
			print "sort_vhost_logs: FAILED: could not open $file: $!\n" if $debug;
		} 
		else 
		{
			foreach (@sorted) {
				# iterate through @sorted, adding the corresponding lines from %beastie to the file
				print VHOST "$beastie{$_}\n";
			};
			close VHOST;
		};

		$utility->file_delete("${file}.bak", $debug) if $clean;
	};
};

sub split_logs_to_vhosts($$)
{

=head1 split_logs_to_vhosts

After collecting the log files from each server in the cluster, we need to split them up based upon the vhost they were intended for. This sub does that.

=cut

	my ($conf, $domains) = @_;
	my (%fhs, %count, %orphans, $bad, $gz);

	my $dir = $conf->{'tmpdir'};
	# normally /var/log/apache/tmp

	use Compress::Zlib;

	my @files = $utility->get_dir_files($dir);

	if ( ! $files[0] or $files[0] eq "" ) 
	{
		print "WARNING: No log files retrieved!\n" if $debug;
		print $Report "WARNING: No log files retrieved!\n";
		return 0;
	};

	unless ( chdir($dir) )
	{
		print $Report "FATAL ERROR: couldn't cd into $dir: $1\n";
		die "couldn't cd into $dir: $!\n";
	};

	unless ( -d "doms" ) 
	{
		unless ( mkdir("doms", 0755) )
		{
			print $Report "FATAL: couldn't create $dir/doms: $!\n";
			die "couldn't create $dir/doms: $!\n";
		};
	};

	my $keys = keys %$domains;

	unless ( $keys )
	{
		print "\nHey, you have no vhosts! You must have at least one!\n";
		print $Report "\nHey, you have no vhosts! You must have at least one!\n";
		die "\n";
	};

	foreach (keys %$domains)
	{
		my $name    = $domains->{$_}->{'name'};
		my $fh      = new FileHandle;    # we create a file handle for each Apache ServerName
		$fhs{$name} = $fh;               # and store it in a hash keyed off the domain name
		print "SplitLogsInfoVhosts: opening doms/$name for $name log entries.\n" if $debug;
		open($fh, "> doms/$name") or warn "WARNING: failed to open doms/$_ for log writing!\n";
	};

	my %domkey = turn_domains_into_sort_key($domains);

	foreach my $file (@files)
	{
		next unless ( -f $file );

		unless ( $gz = gzopen($file, "rb") )
		{
			warn "Couldn't open $file: $gzerrno\n";
			next;
		};

		while ( $gz->gzreadline($_) > 0 ) 
		{
			chomp $_;
			# host, ident, auth, date, request, status, bytes, referer, agent, vhost

# my ($vhost) = $_ =~ / ([a-z-\.]+)$/;
# updated regexp to support numeric vhosts

# regexp should check for logs in these formats:
#
# Apache common (CLF)
# host ident auth date \"request\" status bytes
# $_ =~ /[0-9]{3} [0-9]+$/
#
# standard Apache combined:
# host ident auth date \"request\" status bytes \"referer\"  \"agent\"
# $_ =~ /[0-9]{3} [0-9]+ \".*\" \".*\"$/
#
# logmonster combined:
# host ident auth date \"request\" status bytes \"referer\"  \"agent\" %v
# $_ =~ /[0-9]{3} [0-9]+ \".*\" \".*\" [a-z0-9-.]+$/
#
# When it find a log format other than logmonster's, it should report an
# error and tell the user how to correct it.

			my ($vhost) = $_ =~ / ([0-9a-z-\.]+)$/;
			unless ( $vhost ) 
			{
				# domain names can only have alphanumeric, - and . characters
				# the regexp catches any entries without the vhost appended to them
				# if you have these, read the logmonster FAQ and set up your Apache
				# logs correctly!
				print "HEY!  You have log entried without the vhost tag appended to them! Read the logmonster FAQ and set up your Apache logging correctly.\n" if $debug;
				$bad++;
				next;
			};

			my $main_dom = $domkey{$vhost};

			if ( $main_dom ) 
			{
				my $fh = $fhs{$main_dom};
				print $fh "$_\n";
			}
			else 
			{
				print "split_logs_to_vhosts: the main domain for $vhost is missing!\n" if $debug;
				$orphans{$vhost} = $vhost;
			};
			$count{$vhost}++;
		};
		$gz->gzclose();

		$utility->file_delete($file, 1) if $clean;
	};

	print "\n\t\tSplitToVhost Matched Entries\n\n" unless $quiet;
	print $Report "\n\t\tSplitToVhost Matched Entries\n\n";

	my $HitLog = report_open("HitsPerVhost") if $countlog;

	foreach my $key (keys %fhs)
	{
		close($fhs{$key});

		if ( $count{$key} ) 
		{
			printf "         %15.0f lines to %s\n", $count{$key}, $key unless $quiet;
			printf $Report "         %15.0f lines to %s\n", $count{$key}, $key;
			print $HitLog  "$key:$count{$key}\n" if $countlog;
		};
	};
	report_close($HitLog, $debug) if $countlog;

	print "\n" unless $quiet;
	print $Report "\n";

	foreach my $key (keys %orphans)
	{
		if ( $count{$key} ) 
		{
			printf "Orphans: %15.0f lines to %s\n", $count{$key}, $key unless $quiet;
			printf $Report "Orphans: %15.0f lines to %s\n", $count{$key}, $key;
		};
	};

	if ($bad)
	{
		printf "Skipped: %15.0f lines to unknown.\n", $bad unless $quiet;
		printf $Report "Skipped: %15.0f lines to unknown.\n", $bad;
		print "\nPlease read the FAQ (logging section) to see why records get skipped.\n\n" unless $quiet;
		print $Report "\nPlease read the FAQ (logging section) to see why records get skipped.\n\n";
	};
};

sub turn_domains_into_sort_key($)
{
	my ($domains) = @_;
	my %sorted;

	foreach ( keys %$domains ) 
	{
		print "turn_domains_into_sort_key: \t" if $debug;
		my @vals = split(/:/, $domains->{$_}->{'domlist'});

		my $master = shift(@vals);
		print "master: $master\t" if $debug;

		$sorted{$master} = $master;
		foreach my $slave (@vals)
		{
			print "slave: $slave " if $debug;
			$sorted{$slave} = $master;
		};
		print "\n" if $debug;
	};
	return %sorted;
};

sub get_domain_list($;$)
{
	my ($vals, $debug) = @_;
	my (%domains);

	my $vconfig = $vals->{'vhost'};

	if ( -d $vconfig )
	{
		print "get_domain_list: $vconfig is a directory.\n" if $debug;
		print $Report "get_domain_list: $vconfig is a directory.\n";
		my @files = $utility->get_dir_files($vconfig);
		if ( ! $files[0] or $files[0] eq "" ) 
		{
			print "get_domain_list: no files!\n";
			print $Report "get_domain_list: no files!\n";
			return 0;
		};

		foreach my $file ( @files ) 
		{
			next if $file =~ /~$/;     # ignore vim's backup files
			next if $file =~ /.bak$/;  # ignore .bak files
			my ($vhosts) = get_virtual_domains_from_file($file, $debug);

			foreach ( keys %$vhosts ) 
			{
				print "vhost name: $vhosts->{$_}->{'name'}\n" if $debug;
				$domains{$vhosts->{$_}->{'name'}} = $vhosts->{$_};
			};
		};

		return \%domains;
	} 
	elsif ( -f $vconfig ) 
	{
		my ($vhosts) = get_virtual_domains_from_file($vconfig, $debug);
		return $vhosts;
	} 
	else
	{
		print "$vconfig is not a file or directory!\n";
		print $Report "$vconfig is not a file or directory!\n";
	};
};

sub get_virtual_domains_from_file($;$)
{
	my ($file, $debug) = @_;

	my (%vhosts, $vhost);
	my $in = 0;
	my $count = 0;

	print "\nGetVirtualDomains: retrieving from $file\n" if $debug;
	print $Report "GetVirtualDomains: retrieving from $file...";

	LINE: foreach my $line ( $utility->file_read($file) )
	{
		my $lline = lc($line);
		#print "parsing: $lline\n" if $debug;

		unless ( $in ) 
		{
			if ( $lline=~/^[\s+]?<virtualhost/ ) 
			{
				$in = 1;
				$count++;
				print "\n\topening: $lline\n" if $debug;
			};
			next LINE;
		}

		if ( $lline =~ /^[\s+]?<\/virtualhost/ )  
		{
			print "invalid closing vhost tag in file $file!\n" unless ($vhost);
			print "\tclosing: $lline\n" if $debug;
			undef $vhost;
			$in = 0;
			next LINE;
		} 

		if ($lline =~ /servername/)
		{
			# we need to strip off any trailing port values(:80)  (thanks Raymond Dujkxhoorn)

			# parse this type of line: "  ServerName  foo.com:80  ";
			# regexp explanation:
			#    \b - word boundary
			#    \bservername\b grabs any leading spaces, the word servername, and any trailing spaces
			#    (.*?) grabs any characters (non greedy)
			#    (:\d+)? grabs any optional instance of numeric digits preceded by a :
			#    (\s+)?$ grabs zero or more white space characters immediately before the end of the line

			my ($servername) = $lline =~ /([a-z0-9-\.]+)(:\d+)?(\s+)?$/;
			$vhost = $servername;
			print "\t\tservername: $servername.\n" if $debug;
			$vhosts{$count}{'name'} = $servername;
			#$vhosts{$vhost}{'name'} = $servername;
		}
		elsif ($lline =~ /serveralias/)
		{
			if ($lline =~ /\s+serveralias/) { ($lline) = $lline =~ /\s+(.*)/ };
			my @val = split(/\s+/, $lline);
			shift @val;                       # get rid of serveralias
			my $aliases = join(":", @val);    # pack them together with :'s in a string
			print "\t\taliases are: $aliases\n" if $debug;
			$vhosts{$count}{'aliases'} = $aliases;
			#$vhosts{$vhost}{'aliases'} = $aliases;
		} 
		elsif ($lline =~ /documentroot/)
		{
			my ($docroot) = $lline =~ /documentroot[\s+]["]?(.*?)["]?[\s+]?$/;
			print "\t\tdocroot: $docroot\n" if $debug;
			$vhosts{$count}{'docroot'} = $docroot;
			#$vhosts{$vhost}{'docroot'} = $docroot;
		} 
		else {
			#print "unknown: $line\n" if $debug;
		};
	};

	# create the domlist hash if necessary
	foreach ( keys %vhosts )
	{
		# is there domain aliases?
		if ( $vhosts{$_}->{'aliases'} ) {
			$vhosts{$_}{'domlist'} = "$vhosts{$_}{'name'}:$vhosts{$_}{'aliases'}";
		} else {
			$vhosts{$_}{'domlist'} = $vhosts{$_}{'name'};
		};
	}

	# convert the hash keys from an incrementing number to the hashes domain name
	my %tmp;
	foreach ( keys %vhosts )
	{
		my $vhost_name = $vhosts{$_}{'name'};
		$tmp{$vhost_name} = $vhosts{$_};
	}

	print $Report "done\n";
	return \%tmp;
};

sub fetch_log_files($)
{
	my ($vals) = @_;
	my ($r);

	my $scp     = $utility->find_the_bin("scp"); $scp .= " -q";
	my $ssh     = $utility->find_the_bin("ssh");
	my $gzip    = $utility->find_the_bin("gzip");
	my $gunzip  = $utility->find_the_bin("gunzip");

	my $tmpdir   = $vals->{'tmpdir'};
	my @hosts    = split(/ /, $vals->{'hosts'}); $host_count = @hosts;
	my $logfile  = "$logdir/$conf->{'access'}";
	my $errlog   = "$logdir/$conf->{'error'}";

	if ( -w $tmpdir && -r $tmpdir ) 
	{
		$utility->clean_tmp_dir($tmpdir);
	} 
	else 
	{
		die "FATAL: \$tmpdir ($tmpdir) must be read and writable!\n";
	};
	
	foreach my $host (@hosts) 
	{
		my $llog = "$tmpdir/$host-$conf->{'access'}";

		unless ( $opt_n )
		{
			# compress yesterdays log files
			if ($host eq "localhost")
			{
				if ( -e $logfile ) {
					print "gzipping $logfile\n" unless $quiet;
					print $Report "syscmd: $gzip $logfile\n";
					$r = $utility->syscmd("$gzip $logfile");
					print $Report "syscmd: error result: $r\n" if ($r != 0);
				} else {
					print $Report "fetch_log_files: $logfile does not exist! (already compressed?)\n" unless $quiet;
				};

				print "gzipping $errlog\n" if $debug;
				print $Report "syscmd: $gzip $errlog\n";

				if ( -e $errlog ) {
					$r = $utility->syscmd("$gzip $errlog");
					print $Report "syscmd: error result: $r\n" if ($r != 0);
				} else {
					print $Report "fetch_log_files: $errlog does not exist! (already compressed?)\n";
				};
			}
			else
			{
				print "checking for $logfile on $host..." unless $quiet;
				$r = system "$ssh $host test -f $logfile";
				unless ($quiet) { $r ? print "no.\n" : print "yes..."; };
				unless ($r) {
					print "gzipping.\n" unless $quiet;
					print $Report "syscmd: $ssh $host $gzip $logfile\n";
					$r = $utility->syscmd("$ssh $host $gzip $logfile");
					print $Report "syscmd: error result: $r\n" if ($r != 0);
				};

				print "checking for $errlog on $host..." unless $quiet;
				$r = system "$ssh $host test -f $errlog";
				unless ($quiet) { $r ? print "no.\n" : print "yes..."; };
				unless ($r) {
					print "gzipping.\n" unless $quiet;
					print $Report "syscmd: $ssh $host $gzip $errlog\n";
					$r = $utility->syscmd("$ssh $host $gzip $errlog") if ( ! $opt_n );
					print $Report "syscmd: error result: $r\n" if ($r != 0);
				};
			};
		}

		# retrieve yesterdays log files
		if ($host eq "localhost")
		{
			use File::Copy;
			print "fetching ${logfile}.gz\n" if $debug;
			print $Report "fetch_log_files copy: ${logfile}.gz ${llog}.gz\n";
			$r = copy("${logfile}.gz", "${llog}.gz");
			print $Report "fetch_log_files copy FAILED: $!\n" unless ($r);

			my $size = (stat("$llog.gz"))[7];
			print "fetch_log_files: $size KB retrieved from $host\n" unless $quiet;
			print $Report "fetch_log_files: $size KB retrieved from $host\n";
		}
		else
		{
			print "fetching ${logfile}.gz from $host\n" unless $quiet;
			print $Report "syscmd: $scp $host:${logfile}.gz ${llog}.gz\n";
			$r = $utility->syscmd("$scp $host:${logfile}.gz ${llog}.gz");
			print $Report "syscmd: error result: $r\n" if ($r != 0);

			my $size = (stat("$llog.gz"))[7];
			print "fetch_log_files: $size KB retrieved from $host\n" if $debug;
			print $Report "fetch_log_files: $size KB retrieved from $host\n";
		};
	};
};

sub get_log_dir($)
{
	my ($logbase) = @_;
	my ($dd, $mm, $yy, $lm, $hh, $mn, $logdir);

	if ($opt_b) 
	{
		($dd, $mm, $yy, $lm, $hh, $mn) = $utility->get_the_date($opt_b + 1.04);

		unless ( $utility->yes_or_no("\nDoes the date $yy/$mm/$dd look correct? ") ) 
		{
			die "OK then, try again.\n"; 
		};
	}
	else 
	{
		($dd, $mm, $yy, $lm, $hh, $mn) = $utility->get_the_date(1.04);
	};	

	print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;

	if    ( $opt_h)  { $logdir  = "$conf->{'logbase'}/$yy/$mm/$dd/$hh"    } 
	elsif ( $opt_d ) { $logdir  = "$conf->{'logbase'}/$yy/$mm/$dd"        } 
	elsif ( $opt_m ) { $logdir  = "$conf->{'logbase'}/$yy/$mm"            }
	else             { $logdir  = "$conf->{'logbase'}"                    };

	print "get_log_dir: returning $logdir\n" if $debug;
	return $logdir;
};

sub check_config($)
{
	my ($vals) = @_;

	my $config = "/usr/local/etc/logmonster.conf";

	die "\nFATAL: You are missing $config, please install it!\n\n" unless ($vals);

	$clean    = 1 if ( $conf->{'clean'} );
	$countlog = 1 if ( $conf->{'CountLog'} );

	if ( $clean ) 
	{
		print "check_config: Clean is disabled.\n" if $debug ;
	};

	my $tmpdir = $vals->{'tmpdir'};

	no_dir_err($conf->{'logbase'}, $config) unless ( -d $conf->{'logbase'});

	unless ( -d $tmpdir )
	{
		mkdir($tmpdir, 0755) or no_dir_err($tmpdir, $config);
		$utility->syscmd("chown www:www $tmpdir");
	};
	
	unless ( -e $conf->{'vhost'} ) 
	{
		die "\nFATAL: you must edit $config and set vhost!\n\n";
	};

	print "check_config: All preliminary tests pass.\n" if $debug;	

	sub no_dir_err
	{
		my ($dir, $config) = @_;
		die "FATAL: The directory $dir does not exist and I could not create it. Edit $config or create it.\n";
	};
};

sub check_flags()
{
	if ( $opt_q && $conf->{'processor'} eq "webalizer" ) 
	{ 
		$webalizer .= " -q"; 
	};

	if ( $opt_d or $opt_h )
	{
		if    ( $conf->{'processor'} eq "webalizer"    ) { $webalizer    .= " -p"; }
		elsif ( $conf->{'processor'} eq "http-analyze" ) { $http_analyze .= " -d"; };
	} 
	elsif ( $opt_m ) 
	{
		if    ( $conf->{'processor'} eq "http-analyze" ) { $http_analyze .= " -m"; };
	}
	else 
	{
		print $header;
		die "Usage: $0 interval [-q] [-b <num>] [-a <num>]

      Interval is one of:

         -h    Hourly     (last hour)
         -d    Daily      (yesterday)
         -m    Monthly    (last month)

      Optional:

         -q    Quiet      (nice and quiet, for cron use)
         -v    Verbose    (lots of debugging output)
         -n    Dry run    (do everything except feed the logs into the processor)

         -b x  Back x days (use with -d to process logs older than one day)

         -r    Report last periods hit counts
\n";
	};
#         -a x  Archive     (keep x months worth of logs)

	print "check_flags: Passed all tests.\n" if $debug;
};

__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

Support for analog.

Support for individual webalizer.conf file for each domain

Delete log files older than X days/month

Do something with error logs (other than just compress)

If files to process are larger than 10MB, find a nicer way to sort them rather than reading them all into a hash. Now I create two hashes, one with data and one with dates. I sort the date hash, and using those sorted hash keys, output the data hash to a sorted file. This is necessary as wusage and http-analyze require logs to be fed in chronological order. Take a look at awstats logresolvemerge as a possibility.


=head1 SEE ALSO

http://www.tnpi.biz/internet/www/logmonster


=head1 COPYRIGHT

Copyright (c) 2003-2004, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DIS CLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
