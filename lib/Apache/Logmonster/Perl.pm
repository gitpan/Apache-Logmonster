#!/usr/bin/perl
use strict;

#
# $Id: Perl.pm,v 1.1 2005/02/05 18:30:38 matt Exp $
#

package Apache::Logmonster::Perl;

use Carp;
use vars qw($VERSION);

$VERSION = '4.07';

my $os = $^O;

use lib "lib";
use lib "../..";
require Apache::Logmonster::Utility; my $utility = new Apache::Logmonster::Utility;

=head1 NAME

Apache::Logmonster::Perl

=head1 SYNOPSIS

Perl functions for working with perl and loading modules.


=head1 DESCRIPTION

Apache::Logmonster::Perl is a few frequently used functions that make dealing with perl and perl modules a little more managable. The following methods are available:

	check       - checks perl version
	install     - installs perl
	module_load - loads a perl module (attempts to install if missing)

See the description for each method below.

=head1 METHODS

=head2 new

To use a a method in this class, you must first request a Apache::Logmonster::Perl object:

  use Apache::Logmonster::Perl;
  my $perl = Apache::Logmonster::Perl->new();

You can then call subsequent methods with $perl->method();

=cut


sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};



=head2 check

Checks perl to make sure the version is higher than a minimum (supplied) value.

   $perl->check($vals);

Input is a hashref with at least the following values set: min. If min is unset, it defaults to 5.6.1 (5.006001).

   $perl->check( {min=>5.006001} );

returns 1 for success, 0 for failure.

=cut

sub check
{
	my ($self, $vals) = @_;

	my $min   = $vals->{'min'};   $min   ||= 5.006001;
	my $timer = $vals->{'timer'}; $timer ||= 60;
	my $debug = $vals->{'debug'};

	unless ($] < $min) {
		print "using Perl " . $] . " which is current enough, skipping.\n" if $debug;
		return 1;
	};

	# we probably can't install anything unless we're root
	return 0 unless ( $< eq 0 );

	warn qq{\a\a\a
**************************************************************************
**************************************************************************
  Version $] of perl is NOT SUPPORTED by several mail toaster components. 
  You should strongly consider upgrading perl before continuing.  Perl 
  version 5.6.1 is the lowest version supported.

  Press return to begin upgrading your perl... (or Control-C to cancel)
**************************************************************************
**************************************************************************
	};

	print "You have two choices: perl 5.6.x or perl 5.8.x. I recommend that if you upgrade
to perl 5.8.x as it's already quite stable, in widespread use, and many of the new perl programs
such as SpamAssassin require it for full functionality.";

	my $version = "perl-5.6";
	if ( $utility->yes_or_no("Would you like me to install 5.8?"), 5 ) {
		$version = "perl-5.8";
	};

	$self->perl_install( {version=>$version} );
};


=head2 module_install

Downloads and installs a perl module from sources.

    $perl->module_install($vals, $conf);

$vals is a hashref with the following values:

    module  - module name          (CGI)
    archive - archived module name (CGI-1.35.tar.gz)
    site    - site to download from
    url     - path to downloads on site
    targets - build targets: 
    
    
The values get concatenated to a url like this: $site/$url/$module.tar.gz

$conf is toaster-watcher.conf settings and is optional.

Once downloaded, we expand the archive and attempt to build it. You can optionally pass build targets but if you don't, the default targets are: make, make test, and make install. After install, we clean up the sources and exit. 

This method builds from sources only. Compare to module_load which will attempt to build from FreeBSD ports, CPAN, and then finally resort to sources if all else fails.

returns 1 for success, 0 for failure.

Example:

 my $vals = {
    module   => 'Mail-Toaster',
    archive  => 'Mail-Toaster-4.01.tar.gz',
    site     => 'http://www.tnpi.biz',
    url      => '/internet/mail/toaster/src',
    targets  => ['perl Makefile.PL', 'make install'],
 };

 $perl->module_install($vals);

=cut

sub module_install($;$)
{
	my ($self, $vals, $conf) = @_;

	my $module = $vals->{'module'};

	my $src = $conf->{'toaster_src_dir'}; $src ||= "/usr/local/src";
	$utility->chdir_source_dir($src);

	#$utility->syscmd("rm -rf $module-*");   # nuke any old versions

	my $site = $vals->{'site'};
	$site ||= $conf->{'toaster_dl_site'};
	$site ||= "http://www.tnpi.biz";

	my $url = $vals->{'url'};
	$url ||= $conf->{'toaster_dl_url'}; 
	$url ||= "/internet/mail/toaster";

	my $archive = $vals->{'archive'};
	if ( $archive ) { 
		if ( -e $archive ) {
			print "using existing archive: $archive\n";
		} else {
			print "trying to fetch $site/$url/$archive\n";
			$utility->get_file("$site/$url/$archive");
			unless ( -e $archive ) { $utility->get_file("$site/$url/$archive.tar.gz"); };
			unless ( -e $archive ) { $utility->get_file("$site/$url/$module.tar.gz");  };
		};
	} else {
		print "trying to fetch $site/$url/$module.tar.gz\n";
		$utility->get_file("$site/$url/$module.tar.gz");
		unless ( -e "$module.tar.gz" ) {
			print "FAILED: I don't know how to fetch $module\n";
			return 0;
		};
	}

	print "checking for previous build sources.\n";
	if ( -d $module ) {
		unless ( $utility->source_warning($module, 1, $src) )
		{
			carp "\nmodule_install: OK then, skipping install.\n";
			return 0;
		}
		else {
			$utility->syscmd("rm -rf $module");
		};
	};

	if ( -e $archive ) {
		print "decompressing $archive\n";
		$utility->archive_expand($archive);
	} else {
		if ( -e "$module.tar.gz" ) {
			$utility->archive_expand("$module.tar.gz");
		} else {
			print "FAILED: couldn't find $module sources.\n";
		}
	}

	my $found;
	print "looking for $module in $src...";
	foreach my $file ( $utility->get_dir_files($src) )
	{
		if ( $file =~ /$module-/ || $file =~ /$module/ ) 
		{
			next unless -d $file;

			print "found: $file\n";
			$found++;
			chdir($file);

			my $targets = $vals->{'targets'};
			unless ( @$targets[0] )
			{
				print "module_install: using default targets.\n";
				@$targets = ( "perl Makefile.PL", "make", "make install")
			};

			print "installing with targets " . join(", ", @$targets) . "\n";
			foreach ( @$targets ) {
				return 0 if $utility->syscmd($_);
			};

			chdir("..");
			$utility->syscmd("rm -rf $file");
			last;
		};
	};

	$found ? return 1 : return 0;
};

=head2 module_load

    $perl->module_load( $hashref );

Loads a required Perl module. If the load fails, we attempt to install the required module (rather than failing gracelessly).

Input is a  hashref which uses the following values:

    module      - the name of the module: (ie. LWP::UserAgent)
    ports_name  - is the name of the FreeBSD port
    ports_group - is is the ports group ( "ls /usr/ports" to see groups)
    warn        - if set, we warn instead of dying upon failure
    timer       - how long (in seconds) to wait for user input (default 60)
    site        - site to download sources from
    url         - url at site (see module_install)
    archive     - downloadable archive name (module-1.03.tar.gz)

returns 1 for success, 0 for failure.

=cut

sub module_load($)
{
	my ($self, $vals) = @_;    # was: my ($mod, $name, $dir, $warn) = @_;

	unless ( $vals && $vals->{'module'} ) {
		croak "Sorry, you called module_load incorrectly!\n";
	};

	my $mod   = $vals->{'module'};
	my $name  = $vals->{'ports_name'};
	my $dir   = $vals->{'ports_group'};
	my $warn  = $vals->{'warn'};
	my $timer = $vals->{'timer'}; $timer ||= 60;

	if (eval "require $mod") 
	{
		$mod->import();
		return 1;
	};

	# we probably can't install anything unless we're root
	return 0 unless ( $< eq 0 );

	carp "\ncouldn't import $mod: $@\n";   # show error
	my $try;

	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm $timer;
		$try = $utility->yes_or_no("\n\nWould you like me to try installing $mod: ");
		alarm 0;
	};

	if ($@) {
		($@ eq "alarm\n") ? print "timed out!\n" : carp;  # propagate unexpected errors
	};

	unless ($try) {
		if ($warn) { carp "\n$mod is required, you have been warned.\n"; return 0; }
		else       { croak "\nI'm sorry, $mod is required to continue.\n" };
	};

	if ( $dir && $os eq "freebsd" && -e "/usr/ports/$dir/$name" ) 
	{
		require Mail::Toaster::FreeBSD; my $freebsd = Mail::Toaster::FreeBSD->new();
		$freebsd->port_install($name, $dir);
	}
	else {
		use CPAN;
		install "$mod";
	};

	print "testing install...";
	if (eval "require $mod") { $mod->import(); print "success.\n"; return 1; };
	print "FAILED.\n";

	# finally, try from sources if possible
	if ( $vals->{'site'} ) {
		print "trying to install from sources\n";
		$self->module_install($vals);

		print "testing install...";
		if (eval "require $mod") { $mod->import(); print "success.\n"; return 1; };
		print "FAILED.\n";
	};

	return 0;
};


=head2 perl_install

    $perl->perl_install( {version=>"perl-5.8.5"} );

currently only works on FreeBSD and Darwin (Mac OS X)

input is a hashref with the following values:

    version - perl version to install
    options - compile flags to set (comma separated list)

On FreeBSD, version is the directory name such as "perl5.8" derived from /usr/ports/lang/perl5.8. Ex: $perl->perl_install( {version=>"perl5.8"} );

On Darwin, it's the directory name of the port in Darwin Ports. Ex: $perl->perl_install( {version=>"perl-5.8"} ) because perl is installed from /usr/ports/dports/lang/perl5.8. Otherwise, it's the exact version to download and install, ex: "perl-5.8.5".

Example with option:

$perl->perl_install( {version=>"perl-5.8.5", options=>"ENABLE_SUIDPERL"} );

=cut


sub perl_install
{
	my ($self, $vals) = @_;

	my $version = $vals->{'version'};
	my $options = $vals->{'options'}; $options ||= "ENABLE_SUIDPERL";

	if ( $os eq "freebsd" ) 
	{
		{eval require Mail::Toaster::FreeBSD}; my $freebsd = Mail::Toaster::FreeBSD->new();

		my $port        = $freebsd->is_port_installed("perl");
		my $portupgrade = $utility->find_the_bin("portupgrade");

		if ($port) {
			# perl is installed from ports, upgrade is necessary
			if ( -x $portupgrade ) 
			{
				$utility->syscmd("$portupgrade $port");
				print "\n\nPerl has been upgraded. Now we must upgrade all the perl modules as well. This is going to take a while!\n\n";
				sleep 5;
				$utility->syscmd("$portupgrade -f `pkg_info | grep p5- | cut -d\" \" -f1`");
				$utility->syscmd("$portupgrade -f `pkg_info | grep rrdtool- | cut -d\" \" -f1`");
			};
		} else {
			# install perl from ports
			$freebsd->port_install ($version, "lang", "", "perl-5", $options);
			$utility->syscmd ("/usr/local/bin/use.perl port");
		};
	}
	elsif ( $os eq "darwin" )
	{
		if ( -d "/usr/ports/dports" )
		{
			$self->module_load( {module=>"Mail::Toaster::Darwin"} ); my $darwin = Mail::Toaster::Darwin->new();
			$darwin->port_install("perl5.8");
			$darwin->port_install("p5-compress-zlib");
			return 1;
		}

		# as directed at http://developer.apple.com/internet/macosx/
		
		unless ( -d "/usr/local/src") { mkdir("/usr/local/src", 0755) };
		chdir("/usr/local/src");

		$version ||= "perl-5.8.4";

		if ( $] < 5.008001 )
		{
			unless ( -e "$version.tar.gz" ) {
				$utility->get_file("ftp://ftp.perl.org/pub/CPAN/src/$version.tar.gz");
			};

			if ( -d $version )
			{
				my $r = $utility->source_warning($version, 1);
			};
			my $tar = $utility->find_the_bin("tar");
			$utility->syscmd("$tar -xzf $version.tar.gz");

			chdir($version);
			my $replace = $utility->yes_or_no("\n\n    NOTICE!   \n
Apple installs Perl in /usr/bin. I can install it there as well, overwriting Darwin's
supplied Perl (5.6.0) or it can be installed in /usr/local/bin (The BSD Way). Some
would feel that's safer as it leaves Darwin's distributed version of Perl in tact. I
would suggest that's apt to cause you grief later.\n

Shall I overwrite the default Perl?");

			if ( $replace ) { $utility->syscmd("./Configure -de -Dprefix=/usr"); } 
			else            { $utility->syscmd("./Configure -de");               };
	
			$utility->syscmd("make");
			$utility->syscmd("make test");

			my $install = $utility->yes_or_no("\n\n
OK, I just finished running \"make test\" and the results are show above. You should see
a success rate somewhere along the lines of 99.7% okay with only a couple failures. If that's
the case, just feed me a y and I'll install perl for you. Select n to cancel.\n\n");

			return unless $install;

			my $sudo = "";
			if ( $< ne "0" ) { $sudo = "/usr/bin/sudo -p 'Password for %u@%h:'"; };
	
			if ($replace) 
			{
				# while this code isn't critical, it will fix the problem
				# posted here: http://dev.perl.org/perl5/news/2002/07/18/580ann/perldelta.html#mac%20os%20x%20dyld%20undefined%20symbols
				use File::Copy;
				my $file = "/Library/Perl/darwin/CORE/libperl.dylib";
				if ( -e $file ) {
					move($file, "$file.old") or carp "failed to remove $file\n";
				};
				$file = "/System/Library/Perl/darwin/CORE/libperl.dylib";
				if ( -e $file ) {
					move($file, "$file.old") or carp "failed to remove $file\n";
				};
				$utility->syscmd("$sudo find /Library/Perl -name '*.bundle' -exec rm {} \;");
				$utility->syscmd("$sudo find /System/Library/Perl -name '*.bundle' -exec rm {} \;");
			};
			$utility->syscmd("$sudo make install");
		};
	};
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

=head1 COPYRIGHT

Copyright (c) 2003-2004, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut


