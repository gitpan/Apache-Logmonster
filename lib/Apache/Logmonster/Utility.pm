#!/usr/bin/perl
use strict;

#
# $Id: Utility.pm,v 1.3 2004/11/26 18:09:22 matt Exp $
#

package Apache::Logmonster::Utility;

use Carp;
use POSIX qw(uname);
my $os = lc( (uname)[0] );

use vars qw($VERSION);
$VERSION = '1.43';

use lib "lib";
use lib "../..";

=head1 NAME

Apache::Logmonster::Utility - Common Perl scripting functions

=head1 DESCRIPTION

Just a big hodge podge of useful subs that I use in scripts all over the place. Peruse through the list of methods and surely you too can find something of use. 

=head1 METHODS

=head2 new

To use any of the utility methods, you must create a utility object:

  use Apache::Logmonster::Utility;
  my $utility = Apache::Logmonster::Utility;

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};


sub graceful_exit(;$$)
{
	my ($self, $code, $desc) = @_;

	print "$desc\n" if $desc;
	print "+$code\n" if $code;
	exit 1;
};


=head2 check_pidfile

check_pidfile is a process management method. It will check to make sure an existing pidfile does not exist and if not, it will create the pidfile.

	my $pidfile = $utility->check_pidfile("/var/run/changeme.pid");
	unless ($pidfile) {
		warn "WARNING: couldn't create a process id file!: $!\n";
		exit 0;
	};

	do_a_bunch_of_cool_stuff;
	unlink $pidfile;

The above example is all you need to do to add process checking (avoiding multiple daemons running at the same time) to a program or script. This is used in toaster-watcher.pl and rrdutil. toaster-watcher normally completes a run in a few seconds and is run every 5 minutes. 

However, toaster-watcher can be configured to do things like expire old messages from maildirs and feed spam through a processor like sa-learn. This can take a long time on a large mail system so we don't want multiple instances of toaster-watcher running.

returns the path to the pidfile (on success).

=cut

sub check_pidfile($;$)
{
	my ($self, $pidfile, $debug) = @_;

	# make sure the file & enclosing directory is writable, revert to tmp if not
	unless ( $self->file_check_writable($pidfile, $debug) )
	{
		use File::Basename;
		my ($base, $path, $suffix) = fileparse($pidfile);
		print "NOTICE: using /tmp instead of $path for pidfile\n" if $debug;
		$pidfile = "/tmp/$base";
	};

	if ( -e $pidfile )
	{
		use File::stat;
		my $stats = stat($pidfile);
		my $age   = time() - $stats->mtime;

		if ($age < 3600 )     # if it's less than 1 hour old
		{
			print "\nWARNING! check_pidfile: $pidfile is $age seconds old and might still be running. If this is not the case, please remove it. \n\n";
			return 0;
		} else {
			print "\nWARNING: check_pidfile: $pidfile was found but it's $age seconds old, so I'm ignoring it.\n\n";
		};
	}
	else
	{
		print "check_pidfile: writing process id ", $$, " to $pidfile..." if $debug;
		$self->file_write($pidfile, $$);  # $$ is the process id of this process
		print "done.\n" if $debug;
	};

	return $pidfile;

};


=head2 install_from_sources_php

	$utility->install_from_sources_php();

Downloads a PHP program and installs it. Not completed.

=cut

sub install_from_sources_php($$$$;$$$)
{
	my $self = shift;
	#my ($conf, $vals) = @_;
	my ($conf, $package, $site, $url, $targets, $patches, $debug) = @_;
	my $patch;

	my $src = $conf->{'toaster_src_dir'}; $src ||= "/usr/local/src";
	$self->chdir_source_dir($src);

	if ( -d $package ) 
	{
		unless ( $self->source_warning($package, 1, $src) )
		{
			carp "\ninstall_from_sources_php: OK then, skipping install.\n";
			return 0;
		}
		else
		{
			print "install_from_sources_php: removing any previous build sources.\n";
			$self->syscmd("rm -rf $package-*");   # nuke any old versions
		};
	};

	print "install_from_sources_php looking for existing sources...";

	my $tarball = "$package.tar.gz";
	if    ( -e $tarball )          { print "found.\n"; }
	elsif ( -e "$package.tgz" )    { print "found.\n"; $tarball = "$package.tgz"; } 
	elsif ( -e "$package.tar.bz2") { print "found.\n"; $tarball = "$package.tar.bz2"; } 
	else                           { print "not found.\n" };

	unless ( -e $tarball )
	{
		$site ||= $conf->{'toaster_dl_site'}; $site ||= "http://www.tnpi.biz";
		$url  ||= $conf->{'toaster_dl_url'};  $url ||= "/internet/mail/toaster";

		unless ( $self->get_file("$site$url/$tarball", $debug) )
		{
			croak "install_from_sources_php: couldn't fetch $site$url/$tarball\n";
		};

		if ( `file $tarball | grep ASCII` ) {
			print "install_from_sources_php: oops, file is not binary, we'll try again as .bz2\n";
			unlink $tarball;
			$tarball = "$package.tar.bz2";
			unless ( $self->get_file("$site$url/$tarball", $debug) )
			{
				croak "install_from_sources_php: couldn't fetch $site$url/$tarball\n";
			};
		};
	} 
	else 
	{
		print "install_from_sources_php: using existing $tarball sources.\n";
	};

	if ( $patches && @$patches[0] ) 
	{
		print "install_from_sources_php: fetching patches...\n";
		foreach $patch ( @$patches ) 
		{
			my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
			unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };
			unless ( -e $patch ) {
				unless ( $self->get_file("$toaster/patches/$patch") )
				{
					croak "install_from_sources_php: couldn't fetch $toaster/$patches/$patch\n";
				};
			};
		};
	} 
	else 
	{
		print "install_from_sources_php: no patches to fetch.\n";
	};

	$self->archive_expand($tarball, 1) or die "Couldn't expand $tarball: $!\n";

	if ( -d $package )
	{
		chdir $package;

		if ( $patches && @$patches[0] ) 
		{
			print "yes, should be patching here!\n";
			foreach $patch ( @$patches ) 
			{
				my $patchbin = $self->find_the_bin("patch");
				if ( $self->syscmd("$patchbin < ../$patch") ) 
				{ 
					croak "install_from_sources_php: patch failed: $!\n";
				};
			};
		};

#		unless ( @$targets[0] ) 
#		{
#			print "install_from_sources_php: using default targets (./configure, make, make install).\n";
#			@$targets = ( "./configure", "make", "make install") 
#		};

		foreach my $target ( @$targets ) 
		{ 
			if ( $self->syscmd($target) )
			{
				croak "install_from_source_php: $target failed: $!\n";
			};
		};
#		chdir("..");
#		$self->syscmd("rm -rf $package");
	};
};


=head2 file_check_writable

	use Mail::Toaster::Utility;
	$utility->file_check_writable("/tmp/boogers", $debug) ? print "yes" : print "no";

If the file exists, it checks to see if it's writable. If the file does not exist, then it checks to see if the enclosing directory is writable. 

It will output verbose messages if you set the debug flag.

returns a 1 if writable, zero otherwise.

=cut

sub file_check_writable($;$)
{
	my ($self, $file, $debug) = @_;

	my $nl = "\n"; $nl = "<br>" if ( $ENV{'GATEWAY_INTERFACE'} );

	print "file_check_writable: checking $file..." if $debug;

	if ( -e $file )    # if the file exists
	{
		unless ( -w $file ) 
		{
			print "WARNING: file_check_writable: $file not writable by " . getpwuid($>) . "!$nl$nl>" if $debug;
			#warn "WARNING: file_check_writable: $file not writable by " . getpwuid($>) . "!$nl$nl>";
			return 0;
		};
	} 
	else
	{
		use File::Basename;
		my ($base, $path, $suffix) = fileparse($file);

		unless ( -w $path )
		{
			#print "\nWARNING: file_check_writable: $path not writable by " . getpwuid($>) . "!$nl$nl" if $debug;
			warn "\nWARNING: file_check_writable: $path not writable by " . getpwuid($>) . "!$nl$nl" if $debug;
			return 0;
		};
	};

	print "yes.$nl" if $debug;
	return 1;
};

sub file_check_readable($;$)
{

=head2 file_check_readable

	$utility->file_check_readable($file);

input is a string consisting of a path name to a file. An optional second argument changes the default exit behaviour to warn and continue (rather than dying).

return is 1 for yes, 0 for no.

=cut

	my ($self, $file, $warn) = @_;

	unless ( -e $file )
	{
		print "\nfile_check_readable: ERROR: The file $file currently does not exist. This is most likely because you did not follow the installation instructions correctly. Please read and follow the instructions. If the problems persist, email a complete description of the problem to support\@tnpi.biz.\n\n";
		$warn ? return 0 : croak "\n";
	};

	unless ( -r $file ) 
	{
		print "\nfile_check_readable: ERROR: Pardon me but I need your help. The file $file is currently not readable by the user I'm running as (" . getpwuid($>) . "). You need to fix this, most likely using either chown or chmod.\n\n";
		$warn ? return 0 : croak "\n";
	}

	return 1;
};

sub install_from_source($$)
{

=head2 install_from_source

	$vals = { package => 'simscan-1.07',
			site    => 'http://www.inter7.com',
			url     => '/simscan/',
			targets => ['./configure', 'make', 'make install'],
			patches => '',
			debug   => 1,
	};

	$utility->install_from_source($conf, $vals);

Downloads and installs a program from sources.

returns 1 on success, 0 on failure.

=cut

	my ($self, $conf, $vals) = @_;
	my $patch;

	my $src = $conf->{'toaster_src_dir'}; $src ||= "/usr/local/src";
	$self->chdir_source_dir($src);

	my $package = $vals->{'package'};
	if ( -d $package ) 
	{
		unless ( $self->source_warning($package, 1, $src) )
		{
			carp "\ninstall_from_source: OK then, skipping install.\n";
			return 0;
		}
		else
		{
			print "install_from_source: removing any previous build sources.\n";
			$self->syscmd("rm -rf $package-*");   # nuke any old versions
		};
	};

	print "install_from_source: looking for existing sources...";

	my $tarball = "$package.tar.gz";
	if    ( -e $tarball )           { print "found.\n"; }
	elsif ( -e "$package.tgz"    )  { print "found.\n"; $tarball = "$package.tgz";     } 
	elsif ( -e "$package.tar.bz2" ) { print "found.\n"; $tarball = "$package.tar.bz2"; } 
	else                            { print "not found.\n" };

	if ( -e $tarball ) {
		print "install_from_source: using existing $tarball sources.\n";
	} 
	else 
	{
		my $site = $vals->{'site'};
		$site ||= $conf->{'toaster_dl_site'};  
		$site ||= "http://www.tnpi.biz";        # if all else fails

		my $url = $vals->{'url'};            # get from passed value
		$url ||= $conf->{'toaster_dl_url'};  # get from toaster-watcher.conf
		$url ||= "/internet/mail/toaster";   # finally, a default

		unless ( $self->get_file("$site$url/$tarball", $vals->{'debug'}) )
		{
			carp "install_from_source: couldn't fetch $site$url/$tarball\n";
		};

		if ( -e $tarball ) 
		{
			if ( `file $tarball | grep ASCII` ) {
				print "install_from_source: oops, file is not binary, we'll try again as bz2.\n";
				unlink $tarball;
				$tarball = "$package.tar.bz2";
				unless ( $self->get_file("$site$url/$tarball", $vals->{'debug'}) )
				{
					croak "install_from_source: couldn't fetch $site$url/$tarball\n";
				};
			};
		}
		else
		{
			$tarball = "$package.tar.bz2";
			unless ( $self->get_file("$site$url/$tarball", $vals->{'debug'}) )
			{
				croak "install_from_source: couldn't fetch $site$url/$tarball\n";
			};
		};
	};

	my $patches = $vals->{'patches'};
	if ( $patches && @$patches[0] ) 
	{
		print "install_from_source: fetching patches...\n";
		foreach $patch ( @$patches ) 
		{
			my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
			unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };
			unless ( -e $patch ) {
				unless ( $self->get_file("$toaster/patches/$patch") )
				{
					croak "install_from_source: couldn't fetch $toaster/$patches/$patch\n";
				};
			};
		};
	} 
	else 
	{
		print "install_from_source: no patches to fetch.\n";
	};

	$self->archive_expand($tarball, 1) or die "Couldn't expand $tarball: $!\n";

	if ( -d $package )
	{
		chdir $package;

		if ( $patches && @$patches[0] ) 
		{
			print "yes, should be patching here!\n";
			foreach $patch ( @$patches ) 
			{
				my $patchbin = $self->find_the_bin("patch");
				if ( $self->syscmd("$patchbin < ../$patch") )
				{ 
					croak "install_from_source: patch failed: $!\n";
				};
			};
		};

		my $targets = $vals->{'targets'};
		unless ( @$targets[0] ) 
		{
			print "install_from_source: using default targets (./configure, make, make install).\n";
			@$targets = ( "./configure", "make", "make install") 
		};

		foreach my $target ( @$targets ) 
		{ 
			if ( $self->syscmd($target) )
			{
				croak "install_from_source: $target failed: $!\n";
			};
		};
		chdir("..");
		$self->syscmd("rm -rf $package");
	};
};

sub check_homedir_ownership(;$)
{

=head2 check_homedir_ownership

Checks the ownership on all home directories to see if they are owned by their respective users in /etc/password. Offers to repair the permissions on incorrectly owned directories. This is useful when someone that knows better does something like "chown -R user /home /user" and fouls things up.

   $utility->check_homedir_ownership;

=cut

	my ($self, $debug) = @_;

	unless ( $os eq "freebsd" ) {
		print "WARNING: skipping, I don't know " . $os . "\n";
		return 0;
	};

	# name, passwd, uid, gid, quota, comment, gcos, dir, shell
	my $n;
	setpwent();
	while( my ($name, $uid, $dir) = (getpwent())[0,2,7] ) 
	{
		print "Checking for $name\n" if $debug;
		next if ( $uid < 100 );
		next if ( $name eq "nobody" );
		unless (-e $dir) {
			print "WARNING: ${name}'s home dir: $dir, does not exist.\n";
#			&get_users_domain_list($name);
			next;
		}
		my $dir_stat = stat($dir) or croak "Couldn't stat $dir: $!\n";
		if ( $uid != @$dir_stat[4] ) 
		{
			print "warning: $name is uid $uid, but $dir is owned by @$dir_stat[4].\n";
			if ( $self->yes_or_no("Would you like me to fix it? ", 5) ) 
			{
				my $sudo = $self->sudo;
				my $chown = $self->find_the_bin("chown");
				$self->syscmd("$sudo $chown -R $name $dir");
				print "Changed $dir to be owned by $name\n\n";
				next;
			} 
			else { next; }
		}
	};
	endpwent();
};

sub archive_expand($;$)
{

=head2 archive_expand

	$utility->archive_expand("package.tar.bz2", $debug);

Takes an archive and decompresses and expands it's contents. Works with bz2, gz, and tgz files.

=cut

	my ($self, $archive, $debug) = @_;
	my $r;

	my $tar  = $self->find_the_bin("tar");
	my $file = $self->find_the_bin("file");
	my $grep = $self->find_the_bin("grep");

	if ( $archive =~ /bz2$/ ) 
	{
		print "archive_expand: decompressing $archive...." if $debug;

		# Check to make sure the archive contents match the file extension
		# this shouldn't be necessary but the world isn't perfect. Sigh.

		if ( `$file $archive | $grep bunzip2` ) {
			my $bunzip2 = $self->find_the_bin("bunzip2");
			if ( $self->syscmd("$bunzip2 -c $archive | $tar -xf -") ) {
				print "archive_expand: FAILURE expanding\n";
				return 0;
			} else {
				return 1;
			};
		} else {
			print "FAILURE: $archive is not a bz2 compressed file!\n";
			return 0;
		};
	}
	elsif ( $archive =~ /gz$/ )
	{
		print "archive_expand: decompressing $archive...." if $debug;
		if ( `$file $archive | $grep gzip` ) {
			my $gunzip = $self->find_the_bin("gunzip");
			if ( $self->syscmd("$gunzip -c $archive | $tar -xf -") ) {
				print "archive_expand: FAILURE expanding\n";
				return 0;
			} else {
				return 1;
			};
		} else {
			print "FAILURE: $archive is not a gzip compressed file!\n";
			return 0;
		};
	}
	else
	{
		print "archive_expand: FAILED: I don't know how to expand $archive!\n";
		return 0;
	}
	print "done.\n" if $debug;
	return 1;
};


sub drives_get_mounted(;$)
{

=head2 drives_get_mounted

	$utility->drives_get_mounted($debug);

Uses mount to fetch a list of mounted drive/partitions.

returned is a hashref of mounted slices and their mount points.

=cut

	my ($self, $debug) = @_;

	my %hash;

	my $mountbin = $self->find_the_bin("mount");

	foreach my $mount ( `$mountbin` ) 
	{
		my ($d, $m) = $mount =~ /^(.*) on (.*) \(/;

		if ( $m =~ /^\// && $d =~ /^\// ) 
		{
			print "adding: $m \t $d\n" if $debug;
			$hash{$m} = $d;
		};
	};
	return \%hash;
};


sub is_process_running($)
{

=head2 is_process_running

Verify if a process is running or not.

	$utility->is_process_running($process) ? print "yes" : print "no";

$process is the name as it would appear in the process table.

=cut

	my ($self, $process) = @_;

	my $r = `ps ax | grep $process | grep -v grep`;
	$r ? return 1 : return 0;
};


sub mailtoaster(;$)
{

=head2 mailtoaster

	$utility->mailtoaster();

Downloads and installs Mail::Toaster.

=cut

	my ($self, $debug) = @_;

	my $src = "/usr/local/src";
	$self->chdir_source_dir($src);

	my $conf = $self->parse_config({file=>"toaster-watcher.conf"});
	$self->syscmd("rm -rf Mail-Toaster-*");   # nuke any old versions
	$self->get_file("http://www.tnpi.biz/internet/mail/toaster/Mail-Toaster.tar.gz");
	$self->archive_expand("Mail-Toaster.tar.gz");

	foreach my $file ( $self->get_dir_files($src) )
	{
		if ( $file =~ /Mail-Toaster-/ ) 
		{
			chdir($file);
			$self->syscmd("perl Makefile.PL");
			$self->syscmd("make test");
			if ( -e "/usr/local/etc/toaster-watcher.conf" ) {
				$self->syscmd("make conf");
			} else {
				$self->syscmd("make newconf");
			};
			unless ($conf && $conf->{'preserve_cgifiles'}) {
				$self->syscmd("make cgi");
			};
			$self->syscmd("make install");
			chdir("..");
			$self->syscmd("rm -rf $file");
			last;
		};
	};
};

sub files_diff ($$;$$)
{

=head2 files_diff

	$utility->files_diff($file1, $file2, $type, $debug);

	if ( $utility->files_diff("foo", "bar") ) 
	{ 
		print "different!\n"; 
	};

Determine if the files are different. $type is assumed to be text unless you set it otherwise. For anthing but text files, we do a MD5 checksum on the files to determine if they're different or not.

return 0 if files are the same, 1 if they are different, and -1 on error.

=cut

	my ($self, $f1, $f2, $type, $debug) = @_;

	return -1 unless (-e $f1 && -e $f2);

	$type ||= "text";

	if ($type eq "text") {
		my $diff = `diff $f1 $f2`;
		return $diff;
	} 
	else 
	{
		eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;
		$perl->module_load( {module=>"Digest::MD5", ports_name=>"p5-Digest-MD5", ports_group=>"security"} );

		my @md5sums;
	
		foreach my $f ($f1, $f2) 
		{
			my $ctx = Digest::MD5->new;
			my $sum;
			if(-f "$f.md5"){
				open(F,"$f.md5");
				my $sum=<F>;
				close(F);
				chomp$sum;
			}
			if(!-f "$f.md5" || $sum!~/[0-9a-f]+/i){
				open(F,"$f");
				$ctx->addfile(*F);
				$sum=$ctx->hexdigest;
				close(F);
			}
			push (@md5sums,$sum);
			open(F,">$f.md5");
			print F $sum;
			close(F);
		}

		if ($md5sums[0] eq $md5sums[1]) {
			return 0;
		}
		return 1;
	};
};

sub yes_or_no(;$$)
{

=head2 yes_or_no

	my $r = $utility->yes_or_no("Would you like fries with that?");

	$r ? print "fries are in the bag\n" : print "no fries!\n";

There are two optional arguments that can be passed. The first is a string which is the question to ask. The second is an integer representing how long (in seconds) to wait before timing out.

returns 1 on yes, 0 on negative or null response.

=cut

	my ($self, $question, $timer) = @_;
	my $ans;

	if ($question) {;
		return 1 if ( $question eq "test");
		print "\n\t\t$question";
	};

	print "\n\nYou have $timer seconds to respond: " if $timer;

	# should check for Term::Readkey and use it

	if ($timer) {
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" };
			alarm $timer;
			do {
				print "(y/n): ";
				$ans = lc(<STDIN>); chomp($ans);
			} until ( $ans eq "n" || $ans eq "y" );
			alarm 0;
		};

		if ($@) { 
			($@ eq "alarm\n") ? print "timed out!\n" : carp;  # propagate unexpected errors
		};

		$ans eq "y" ? return 1 : return 0;
	};

	do {
		print "(y/n): ";
		$ans = lc(<STDIN>); chomp($ans);
	} until ( $ans eq "n" || $ans eq "y" );

	$ans eq "y" ? return 1 : return 0;
};

sub file_write($@)
{

=head2 file_write

	$utility->file_write ($file, @lines)

	my $file = "/tmp/foo";
	my @lines = "1", "2", "3";

	print "success" if ($utility->file_write($file, @lines));

$file is the file you want to write to
@lines is a an array, each array element is a line in the file

1 is returned on success, 0 or undef on failure

=cut

	my ($self, $file, @lines) = @_;

	if ( -d $file ) {
		print "file_write FAILURE: $file is a directory!\n";
		return 0;
	};

	if( -f $file && ! -w $file )
	{
		print "file_write FAILURE: $file is not writable!\n";
		return 0;
	}

	unless ( open FILE, ">$file" )
	{
		carp "file_write: couldn't open $file: $!";
		return 0;
	};

	for (@lines) { print FILE "$_\n" };
	close FILE;

	return 1;
};

sub file_read($)
{
	my ($self, $file) = @_;

=head2 file_read

	my @lines = $utility->file_read($file)

Reads in a file, and returns an array with the files contents, one line per array element. All lines in array are chomped.

=cut

	unless ( -e $file ) {
		carp "file_read: $file does not exist!\n";
		return if defined wantarray;     # error checking is likely done by caller
		die "FATAL: file_read could not find $file: $!\n";
	};

	unless ( -r $file ) {
		carp "file_read: $file is not readable!\n";
		return if defined wantarray;     # error checking is likely done by caller
		die "FATAL: file_read could not find $file: $!\n";
	};

	open(FILE, $file) or carp "file_read: couldn't open $file: $!";
	my @lines = <FILE>;
	close FILE;

	chomp @lines;
	return @lines;
};

sub find_the_bin($;$)
{
	my ($self, $bin, $dir) = @_;

=head2 find_the_bin

	$utility->find_the_bin($bin, $dir);

	my $apachectl = $utility->find_the_bin("apachectl", "/usr/local/sbin")

Check all the "normal" locations for a binary that should be on the system and returns the full path to the binary. Return zero if we can't find it.

If the optional $dir is sent, then check that directory first.

=cut

	my $prefix = "/usr/local";
  
	if    ( $dir && -x "$dir/$bin"      ) { return "$dir/$bin"; };

	if    ( -x "$prefix/bin/$bin"       ) { return "/usr/local/bin/$bin";  }
	elsif ( -x "$prefix/sbin/$bin"      ) { return "/usr/local/sbin/$bin"; }
	elsif ( -x "$prefix/mysql/bin/$bin" ) { return "$prefix/mysql/bin/$bin"; }
	elsif ( -x "/bin/$bin"              ) { return "/bin/$bin";            }
	elsif ( -x "/usr/bin/$bin"          ) { return "/usr/bin/$bin";        }
	elsif ( -x "/sbin/$bin"             ) { return "/sbin/$bin";           }
	elsif ( -x "/usr/sbin/$bin"         ) { return "/usr/sbin/$bin";       }
	elsif ( -x "/opt/local/bin/$bin"    ) { return "/opt/local/bin/$bin";  }
	else  { return };
};

sub syscmd($;$)
{
	my ($self, $cmd, $fatal) = @_;

=head2 syscmd

Just a little wrapper around system calls, that returns any failure codes and prints out the error(s) if present.

	my $r = $utility->syscmd($cmd)

	print "syscmd: error result: $r\n" if ($r);

return is the exit status of the program you called.

=cut

	my $r = system $cmd;

	if ($? == -1) {
		print "syscmd: $cmd\n";
		print "failed to execute: $!\n";
	}
	elsif ($? & 127) {
		print "syscmd: $cmd\n";
		printf "child died with signal %d, %s coredump\n",
		($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
		# all is likely well
		#printf "child exited with value %d\n", $? >> 8;
	}

	if ($r != 0)
	{
		print "syscmd: $cmd\n";

		if ( defined $fatal && $fatal ) { croak "syscmd: result: $r\n"; } 
		else                            { print "syscmd: result: $r\n"; };
	};    

	return $r;
};


=head2 file_archive

	$utility->file_archive ($file)

Make a backup copy of a file by copying the file to $file.timestamp.

=cut

sub file_archive($)
{
	my ($self, $file) = @_;
	my $date = time;

	if ( $< != 0 )  # we're not root
	{
		my $sudo = $self->find_the_bin("sudo");
		my $cp   = $self->find_the_bin("cp");
		$self->syscmd( "$sudo cp $file $file.$date");
	} 
	else 
	{
		use File::Copy;
		copy($file, "$file\.$date") or croak "backup of $file to $file.$date failed: $!\n";
	};

	print "file_archive: $file backed up to $file.$date\n";
};

sub get_dir_files($;$)
{

=head2 get_dir_files

	$utility->get_dir_files($dir, $debug)

$dir is a directory. The return will be an array of files names contained in that directory.

=cut

	my ($self, $dir, $debug) = @_;
	my @files;

	opendir(D, $dir) or croak "get_dir_files: couldn't open $dir: $!";
	while( defined ( my $f = readdir(D) ) )
	{
		next if $f =~ /^\.\.?$/;
		push @files, "$dir/$f";
	};
	closedir(D);
	return @files;
};

sub clean_tmp_dir($)
{
	my ($self, $dir) = @_;

=head2 clean_tmp_dir

	$utility->clean_tmp_dir($dir)

$dir is a directory. Running this will empty it. Be careful!

=cut

	my @list = $self->get_dir_files($dir);
	chdir ($dir);
	foreach my $e (@list)
	{
		if ( -f $e )
		{
			$self->file_delete($e);
		}
		elsif ( -d $e )
		{
			use File::Path;
			rmtree $e or croak "CleanTmpdir: couldn't delete $e\n";
		};
	};
};

sub file_delete($;$)
{       

=head2 file_delete

Deletes a file. Uses unlink if we have appropriate permissions, otherwise uses a system rm call, using sudo if it's not being run as root. This sub will try very hard to delete the file!

	$utility->file_delete($file, $warn);

Arguments are a file path and $warn is an optional boolean.

returns 1 for success, 0 for failure.

=cut

	my ($self, $file, $warn) = @_;

	unless ( -e $file ) {
		print "WARNING: $file to delete does not exist!\n";
		return 0;
	};

	if ( -w $file ) {  # we have write permissions on the file
		if ( $warn ) {
			unlink $file or croak "FATAL: couldn't delete $file: $!\n";
		} else {
			unlink $file or carp "WARNING: couldn't delete $file: $!\n";
		};
	} 
	else {
		my $rm = $self->find_the_bin("rm");
		if ( $< == 0 ) {   # we're running as root
			$self->syscmd("$rm -f $file");
		} else {
			my $sudo = $self->sudo();
			$self->syscmd("$sudo $rm -f $file");
		};
	}

	(-e $file) ? return 0 : return 1;
};

sub get_the_date(;$$)
{
	my ($self, $bump, $debug) = @_;

=head2 get_the_date

	$utility->get_the_date ($bump, $debug)

$bump is the optional offset (in seconds) to subtract from the date.

returned is an array:

	$dd = day
	$mm = month
	$yy = year
	$lm = last month
	$hh = hours
	$mn = minutes
	$ss = seconds

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = $utility->get_the_date();

=cut

	eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;
	$perl->module_load( {module=>"Date::Format", ports_name=>"p5-TimeDate", ports_group=>"devel"} );

	if ($bump) 
	{
		$bump  = $bump * 86400;
		my $ss = Date::Format::time2str("%S", ( time                   ));
		my $mn = Date::Format::time2str("%M", ( time                   ));
		my $hh = Date::Format::time2str("%H", ( time - (        $bump) ));
		my $dd = Date::Format::time2str("%d", ( time - (        $bump) ));
		my $mm = Date::Format::time2str("%m", ( time - (        $bump) ));
		my $yy = Date::Format::time2str("%Y", ( time - (        $bump) ));
		my $lm = Date::Format::time2str("%m", ( time - (2592000+$bump) ));

		print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
		return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
	}
	else
	{
		my $ss = Date::Format::time2str("%S", (time          ));
		my $mn = Date::Format::time2str("%M", (time          ));
		my $hh = Date::Format::time2str("%H", (time          ));
		my $dd = Date::Format::time2str("%d", (time          ));
		my $mm = Date::Format::time2str("%m", (time          ));
		my $yy = Date::Format::time2str("%Y", (time          ));
		my $lm = Date::Format::time2str("%m", (time - 2592000));
		print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
		return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
	};
};

sub get_file($;$)
{

=head2 get_file

	use Mail::Toaster::Utility;
	my $utility = new Mail::Toaster::Utility;

	$utility->get_file($url, $debug);

Use an appropriate URL fetching utility (fetch, curl, wget, etc) based on your OS to download a file from the $url handed to us. 

Returns 1 for success, 0 for failure.

=cut

	my ($self, $url, $debug) = @_;
	my ($fetchbin, $fetchcmd);

	print "get_file: fetching $url\n" if $debug;

	if ( $os eq "freebsd" )
	{
		$fetchbin = $self->find_the_bin("fetch");
		$fetchcmd = "$fetchbin $url";
	}
	elsif ( $os eq "darwin" )
	{
		$fetchbin = $self->find_the_bin("curl");
		$fetchcmd = "$fetchbin -O $url";
	}
	else
	{
		$fetchbin = $self->find_the_bin("wget");
		$fetchcmd = "$fetchbin $url";
	};

	my $r = $self->syscmd($fetchcmd);

	if ( $r != 0 )
	{
		print "get_file error executing $fetchcmd\n";
		print "get_file error result:  $r\n";
		return 0;
	};

	return 1;
};

=head2 answer

	use Mail::Toaster::Utility;
	my $utility = Mail::Toaster::Utility->new();

	my $answer = $utility->answer("question", $default, $timer)

arguments:
 $q is the question
 $default is an optional default answer.
 $timer is how long (in seconds) to wait for a response

returned is a string. If the user responded, their response is returned. If not, then the default response is returned. If no default was supplied, 0 is returned.

=cut

sub answer
{
	my ($self, $q, $default, $timer) = @_;
	my $ans;

	if ($default) { print "Please enter $q. ($default) :" }
	else          { print "Please enter $q: "             };

	if ($timer) {
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" };
			alarm $timer;
			$ans = <STDIN>;
			alarm 0;
		};
		if ($@) { 
			($@ eq "alarm\n") ? print "timed out!\n" : carp;  # propagate unexpected errors
		};
	} 
	else {
		$ans = <STDIN>;
	}

	chomp $ans;

	if ($ans ne "") { return $ans; }
	else
	{
		return ($default) if $default;
		return 0;
	};
};

sub file_append($$)
{
	my ($self, $file, $lines) = @_;

=head2 file_append

	$utility->file_append($file, $lines)

Pass a filename and an array ref and it'll append the array contents to the file. It's that simple.

=cut

	unless ( open FILE, ">>$file" )
	{
		carp "file_append: couldn't open: $!";
		return 0;
	};

	foreach my $line (@$lines)
	{
		print FILE "$line\n";
	};

	close FILE;
	return 1;
};

sub logfile_append($$)
{
	my ($self, $file, $lines) = @_;

=head2 logfile_append

	$utility->logfile_append($file, \@lines)

Pass a filename and an array ref and it'll append a timestamp and the array contents to the file. Here's a working example:

	$utility->logfile_append($file, ["proggy", "Starting up", "Shutting down"] )

That will append a line like this to the log file:

   2004-11-12 23:20:06 proggy Starting up
   2004-11-12 23:20:06 proggy Shutting down

=cut

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = get_the_date();
	my $prog = shift @$lines;

	unless ( open FILE, ">>$file" ) {
		carp "logfile_append: couldn't open $file: $!";
		return {error_code=>500, error_desc=>"couldn't open $file: $!"};
	};

	print FILE "$yy-$mm-$dd $hh:$mn:$ss $prog ";

	foreach my $line (@$lines)
	{
		print FILE "$line ";
	};

	print FILE "\n";
	close FILE;

	return { error_code=>200, error_desc=>"file append success" };
};

sub chdir_source_dir($;$)
{

=head2 chdir_source_dir

	$utility->chdir_source_dir("/usr/local/src");

changes your working directory to the supplied one. Creates it if it doesn't exist.

returns 1 on success

=cut

	my ($self, $dir, $src) = @_;

	if ( $src ) 
	{
		unless ( -e $src )
		{
			mkdir($src, 0755);
			unless ( -d $src ) 
			{
				print "chdir_source_dir: mkdir failed! trying with mkdir -p....";
				$self->syscmd("mkdir -p $src");
				unless ( -d $src ) { croak "Couldn't create $src.\n"; };
			};
		} 
		else 
		{
			unless (-d $src)
			{
				croak "Something (other than a directory) is at $src and that's my build directory. Please remove it and try again!\n";
			};
		};
	};

	unless ( -d $dir ) { mkdir($dir, 0755) or croak "chdir_source_dir: FAILED to create $dir: $!\n"; };

	chdir($dir) or croak "chdir_source_dir: FAILED to cd to $dir: $!\n";
	return 1;
}; 

sub source_warning($;$$)
{

=head2 source_warning

    if ( -d $package )
    {
        unless ( $utility->source_warning($package, 1, $src) )
        { 
            carp "OK then, skipping install.\n";
            exit 0;
        };
    };

Just check to see if the sources are present. If they are, offer to remove them.

returns 1 if removed.

=cut

	my ($self, $package, $clean, $src) = @_;

	$src ||= "/usr/local/src";

	print "\n$package sources are already present, indicating that you've already\n";
	print "installed $package. If you want to reinstall it, remove the existing\n";
	print "sources (rm -r $src/mail/$package) and re-run this script\n\n";

	return 0 unless $clean;

	if ( $self->yes_or_no("\n\tWould you like me to remove the sources for you? ") )
	{
		print "Deleting $package...";
		rmtree $package;
		print "done.\n";
		return 1;
	} 
	else 
	{
		return 0;
	};
};

sub parse_config($)
{
	my ($self, $vals) = @_;

=head2 parse_config

	$conf = $utility->parse_config( { 
		file   => $file, 
		debug  => $debug, 
		etcdir => $etcdir,
	} )

pass parse_config a hashref. $file is the file to be parsed. $etcdir is where the file should be found. It defaults to /usr/local/etc and will also check the current working directory. 

A hashref is returned with the key/value pairs.

=cut

	my $file = $vals->{'file'};

	my $etcdir = $vals->{'etcdir'};  $etcdir ||= "/usr/local/etc";

	if ( -r "$etcdir/$file" )
	{
		$file = "$etcdir/$file" 
	} 
	else 
	{
		if ( -r "./$file" )
		{
			$file = "./$file" 
		} 
		else { $file = "./$file-dist" if ( -r "./$file-dist" ); };
	};

	unless ( -r $file) 
	{
		carp "WARNING: parse_config: can't read $file!\n";
		return 0;
	};

	my (%array);

	print "parse_config: $file\n" if $vals->{'debug'};
	open(CONFIG, $file) or carp "WARNING: Can't open $file: $!";

	while ( <CONFIG> ) 
	{
		chomp;
		next if /^#/;       # skip lines beginning with #
		next if /^[\s+]?$/;    # skip empty lines
		print "$_ \n" if $vals->{'debug'};

		# this regexp must match and return these patterns
		# localhost1  = localhost, disk, da0, disk_da0
		# htmldir = /usr/local/rrdutil/html
		# hosts   = localhost lab.simerson.net seattle.simerson.net

		my ($key, $val) = $_ =~ /\s*(.*?)\s*=\s*(.*)\s*$/;
		if ($val && $val =~ /#/) { ($val) = $val =~ /(.*?\S)\s*#/ };

		print "$key. \t\t = .$val. \n" if $vals->{'debug'};

		$array{$key} = $val if $key;
#		$array{$key} = $val if $val;
	};

	close(CONFIG);
	return \%array;
};


=head2	sudo

	my $sudo = $utility->sudo();

	$utility->syscmd("$sudo rm /etc/root-owned-file");

Often you want to run a script as an unprivileged user. However, the script may need elevated privileges for a plethora of reasons. Rather than running the script suid, or as root, configure sudo allowing the script to run system commands with appropriate permissions.

If sudo is not installed and you're running as root, it'll offer to install sudo for you. This is recommended, as is properly configuring sudo.

=cut

sub sudo()    
{
	my $self = shift;
	my $sudo;

	my $sudobin = $self->find_the_bin("sudo");

	if ( -x $sudobin ) {    # sudo is installed
		if ( $< eq 0 ) {    # we are root
			return $sudo;   # return an empty string for $sudo
		} 
		else {
			return "$sudobin -p 'Password for %u@%h:'";
		}
	};

	# try installing sudo
	if ( $< eq 0 )
	{
		if ( $self->yes_or_no("sudo is not installed, shall I try to install it?" ) )
		{
			if ( $os eq "freebsd" )
			{
				eval { require Mail::Toaster::FreeBSD };
				if ($@) {
					print "couldn't load Mail::Toaster::FreeBSD!: $@\n";
					print "skipping port install attempt\n";
				} 
				else {
					my $freebsd = Mail::Toaster::FreeBSD->new();
					$freebsd->port_install("sudo", "security");
					$sudobin = $self->find_the_bin("sudo");
				};
			} 
			else 
			{
				# try installing from sources!
				my $vals = { package => 'sudo-1.6.8p2',
						site    => 'http://www.courtesan.com',
						url     => '/sudo/',
						targets => ['./configure', 'make', 'make install'],
						patches => '',
						debug   => 1,
				};
				$self->install_from_source(undef, $vals);
			};
			return "$sudobin -p 'Password for %u@%h:'" if ( -x $sudobin );
			carp "sudo installation failed!\n";
		}
		else
		{    
			print "very well then, skipping along.\n";
		};
	} 
	else 
	{
		print "\n\n\tWARNING: Couldn't find sudo. Some features require root ";
		print "permissions and will not work without it. You have been warned!\n\n";
	};

	return $sudo;
};

1;
__END__


=head1 AUTHOR

	Matt Simerson <matt@cadillac.net>

=head1 BUGS

	None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

	http://www.tnpi.biz/internet/www/logmonster


=head1 COPYRIGHT

Copyright 2003-2004, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

