#!perl
use strict;
use warnings;

package Apache::Logmonster;

use lib "inc";
use lib "lib";

use Carp;
use Compress::Zlib;
use Cwd;
use Date::Parse;
use FileHandle;
use File::Basename;
use File::Copy;
use Regexp::Log;
use Regexp::Log::Monster;

use vars qw($VERSION $err);

$VERSION  = '3.05';

use Apache::Logmonster::Utility; 
my $utility = Apache::Logmonster::Utility->new();

sub new {
    my $class = shift;
    my $conf  = shift;
    my $debug = shift;

    unless ( $conf && $utility->is_hashref($conf) ) {
        croak "new: method called incorrectly, please see perldoc Apache::Logmonster for propery invocation";
    };

    my $self = { 
        name  => $class,
        conf  => $conf,
        debug => $debug || 0,
    };
    bless( $self, $class );
    return $self;
}

sub check_awstats_file {

    my $self = shift;
	my ($domain, $vstatsdir) = @_;

	my $statsdir = "/etc/awstats";

	unless ( -d $statsdir ) 
	{
		mkdir( $statsdir, oct('0755') ) or carp "Failed to create $statsdir: $!\n";
	};

	unless ( -f "$statsdir/awstats.conf" )
	{
        $self->install_default_awstats_conf;
	}

	my $awstats_dot_conf = "$statsdir/awstats.$domain.conf";

	unless ( -f $awstats_dot_conf )
	{
		$utility->file_write(
            file  => $awstats_dot_conf,
            lines => [ <<"EO_AWSTATS_VHOST"
Include "/etc/awstats/awstats.conf"
SiteDomain = $domain
DirData = $vstatsdir
HostAliases = $domain localhost 127.0.0.1
EO_AWSTATS_VHOST
],
            debug => 0,
        );
	}
}

sub check_config {

    my $self  = shift;
    my $debug = $self->{'debug'};
    my $conf  = $self->{'conf'};

    $err = "check_config: performing basic sanity tests";
    $utility->_progress_begin($err) if $debug;

    print "\n\t verbose mode $debug\n" if $debug>1;

    if ( ! $conf || ! $utility->is_hashref($conf) ) {
        croak "value passed as \$conf is invalid.\n";
    } else {
        print "\t \$conf hashref validated.\n" if $debug>1;
    };

    if ( $debug > 1 ) {
        print "\t clean mode ";
        $conf->{'clean'} ? print "enabled.\n" : print "disabled.\n";
	};

    # this may be invalid if localhost is not a webserver
#    my $logbase = $conf->{'logbase'};
#    unless ( $logbase && -d $logbase ) {
#        no_dir_err($logbase);
#    };

	my $tmpdir = $conf->{'tmpdir'};
    print "\t temporary working directory is $tmpdir.\n" if $debug>1;

	unless ( -d $tmpdir )
	{
        print "\t temp dir does not existing, creating..." if $debug>1;
		if ( ! mkdir $tmpdir, oct('0755') ) {
            die "FATAL: The directory $tmpdir does not exist and I could not "
                . "create it. Edit logmonster.conf or create it.\n";
        };
        print "done.\n" if $debug>1;

        # this will fail unless we're root, but that should not matter much
        print "\t setting permissions on temp dir..." if $debug>1;
        $utility->file_chown(
            file_or_dir => $tmpdir,
            uid         => $conf->{'log_user'} || "www",
            gid         => $conf->{'log_group'} || "www",
            debug       => $debug>1 ? 1 : 0,
            fatal       => 0,
        );
        print "done.\n" if $debug>1;
	};
	
	if ( ! -w $tmpdir || ! -r $tmpdir ) {
		die "FATAL: \$tmpdir ($tmpdir) must be read and writable!";
    };

    if ( $conf->{'clean'} ) {
		if ( ! $utility->clean_tmp_dir(dir=>$tmpdir,debug=>0) ) {
            croak "\nfailed to clean out $tmpdir";
        };
	} 

	if ( ! defined $conf->{'vhost'} ) 
	{
		die "\nFATAL: you must edit logmonster.conf and set vhost!\n";
	};

    if ( $conf->{'time_offset'} ) {
        my ($dd, $mm, $yy, $lm, $hh, $mn) = 
            $utility->get_the_date( debug  => 0, ); 

        my $interval = $self->{'rotation_interval'} || "day";
        my $bump     = $conf->{'time_offset'};
        my $logbase  = $conf->{'logbase'};

        my $how_far_back = $interval eq "hour"  ? .04   # back 1 hour
                        : $interval eq "month" ? $dd+1 # last month
                        : 1;  # 1 day

        ($dd, $mm, $yy, $lm, $hh, $mn) = 
            $utility->get_the_date( bump=>$bump + $how_far_back, debug  => 0, ); 

        unless ( $utility->yes_or_no(question=>"\nDoes the date $yy/$mm/$dd look correct? ") )
        {
            die "OK then, try again.\n";
        };
    };

    $utility->_progress_end("passed") if $debug==1;

    return 1;
};

sub check_stats_dir {

############################################
# Usage      : see t/Logmonster.t for working example
# Purpose    : determine if the vhost "stats" dir exists. If not, discard the
#              vhost logs as we have nowhere to output their results.
# Returns    : boolean, one for success
# Parameters : domains - a hashref of domains and their attributes,
#                 specifically their DocumentRoot.

    my $self        = shift;
    my $domains_ref = shift;
    my $debug       = $self->{'debug'};
    my $conf        = $self->{'conf'};
    my $REPORT      = $self->{'report'};

    unless ( $conf ) {
        croak "check_stats_dir: \$conf is not set!";
    };

    unless ( $domains_ref && $utility->is_hashref($domains_ref) ) {
        croak "check_stats_dir: passed invalid argument!";
    };

    # defaults to clean mode
    my $clean = $conf->{'clean'} || 1;

    my $temp_dir = $conf->{'tmpdir'} || "/var/tmp";
    $temp_dir .= "/doms";

    unless ( -d $temp_dir ) {
        warn "check_stats_dir: dir ($temp_dir) not found!\n";
        return;
    };

    if ($debug) {
        print "check_stats_dir: using temp dir: $temp_dir.\n";
        print "    checking each domains stats dir...\n";
    };
    
	foreach my $file ( $utility->get_dir_files( dir=> $temp_dir ) )
	{
		if ( -s $file == 0)
		{
			$utility->file_delete(file=>$file,debug=>0) if $clean;
			next;
		};

		my $domain   = fileparse($file);
		my $statsdir = $conf->{'statsdir'};

		if ($statsdir =~ m{ \A / }xms ) {  # fully qualified (starts with /)
			$statsdir = "$statsdir/$domain";
		} 
        else {
		    my $docroot  = $domains_ref->{$domain}->{'docroot'};
            if ( !$docroot ) {
                print "     DOCROOT for $domain undeclared!\n";
                next;
            };
			$statsdir = "$docroot/$statsdir";
		};

		if ( ! $statsdir or ! -d $statsdir ) 
		{
			if ( $conf->{'statsdir_policy'} eq "creating" ) {
                my $old_working_directory = cwd;
				$utility->chdir_source_dir(dir=>$statsdir,debug=>0);
                chdir($old_working_directory);
                if ($debug) {
                    printf "      %-45s...created.", $statsdir;
                };
			} 
            else {
                $err = "MISSING. Discarding logs.\n";
                if ($debug) {
                    printf "      %-45s...$err", $statsdir;
                };
				print $REPORT $err . "\n";
				$utility->file_delete(file=>$file,debug=>0) if $clean;
			}
		}
	}

    return 1;
};

sub compress_log_file {
    my $self = shift;
    my $host = shift;
    my $logfile = shift;

    my $debug = $self->{'debug'};

    unless ( $host && $logfile ) {
        croak "compress_log_file: called incorrectly!";
    };

    my $REPORT = $self->{'report'};

    if ($host eq "localhost")
    {
	    my $gzip = $utility->find_the_bin(bin=>"gzip",debug=>0);

        if ( ! -e $logfile ) {
            print $REPORT "compress_log_file: $logfile does not exist!\n";
            if ( -e "$logfile.gz" ) {
                print $REPORT "     already compressed as $logfile.gz!\n";
                return 1;
            };
            return;
        };

        my $cmd = "$gzip $logfile";
        $utility->_progress("gzipping localhost:$logfile") if $debug;
        print $REPORT "syscmd: $cmd\n";
        my $r = $utility->syscmd(cmd=>$cmd,debug=>0);
        print $REPORT "syscmd: error result: $r\n" if ($r != 0);

        return 1;
    };

    $utility->_progress_begin("checking $host for $logfile") if $debug;

    # $host is remote, so we interact via SSH
	my $ssh = $utility->find_the_bin(bin=>"ssh",debug=>0);
    my $cmd = "$ssh $host test -f $logfile";

    print $REPORT "compress_log_file: checking $host\n";
    print $REPORT "\tsyscmd: $cmd\n";

    $utility->_progress_continue() if $debug;

    # does the file exist?
    if ( ! $utility->syscmd(cmd=>$cmd,debug=>0,fatal=>0)  ) 
    {
        $utility->_progress_continue() if $debug;
        
        # does file.gz exist?
        if ( $utility->syscmd(cmd=>"$cmd.gz",debug=>0,fatal=>0) ) 
        {
            $err = "ALREADY COMPRESSED"; print $REPORT "\t$err\n"; 

            $utility->_progress_end($err) if $debug;

            return 1;
        };
        $utility->_progress_end("no") if $debug;

        print $REPORT "no\n"; 
        return;
    }

    $utility->_progress_end("yes") if $debug;

    print $REPORT "yes\n";

    $err = "compressing log file on $host";
    $utility->_progress_begin($err) if $debug;

    $cmd = "$ssh $host gzip $logfile";
    print $REPORT "\tcompressing\n\tsyscmd: $cmd \n";

    $utility->_progress_continue() if !$debug;

    my $r = $utility->syscmd(cmd=>$cmd,debug=>0,fatal=>0);
    if ( ! $r ) {
        print $REPORT "\terror result: $r\n";
        return;
    };
    $debug ? print "done\n"
           : $utility->_progress_end();

    return 1;
};

sub consolidate_logfile {

    my $self = shift;
    my $host = shift;
    my $remote_logfile = shift;
    my $local_logfile  = shift;

    my $dry_run = $self->{'dry_run'};
    my $debug   = $self->{'debug'};
    my $REPORT  = $self->{'report'};

    my ($r, $size);

    # retrieve yesterdays log files
    if ($host eq "localhost")
    {
        $err = "consolidate_logfile: checking localhost for\n\t $remote_logfile...";
        $utility->_progress_begin($err) if $debug; 
        print $REPORT $err;

        # requires "use File::Copy"
        $r = copy $remote_logfile, $local_logfile;
        print $REPORT "FAILED: $!\n" unless ($r);

        $size = (stat $local_logfile )[7];

        if ($size > 1000000) { $size = sprintf "%.2f MB", $size / 1000000; } 
        else                 { $size = sprintf "%.2f KB", $size / 1000;    };

        $err = "retrieved $size\n";
        $utility->_progress_end($err) if $debug;
        print $REPORT $err;
        return 1;
    }

	return 1 if $dry_run;

	my $scp = $utility->find_the_bin(bin=>"scp",debug=>0); 
    $scp .= " -q";

    $utility->_progress_begin( "\tconsolidate_logfile: fetching") if $debug;

    print $REPORT "\tsyscmd: $scp \n\t\t$host:$remote_logfile \n\t\t$local_logfile\n";

    $r = $utility->syscmd(cmd=>"$scp $host:$remote_logfile $local_logfile",debug=>0);
    print $REPORT "syscmd: error result: $r\n" if !$r;

    $size = (stat $local_logfile)[7];
    if ( ! $size ) {
        $err = "FAILED. No logfiles retrieved!";
        $utility->_progress_end($err) if $debug;
        print $REPORT "\t $err \n";
        return;
    };

    if ($size > 1000000) { $size = sprintf "%.2f MB", $size / 1000000; } 
    else                 { $size = sprintf "%.2f KB", $size / 1000;    };

    $err = "retrieved $size";
    $utility->_progress_end($err) if $debug;
    print $REPORT "\t $err\n";

    return 1;
};

sub feed_the_machine {

    my $self        = shift;
    my $domains_ref = shift;

    if ( ! $domains_ref or !$utility->is_hashref($domains_ref) ) {
        croak "feed_the_machine: invalid parameters passed.";
    };

    my $debug       = $self->{'debug'};
    my $conf        = $self->{'conf'};
    my $REPORT      = $self->{'report'};
    my $interval    = $self->{'rotation_interval'};

	my ($cmd, $r);

	my $tmpdir    = $conf->{'tmpdir'};
	my $processor = $conf->{'processor'};

	foreach my $file ( $utility->get_dir_files(dir=>"$tmpdir/doms") )
	{
		next if ( $file =~ /\.bak$/ );

		use File::Basename;
		my $domain   = fileparse($file);
		my $statsdir = $conf->{'statsdir'};
		my $docroot  = $domains_ref->{$domain}->{'docroot'};

		if ($statsdir =~ /^\// ) {  # fully qualified (starts with /)
			$statsdir = "$statsdir/$domain";
		} else {
            if ( ! $docroot ) {
                print "     feed_the_machine: docroot not defined for $domain."
                    ." Cannot generate web stats!\n";
                next;
            };
			$statsdir = "$docroot/$statsdir";
		};

		unless ( -d $statsdir )
		{
			print "skipping $file because $statsdir is not a directory.\n" if $debug;
			next;
		};

        # allow domain to select their stats processor
		if ( -f "$statsdir/.processor" ) {
			$processor = `head -n1 $statsdir/.processor`;
			chomp $processor;
		};

		if ($processor eq "webalizer") 
		{
            my $webalizer = $utility->find_the_bin(bin=>"webalizer",debug=>0);
            $webalizer .= " -q" if !$debug;
            $webalizer .= " -p" if ($interval eq "hour" || $interval eq "day");
			$cmd = "$webalizer -n $domain -o $statsdir $file";
			printf "$webalizer -n %-20s -o $statsdir\n", $domain if $debug;
			printf $REPORT "$webalizer -n %-20s -o $statsdir\n", $domain;
		}
		elsif ($processor eq "http-analyze")
		{
            my $http_analyze = $utility->find_the_bin(bin=>"http-analyze",debug=>0);
            $http_analyze .= " -d" if ($interval eq "hour" || $interval eq "day");
            $http_analyze .= " -m" if ($interval eq "month");
			$cmd = "$http_analyze -S $domain -o $statsdir $file";
			printf "$http_analyze -S %-20s -o $statsdir\n", $domain if $debug;
			printf $REPORT "$http_analyze -S %-20s -o $statsdir\n", $domain;
		}
		elsif ($processor eq "awstats")
		{
			$self->check_awstats_file($domain, $statsdir);

            my $aws_cgi = "/usr/local/www/awstats/cgi-bin";  # freebsd port installs here
            $aws_cgi = "/usr/local/www/cgi-bin" unless ( -d $aws_cgi );
            $aws_cgi = "/var/www/cgi-bin" unless ( -d $aws_cgi );

            my $awstats = $utility->find_the_bin(
                bin =>"awstats.pl",  debug => 0, dir => $aws_cgi, );
			$cmd = "$awstats -config=$domain -logfile=$file";
			printf "$awstats for \%-20s to $statsdir\n", $domain if $debug;
			printf $REPORT "$awstats for \%-20s to $statsdir\n", $domain;
		}
		else
		{
            $err = "Sorry, but $processor is not supported! Valid options are: webalizer, http-analyze, and awstats.\n";
			print $err;
			print $REPORT $err;
		};

		unless ( $self->{'dry_run'} )
		{
			print "running $processor!\n" if $debug;
			print $REPORT "syscmd: $cmd\n" if $debug;
			$r = $utility->syscmd(cmd=>$cmd,debug=>0);
			print $REPORT "syscmd: error result: $r\n" if ($r != 0);
		}

		if ( -d "$docroot/$conf->{'userlogs'}" )
		{
			my $vlog = "$docroot/$conf->{'userlogs'}/$conf->{'access'}";

            my $bump = $conf->{'time_offset'} || 0;
			my ($dd, $mm, $yy, $lm, $hh, $mn) 
                = $utility->get_the_date(bump=>$bump,debug=>0);

			unless ( -f $vlog )
			{
				use File::Copy;
				copy($file, "$vlog-$yy-$mm-$dd");
				#copy($file, $vlog);
			}
			else {
				$utility->syscmd(cmd=>"cat $file >> $vlog-$yy-$mm-$dd",debug=>0);
				#$utility->syscmd(cmd=>"cat $file >> $vlog");
			};
		};

		if ( $conf->{'clean'} ) 
		{
			$utility->file_delete(file=>$file,debug=>0);
		} 
		else 
		{
			print "\nDon't forget about $file\n";
			print $REPORT "\nDon't forget about $file\n";
		};
	};
};

sub fetch_log_files {

    my $self    = shift;
    my $debug   = $self->{'debug'};
    my $conf    = $self->{'conf'};
    my $dry_run = $self->{'dry_run'};

	my $r;

    # in a format like this: /var/log/apache/200?/09/25
    my $logdir = $self->get_log_dir(); 
    my $tmpdir = $conf->{'tmpdir'};

	my $access_log  = "$logdir/" . $conf->{'access'};
	my $error_log   = "$logdir/" . $conf->{'error'};
	
    print "fetch_log_files: warming up.\n" if $debug>1;

    WEBHOST:
	foreach my $webserver ( split(/ /, $conf->{'hosts'}) ) 
	{
        my $compressed = 0;

		if ( ! $dry_run )
		{
			# compress yesterdays log files
            $self->compress_log_file($webserver, $error_log);

            if ( ! $self->compress_log_file($webserver, $access_log) ) {
                # if there is no compressed logfile, there is no point in
                # trying to retrieve.
                next WEBHOST;
            };
        };

		my $local_logfile = "$tmpdir/$webserver-" . $conf->{'access'} . ".gz";

        $self->consolidate_logfile(
            $webserver,        # hostname to retrieve from
            "$access_log.gz",  # the logfile to fetch
            $local_logfile,    # where to put it
        );
	};

    return 1;
};

sub get_domains_list {

    my $self   = shift;
    my $debug  = $self->{'debug'};
    my $conf   = $self->{'conf'};
    my $REPORT = $self->{'report'};

	my (%domains, $vhosts_ref, $count);

    $err = "get_domains_list: fetching list of virtual hosts";
    $utility->_progress_begin($err) if $debug;

	my $vconfig = $conf->{'vhost'};

    # keyword test
    if ( $vconfig =~ /<SITE>/ ) {
        return $self->get_domains_list_from_directories();
    };

    # the Apache vhosts are in a file (usually httpd.conf)
	if ( -f $vconfig ) 
	{
        $err = "vhosts are in $vconfig.\n";
        print $REPORT $err;
        print "\n\t$err" if $debug>1; 

        $vhosts_ref = $self->get_vhosts_from_file($vconfig, $debug);

        $count = keys %$vhosts_ref;
        $utility->_progress_end("$count found.") if $debug;

		return $vhosts_ref;
	};

    $err = "$vconfig is a directory.\n";
    print "\n\t$err" if $debug>1; 
    print $REPORT $err if $REPORT;

    # the Apache vhosts are in a directory
	if ( -d $vconfig )
	{
		my @files = $utility->get_dir_files(dir=>$vconfig);

		if ( ! $files[0] or $files[0] eq "" ) {
            $err = "get_domains_list: no files!\n";
			print $err; print $REPORT $err;
			return;
		};

		foreach my $file ( @files ) 
		{
            $utility->_progress_continue() if $debug==1;

			next if $file =~ /~$/;     # ignore vim's backup files
			next if $file =~ /.bak$/;  # ignore .bak files

			$vhosts_ref = $self->get_vhosts_from_file($file, $debug);
            $count += keys %$vhosts_ref;

			foreach ( keys %$vhosts_ref ) 
			{
				print "\t\tvhost name: $vhosts_ref->{$_}->{'name'}\n" if $debug > 3;
				$domains{$vhosts_ref->{$_}->{'name'}} = $vhosts_ref->{$_};
			};
		};

        $utility->_progress_end("$count found.") if $debug;

		return \%domains;
	} 

    print "$vconfig is not a file or directory!\n";
    print $REPORT "$vconfig is not a file or directory!\n";

    return;
};

sub get_domains_list_from_directories {
    my $self = shift;

    my $debug   = $self->{'debug'};
    my $conf    = $self->{'conf'};
	my $vconfig = $conf->{'vhost'};

    my (%domains, @symlink_dirs);
    print "\nAuto-detecting vhosts from domain directories.\n";

    my ($prefix, $suffix) = $vconfig =~ /(.*)<SITE>(.*)/g;

    my @dirs_found = `ls -d $prefix*$suffix`;
    chomp @dirs_found;
    DIR: foreach my $raw_dir ( @dirs_found ) {

        my ($vhost_name) = $raw_dir =~ /$prefix(.*)$suffix/;

        # if a symlink, then assume a vhost alias, process later
        if ( -l "$prefix/$vhost_name"  ) {
            push @symlink_dirs, $raw_dir;
            next DIR;
        };

        # set up the hash values we need later
        $domains{$vhost_name} = { 
            'name'    => $vhost_name, 
            'docroot' => $prefix.$vhost_name.$suffix,
            'domlist' => $vhost_name,
        };
    };

    # now deal with those vhost aliases
    foreach ( @symlink_dirs ) {
        my ($vhost_name) = $_ =~ /$prefix(.*)$suffix/;

        my $symlink_target = readlink "$prefix/$vhost_name";

        # if the target of the symlink has been added to our list...
        if ( defined $domains{$symlink_target}->{'domlist'} ) {
            # add our hostname to the domlist
            $domains{$symlink_target}{'domlist'} .= ":$vhost_name";

            # and add ourself to the aliases list
            if ( defined $domains{$symlink_target}->{'aliases'} ) {
                $domains{$symlink_target}{'aliases'} .= ":$vhost_name";
            } else {
                $domains{$symlink_target}{'aliases'} = $vhost_name;
            };
        } else {
            # the target doesn't exist, so we are the "main" domain.
            $domains{$vhost_name} = { 
                'name'    => $vhost_name, 
                'docroot' => $prefix.$vhost_name.$suffix,
                'domlist' => $vhost_name,
            };
        };
    };

#    use Data::Dumper;
#    warn Dumper %domains;
    return \%domains;
};

sub get_vhosts_from_file {

    my $self = shift;
	my $file = shift;

    $file || croak "get_vhosts_from_file called incorrectly!\n";

    my $debug  = $self->{'debug'};
    my $REPORT = $self->{'report'};

	my (%vhosts, $vhost);
	my $in = 0;
	my $count = 0;

    $err = "\tretrieving from $file.\n";
	print $err if $debug>1; 
    print $REPORT $err if $REPORT;

	LINE: 
    foreach my $line ( $utility->file_read(file=>$file) ) {

		my $lc_line = lc($line);

        next LINE if $lc_line =~ /^#/;    # discard comment lines
        next LINE if $lc_line =~ /^\s*$/; # discard empty lines

        if ( $lc_line =~ /#/ ) {
            $lc_line =~ s/\A .*? \s* #//xms;   # strip off comments
        };

        # strip leading and and trailing whitespace
        $lc_line =~ s{\A \s* | \s* \z}{}gxm;   

		print "\t parsing: $lc_line\n" if $debug > 3;

		if ( !$in ) 
		{
			if ( $lc_line =~ m{\A <virtualhost }xms ) 
			{
				$in = $line;
				$count++;
				print "\n\t\t opening: $lc_line\n" if $debug > 2;
			};
			next LINE;
		}

		if ( $lc_line =~ m{\A </virtualhost }xms )  
		{
            if (! $vhost) {
                print "closing vhost tag found but no ServerName declared!\n"
                    . "\tin file $file\n\tin declaration $in\n";
            };

			print "\t\t closing: $lc_line\n" if $debug > 2;
			undef $vhost;
			$in = 0;
			next LINE;
		} 
        
		if ($lc_line =~ /\A servername/xms )
		{
			# we need to strip off any trailing port values(:80)  (thanks Raymond Dujkxhoorn)

			# parse this type of line: "  ServerName  foo.com:80  ";
            if ( $lc_line !~ 
                    m{
                        \A                 # start of string
                        servername         # the string "servername"
                        \s+                # 1 or more whitespace characters
                        ([a-z0-9\-\.\*]+)  # any characters valid for a domain name
                        [:\d+]?            # an optional :80 or :443 pattern
                        \z                 # end of string
                    }xms
                ) 
            {
                carp "unknown servername declaration in line: $line!";
                return;
            }

			my $servername = $1;
			print "\t\t\t servername: $servername.\n" if $debug > 2;

			$vhost = $servername;

            # %vhosts is keyed off $count 
			$vhosts{$count}{'name'} = $servername;
		}
		elsif ($lc_line =~ /serveralias/)
		{
			my @val = split(/\s+/, $lc_line); # space delimited in httpd.conf
			shift @val;                       # get rid of serveralias
			my $aliases = join(":", @val);    # pack them together with :'s in a string
			print "\t\t\t aliases are: $aliases\n" if $debug > 2;
			$vhosts{$count}{'aliases'} = $aliases;
			#$vhosts{$vhost}{'aliases'} = $aliases;
		} 
		elsif ($lc_line =~ /documentroot/)
		{
            if ( $lc_line !~ 
                    m{
                        \A            # start of string
                        documentroot  # keyword
                        \s+           # one or more whitespace 
                        ["]?          # optional quote character
                        (.*?)         # the declarations we want
                        ["]?          # optional quote character
                        \z            # end of string
                     }xms
                ) 
            {
                carp "unknown documentroot declaration: $line";
                return;
            }

			my $docroot = $1;
			print "\t\t\t docroot: $docroot\n" if $debug > 2;
			$vhosts{$count}{'docroot'} = $docroot;
		} 
		else {
			#print "unknown: $line\n" if $debug;
		};
	};

	# create the domlist hash element if necessary
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

    print "done.\n" if $debug>3;
	print $REPORT "get_domains_from_file: done.\n" if $REPORT;
	return \%tmp;
};

sub get_log_dir {

    my $self  = shift;
    my $debug = $self->{'debug'};
    my $conf  = $self->{'conf'};

    my $interval = $self->{'rotation_interval'} || "day";
 
    unless ( $conf ) {
        croak "get_log_dir: \$conf is not set!\n";
    };

    my $bump     = $conf->{'time_offset'};
	my $logbase  = $conf->{'logbase'};

	my ($dd, $mm, $yy, $lm, $hh, $mn) = $utility->get_the_date(debug=>0);

    my $how_far_back = $interval eq "hour"  ? .04   # back 1 hour
                     : $interval eq "month" ? $dd+1 # last month
                     : 1;  # 1 day

	if ($bump) 
	{
		($dd, $mm, $yy, $lm, $hh, $mn) 
            = $utility->get_the_date(
                bump   => $bump + $how_far_back,
                debug  => $debug>1 ? 1 : 0,
              );
	}
	else 
	{
		($dd, $mm, $yy, $lm, $hh, $mn) 
            = $utility->get_the_date(
                    bump  => $how_far_back,
                    debug => $debug > 1 ? 1 : 0,
                );
	};

    my $logdir = $interval eq "hour"  ? "$logbase/$yy/$mm/$dd/$hh"
               : $interval eq "day"   ? "$logbase/$yy/$mm/$dd"
               : $interval eq "month" ? "$logbase/$yy/$mm"
               :                        "$logbase";

	print "get_log_dir: using $logdir\n" if $debug>1;
	return $logdir;
};

sub install_default_awstats_conf {

    my @lines = <<'EO_AWSTATS_CONF';
# installed by logmonster
LogFile="gzip -d </var/log/apache/%YYYY-24/%MM/%DD-24/access.log.gz |"
LogFormat = "%host %other %logname %time1 %methodurl %code %bytesd %refererquot %uaquot %virtualname"
LogSeparator=" "
DNSLookup=2
DirCgi="/cgi-bin"
DirIcons="/icons"
AllowToUpdateStatsFromBrowser=0
EnableLockForUpdate=0
DNSStaticCacheFile="dnscache.txt"
DNSLastUpdateCacheFile="dnscachelastupdate.txt"
SkipDNSLookupFor=""
AllowAccessFromWebToAuthenticatedUsersOnly=0
AllowAccessFromWebToFollowingAuthenticatedUsers=""
AllowAccessFromWebToFollowingIPAddresses=""
CreateDirDataIfNotExists=0
SaveDatabaseFilesWithPermissionsForEveryone=1

PurgeLogFile=0
ArchiveLogRecords=0
KeepBackupOfHistoricFiles=1
DefaultFile="index.html"
SkipHosts=""
SkipUserAgents=""
SkipFiles=""
OnlyHosts=""
OnlyFiles=""
NotPageList="css js class gif jpg jpeg png bmp"
ValidHTTPCodes="200 304"
ValidSMTPCodes="1"
AuthenticatedUsersNotCaseSensitive=0
URLNotCaseSensitive=0
URLWithAnchor=0
URLQuerySeparators="?;"
URLWithQuery=0
URLWithQueryWithoutFollowingParameters=""
URLReferrerWithQuery=0

WarningMessages=1
ErrorMessages=""
DebugMessages=1
NbOfLinesForCorruptedLog=50
WrapperScript=""
DecodeUA=0
MiscTrackerUrl="/js/awstats_misc_tracker.js"

LevelForRobotsDetection=2
LevelForBrowsersDetection=2
LevelForOSDetection=2
LevelForRefererAnalyze=2

UseFramesWhenCGI=0
DetailedReportsOnNewWindows=1
Expires=0
MaxRowsInHTMLOutput=1000
Lang="auto"
DirLang="./lang"

ShowMenu=1                                      
ShowMonthStats=UVPHB
ShowDaysOfMonthStats=VPHB
ShowDaysOfWeekStats=PHB
ShowHoursStats=PHB
ShowDomainsStats=PHB
ShowHostsStats=PHBL
ShowAuthenticatedUsers=0
ShowRobotsStats=HBL
ShowEMailSenders=0
ShowEMailReceivers=0
ShowSessionsStats=1
ShowPagesStats=PBEX
ShowFileTypesStats=HB
ShowFileSizesStats=0            
ShowOSStats=1
ShowBrowsersStats=1
ShowScreenSizeStats=0
ShowOriginStats=PH
ShowKeyphrasesStats=1
ShowKeywordsStats=1
ShowMiscStats=ajdfrqwp
ShowHTTPErrorsStats=1
ShowSMTPErrorsStats=0

AddDataArrayMonthStats=1
AddDataArrayShowDaysOfMonthStats=1
AddDataArrayShowDaysOfWeekStats=1
AddDataArrayShowHoursStats=1


MaxNbOfDomain = 10
MinHitDomain  = 1
MaxNbOfHostsShown = 10
MinHitHost    = 1
MaxNbOfLoginShown = 10
MinHitLogin   = 1
MaxNbOfRobotShown = 10
MinHitRobot   = 1
MaxNbOfPageShown = 10
MinHitFile    = 1
MaxNbOfOsShown = 10
MinHitOs      = 1
MaxNbOfBrowsersShown = 10
MinHitBrowser = 1
MaxNbOfScreenSizesShown = 5
MinHitScreenSize = 1
MaxNbOfRefererShown = 10
MinHitRefer   = 1
MaxNbOfKeyphrasesShown = 10
MinHitKeyphrase = 1
MaxNbOfKeywordsShown = 10
MinHitKeyword = 1
MaxNbOfEMailsShown = 20
MinHitEMail   = 1

FirstDayOfWeek=1
ShowFlagLinks="en fr de nl es"
ShowLinksOnUrl=1
UseHTTPSLinkForUrl=""
MaxLengthOfURL=72
ShowLinksToWhoIs=0

LinksToWhoIs="http://www.whois.net/search.cgi2?str="
LinksToIPWhoIs="http://ws.arin.net/cgi-bin/whois.pl?queryinput="
HTMLHeadSection=""
HTMLEndSection=""

Logo="awstats_logo1.png"
LogoLink="http://awstats.sourceforge.net"

BarWidth   = 260
BarHeight  = 90

StyleSheet=""

color_Background="FFFFFF"
color_TableBGTitle="CCCCDD"
color_TableTitle="000000"
color_TableBG="CCCCDD"
color_TableRowTitle="FFFFFF"
color_TableBGRowTitle="ECECEC"
color_TableBorder="ECECEC"
color_text="000000"
color_textpercent="606060"
color_titletext="000000"
color_weekend="EAEAEA"
color_link="0011BB"
color_hover="605040"
color_u="FFB055"
color_v="F8E880"
color_p="4477DD"
color_h="66F0FF"
color_k="2EA495"
color_s="8888DD"
color_e="CEC2E8"
color_x="C1B2E2"

LoadPlugin="userinfo"
LoadPlugin="hashfiles"
LoadPlugin="timehires"
EO_AWSTATS_CONF

    my $statsdir = "/etc/awstats";
    $utility->file_write(
        file  => "$statsdir/awstats.conf",
        debug => 0,
        fatal => 0,
        lines => \@lines,
    ) or carp "couldn't install $statsdir/awstats.conf: $!\n";
};

sub report_hits {

	my $self   = shift;
    my $logdir = shift;
    my $debug  = $self->{'debug'};

    $self->{'debug'} = 0;     # hush get_log_dir
    $logdir  ||= $self->get_log_dir();

	my $vhost_count_summary = $logdir . "/HitsPerVhost.txt";

    # fail if $vhost_count_summary is not present
    unless (  $vhost_count_summary 
        && -e $vhost_count_summary 
        && -f $vhost_count_summary ) 
    {
        print "report_hits: ERROR: hit summary file is missing. It should have"
            . " been at: $vhost_count_summary. Report FAILURE.\n";
        return;
    };

	print "report_hits: reporting summary from file $vhost_count_summary\n" if $debug;

    my @lines = $utility->file_read(
        file  => $vhost_count_summary,
        debug => $debug,
        fatal => 0,
    );

    my $lines_in_array = @lines;

    if ( $lines_in_array > 0 ) {
        print join(':', @lines) . "\n";
        return 1;
    };

	print "report_hits: no entries found!\n" if $debug;
    return;
};

sub report_close {

    my $self = shift;
	my $fh   = shift;

    if ( $fh ) {
	    close($fh);
        return 1;
    };

    carp "report_close: was not passed a valid filehandle!";
    return;
};

sub report_open {

    my $self  = shift;
    my $name  = shift;
	my $debug = $self->{'debug'};

    $name || croak "report_open: no filename passed!";

    my $logdir = $self->get_log_dir();

	unless ( $logdir && -w $logdir ) 
	{
		print "\tNOTICE!\nreport_open: logdir $logdir is not writable!\n";
		$logdir = "/tmp";
	};

	my $report_file = "$logdir/$name.txt";
    my $REPORT;

	if ( ! open $REPORT, ">", $report_file) {
        carp "couldn't open $report_file for write: $!";
        return;
    };

	print "\n ***  this report is saved in $report_file *** \n" if $debug;
	return $REPORT;
};

sub sort_vhost_logs {

############################################
# Usage      : see t/Logmonster.t for usage example
# Purpose    : since the log entries for each host are concatenated, they are
#              no longer in cronological order. Most stats post-processors
#              require that log entries be in chrono order so this sorts them
#              based on their log entry date, which also resolves any timezone
#              differences.
# Returns    : boolean, 1 for success
# Parameters : conf - hashref of setting from logmonster.conf
#              report

    my $self   = shift;
    my $debug  = $self->{'debug'};
    my $conf   = $self->{'conf'};
    my $REPORT = $self->{'report'};

	my (%beastie, %sortme);

    my $dir = $conf->{'tmpdir'} || croak "tmpdir not set in \$conf";

    if ( $self->{'host_count'} < 2 ) {
        print "sort_vhost_logs: only one log host, skipping sort.\n" if $debug;
        return 1;  # sort not needed with only one host
    };

    $utility->_progress_begin("sort_vhost_logs: sorting each vhost logfile...")
        if $debug==1;

	my $lines = 0;

    VHOST_FILE:
	foreach my $file ( $utility->get_dir_files(dir=>"$dir/doms",fatal=>0) )
	{
		undef %beastie;    # clear the hash
		undef %sortme;

        if ( -s $file > 10000000 ) 
		{
			print "\nsort_vhost_logs: logfile $file is greater than 10MB\n" if $debug;
			print $REPORT "sort_vhost_logs: logfile $file is greater than 10MB\n";
		};

		unless ( open UNSORTED, "<", $file )
		{
			warn "\nsort_vhost_logs: WARN: could not open input file $file: $!";
			next VHOST_FILE;
		};

        # make sure we can write out the results before doing all the work
		unless ( open SORTED, ">", "$file.sorted" )
		{
			print "\n sort_vhost_logs: FAILED: could not open output file $file: $!\n"
                if $debug;
            next VHOST_FILE;
		}

        $utility->_progress_begin("    sorting $file...") if $debug>1;

		while (<UNSORTED>)
		{
            $utility->_progress_continue() if $debug>1;
			chomp;
###
# Per Earl Ruby, switched from / / to /\s+/ so that naughty modules like 
# Apache::Register that insert extra spaces in the Log output won't mess
# up logmonsters parsing.
#    @log_entry_fields = split(/ /, $_)  =>  @log.. = split(/\s+/, $_)
### 
#    sample log entry
#216.220.22.182 - - [16/Jun/2004:09:37:51 -0400] "GET /images/google-g.jpg HTTP/1.1" 200 539 "http://www.tnpi.biz/internet/mail/toaster/" "Mozilla/5.0 (Windows; U; Windows NT 5.0; en-US; rv:1.6) Gecko/20040113" www.thenetworkpeople.biz

# From an Apache log entry, we first split apart the line based on whitespace

			my @log_entry_fields = split(/\s+/, $_); # split the log entry into fields

# Then we use substr to extract the middle 26 characters:
#   16/Jun/2004:09:37:51 -0400
#
# We could also use a regexp to do this but substr is more efficient and we
# can safely expect the date format of ApacheLog to remain constant.

			my $rawdate = substr("$log_entry_fields[3] $log_entry_fields[4]", 1, 26);

# then we convert that date string to a numeric string that we can use for sorting.

			my $date = str2time($rawdate);

# Finally, we put the entire line into the hash beastie (keyed with $lines,
# an incrementing number) and create a second hash ($sortme) with the 
# same key but the value is the timestamp. 

			$beastie{$lines} = $_;
			$sortme{$lines}  = $date;

			$lines++;
		}; 
		close(UNSORTED) || croak "sort_vhost_logs: Gack, could not close $file: $!\n";
        $utility->_progress_end() if $debug>1;

# We create an array (because elements in arrays stay in order) of line
# numbers based on the sortme hash, sorted based on date

		my @sorted = sort { ($sortme{$a} <=> $sortme{$b}) || 
			($sortme{$a} cmp $sortme{$b}); } ( keys(%sortme) );

        foreach (@sorted) {
            # iterate through @sorted, adding the corresponding lines from %beastie to the file
            print SORTED "$beastie{$_}\n";
        };
        close SORTED;

        move("$file.sorted", $file) 
            or carp "sort_vhost_logs: could not replace $file with $file.sorted: $!\n";

        $utility->_progress_continue() if $debug==1;
	};

    $utility->_progress_end() if $debug==1;

    return 1;
};

sub split_logs_to_vhosts {

# hey, neato. I just (7/19/2006) learned that the little trick I employ to
# sort the log files (create a hash with non-obvious data used to sort the 
# contents of another hash) is called a Schwartzian Transform. It is rather 
# fun to learn that something I thought up and wrote many years ago actually
# has a name and is a recommended technique. I should read more...

    my ($self, $domains_ref) = @_;

    # sanity check our required argument
    unless ( $domains_ref && $utility->is_hashref($domains_ref) ) {
        croak "split_logs_to_vhosts called incorrectly!";
    };

    my $debug   = $self->{'debug'};
    my $conf    = $self->{'conf'};
    my $REPORT  = $self->{'report'};

	my (%fhs, %count, %orphans, $bad, $gz);

	my $dir      = $conf->{'tmpdir'};   # normally /var/log/apache/tmp
    my $countlog = $conf->{'CountLog'} || 1;

	my @webserver_logs = <$dir/*.gz>;

    # make sure we have logs to process
	if ( ! $webserver_logs[0] or $webserver_logs[0] eq "" ) 
	{
        $err =  "WARNING: No web server log files found!\n";
		print $err if $debug; print $REPORT $err;
		return;
	};

    print "split_logs_to_vhosts: found logfiles \n\t"
        . join("\n\t", @webserver_logs) . "\n" if $debug>1;

	if ( !-d "$dir/doms" ) 
	{
		if ( ! mkdir "$dir/doms", oct('0755')  )
		{
            $err = "FATAL: couldn't create $dir/doms: $!\n";
			print $REPORT $err;
			die $err;
		};
	};

	my $key_count = keys %$domains_ref;

	unless ( $key_count ) {
        $err = "\nHey, you have no vhosts! You must have at least one!";
		print $REPORT $err . "\n";
		die $err;
	};

    print "\t output working dirs is $dir/doms\n" if $debug>1;

    # open a file for each vhost
	foreach (keys %$domains_ref)
	{
		my $name = $domains_ref->{$_}->{'name'};

		my $fh = new FileHandle;  # create a file handle for each ServerName
		$fhs{$name} = $fh;        # store in a hash keyed off the domain name

		if ( open($fh, ">", "$dir/doms/$name")  ) {
            if ($debug>1) {
                print "            ";
                printf "opening file for %35s...ok\n", $name;
            };
        } 
        else {
            print "            ";
            printf "opening file for %35s...FAILED.\n", $name;
        }
	};

	my $domkey_ref = $self->turn_domains_into_sort_key($domains_ref);

    # use my Regexp::Log::Monster
    my $regexp_parser = Regexp::Log::Monster->new(
        format  => ':logmonster',
        capture => [qw( host vhost status bytes ref ua )],
		# Apache fields
			# host, ident, auth, date, request, status, bytes, referer, agent, vhost
		# returned from parser (available for capture) as: 
			# host, rfc, authuser, date, ts, request, req, status, bytes, referer, ref, 
			# useragent, ua, vhost
    );
    my @captured_fields = $regexp_parser->capture;
    my $re = $regexp_parser->regexp;

	foreach my $file (@webserver_logs)
	{
		unless ( $gz = gzopen($file, "rb") )
		{
			warn "Couldn't open $file: $gzerrno";
			next;
		};

        my $lines = 0;
        $utility->_progress_begin("\t parsing entries from $file") if $debug;

		LOGENTRY: while ( $gz->gzreadline($_) > 0 ) 
		{
			chomp $_;
            $lines++;
            $utility->_progress_continue() if ($debug && $lines =~/00$/ );
            
            my %data;
            @data{@captured_fields} = /$re/;    # no need for /o, it's a compiled regexp

            # make sure the log format has the vhost tag appended
			my $vhost = $data{'vhost'};
			if (!$vhost) 
			{
				# domain names can only have alphanumeric, - and . characters
				# the regexp catches any entries without the vhost appended to them
				# if you have these, read the logmonster FAQ and set up your Apache
				# logs correctly!

				print "ERROR: You have invalid log entries!"
                 . " Read the FAQ for setting up logging correctly.\n" if $debug;
                print $_ . "\n" if $debug>2;
				$bad++;
				next;
			};

            if ( $conf->{'spam_check'} ) {
                my $spam_score = 0;

                # check for spam quotient
                if ( $data{'status'} ) {
                    if ( $data{'status'} == 404 ) {    	# check for 404 status
                        # a 404 error alone is not a sign of naughtiness
                        $spam_score++;
                    };

                    if ( $data{'status'} == 412 ) {
                        # a 412 error was likely my Apache config slapping them
                        $spam_score++;
                    };

                    if ( $data{'status'} == 403 ) {
                        # a 403 error was almost certainly my Apache config slapping them
                        $spam_score += 2;
                    };
                };

                # nearly all of my referer spam has a # ending the referer string
                if ( $data{'ref'} && $data{'ref'} =~ /#$/ ) {
                    $spam_score += 2;
                };

                # should check for invalid/suspect useragent strings here
                if ( $data{'ua'} ) {
                    $data{'ua'} =~ /crazy/ixms  ? $spam_score += 1
                    : $data{'ua'} =~ /email/i   ? $spam_score += 3
#                : $data{'ua'} =~ /windows/    ? $spam_score += 1
                    : print "";
                };

                # if we fail more than one spam test...
                if ( $spam_score > 2 ) 
                {
                    $count{'spam'}++;
                    if ( defined $data{'bytes'} && $data{'bytes'} =~ /[0-9]+/ ) {
                        $count{'bytes'} += $data{'bytes'} 
                    };

                    $count{'spam_agents'}{$data{'ua'}}++;
                    $count{'spam_referers'}{$data{'ref'}}++;

#				printf "%3s - %30s - %30s \n", $data{'status'}, $data{'ref'}, $data{'ua'};
                    next LOGENTRY;     # skips processing the line
                }
# TODO: also keep track of ham referers, and print in referer spam reports, so
# that I can see which UA are entirely spammers and block them in my Apache
# config.
#                else 
#                {
#                    $count{'ham_referers'}{$data{'ref'}}++;
#                }
            };

            # we lc everything we pull out of the apache config files so we
            # must also do it here.
            $vhost = lc($vhost);   

            # write it out to the proper vhost file
			my $main_dom = $domkey_ref->{$vhost};

			if ( $main_dom ) 
			{
				my $fh = $fhs{$main_dom};
				print $fh "$_\n";
			    $count{$main_dom}++;
			}
			else 
			{
				print "\nsplit_logs_to_vhosts: the main domain for $vhost is missing!\n" if $debug>1;
				$orphans{$vhost} = $vhost;
			};
		};
		$gz->gzclose();

        $utility->_progress_end() if $debug;

		#$utility->file_delete(file=>$file, debug=>0) if $conf->{'clean'};
	};

	print "\n\t\t\t Matched Entries\n\n" if $debug;
	print $REPORT "\n\t\t Matched Entries\n\n";

	my $HitLog = $self->report_open("HitsPerVhost") if $countlog;

	foreach my $key (keys %fhs)
	{
		close($fhs{$key});

		if ( $count{$key} ) 
		{
			printf "         %15.0f lines to %s\n", $count{$key}, $key if $debug;
			printf $REPORT "         %15.0f lines to %s\n", $count{$key}, $key;
			print $HitLog  "$key:$count{$key}\n" if $countlog;
		};
	};
	$self->report_close($HitLog, $debug) if $countlog;

	print "\n" if $debug;
	print $REPORT "\n";

	foreach my $key (keys %orphans)
	{
		if ( $count{$key} ) 
		{
			printf "Orphans: %15.0f lines to %s\n", $count{$key}, $key if $debug;
			printf $REPORT "Orphans: %15.0f lines to %s\n", $count{$key}, $key;
		};
	};

    $self->report_spam_hits(\%count, $REPORT);

	if ($bad)
	{
		printf "Skipped: %15.0f lines to unknown.\n", $bad if $debug;
		printf $REPORT "Skipped: %15.0f lines to unknown.\n", $bad;
		print "\nPlease read the FAQ (logging section) to see why records get skipped.\n\n" if $debug;
		print $REPORT "\nPlease read the FAQ (logging section) to see why records get skipped.\n\n";
	};

    return 1;
};

sub report_spam_hits {

    my $self = shift;
    my $count = shift;
    my $REPORT = shift;

    return if ( ! $count->{'spam'} );

    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    if ( $conf->{'report_spam_user_agents'} ) {

        printf "Referer spammers hit you $count->{'spam'} times" if $debug;

        if ($debug && $count->{'bytes'}) {
            if ($count->{'bytes'} > 1000000) { 
                $count->{'bytes'} = sprintf "%.2f MB", $count->{'bytes'} / 1000000; 
            } else {
                $count->{'bytes'} = sprintf "%.2f KB", $count->{'bytes'} / 1000;
            };

            print " and wasted " . $count->{'bytes'} . " of your bandwidth.";
        };
        print "\n\n" if $debug;

        printf $REPORT "Referer Spam: %15.0f lines\n", $count->{'spam'};

        my $spamagents = $count->{'spam_agents'};
        foreach my $value ( sort {$spamagents->{$b} cmp $spamagents->{$a} } keys %$spamagents ) {
            print "\t $spamagents->{$value} \t $value\n";
        };
    };

    if ( $conf->{'report_spam_referrers'} ) {
        # This report can get very, very long
        my $spam_referers = $count->{'spam_referers'};
        foreach my $value ( sort {$spam_referers->{$b} <=> $spam_referers->{$a} } keys %$spam_referers ) {
            print "$spam_referers->{$value} \t $value\n";
        };
    };
}

sub turn_domains_into_sort_key {

# From the info in $domains_ref, we create a hash like this:
#
#   example.com => 'example.com',
#   example.net => 'example.com',
#   example.org => 'example.com',
#
# as we parse through the log files, we do a lookup on this hash 
# to see which logfile to write the entries out to. In theory, this is not
# necessary as we have appended the vhost name to the log entry, but this is
# absolutely required for the fallback method.

    my $self = shift;
	my $domains_ref = shift;

    unless ( $domains_ref && $utility->is_hashref($domains_ref) ) {
        die "turn_domains_into_sort_key was passed an invalid argument.";
    };

    my $debug = $self->{'debug'};

	my %sorted;

	print "turn_domains_into_sort_key: working..." if $debug>1;

    while ( my ($key, $value) = each %$domains_ref )
	{
        # domlist contains a colon delimited list of domain names 
        # and aliases for a given Apache vhost. 
		my @vals = split(/:/, $domains_ref->{$key}->{'domlist'});

		my $master = shift(@vals);  # the first vhost is the "master"
		print "\t\t master: $master" if $debug>2;

		$sorted{$master} = $master;
		foreach my $slave (@vals)
		{
			print "slave: $slave " if $debug>2;
			$sorted{$slave} = $master;
		};
		print "\n" if $debug>2;
	};

    print "done.\n" if $debug==2;
	return \%sorted;
};


1;   # magic 1 for modules
__END__


=head1 NAME

Apache::Logmonster - Apache log file splitter, processor, sorter, etc


=head1 AUTHOR

Matt Simerson (matt@tnpi.net)


=head1 SUBROUTINES

=over

=item new

Creates a new Apache::Logmonster object. All methods in this module are Object Oriented and need to be accessed through the object you create. When you create a new object, you must pass as the first argument, a hashref of values from logmonster.conf. See t/Logmonster.t for a working example.


=item check_awstats_file

Checks to see if /etc/awstats is set up for awstats. If not, it creates it and installs a default awstats.conf. Finally, it makes sure the $domain it was passed has an awstats file configured for it. If not, it installs it.

=item check_config

perform some basic sanity tests on the environment Logmonster is running in. It will complain quite loudly if it finds things not to its liking.


=item check_stats_dir

Each virtual host that gets stats processing is expected to have a "stats" dir. I name mine "stats" and locate in the vhosts document root. I set the files ownership to root so that the user doesn't inadvertantly delete it via FTP. After splitting up the log files based on vhist, this sub first goes through the list of files in $tmpdir/doms. If the file name matches the vhost name, the contents of that log correspond to that vhost.

If the file is zero bytes, it deletes it as there is nothing to do. 

Otherwise, it gathers the vhost name from the file and checks the %domains hash to see if a directory path exists for that vhost. If no hash entry is found or the entry is not a directory, then we declare the hits unmatched and discard them.

For log files with entries, we check inside the docroot for a stats directory. If no stats directory exists, then we discard those entries as well.

=item compress_log_file

Compresses a file. Does a test first to make sure the file exists and then compresses it using gzip. You pass it a hostname and a file and it compresses the file on the remote host. Uses SSH to make the connection so you will need to have key based authentication set up.


=item consolidate_logfile

Collects compressed log files from a list of servers into a working directory for processing. 


=item feed_the_machine

feed_the_machine takes the sorted vhost logs and feeds them into the stats processor that you chose.


=item fetch_log_files

extracts a list of hosts from logmonster.conf, checks each host for log files and then downloads them all to the staging area.

=item get_domains_list

checks your vhosts setting in logmonster.conf to determine where to find your Apache vhost information, and then parses your Apache config files to retrieve a list of the virtual hosts you server for as well as some attributes about each vhost (docroot, aliases). 

If successful, it returns a hashref of elements.

=item get_domains_list_from_directories

Determines your list of domain and domain aliases based on presense of directories and symlinks on the file system. See the FAQ for details.

=item get_vhosts_from_file

Parses a file looking for virtualhost declarations. It stores several attributes about each vhost including: servername, serveralias, and documentroot as these are needed to determine where to output logfiles and statistics to.

returns a hashref, keyed with the vhost servername. The value of the top level hashref is another hashref of attributes about that servername.

=item get_log_dir

Determines where to fetch an intervals worth of logs from. Based upon the -i setting (hour,day,month), this sub figures out where to find the requested log files that need to be processed.

=item install_default_awstats_conf

Installs /etc/awstats.awstats.conf

=item report_hits

report_hits reads a days log results file and reports the results to standard out. The logfile contains key/value pairs like so:
	
    matt.simerson:4054
    www.tnpi.biz:15381
    www.nictool.com:895

This file is read by logmonster when called in -r (report) mode
and is expected to be called via a SNMP agent.


=item report_close

Accepts a filehandle, which it then closes. 


=item report_spam_hits

Appends information about referrer spam to the logmonster -v report. An example of that report can be seen here: http://www.tnpi.net/wiki/Referral_Spam


=item report_open

In addition to emailing you a copy of the report, Logmonster leaves behind a copy in the log directory. This file is ready when logmonster -r is run (typically by snmpd). This function simply opens the report and returns the filehandle.


=item sort_vhost_logs

By now we have collected the Apache logs from each web server and split them up based on vhost. Most stats processors require the logs to be sorted in cronological order. So, we open up each vhosts logs for the day, read them into a hash, sort them based on their log entry date, and then write them back out.


=item split_logs_to_vhosts

After collecting the log files from each server in the cluster, we need to split them up based upon the vhost they were intended for. This sub does that.

=item turn_domains_into_sort_key

From the info in $domains_ref, creates a hash like this:

  example.com => 'example.com',
  example.net => 'example.com',
  example.org => 'example.com',

as we parse through the log files, we do a lookup on this hash to see which logfile to write the entries out to. In theory, this is not necessary as we have appended the vhost name to the log entry, but this is absolutely required for the fallback method.

=back

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

Copyright (c) 2003-2006, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DIS CLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
