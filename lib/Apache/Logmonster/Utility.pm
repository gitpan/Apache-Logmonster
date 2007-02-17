#!/usr/bin/perl
use strict;
use warnings;
#use diagnostics;

#
# $Id: Utility.pm 538 2007-02-16 20:20:23Z matt $
#

package Apache::Logmonster::Utility;

use Cwd;
use Carp;
use English qw( -no_match_vars );
use File::Copy;
use Params::Validate qw(:all);
use Scalar::Util qw( openhandle );
#use Smart::Comments;

use vars qw($VERSION $fatal_err $err);
$VERSION = '5.05';

use lib "inc";
use lib "lib";

sub new {
    my ( $class, $name ) = @_;
    my $self = { name => $name };
    bless( $self, $class );
    return $self;
}

sub answer {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'question' => { type=>SCALAR, optional=>1 },
            'q'        => { type=>SCALAR, optional=>1 },
            'default'  => { type=>SCALAR, optional=>1 },
            'timeout'  => { type=>SCALAR, optional=>1 },
            'test_ok'  => { type=>BOOLEAN, optional=>1 },
        }
    );

    my $question = $p{'question'};
    my $default  = $p{'default'};
    my $timeout  = $p{'timeout'};

    # q is an alias for question
    if ( !defined $question && defined $p{'q'} ) { $question = $p{'q'}; }

    # this sub is useless without a question.
    unless ($question) {
        croak "question called incorrectly. RTFM. \n";
    }
    
    # only propmpt if we are running interactively
    unless ( $self->is_interactive() ) {
        warn "     not interactive, can not prompt!\n";
        return $default;
    }

    # some basic input validation
    #if ( $question !~ m{^([-\@\w\d. \(\)\!]+)$} ) {
    if ( $question !~ m{\A \p{Any}* \z}xms ) {
        croak "question called with \'$question\' which looks unsafe. FATAL.\n";
        return;
    }

    my ($response);

    if ( defined $p{'test_ok'}) { return $p{'test_ok'} };
    
    print "Please enter $question: ";
    print "($default) : " if $default;

    #    if ($default) { print "Please enter $question. ($default) :" }
    #    else          { print "Please enter $question: "; }

    if ($timeout) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            $response = <STDIN>;
            alarm 0;
        };
        if ($EVAL_ERROR) {
            ( $EVAL_ERROR eq "alarm\n" ) 
              ? print "timed out!\n"
              : carp;    # propagate unexpected errors
        }
    }
    else { 
        $response = <STDIN>;
    }

    chomp $response;

    # if they typed something, return it
    return $response if ( $response ne "" );
    
    # otherwise, return the default if available
    return $default if $default;
    
    # and finally return empty handed
    return "";
}

sub archive_expand {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'archive' => { type=>SCALAR, optional=>0, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1},
        }
    );

    my ( $archive, $fatal, $debug, $test_ok ) = 
        ($p{'archive'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    my ($r);

    if ( ! -e $archive ) {
        if    ( -e "$archive.tar.gz" )  { $archive = "$archive.tar.gz" }
        elsif ( -e "$archive.tgz" )     { $archive = "$archive.tgz" }
        elsif ( -e "$archive.tar.bz2" ) { $archive = "$archive.tar.bz2" }
        else {
            $self->_formatted( "archive_expand: file $archive is missing!",
                "FAILED" );
            croak if $fatal;
            return 0;
        }
    }
    
    if ($debug) {
        my $message = "archive_expand: looking for $archive" ;
        -e $archive ? $self->_formatted($message, "ok") 
                    : $self->_formatted($message, "FAILED");
    };
    
    $ENV{PATH} = '/bin:/usr/bin';   # do this or taint checks will blow up on ``

    unless ( $archive =~ /[bz2|gz]$/ ) {
        print "archive_expand: FAILED: I don't know how to expand $archive!\n";
        croak if $fatal;
        return 0;
    }

    # find these binaries, we need them to decompress the archive
    my $tar  = $self->find_the_bin( program => 'tar',  debug => $debug );
    my $file = $self->find_the_bin( program => 'file', debug => $debug );
    my $grep = $self->find_the_bin( program => 'grep', debug => $debug );

    if ( $archive =~ /bz2$/ ) {

        # Check to make sure the archive contents match the file extension
        # this shouldn't be necessary but the world isn't perfect. Sigh.

        # file $file on BSD yields bunzip2, on Linux bzip2
        unless ( `$file $archive | $grep bunzip2`
            or `$file $archive | $grep bzip2` )
        {
            print $self->_formatted(
                "archive_expand: $archive not a bz2 compressed file", "ERROR" );
            croak if $fatal;
            return;
        }

        my $bunzip2 =
          $self->find_the_bin( program => 'bunzip2', debug => $debug );

        if (
            $self->syscmd(
                command => "$bunzip2 -c $archive | $tar -xf -",
                debug   => 0
            )
          )
        {
            print $self->_formatted( "archive_expand: extracting $archive",
                "ok" )
              if $debug;
            return 1;
        }

        print $self->_formatted( "archive_expand: extracting $archive",
            "FAILED" );
        croak if $fatal;
        return 0;
    }
    elsif ( $archive =~ /gz$/ ) {

        # use 'file' to determine if the archive is the right type
        unless (`$file $archive | $grep gzip`) {
            print $self->_formatted(
                "archive_expand: $archive not a gzip compressed file",
                "ERROR" );
            croak if $fatal;
            return 0;
        }

        # find gunzip binary
        # would be a good place to check for presense of Compress::Zlib instead
        my $gunzip =
          $self->find_the_bin( program => 'gunzip', debug => $debug );
        if (
            $self->syscmd(
                command => "$gunzip -c $archive | $tar -xf -",
                debug   => 0
            )
          )
        {
            print $self->_formatted( "archive_expand: extracting $archive",
                "ok" )
              if $debug;
            return 1;
        }

        print $self->_formatted( "archive_expand: extracting $archive",
            "FAILED" );
        croak if $fatal;
        return 0;
    }

    print "archive_expand: unknown error.\n" if $debug;
    return 0;
}

sub chdir_source_dir {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'dir'     => { type=>SCALAR,  optional=>0, },
            'src'     => { type=>SCALAR,  optional=>1, },
            'sudo'    => { type=>BOOLEAN, optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $src, $sudo, $fatal, $debug )
        = ($p{'dir'}, $p{'src'}, $p{'sudo'}, $p{'fatal'}, $p{'debug'});
        
    if ( -e $dir && !-d $dir ) {
        croak
"Something (other than a directory) is at $dir and that's my build directory. Please remove it and try again!\n";
    }

    if ( !-d $dir ) {

        # use the perl builtin mkdir
        try_mkdir( $dir, $debug );

        if ( !-d $dir ) {
            print "chdir_source_dir: trying again with system mkdir...\n";
            $self->mkdir_system( dir => $dir, debug=>$debug );

            if ( !-d $dir ) {
                print
"chdir_source_dir: trying one last time with $sudo mkdir -p....\n";
                $self->mkdir_system( dir => $dir, sudo => 1, debug=>$debug );
                croak "Couldn't create $dir.\n";
            }
        }
    }

    chdir($dir) or croak "chdir_source_dir: FAILED to cd to $dir: $!\n";
    return 1;

    sub try_mkdir {
        my ( $foo, $debug ) = @_;
        print "try_mkdir: trying to create $foo\n" if $debug;
        mkdir( $foo, oct("0755") )
          or carp "chdir_source_dir: mkdir $foo failed: $!";
    }
}

sub check_homedir_ownership {

    my $self = shift;
    my %p = validate (@_, {
            'auto'    => { type=>BOOLEAN, optional=>1, default=>0 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1,  },
        }
    );
 
    my ( $auto, $fatal, $debug ) 
        = ($p{'auto'}, $p{'fatal'}, $p{'debug'} );
        
    unless ( $OSNAME eq "freebsd" || $OSNAME eq "darwin" ) {
        print "FAILURE: I don't know " . $OSNAME
          . " so I'm being safe and refusing to run.\n";
        return;
    }

    my $checked = 0;
    my $updated = 0;
    my $broken  = 0;

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'} };

    # name, passwd, uid, gid, quota, comment, gcos, dir, shell
    setpwent();    # tell perl we want system passwd entries

    # iterate through all of them
    while ( my ( $name, $uid, $dir ) = ( getpwent() )[ 0, 2, 7 ] ) {
        $checked++;
        print "Checking homedir of $name\n" if $debug;

        # skip all low numbered (system) users.
        next if ( $uid < 100 );
        next if ( $name eq "nobody" );
        next if ( $uid < 210 && $OSNAME eq "darwin" );

        # skip passwd users who have no home directory
        unless ( -e $dir ) {
            print "WARNING: ${name}'s home dir: $dir, does not exist.\n";

            #&get_users_domain_list($name);
            next;
        }

       # get file attributes for the dir
       # (dev,ino,mode,nlink,uid,gid,rdev,size,atime,mtime,ctime,blksize,blocks)
        my @dir_stat = stat($dir) or croak "Couldn't stat $dir: $!\n";

        # if the home directory is NOT owned by the uid
        if ( $uid != $dir_stat[4] ) {
            $broken++;
            print
"warning: $dir should be owned by $name ($uid), it is owned by $dir_stat[4].\n";

            if ($auto) {
                $self->chown_system( dir => $dir, recurse => 1, user => $name, debug=>$debug );
                $updated++;
                next;
            }
            if (
                $self->yes_or_no(
                    question => "Would you like me to fix it? ",
                    timeout  => 8
                )
              )
            {
                $self->chown_system( dir => $dir, recurse => 1, user => $name, debug=>$debug );
                $updated++;
            }
        }
    }
    endpwent();    # all done with passwd entries

    print
"check_homedir_ownership: checked: $checked users. incorrect: $broken. repaired: $updated.\n"
      if $debug;

    return 1;
}

sub chown_system {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'         => { type=>SCALAR,  optional=>1, },
            'file_or_dir'  => { type=>SCALAR,  optional=>1, },
            'dir'          => { type=>SCALAR,  optional=>1, },
            'user'         => { type=>SCALAR,  optional=>0, },
            'group'        => { type=>SCALAR,  optional=>1, },
            'recurse'      => { type=>BOOLEAN, optional=>1, },
            'fatal'        => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'        => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $user, $group, $recurse, $fatal, $debug ) 
        = ($p{'dir'}, $p{'user'}, $p{'group'}, $p{'recurse'}, $p{'fatal'}, $p{'debug'});

    # look for file, but if missing, check file_or_dir and dir
    if    ( !$dir && defined $p{'file_or_dir'} ) { $dir = $p{'file_or_dir'} }
    elsif ( !$dir && defined $p{'file'} )        { $dir = $p{'file'}        };

    if ( !$dir ) {
        $self->_invalid_params( sub => 'chown_system' );
    }

    my $chown = $self->find_the_bin(
        program => 'chown',
        fatal   => $fatal,
        debug   => $debug,
    );

    my $cmd = $chown;
    $cmd .= " -R" if $recurse;
    $cmd .= " $user";
    $cmd .= ":$group" if $group;
    $cmd .= " $dir";

    # prepend sudo if necessary (and available)
    if ( ! -w $dir ) {
        my $sudo = $self->sudo( debug => $debug );    
        $cmd = "$sudo $cmd" if $sudo;
    };

    print "chown_system: cmd: $cmd\n" if $debug;

    if ( !$self->syscmd( command => $cmd, fatal => 0, debug => 0 ) ) {
        print "cmd: $cmd\n";
        $err = "couldn't chown with $cmd: $!";
        croak $err if $fatal;
        carp $err if $debug;
        return 0;
    }

    print "Recursively " if ( $recurse && $debug );
    print "changed $dir to be owned by $user\n\n" if $debug;
    return 1;
}

# exists solely for backwards compatability
sub check_pidfile { my $self = shift; return $self->pidfile_check(@_); }

sub clean_tmp_dir {

    my $self = shift;
    
    # parameter validation here
    my %p = validate (@_, {
            'dir'     => { type=>SCALAR,  optional=>0, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $fatal, $debug ) = ($p{'dir'}, $p{'fatal'}, $p{'debug'});

    # be a friendly program and remember where we started
    my $before = cwd;

    if ( !chdir $dir ) {
        carp "couldn't chdir to $dir: $!";
        croak if $fatal;
        return 0;
    }

    foreach ( $self->get_dir_files( dir => $dir ) ) {
        next unless $_;

        my ($file) = $_ =~ /^(.*)$/;

        print "\tdeleting file: $file\n" if $debug;

        if ( -f $file ) {
            unless ( unlink $file ) {
                $self->file_delete( file => $file,debug=>$debug );
            }
        }
        elsif ( -d $file ) {
            use File::Path;
            rmtree $file or croak "CleanTmpdir: couldn't delete $file\n";
        }
        else {
            print "What the heck is $file?\n";
        }
    }

    chdir($before);
    return 1;
}

sub drives_get_mounted {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );
 
    my %hash;

    my $mount =
      $self->find_the_bin( program => 'mount', debug => $debug, fatal => 0 );
      
    unless ( -x $mount ) {
        carp "drives_get_mounted: I couldn't find mount!";
        croak if $fatal;
        return 0;
    }

    $ENV{PATH} = "";
    foreach (`$mount`) {
        my ( $d, $m ) = $_ =~ /^(.*) on (.*) \(/;

        #		if ( $m =~ /^\// && $d =~ /^\// )  # mount drives that begin with /
        if ( $m && $m =~ /^\// )    # only mounts that begin with /
        {
            print "adding: $m \t $d\n" if $debug;
            $hash{$m} = $d;
        }
    }
    return \%hash;
}

sub file_archive {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'    => { type=>SCALAR },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'sudo'    => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my ( $file, $fatal, $debug, $try_sudo ) 
        = ($p{'file'}, $p{'fatal'}, $p{'debug'}, $p{'sudo'} );

    my $date = time;

    # see if we can write to both files (new & archive) with current user
    if ( ! -e $file ) {
        print "file_archive: the file to back up ($file) is missing!\n" if $debug;
        return 0;
    };

    if (
        $self->is_writable(
            file  => $file,
            debug => $debug,
            fatal => $fatal
        )
        && $self->is_writable(
            file  => "$file.$date",
            debug => $debug,
            fatal => $fatal
        )
      )
    {

        # since we have permission, use perl's native copy
        if ( copy( $file, "$file.$date" ) ) {
            print "file_archive: $file backed up to $file.$date\n" if $debug;
            return "$file.$date" if -e "$file.$date";
        }
    }

    # since we failed with existing permissions, try to escalate
    if ( $< != 0 )    # we're not root
    {
        if ( $try_sudo ) {
            my $sudo = $self->sudo( debug => $debug, fatal => $fatal );
            my $cp = $self->find_the_bin(
                program => 'cp',
                debug   => $debug,
                fatal   => $fatal
            );

            if ( $sudo && $cp && -x $cp ) {
                $self->syscmd( command => "$sudo $cp $file $file.$date", debug=>$debug, fatal=>$fatal );
            }
            else {
                print "file_archive: sudo or cp was missing, could not escalate.\n"
                if $debug;
            }
        };
    }

    if ( -e "$file.$date" ) {
        print "file_archive: $file backed up to $file.$date\n" if $debug;
        return "$file.$date";
    }

    croak "backup of $file to $file.$date failed: $!\n" if $fatal;
    return;
}

sub file_delete {

    my $self = shift;

    my %p = validate (@_, {
            'file'    => { type=>SCALAR },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my ( $file, $fatal, $debug ) = ($p{'file'}, $p{'fatal'}, $p{'debug'});

    my $status_message = "file_delete: checking $file existence";
    if ( -e $file ) {
        $self->_formatted($status_message, "ok") if $debug
    }
    else {
        $err = $status_message;
        croak "$err: $!" if $fatal;
        carp "$err: $!" if $debug;
        return 0;
    }

    $status_message = "file_delete: checking write permissions";
    if ( -w $file ) {
        $self->_formatted($status_message, "ok") if $debug;

        $status_message = "file_delete: deleting file $file";
        if ( unlink $file ) {
            $self->_formatted($status_message, "ok") if $debug;
            return 1;
        }
        
        $self->_formatted($status_message, "FAILED") if $debug;
        croak "\t\t $!" if $fatal;
        carp "\t\t $!";
    }
    else {
        $self->_formatted($status_message, "NO") if $debug;
    }

    $status_message = "file_delete: trying with system rm";
    my $rm = $self->find_the_bin( program => "rm", debug=>$debug );

    my $rm_command = "$rm -f $file";
    
    if ( $< != 0 ) {     # we're not running as root
        my $sudo = $self->sudo(debug=>$debug);
        $rm_command = "$sudo $rm_command";
        $status_message .= " (sudo)";
    };
    
    if ( $self->syscmd(
            command => $rm_command,
            fatal   => $fatal,
            debug   => $debug,
        )
    ) {
         $self->_formatted($status_message, "ok") if $debug;
    }
    else {
        $self->_formatted($status_message, "FAILED") if $debug;
        croak "\t\t $!" if $fatal;
        carp "\t\t $!";
    }

    -e $file ? return : return 1;
}

sub file_get {

    my $self = shift;

    my %p = validate (@_, {
            'url'     => { type=>SCALAR },
            'timeout' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my (      $url,       $timer,       $fatal,      $debug ) 
        = ($p{'url'}, $p{'timeout'}, $p{'fatal'}, $p{'debug'});
    
    my ( $fetchbin, $fetchcmd, $found );

    print "file_get: fetching $url\n" if $debug;

    if ( $OSNAME eq "freebsd" ) {
        $fetchbin = $self->find_the_bin(
            program => "fetch",
            debug   => $debug,
            fatal   => 0
        );
        if ( $fetchbin && -x $fetchbin ) { $found = "fetch" }
    }
    elsif ( $OSNAME eq "darwin" ) {
        $fetchbin =
          $self->find_the_bin( program => "curl", debug => $debug, fatal => 0 );
        if ( $fetchbin && -x $fetchbin ) { $found = "curl" }
    }

    unless ($found) {
        $fetchbin =
          $self->find_the_bin( program => "wget", debug => $debug, fatal => 0 );
        if ( $fetchbin && -x $fetchbin ) { $found = "wget"; }
    }

    unless ($found) {

        # should use LWP here if available
        print "Yikes, couldn't find wget! Please install it.\n" if $debug;
        return 0;
    }

    $fetchcmd = "$fetchbin ";

    if ( $found eq "fetch" ) {
        $fetchcmd .= "-q " unless $debug;
    }
    elsif ( $found eq "curl" ) {
        $fetchcmd .= "-O ";
        $fetchcmd .= "-s " unless $debug;
    }
    $fetchcmd .= "$url";

    my $r;

    # timeout stuff goes here.
    if ($timer) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timer;
            $r = $self->syscmd( command => $fetchcmd, debug => $debug );
            alarm 0;
        };
    }
    else {
        $r = $self->syscmd( command => $fetchcmd, debug => $debug );
    }

    if ($@) {
        ( $@ eq "alarm\n" )
          ? print "timed out!\n"
          : carp $@;    # propagate unexpected errors
    }

    if ( $r == 0 ) {
        print "file_get error executing $fetchcmd\n";
        print "file_get error result:  $r\n" if $debug;
        return 0;
    }

    return 1;
}

sub file_is_newer {

    my $self = shift;
    
    my %p = validate(@_, {
            f1  => {type=>SCALAR},
            f2  => {type=>SCALAR},
            debug => { type=>SCALAR, optional=>1, default=>1 },
        }
    );
    
    my ( $file1, $file2, $debug ) = ($p{'f1'}, $p{'f2'}, $p{'debug'} );

    # get file attributes via stat
    # (dev,ino,mode,nlink,uid,gid,rdev,size,atime,mtime,ctime,blksize,blocks)

    print "file_is_newer: checking age of $file1 and $file2\n" if $debug;

    use File::stat;
    my $stat1 = stat($file1)->mtime;
    my $stat2 = stat($file2)->mtime;

    print "\t timestamps are $stat1 and $stat2\n" if $debug;

    if ( $stat2 > $stat1 ) {
        return 1;
    }

    return 0;

    # yes, I know I could just do something quick and dirtly like:
    #
    # if ( stat($f1)[9] > stat($f2)[9] )
    #
    # but, that is not the least bit obvious to a reader of the code
    # and forces them to read the man page for stat to see what's happening
}

sub file_read {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'       => { type=>SCALAR },
            'max'        => { type=>SCALAR,  optional=>1},
            'max_lines'  => { type=>SCALAR,  optional=>1},
            'max_length' => { type=>SCALAR,  optional=>1},
            'fatal'      => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'      => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my (  $filename,      $max_lines,      $max_length,      $fatal,      $debug ) 
        = ($p{'file'}, $p{'max_lines'}, $p{'max_length'}, $p{'fatal'}, $p{'debug'});
    
    # backwards compatible shim
    if ( !$max_lines && defined $p{'max'} ) { $max_lines = $p{'max'} };
    
    unless ( -e $filename ) {
        $err = "file_read: $filename does not exist!";
        #return if defined wantarray; # error checking is likely done by caller
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    unless ( -r $filename ) {
        $err = "file_read: $filename is not readable!";
        #return if defined wantarray;   # error checking is likely done by caller
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    open my $FILE, '<', $filename or $fatal_err++;

    if ( $fatal_err ) {
        $err = "file_read: could not open $filename: $OS_ERROR";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    my ($line, @lines);

    if ($max_lines) {
        while ( my $i < $max_lines ) {
            if ( $max_length ) {
                $line = substr <$FILE>, 0, $max_length;
            } else {
                $line = <$FILE>;
            }
            push @lines, $line;
            $i++;
        }
        chomp @lines;
        close $FILE;
        return @lines;
    }

#TODO, make max_length work with slurp mode, without doing something ugly like
# reading in the entire line and then truncating it. 

    chomp( @lines = <$FILE> );
    close $FILE;

    return @lines;
}

sub file_chown {

    my $self = shift;
    
    my %p = validate (@_, {
            'file'         => { type=>SCALAR,  optional=>1, },
            'file_or_dir'  => { type=>SCALAR,  optional=>1, },
            'dir'          => { type=>SCALAR,  optional=>1, },
            'uid'          => { type=>SCALAR,  optional=>0, },
            'gid'          => { type=>SCALAR,  optional=>0, },
            'sudo'         => { type=>BOOLEAN, optional=>1, default=>0 },
            'fatal'        => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'        => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'      => { type=>BOOLEAN, optional=>1 },
        }
    );
 
    my ( $file,           $uid,      $gid,    $sudo,        $fatal,      $debug ) 
        = ($p{'file'}, $p{'uid'}, $p{'gid'}, $p{'sudo'}, $p{'fatal'}, $p{'debug'});

    # look for file, but if missing, check file_or_dir and dir
    unless ( $file ) {
        $file = defined $p{'file_or_dir'} ? $p{'file_or_dir'}
              : defined $p{'dir'}         ? $p{'dir'}
              : "";
    };

    if ( !$file ) {
        $err = "file_chown: you did not set a required parameter!";
        croak $err if $fatal;
        carp $err;
        return;
    }

    print "file_chown: preparing to chown $uid:$gid $file\n" if $debug;

    unless ( -e $file ) {
        $self->_formatted( "file_chown: file $file does not exist!", "FAILED" );
        croak if $fatal;
        return 0;
    }

    # sudo forces us to use the system chown instead of the perl builtin
    if ($sudo) {
        return $self->chown_system(
            dir   => $file,
            user  => $uid,
            group => $gid,
            fatal => $fatal,
            debug => $debug,
        );
    }

    # if uid or gid is not numeric, we convert it
    my ( $nuid, $ngid );

    if ( $uid =~ /\A[0-9]+\z/ ) { 
        $nuid = int($uid);
        carp "using $nuid from int($uid)" if $debug;
    }
    else {
        $nuid = getpwnam($uid); 
        unless ( defined $nuid ) {
            $err = "failed to get uid for $uid. FATAL!";
            croak $err if $fatal;
            carp $err if $debug;
            return;
        };
        carp "converting $uid to a number: $nuid" if $debug;
    };

    if ( $gid =~ /\A[0-9]+\z/ ) { 
        $ngid = int($gid);
        carp "using $ngid from int($gid)" if $debug;
    }
    else {
        $ngid = getgrnam($gid); 
        unless ( defined $ngid ) {
            $err = "failed to get gid for $gid. FATAL!";
            croak $err if $fatal;
            carp $err if $debug;
            return;
        };
        carp "converting $gid to a number: $ngid" if $debug;
    };

    unless ( chown $nuid, $ngid, $file ) {
        $err = "couldn't chown $file: $!";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    return 1;
}

sub file_chmod {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'         => { type=>SCALAR,  optional=>1, },
            'file_or_dir'  => { type=>SCALAR,  optional=>1, },
            'dir'          => { type=>SCALAR,  optional=>1, },
            'mode'         => { type=>SCALAR,  optional=>0, },
            'sudo'         => { type=>BOOLEAN, optional=>1, default=>0 },
            'fatal'        => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'        => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'      => { type=>BOOLEAN, optional=>1 },
        }
    );
 
    my ( $file, $mode, $sudo, $fatal, $debug ) 
        = ( $p{'file'}, $p{'mode'}, $p{'sudo'}, $p{'fatal'}, $p{'debug'} );

    # look for file, but if missing, check file_or_dir and dir
    unless ( $file ) {
        $file = defined $p{'file_or_dir'} ? $p{'file_or_dir'}
              : defined $p{'dir'}         ? $p{'dir'}
              : "";
    };

    unless ( $file ) {
        $self->_formatted("file_chmod: invalid params, see perldoc Apache::Logmonster::Utility");
        return;
    };

    if ($sudo) {
        my $chmod = $self->find_the_bin( program => 'chmod', debug => $debug );
        $sudo = $self->sudo();
        my $cmd = "$sudo $chmod $mode $file";
        print "cmd: " . $cmd . "\n" if $debug;
        if ( !$self->syscmd( command => $cmd, debug=>0 ) ) {
            $err = "couldn't chmod $file: $!\n";
            croak $err if $fatal;
            carp $err if $debug;
            return;
        }
    }

    print "file_chmod: chmod $mode $file.\n" if $debug;

    # note how we convert a string ($mode) to an octal value. Very Important!
    unless ( chmod oct($mode), $file ) {
        carp "couldn't chmod $file: $!";
        croak if $fatal;
        return;
    }
}

sub file_write {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'       => { type=>SCALAR },
            'lines'      => { type=>ARRAYREF },
            'append'     => { type=>BOOLEAN, optional=>1, default=>0 },
            'mode'       => { type=>SCALAR,  optional=>1             },
            'fatal'      => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'      => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my ( $file, $lines, $append, $fatal, $debug ) 
        = ($p{'file'}, $p{'lines'}, $p{'append'}, $p{'fatal'}, $p{'debug'});
    

    if ( -d $file ) {
        carp "file_write FAILURE: $file is a directory!" if $debug;
        croak if $fatal;
        return;
    }

    if (
        -f $file && !$self->is_writable(
            file  => $file,
            debug => $debug,
            fatal => 0,
        )
      )
    {
        $err = "file_write FAILURE: $file is not writable!";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    my $write_mode = '>';    # (over)write
    $write_mode = '>>' if $append;  # file append mode

    open my $HANDLE, $write_mode, $file or $fatal_err++;

    if ( $fatal_err ) {
        carp "file_write: couldn't open $file: $!";
        croak if $fatal;
        return;
    }

    my $m = "writing";
    $m = "appending" if $append;
    $self->_formatted( "file_write: opened $file for $m", "ok" ) if $debug;

    my $c = 0;
    for (@$lines) { chomp; print $HANDLE "$_\n"; $c++ }
    close $HANDLE or return;

    $self->_formatted( "file_write: wrote $c lines to $file", "ok" ) if $debug;

    # if a file permissions mode was passed, set it
    if ( $p{'mode'} ) {
        $self->file_chmod(file=>$file, mode=>$p{'mode'}, debug=>$debug);
    };

    return 1;
}

sub files_diff {

    my $self = shift;
    
    # parameter validation here
    my %p = validate(@_, {    
            'f1'    => { type=>SCALAR },
            'f2'    => { type=>SCALAR },
            'type'  => { type=>SCALAR,  optional=>1, default=>'text'},
            'fatal' => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug' => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
    
    my      (  $f1,     $f2,     $type,     $fatal,     $debug )
        = ( $p{'f1'},$p{'f2'},$p{'type'},$p{'fatal'},$p{'debug'} );

    unless ( -e $f1 && -e $f2 ) {
        print "files_diff: a file to compare does not exist!\n";
        croak if $fatal;
        return -1;
    }

    my ($FILE);

    if ( $type eq "text" ) {
### TODO
        # use file here to make sure files are ASCII
        #
        $self->_formatted("files_diff: comparing $f1 and $f2 using diff")
          if $debug;

        my $diff = $self->find_the_bin( program => 'diff', debug => $debug );

        my $differ = `$diff $f1 $f2`;

        chomp $differ;
        return $differ;
    }

    $self->_formatted("files_diff: comparing $f1 and $f2 using md5") if $debug;

    eval { require Digest::MD5 };
    if ($@) {
        carp "couldn't load Digest::MD5!";
        croak if $fatal;
        return 0;
    }

    $self->_formatted( "\t Digest::MD5 loaded", "ok" ) if $debug;

    my @md5sums;

  FILE: foreach my $f ( $f1, $f2 ) {
        my ( $sum, $changed );

        $self->_formatted("$f: checking md5") if $debug;

        # if the file is already there, read it in.
        if ( -f "$f.md5" ) {
            $sum = $self->file_read( file => "$f.md5" );
            $self->_formatted( "\t md5 file exists", "ok" ) if $debug;
        }

     # if the md5 file is missing, invalid, or older than the file, recompute it
        if (   !-f "$f.md5"
            or $sum !~ /[0-9a-f]+/i
            or $self->file_is_newer( f1=>"$f.md5", f2=>$f, debug=>$debug ) )
        {
            my $ctx = Digest::MD5->new;
            open $FILE, '<', $f;
            $ctx->addfile(*$FILE);
            $sum = $ctx->hexdigest;
            close($FILE);
            $changed++;
            $self->_formatted("\t created md5: $sum") if $debug;
        }

        push( @md5sums, $sum );

        # update the md5 file
        if ($changed) {
            open $FILE, '>', "$f.md5";
            print $FILE $sum;
            close $FILE;
            $self->_formatted( "\t saved md5 to $f.md5", "ok" ) if $debug;
        }
    }

    # compare the two md5 sums
    return 0 if ( $md5sums[0] eq $md5sums[1] );

    return 1;
}

sub find_config {

    my $self = shift;

    # parameter validation
    my %p = validate(@_, {
            'file'    => { type=>SCALAR, },
            'etcdir'  => { type=>SCALAR|UNDEF, optional=>1, },
            'fatal'   => { type=>SCALAR, optional=>1, default=>1 },
            'debug'   => { type=>SCALAR, optional=>1, default=>1 },
            'test_ok' => { type=>SCALAR, optional=>1, },
        }
    );

    my ( $file, $etcdir, $fatal, $debug, $test_ok ) 
        = ( $p{'file'}, $p{'etcdir'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'}, );

    print "find_config: searching for config file: $file\n" if $debug;
    
    # if both etcdir and file are given...
    if ( $etcdir && -f "$etcdir/$file" ) {

        # and the file is readable
        if ( -r "$etcdir/$file" ) { 

            # we have succeeded and are finished.
            $self->_formatted( "    found it: $etcdir/$file.","ok" ) if $debug;
            return "$etcdir/$file";
        }

        # it is not readable, we have an error
        $err = "find_config: $etcdir/$file is not readable";
        croak $err if $fatal;
        $self->_formatted( $err, "ERROR" );
        return;
    }

    # etcdir is set and the file does not exist
    if ($etcdir) {
        $err = "find_config: $etcdir/$file selected but non-existent!";
        croak $err if $fatal;
        carp $err;
        return;
    }

    # etcdir was not set, so lets go looking
    $etcdir = -e "/opt/local/etc/$file" ? "/opt/local/etc"
            : -e "/usr/local/etc/$file" ? "/usr/local/etc"
            : -e "/etc/$file"           ? "/etc"
            : "/usr/local/etc";

    # at this point, etcdir is guaranteed to be set
    if ( -r "$etcdir/$file" ) {    # if we can read it...
        $self->_formatted( "    found $etcdir/$file.", "ok" ) if $debug;
        return "$etcdir/$file";    # then we have succeeded
    }

    print "    not found in any etc dir 
        see find_config in 'perldoc Apache::Logmonster::Utility'.\n" if $debug;
    
    # try the working directory
    my $working_directory = cwd;
    if ( -r "./$file" ) {
        $self->_formatted( "    checking ./ ", "ok" ) if $debug;
        return "$working_directory/$file";
    }
    $self->_formatted( "    checking ./ ", "no" ) if $debug;

    # try $file-dist in the working dir
    if ( -r "./$file-dist" ) {
        $self->_formatted( "    found config file: ./$file-dist", "ok" )
          if $debug;
        return "$working_directory/$file-dist";
    }

    $self->_formatted( "    checking ./$file-dist", "no" ) if $debug;

    croak "could not find $file" if $fatal;
    carp "could not find $file" if $debug;
    return;
}

sub find_the_bin {

    my $self = shift;

    # parameter validation here
    my %p = validate(@_, {
            'bin'     => { type=>SCALAR, optional=>1, },
            'dir'     => { type=>SCALAR, optional=>1, },
            'fatal'   => { type=>SCALAR, optional=>1, default=>1 },
            'debug'   => { type=>SCALAR, optional=>1, default=>1 },
            'program' => { type=>SCALAR, optional=>1, },   # deprecated 
         },
    );

    my ( $bin, $dir, $fatal, $debug ) = 
        ( $p{'bin'},  $p{'dir'},  $p{'fatal'},  $p{'debug'}, );

    # expand the bin alias
    if ( !$bin && defined $p{'program'} ) { $bin = $p{'program'} }

    unless ($bin) {
        $self->_invalid_params(
            sub   => 'find_the_bin',
            debug => $debug,
            fatal => $fatal
        );
        return;
    }

    print "find_the_bin: searching for $bin\n" if $debug;

    my $prefix = "/usr/local";

    if ( $dir && -x "$dir/$bin" ) { return "$dir/$bin"; }
    if ( $bin =~ /^\// && -x $bin ) { return $bin }
    ;    # we got a full path

    if    ( -x "$prefix/bin/$bin" )       { return "/usr/local/bin/$bin"; }
    elsif ( -x "$prefix/sbin/$bin" )      { return "/usr/local/sbin/$bin"; }
    elsif ( -x "$prefix/mysql/bin/$bin" ) { return "$prefix/mysql/bin/$bin"; }
    elsif ( -x "/bin/$bin" )              { return "/bin/$bin"; }
    elsif ( -x "/usr/bin/$bin" )          { return "/usr/bin/$bin"; }
    elsif ( -x "/sbin/$bin" )             { return "/sbin/$bin"; }
    elsif ( -x "/usr/sbin/$bin" )         { return "/usr/sbin/$bin"; }
    elsif ( -x "/opt/local/bin/$bin" )    { return "/opt/local/bin/$bin"; }
    elsif ( -x "/opt/local/sbin/$bin" )   { return "/opt/local/sbin/$bin"; }
    else {
        $err = "find_the_bin: WARNING: could not find $bin";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }
}

sub fstab_list {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    my ( $program, $bin, $dir);

    if ( $OSNAME eq "darwin" ) {
        return ['fstab not used on Darwin!'];
    }

    my $fstab = "/etc/fstab";
    if ( !-e $fstab ) {
        print "fstab_list: FAILURE: $fstab does not exist!\n" if $debug;
        return;
    }

    my $grep   = $self->find_the_bin( bin => "grep", debug => 0 );
    my @fstabs = `$grep -v cdr $fstab`;

    #	foreach my $fstab (@fstabs)
    #	{}
    #		my @fields = split(" ", $fstab);
    #		#print "device: $fields[0]  mount: $fields[1]\n";
    #	{};
    #	print "\n\n END of fstabs\n\n";

    return \@fstabs;
}

sub get_dir_files {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'dir'     => { type=>SCALAR,  optional=>0, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $fatal, $debug ) = ($p{'dir'}, $p{'fatal'}, $p{'debug'});

    my @files;

    unless ( -d $dir ) {
        carp "get_dir_files: dir $dir is not a directory!";
        return;
    };

    unless ( opendir D, $dir ) {
        $err = "get_dir_files: couldn't open $dir: $!";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    while ( defined( my $f = readdir(D) ) ) {
        next if $f =~ /^\.\.?$/;
        push @files, "$dir/$f";
    }

    closedir(D);

    return @files;
}

# here for compatability
sub get_file { my $self = shift; return $self->file_get(@_) }
sub get_my_ips {

############################################
# Usage      : @list_of_ips_ref = $utility->get_my_ips();
# Purpose    : get a list of IP addresses on local interfaces
# Returns    : an arrayref of IP addresses
# Parameters : only - can be one of: first, last
#            : exclude_locahost  (all 127.0 addresses)
#            : exclude_internals (192.168, 10., 169., 172.)
#            : exclude_ipv6
# Comments   : exclude options are boolean and enabled by default.
#     tested on Mac OS X and FreeBSD

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'only'              => { type=>SCALAR,  optional=>1, default=>0 },
            'exclude_localhost' => { type=>BOOLEAN, optional=>1, default=>1 },
            'exclude_internals' => { type=>BOOLEAN, optional=>1, default=>1 },
            'exclude_ipv6'      => { type=>BOOLEAN, optional=>1, default=>1 },
            'fatal'             => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'             => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my $debug = $p{'debug'};

    my $ifconfig = $self->find_the_bin(bin=>"ifconfig", debug=>0);
    my $grep = $self->find_the_bin(bin=>"grep", debug=>0);
    my $cut  = $self->find_the_bin(bin=>"cut", debug=>0);

    my $once = 0;

    TRY:
    my $cmd = "$ifconfig | $grep inet ";

    if ( $p{'exclude_ipv6'} ) {
        $cmd .= "| $grep -v inet6 ";
    };

    $cmd .= "| $cut -d' ' -f2 ";

    if ( $p{'exclude_localhost'} ) { 
        $cmd .= "| $grep -v '^127.0.0' "  
    };

    if ( $p{'exclude_internals'} ) { 
        $cmd .= "| $grep -v '^192.168.' | $grep -v '^10.' " .
                "| $grep -v '^172.16.'  | $grep -v '^169.254.' ";
    };

    if    ( $p{'only'} eq "first" ) { 
        my $head = $self->find_the_bin(bin=>"head", debug=>0);
        $cmd .= "| $head -n1 "; 
    }
    elsif ( $p{'only'} eq "last"  ) { 
        my $tail = $self->find_the_bin(bin=>"tail", debug=>0);
        $cmd .= "| $tail -n1 "; 
    };

    #carp "get_my_ips command: $cmd" if $debug;
    my @ips = `$cmd`;
    chomp @ips;

    # this keeps us from failing if the box has only internal IP space
    if ( @ips < 1 || $ips[0] eq "" ) {
        carp "yikes, you really don't have any public IPs?!" if $debug;
        $p{'exclude_internals'} = 0;
        $once++;
        goto TRY if ( $once < 2);
    };

    return \@ips;
}

sub get_the_date {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'bump'    => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $bump, $fatal, $debug ) = ($p{'bump'}, $p{'fatal'}, $p{'debug'});

    my $time = time;
    print "time: " . time . "\n" if $debug;

    $bump = $bump ? $bump * 86400 : 0;
    my $offset_time = time - $bump;
    print "selected time: $offset_time\n" if $debug;

    # load Date::Format to get the time2str function
    eval { require Date::Format };
    if ( ! $EVAL_ERROR) {

        my $ss = Date::Format::time2str( "%S", ( $offset_time ) );
        my $mn = Date::Format::time2str( "%M", ( $offset_time ) );
        my $hh = Date::Format::time2str( "%H", ( $offset_time ) );
        my $dd = Date::Format::time2str( "%d", ( $offset_time ) );
        my $mm = Date::Format::time2str( "%m", ( $offset_time ) );
        my $yy = Date::Format::time2str( "%Y", ( $offset_time ) );
        my $lm = Date::Format::time2str( "%m", ( $offset_time - 2592000 ) );

        print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
        return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
    }
    
    #  0    1    2     3     4    5     6     7     8
    # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    #                    localtime(time);
    # 4 = month + 1   ( see perldoc localtime)
    # 5 = year + 1900     ""

    my @fields = localtime( $offset_time );

    my $ss = sprintf("%02i", $fields[0]);    # seconds
    my $mn = sprintf("%02i", $fields[1]);    # minutes
    my $hh = sprintf("%02i", $fields[2]);    # hours (24 hour clock)

    my $dd = sprintf("%02i", $fields[3]);    # day of month
    my $mm = sprintf("%02i", $fields[4]+1);  # month
    my $yy = ($fields[5]+1900);              # year

    print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
    return $dd, $mm, $yy, undef, $hh, $mn, $ss;
}

sub graceful_exit {

### TODO
    # go through provision.pm and passwd.pm and depreciate this entirely

    my ( $self, $code, $desc ) = @_;

    print "$desc\n"  if $desc;
    print "+$code\n" if $code;
    exit 1;
}

sub install_if_changed {

    my $self = shift;

    # parameter validation here

    my %p = validate( @_, {
            'newfile'  => { type=>SCALAR, optional=>0, },
            'existing' => { type=>SCALAR, optional=>0, },
            'mode'     => { type=>SCALAR, optional=>1, },
            'uid'      => { type=>SCALAR, optional=>1, },
            'gid'      => { type=>SCALAR, optional=>1, },
            'sudo'     => { type=>SCALAR, optional=>1, default=>0 },
            'notify'   => { type=>SCALAR, optional=>1, },
            'email'    => { type=>SCALAR, optional=>1, default=>'postmaster'},
            'clean'    => { type=>SCALAR, optional=>1, default=>1 },
            'archive'  => { type=>SCALAR, optional=>1, default=>0 },
            'fatal'    => { type=>SCALAR, optional=>1, default=>1 },
            'debug'    => { type=>SCALAR, optional=>1, default=>1 },
        },
    );

    my ( $newfile, $existing, $mode, $uid,
         $gid, $sudo, $notify, $email,
         $clean, $archive, $fatal, $debug )
            = ( $p{'newfile'}, $p{'existing'}, $p{'mode'},  $p{'uid'},   
                $p{'gid'}, $p{'sudo'}, $p{'notify'}, $p{'email'}, 
                $p{'clean'}, $p{'archive'}, $p{'fatal'}, $p{'debug'} );


    # make sure the new file exists and is a normal file
    unless ( -e $newfile && -f $newfile ) {
        $err = "the file to install ($newfile) does not exist, ERROR!\n";
        print $err;

        if ( $newfile !~ /\// ) {
            # relative filename given
            carp "relative filename given, use complete paths " .
                "for more predicatable results!";
 
            carp "working directory is " . cwd();
        }

        croak $err if $fatal;
        return 0;
    }

    # make sure existing and new are writable, otherwise try sudo
    if ( ! $self->is_writable(
            file  => $existing,
            debug => $debug,
            fatal => 0,
        )
        || ! $self->is_writable(
            file  => $newfile,
            debug => $debug,
            fatal => 0,
        )
    )
    {
        # if we are root and did not have permissions
        if ( $UID == 0 ) {
            # then sudo won't do us any good!
            #carp "FAILED: you are root, but you don't have write permission" .
            #    "to either $newfile or $existing. Sorry, I can't go on!\n";
            #croak if $fatal;
            return;
        }

        $sudo = $self->find_the_bin( program => 'sudo', fatal=>0, debug=>0 );
        unless ( -x $sudo ) {
            carp "FAILED: you are not root, sudo is not installed,".
                " and you don't have permission to write to ".
                " $newfile and $existing. Sorry, I can't go on!\n";
            croak if $fatal;
            return;
        }
    }

    # if the target file exists, use diff to determine the differences
    if ( -e $existing ) {
        unless (
            $self->files_diff(
                f1    => $newfile,
                f2    => $existing,
                type  => "text",
                debug => $debug
            )
          )
        {
            print "install_if_changed: $existing is already up-to-date.\n"
              if $debug;
            unlink $newfile if ($clean);
            return 2;
        }
    }

    $self->_formatted("install_if_changed: checking $existing") if $debug;

    # set file ownership on the new file
    if ( $uid && $gid ) {
        $self->file_chown(
            file_or_dir => $newfile,
            uid         => $uid,
            gid         => $gid,
            sudo        => $sudo,
            debug       => $debug,
        );
    }

    # set file permissions on the new file
    if ( $mode && -e $existing ) {
        $self->file_chmod(
            file_or_dir => $existing,
            mode        => $mode,
            sudo        => $sudo,
            debug       => $debug,
        );
    }

    # email diffs to admin
    if ($notify && -f $existing ) {
        my $diff = $self->find_the_bin( program => 'diff', debug=>$debug );

        eval { require Mail::Send; };

        if ( $EVAL_ERROR ) {
            carp "ERROR: could not send notice, Mail::Send is not installed!";
#            croak if $fatal;
            goto EMAIL_SKIPPED;
        };

        my $msg = Mail::Send->new;
        $msg->subject("$existing updated by $0");
        $msg->to($email);
        my $email_message = $msg->open;

        print $email_message
"This message is to notify you that $existing has been altered. The difference between the new file and the old one is:\n\n";

        my $diffie = `$diff $newfile $existing`;
        print $email_message $diffie;
        $email_message->close;

        EMAIL_SKIPPED:
    }

    # archive the existing file
    if ( -e $existing && $archive ) {
        $self->file_archive( file=> $existing, debug=>$debug );
    };

    # install the new file
    if ($sudo) {
        my $cp = $self->find_the_bin( program => 'cp', debug=>$debug );

        # make a backup of the existing file
        $self->syscmd( command => "$sudo $cp $existing $existing.bak", debug=>$debug )
          if ( -e $existing );

        # install the new one
        if ($clean) {
            $self->syscmd( command => "$sudo  mv $newfile $existing", debug=>$debug );
        }
        else { $self->syscmd( command => "$sudo $cp $newfile $existing", debug=>$debug ); }
    }
    else {

        # back up the existing file
        if ( -e $existing ) {
            copy( $existing, "$existing.bak" ) 
        };

        if ($clean) {
            unless ( move( $newfile, $existing ) ) {
                $err = "install_if_changed: copy $newfile to $existing";
                $self->_formatted( $err, "FAILED");
                croak "$err: $!" if $fatal;
                carp "$err: $!";
                return;
            }
        }
        else {
            unless ( copy( $newfile, $existing ) ) {
                $err = "install_if_changed: copy $newfile to $existing";
                $self->_formatted( $err, "FAILED" );
                croak "$err: $!" if $fatal;
                carp  "$err: $!";
                return;
            }
        }
    }

    # set ownership on the existing file
    if ( $uid && $gid ) {
        $self->file_chown(
            file_or_dir => $existing,
            uid         => $uid,
            gid         => $gid,
            sudo        => $sudo,
            debug       => 0
        );
    }

    # set file permissions (paranoid)
    if ($mode) {
        $self->file_chmod(
            file_or_dir => $existing,
            mode        => $mode,
            sudo        => $sudo,
            debug       => 0
        );
    }

    $self->_formatted( "install_if_changed: updating $existing", "ok" );
    return 1;
}

sub install_from_source_php {


=begin install_from_sources_php

  $utility->install_from_sources_php();

Downloads a PHP program and installs it. Not completed.

=end install_from_sources_php

=cut


### TODO
    # finish writing this.

    my $self = shift;

    #my ($conf, $vals) = @_;
    my ( $conf, $package, $site, $url, $targets, $patches, $debug ) = @_;
    my $patch;

    my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
    $self->chdir_source_dir( dir => $src );

    if ( -d $package ) {
        if ( !$self->source_warning( $package, 1, $src ) ) {
            carp "\ninstall_from_sources_php: OK then, skipping install.";
            return 0;
        }

        print
          "install_from_sources_php: removing any previous build sources.\n";

        $self->syscmd( command => "rm -rf $package-*" ); # nuke any old versions
    }

    print "install_from_sources_php looking for existing sources...";

    my $tarball = "$package.tar.gz";
    if ( -e $tarball ) { print "found.\n"; }
    elsif ( -e "$package.tgz" ) { print "found.\n"; $tarball = "$package.tgz"; }
    elsif ( -e "$package.tar.bz2" ) {
        print "found.\n";
        $tarball = "$package.tar.bz2";
    }
    else { print "not found.\n" }

    unless ( -e $tarball ) {
        $self->sources_get(
            conf    => $conf,
            package => $package,
            site    => $site,
            url     => $url,
            debug   => $debug,
        );
    }
    else {
        print "install_from_sources_php: using existing $tarball sources.\n";
    }

    if ( $patches && @$patches[0] ) {
        print "install_from_sources_php: fetching patches...\n";
        foreach my $patch (@$patches) {
            my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
            unless ($toaster) {
                $toaster = "http://www.tnpi.biz/internet/mail/toaster";
            }
            unless ( -e $patch ) {
                unless ( $self->file_get( 
                    url => "$toaster/patches/$patch", 
                    debug=>$debug, ),
                ) {
                    croak "install_from_sources_php: couldn't fetch " .
                        "$toaster/$patches/$patch\n";
                }
            }
        }
    }
    else {
        print "install_from_sources_php: no patches to fetch.\n";
    }

    $self->archive_expand( archive => $tarball, debug => $debug )
      or croak "Couldn't expand $tarball: $!\n";

    if ( -d $package ) {
        chdir $package;

        if ( $patches && @$patches[0] ) {
            print "yes, should be patching here!\n";
            foreach my $patch (@$patches) {
                my $patchbin = $self->find_the_bin( program => 'patch', debug=>$debug );
                if ( ! $self->syscmd( command => "$patchbin < ../$patch", debug=>$debug ) ) {
                    croak "install_from_sources_php: patch failed: $!\n";
                }
            }
        }

#		unless ( @$targets[0] ) {}
#			print "install_from_sources_php: using default targets (./configure, make, make install).\n";
#			@$targets = ( "./configure", "make", "make install")
#		{};

        foreach my $target (@$targets) {
            if ( ! $self->syscmd( command => $target, debug=>$debug ) ) {
                croak "install_from_source_php: $target failed: $!\n";
            }
        }

        #		chdir("..");
        #		$self->syscmd( command=>"rm -rf $package" );
    }
}

sub install_from_source {

    my $self = shift;

    # parameter validation here
    my %p = validate(@_, {
            'conf'           => { type=>HASHREF, optional=>1, },
            'site'           => { type=>SCALAR,  optional=>0, },
            'url'            => { type=>SCALAR,  optional=>0, },
            'package'        => { type=>SCALAR,  optional=>0, },
            'targets'        => { type=>ARRAYREF, optional=>1, },
            'patches'        => { type=>ARRAYREF, optional=>1, },
            'patch_args'     => { type=>SCALAR,  optional=>1, },
            'source_sub_dir' => { type=>SCALAR,  optional=>1, },
            'bintest'        => { type=>SCALAR,  optional=>1, },
            'fatal'          => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'          => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'        => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf,       $site,    $url,        $package,
         $targets,    $patches, $patch_args, $source_sub_dir,
         $bintest,    $fatal,   $debug      ) 
        = ( $p{'conf'},    $p{'site'},    $p{'url'},        $p{'package'},
            $p{'targets'}, $p{'patches'}, $p{'patch_args'}, $p{'source_sub_dir'},
            $p{'bintest'}, $p{'fatal'},   $p{'debug'} );

    my $patch;

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $original_directory = cwd;

    my $src =  $conf->{'toaster_src_dir'} || "/usr/local/src";
       $src .= "/$source_sub_dir" if $source_sub_dir;

    $self->chdir_source_dir( dir => $src, debug=>$debug );

    if ( $bintest ) {
        if ( $self->find_the_bin( 
                    bin   => $bintest, 
                    fatal => 0, 
                    debug => 0, ) ) {

            return if ( !$self->yes_or_no(
                    timeout => 60,
                    question => "I detected $bintest "
                        . "which means that $package is installed."
                        . "Do you want to reinstall?",
                )
            );
        }
    }

    print "install_from_source: building $package in $src\n" if $debug;

    # make sure there are no previous sources in the way
    if ( -d $package ) {
        unless (
            $self->source_warning(
                package => $package,
                clean   => 1,
                src     => $src,
                debug   => $debug,
            )
          )
        {
            carp "\ninstall_from_source: OK then, skipping install.";
            return 0;
        }

        print "install_from_source: removing previous build sources.\n";
        $self->syscmd( command => "rm -rf $package-*", debug=>$debug ); # nuke any old versions
    }

    #print "install_from_source: looking for existing sources...";
    $self->sources_get(
        conf    => $conf,
        package => $package,
        site    => $site,
        url     => $url,
        debug   => $debug,
    );

    if ( $patches && @$patches[0] ) {

        print "install_from_source: fetching patches...\n";

        my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
        $toaster ||= "http://mail-toaster.org";

        PATCH:
        foreach my $patch (@$patches) {
            next PATCH if ( -e $patch );
            
            unless ( $self->file_get( 
                    url   => "$toaster/patches/$patch", 
                    debug => $debug, ) 
            ) {
                if ( $toaster ne "http://www.tnpi.net/internet/mail/toaster" ) {
                    print <<"EO_OOPS";
  ERROR: apparently you have edited toaster_dl_site or toaster_dl_url
  in your toaster-watcher.conf. You should not do that. Now I cannot 
  find a patch ($patch) that I need to install $package. 
  Fix your toaster-watcher.conf file and try again.
EO_OOPS
                }
                croak
"install_from_source: could not fetch $toaster/patches/$patch\n";
            }
        }
    }
    else {
        print "install_from_source: no patches to fetch.\n" if $debug;
    }

    # expand the tarball
    $self->archive_expand( archive => $package, debug => $debug )
      or croak "Couldn't expand $package: $!\n";

    # cd into the package directory
    my $sub_path;
    if ( -d $package ) {
        unless ( chdir $package ) {
            $err = "FAILED to chdir $package!";
            croak $err if $fatal;
            carp $err;
            return;
        }
    }
    else {

   # some packages (like daemontools) unpack within an enclosing directory, grrr
        $sub_path = `find ./ -name $package`;    # tainted data
        chomp $sub_path;

        # untaint it
        ($sub_path) = $sub_path =~ /^([-\w\/.]+)$/;

        print "found sources in $sub_path\n" if $sub_path;
        unless ( -d $sub_path && chdir($sub_path) ) {
            print "FAILED to find $package sources!\n";
            return 0;
        }
    }

    if ( $patches && @$patches[0] ) {
        print "yes, should be patching here!\n" if $debug;

        foreach my $patch (@$patches) {

            my $patchbin = $self->find_the_bin( bin => "patch", debug=>$debug );
            unless ( -x $patchbin ) {
                print "install_from_sources: FAILED, could not find patch!\n";
                return 0;
            }

            if ( ! $self->syscmd(
                    command => "$patchbin $patch_args < $src/$patch",
                    debug   => $debug, )
              )
            {
                croak "install_from_source: patch failed: $!\n";
            }
        }
    }

    # set default targets if none are provided
    if ( !@$targets[0] ) {
        print
"install_from_source: using default targets (./configure, make, make install).\n";
        @$targets = ( "./configure", "make", "make install" );
    }

    if ($debug) {
        print "install_from_source: using targets \n";
        foreach (@$targets) { print "\t$_\n " }
        print "\n";
    }

    # build the program
  TARGET:
    foreach my $target (@$targets) {

        print "\t pwd: " . cwd . "\n";
        if ( $target =~ /^cd (.*)$/ ) {
            chdir($1) or croak "couldn't chdir $1: $!\n";
            next TARGET;
        }

        if ( ! $self->syscmd( command => $target, debug => $debug ) ) {
            print "\t pwd: " . cwd . "\n";
            croak "install_from_source: $target failed: $!\n" if $fatal;
            return;
        }
    }

    # clean up the build sources
    chdir($src);
    if ( -d $package ) {
        $self->syscmd( command => "rm -rf $package", debug => $debug );
    };

    if ( defined $sub_path && -d "$package/$sub_path" ) {
        $self->syscmd( command => "rm -rf $package/$sub_path", debug => $debug );
    };

    chdir($original_directory);
    return 1;
}

sub is_arrayref {

    my ( $self, $should_be_arrayref, $debug ) = @_;

    my $error;

    unless ( defined $should_be_arrayref ) {
        print "is_arrayref: not defined!\n" if $debug;
        $error++;
    }

    if ( !$error ) {
        eval {

            # simply accessing it will generate an exception.
            if ( $should_be_arrayref->[0] ) {
                print "is_arrayref is a arrayref!\n" if $debug;
            }
        };
        return 1 if ( !$@ );
    }

    print "is_arrayref: not a arrayref!\n" if $debug;

    my ( $package, $filename, $line ) = caller;
    if ( $package ne "main" ) {
        print "WARNING: Package $package passed $filename an invalid argument "
          if $debug;
    }
    else {
        print "WARNING: $filename was passed an invalid argument "
          if $debug;
    }

    if ($debug) {
        $line ? print "(line $line)\n" : print "\n";
    }
    return 0;
}

sub is_hashref {

    my ( $self, $should_be_hashref, $debug ) = @_;

    my $error;

    unless ( defined $should_be_hashref ) {
        print "is_hashref: not defined!\n" if $debug;
        $error++;
    }

    if ( !$error ) {
        eval {

            # simply accessing it will generate the exception.
            if ( $should_be_hashref->{'debug'} ) {
                print "is_hashref is a hashref!\n" if $debug;
            }
        };
        return 1 if ( !$@ );
    }

    print "is_hashref: $should_be_hashref is not a hashref!\n" if $debug;

    my ( $package, $filename, $line ) = caller;
    if ( $package ne "main" ) {
        print "WARNING: Package $package was passed an invalid argument "
          if $debug;
    }
    else {
        print "WARNING: $filename passed an invalid argument " if $debug;
    }

    if ($debug) {
        $line ? print "(line $line)\n" : print "\n";
    }
    return 0;
}

sub is_interactive {

    ## no critic
    # shamelessly stolen from IO::Interactive
    my $self = shift;
    my ($out_handle) = (@_, select);    # Default to default output handle

    # Not interactive if output is not to terminal...
    return 0 if not -t $out_handle;

    # If *ARGV is opened, we're interactive if...
    if (openhandle *ARGV) {
        # ...it's currently opened to the magic '-' file
        return -t *STDIN if defined $ARGV && $ARGV eq '-';

        # ...it's at end-of-file and the next file is the magic '-' file
        return @ARGV>0 && $ARGV[0] eq '-' && -t *STDIN if eof *ARGV;

        # ...it's directly attached to the terminal 
        return -t *ARGV;
    }

    # If *ARGV isn't opened, it will be interactive if *STDIN is attached 
    # to a terminal and either there are no files specified on the command line
    # or if there are files and the first is the magic '-' file
    else {
        return -t *STDIN && (@ARGV==0 || $ARGV[0] eq '-');
    }
}

sub is_process_running {

    my ( $self, $process ) = @_;

    my $ps   = $self->find_the_bin( bin => 'ps',   debug => 0 );
    my $grep = $self->find_the_bin( bin => 'grep', debug => 0 );

    my $r = `$ps ax | $grep $process | $grep -v grep`;
    $r ? return 1 : return 0;
}

sub is_readable {

    my $self = shift;
    
    my %p = validate (@_, {
            'file'    => { type=>SCALAR },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my ( $file, $fatal, $debug ) = ($p{'file'}, $p{'fatal'}, $p{'debug'});
    
    unless ( -e $file ) {
        $err = "\nis_readable: ERROR: The file $file does not exist.";
        croak $err if $fatal;
        carp $err if $debug;
        return 0;
    }

    unless ( -r $file ) {
        carp "\nis_readable: ERROR: The file $file is not "
            . "readable by you (" . getpwuid($>) . "). You need to "
            . "fix this, using chown or chmod.\n";
        croak if $fatal;
        return 0;
    }

    return 1;
}

sub is_writable {

    my $self = shift;
    
    my %p = validate (@_, {
            'file'    => SCALAR,
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );

    my ( $file, $fatal, $debug ) = ($p{'file'}, $p{'fatal'}, $p{'debug'});
    
    my $nl = "\n";
    $nl = "<br>" if ( $ENV{'GATEWAY_INTERFACE'} );

    #print "is_writable: checking $file..." if $debug;

    if ( !-e $file ) {

        use File::Basename;
        my ( $base, $path, $suffix ) = fileparse($file);

        if ( !-w $path ) {

            #print "\nWARNING: is_writable: $path not writable by "
            #	. getpwuid($>) . "!$nl$nl" if $debug;
            $err = "\nWARNING: is_writable: $path not writable by "
              . getpwuid($>)
              . "!$nl$nl";
            croak $err if $fatal;
            carp $err if $debug;
            return 0;
        }
        return 1;
    }

    # if we get this far, the file exists
    unless ( -f $file ) {
        $err = "is_writable: $file is not a file!\n";
        croak $err if $fatal;
        carp $err if $debug;
        return 0;
    }

    unless ( -w $file ) {
        $err = "is_writable: WARNING: $file not writable by "
          . getpwuid($>) . "!$nl$nl>";

        croak $err if $fatal;
        carp $err if $debug;
        return 0;
    }

    $self->_formatted( "is_writable: checking $file.", "ok" ) if $debug;
    return 1;
}

sub logfile_append {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'file'  => { type=>SCALAR,   optional=>0, },
            'lines' => { type=>ARRAYREF, optional=>0, },
            'prog'  => { type=>BOOLEAN,  optional=>1, default=>0, },
            'fatal' => { type=>BOOLEAN,  optional=>1, default=>1 },
            'debug' => { type=>BOOLEAN,  optional=>1, default=>1 },
        },
    );
 
    my ( $file, $lines, $prog, $fatal, $debug ) 
        = ( $p{'file'}, $p{'lines'}, $p{'prog'}, $p{'fatal'}, $p{'debug'} );


    my ( $dd, $mm, $yy, $lm, $hh, $mn, $ss ) =
      $self->get_the_date( debug => $debug );

    open my $LOG_FILE, '>>', $file or $fatal_err++;

    if ( $fatal_err ) {
        carp "logfile_append: couldn't open $file: $OS_ERROR";
        croak if $fatal;
        return { error_code => 500, error_desc => "couldn't open $file: $OS_ERROR" };
    }

    $self->_formatted( "logfile_append: opened $file for writing", "ok" )
      if $debug;

    print $LOG_FILE "$yy-$mm-$dd $hh:$mn:$ss $prog ";

    my $c;
    foreach (@$lines) { print $LOG_FILE "$_ "; $c++ }

    print $LOG_FILE "\n";
    close $LOG_FILE;

    $self->_formatted( "    wrote $c lines", "ok" ) if $debug;
    return { error_code => 200, error_desc => "file append success" };
}

sub mailtoaster {

    my ( $self, $debug ) = @_;
    my ($conf);

    my $perlbin = $self->find_the_bin( program => "perl", debug=>0 );

    if ( -e "/usr/local/etc/toaster-watcher.conf" ) {

        $conf = $self->parse_config( file   => "toaster-watcher.conf", 
                                     debug  => 0,
                                     etcdir => "/usr/local/etc", );
    };

    my $archive = "Mail-Toaster.tar.gz";
    my $url     = "/internet/mail/toaster";

    my $ver;
    $ver = $conf->{'toaster_version'} if $conf;

    if ($ver) {
        $archive = "Mail-Toaster-$ver.tar.gz";
        $url     = "/internet/mail/toaster/src";
    }

    print "going for archive $archive.\n";

    my @targets = ( "$perlbin Makefile.PL", "make", "make conf", "make install" );

    push @targets, "make test" if $debug;

    require Apache::Logmonster::Perl;
    my $perl = Apache::Logmonster::Perl->new;

    $perl->module_install(
        module  => 'Mail-Toaster',
        archive => $archive,
        site    => 'http://www.tnpi.biz',
        url     => $url,
        targets => \@targets,
        debug   => $debug,
    );
}

sub mkdir_system {

    my $self = shift;

    # parameter validation here
    my %p = validate (@_, {
            'dir'     => { type=>SCALAR,  optional=>0, },
            'mode'    => { type=>SCALAR,  optional=>1, },
            'sudo'    => { type=>BOOLEAN, optional=>1, default=>0 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $mode, $fatal, $sudo, $debug ) 
        = ($p{'dir'}, $p{'mode'}, $p{'fatal'}, $p{'sudo'}, $p{'debug'});

    if ( -d $dir ) {
        print "mkdir_system: $dir already exists.\n" if $debug;
        return 1;
    }

    # can't do anything without mkdir
    my $mkdir = $self->find_the_bin( program => 'mkdir', debug => $debug );

    # if we are root, just do it (no sudo nonsense)
    if ( $< == 0 ) {

        print "mkdir_system: trying mkdir -p $dir..\n" if $debug;
        $self->syscmd( command => "$mkdir -p $dir", debug => $debug );

        if ( $mode ) {
            $self->file_chmod(dir=>$dir, mode=>$mode, debug=>$debug);
        };

        -d $dir ? return 1 : return 0;
    }

    if ($sudo) {

        $sudo = $self->sudo();

        print "mkdir_system: trying $sudo mkdir -p....\n" if $debug;
        $mkdir = $self->find_the_bin( program => 'mkdir', debug => $debug );
        $self->syscmd( command => "$sudo $mkdir -p $dir", debug => $debug );

        print "mkdir_system: setting ownership to $<.\n" if $debug;
        my $chown = $self->find_the_bin( program => 'chown', debug => $debug );
        $self->syscmd( command => "$sudo $chown $< $dir", debug => $debug );

        if ( $mode ) {
            $self->file_chmod(dir=>$dir, mode=>$mode, sudo=>$sudo, debug=>$debug );
        };

        -d $dir ? return 1 : return 0;
    }

    print "mkdir_system: trying mkdir -p $dir....." if $debug;

    # no root and no sudo, just try and see what happens
    $self->syscmd( command => "$mkdir -p $dir", debug => 0 );

    if ( $mode ) {
        $self->file_chmod(dir=>$dir, mode=>$mode, debug=>$debug );
    };

    if ( -d $dir ) {
        print "done... (ok)\n" if $debug;
        return 1;
    }

    return 0;
}

sub make_safe_for_shell {

    my ( $self, $string ) = @_;

    if ( $string !~ /^([-\@\w.]+)$/ ) {
        croak "Bad data in tainted string: $string"
          ;    # Log this somewhere if running as CGI
    }

    return $1;    # $string now untainted.
}

sub path_parse {

    my ( $self, $dir ) = @_;

    # if it ends with a /, chop if off
    if ( $dir =~ q{/$} ) { chop $dir }

    # get the position of the last / in the path
    my $rindex = rindex( $dir, "/" );

    # grabs everything up to the last /
    my $updir = substr( $dir, 0, $rindex );
    $rindex++;

    # matches from the last / char +1 to the end of string
    my $curdir = substr( $dir, $rindex );

    return $updir, $curdir;
}

sub parse_config {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'file'   => { type=>SCALAR,  optional=>0, },
            'etcdir' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $file, $etcdir, $fatal, $debug )
        = ( $p{'file'}, $p{'etcdir'}, $p{'fatal'}, $p{'debug'} );
    
    print "parse_config: finding location of $file.\n" if $debug;

    my $config_file =  $self->find_config( 
          file   => $file, 
          etcdir => $etcdir,
          debug  => $debug, 
          fatal  => $fatal,
    );
    
    unless ( $config_file && -r $config_file ) {
        croak "WARNING: parse_config: could not find $file!\n" if $fatal;
        carp "WARNING: parse_config: could not find $file!" if $debug;
        return 0;
    }

    my (%hash);

    print "parse_config: from file $config_file\n" if $debug;

    open my $CONFIG, '<', $config_file or $fatal_err++;

    if ( $fatal_err ) {
        croak "WARNING: Could not open $config_file: $OS_ERROR" if $fatal;
        carp "WARNING: Could not open $config_file: $OS_ERROR";
        return 0;
    }

    while (<$CONFIG>) {        ### Parsing===    done
        chomp;
        next if /^#/;          # skip lines beginning with #
        next if /^[\s+]?$/;    # skip empty lines

        #		print "$_ \t" if $debug;

        my ( $key, $val ) = $self->parse_line( line => $_ );

        next if ( !$key );

        #print "$key \t\t = $val\n" if $debug;

        $hash{$key} = $val;
    }

    close $CONFIG;
    return \%hash;
}

sub parse_line {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'line'    => SCALAR,
            'strip'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $line, $strip, $fatal, $debug ) = 
        ( $p{'line'}, $p{'strip'}, $p{'fatal'}, $p{'debug'} );

    # this regexp must match and return these patterns
    # localhost1  = localhost, disk, da0, disk_da0
    # htmldir = /usr/local/rrdutil/html
    # hosts   = localhost lab.simerson.net seattle.simerson.net

    my ( $key, $val ) = $line =~ /\A
        \s*      # any amount of leading white space, greedy
        (.*?)    # all characters, non greedy
        \s*      # any amount of white space, greedy
        =
        \s*      # same, except on the other side of the =
        (.*?)
        \s*
        \z/xms;

    # remove any comments
    if ( $strip && $val && $val =~ /#/ ) {

        # removes everything from a # to the right, including
        # any spaces to the left of the # symbol.
        ($val) = $val =~ /(.*?\S)\s*#/;
    }

    return ( $key, $val );
}

sub pidfile_check {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'pidfile' => { type=>SCALAR },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $pidfile, $fatal, $debug )
        = ( $p{'pidfile'}, $p{'fatal'}, $p{'debug'} );

    # if $pidfile exists, verify that it is a file
    if ( -e $pidfile && ! -f $pidfile ) {
        $err = "pidfile_check: $pidfile is not a regular file!";
        croak $err if $fatal;
        carp $err if $debug;
        return 0;
    }

   # make sure the file & enclosing directory is writable, revert to /tmp if not
    if (
        !$self->is_writable(
            file  => $pidfile,
            debug => $debug,
            fatal => $fatal
        )
      )
    {
        use File::Basename;
        my ( $base, $path, $suffix ) = fileparse($pidfile);
        carp "NOTICE: using /tmp for pidfile, $path is not writable!"
          if $debug;
        $pidfile = "/tmp/$base";
    }

    # if it does not exist
    if ( !-e $pidfile ) {
        print "pidfile_check: writing process id ", $PROCESS_ID,
          " to $pidfile..."
          if $debug;

        if ( $self->file_write(
                file  => $pidfile,
                lines => [$PROCESS_ID],
                debug => $debug,
            ) 
        ) {
            print "done.\n" if $debug;
            return $pidfile;
        };
    };

    use File::stat;
    my $age = time() - stat($pidfile)->mtime;

    # if less than 1 hour old
    if ( $age < 3600 ) {
        carp "\nWARNING! pidfile_check: $pidfile is " . $age / 60
          . " minutes old and might still be running. If this is not "
          . "the case, please remove it. \n"
          ; #if $debug;

        return;
    }
    else {
        print
"\nWARNING: pidfile_check: $pidfile is $age seconds old, ignoring.\n\n"
          if $debug;
    }

    return $pidfile;
};

sub regexp_test {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'exp'     => { type=>SCALAR },
            'string'  => { type=>SCALAR },
            'pbp'     => { type=>BOOLEAN, optional=>1, default=>0 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $exp, $string, $pbp, $fatal, $debug )
        = ( $p{'exp'}, $p{'string'}, $p{'pbp'}, $p{'fatal'}, $p{'debug'} );

    if ( $pbp ) {
        if ( $string =~ m{($exp)}xms ) {
            print "\t Matched pbp: |$`<$&>$'|\n" if $debug;
            return $1;
        }
        else {
            print "\t No match.\n" if $debug;
            return;
        }
    };

    if ( $string =~ m{($exp)} ) {
        print "\t Matched: |$`<$&>$'|\n" if $debug;
        return $1;
    }

    print "\t No match.\n" if $debug;
    return;
}

sub sources_get {

    my $self = shift;

    # parameter validation here
    my %p = validate(@_, {
            'conf'    => { type=>HASHREF|UNDEF, optional=>1 },
            'package' => { type=>SCALAR,  optional=>1 },
            'site'    => { type=>SCALAR,  optional=>1 },
            'url'     => { type=>SCALAR,  optional=>1 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $package, $site, $url, $fatal, $debug )
        = ( $p{'conf'}, $p{'package'}, $p{'site'}, $p{'url'}, $p{'fatal'}, $p{'debug'} );

    print "sources_get: site from args: " . $site . "\n" if $debug;
    print "sources_get: site from conf: " . $conf->{'toaster_dl_site'} . "\n"
      if ( $debug && $conf->{'toaster_dl_site'} );

    $site ||= $conf->{'toaster_dl_site'};    # get from toaster-watcher.conf
    $site ||= "http://www.tnpi.net";         # if all else fails

    print "sources_get: fetching $package from site $site\n" if $debug;

    $url ||= $conf->{'toaster_dl_url'};      # get from toaster-watcher.conf
    $url ||= "/internet/mail/toaster";       # finally, a default

    print "\t url: $url\n" if $debug;

    my $tarball = "$package.tar.gz";         # try gzip first

    if ( !-e $tarball ) {                    # check for all the usual suspects
        if ( -e "$package.tgz" )     { $tarball = "$package.tgz"; }
        if ( -e "$package.tar.bz2" ) { $tarball = "$package.tar.bz2"; }
    }

    print "\t found $tarball!\n" if ( -e $tarball );

    my $filet = $self->find_the_bin( bin => 'file', debug => $debug );
    my $grep  = $self->find_the_bin( bin => 'grep', debug => $debug );

    if ( -e $tarball && `$filet $tarball | $grep compressed` ) {
        if (
            $self->yes_or_no(
                question =>
                  "You have a (possibly older) version already downloaded as
	$tarball.	   Shall I use it?: "
            )
          )
        {
            print "\n\t ok, using existing archive: $tarball\n";
            return 1;
        }

        $self->file_delete( file => $tarball, debug=>$debug );
    }

    $tarball = "$package.tar.gz";    # reset to gzip

    print "sources_get: fetching as gzip $site$url/$tarball...";

    if ( $self->file_get( url => "$site$url/$tarball", debug => $debug ) ) {
        print "done.\n";
    }
    else {
        carp "install_from_source: couldn't fetch $site$url/$tarball";
    }

    if ( -e $tarball ) {
        print "sources_get: testing $tarball ...";

        if (`$filet $tarball | $grep gzip`) {
            print "sources_get: looks good!\n";
            return 1;
        }
        else {
            print "YUCK, is not gzipped data!\n";
            $self->file_delete( file => $tarball, debug=>$debug );
        }
    }

    $tarball = "$package.tar.bz2";

    print "sources_get: fetching as bz2: $site$url/$tarball...";

    unless ( $self->file_get( url => "$site$url/$tarball", debug => $debug ) ) {
        print "FAILED.\n";
        carp "install_from_source: couldn't fetch $site$url/$tarball";
    }
    else {
        print "done.\n";
    }

    print "sources_get: testing $tarball ...";
    if (`$filet $tarball | $grep bzip`) {
        print "ok\n";
        return 1;
    }
    else {
        print "YUCK, is not bzipped data!!\n";
        $self->file_delete( file => $tarball, debug=>$debug );
    }

    $tarball = "$package.tgz";

    print "sources_get: fetching as tgz: $site$url/$tarball...";

    unless ( $self->file_get( url => "$site$url/$tarball", debug => $debug ) ) {
        print "FAILED.\n";
        carp "install_from_source: couldn't fetch $site$url/$tarball";
    }
    else {
        print "done.\n";
    }

    print "sources_get: testing $tarball ...";
    if (`$filet $tarball | $grep gzip`) {
        print "ok\n";
        return 1;
    }
    else {
        print "YUCK, is not bzipped data!!\n";
        $self->file_delete( file => $tarball, debug=>$debug );
    }

    print "sources_get: FAILED, I am giving up!\n";
    return 0;
}

sub source_warning {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'package' => { type=>SCALAR, },
            'clean'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'src'     => { type=>SCALAR,  optional=>1, default=>"/usr/local/src" },
            'timeout' => { type=>SCALAR,  optional=>1, default=>60 },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $package, $clean, $src, $timeout, $fatal, $debug ) 
        = ( $p{'package'}, $p{'clean'}, $p{'src'}, $p{'timeout'}, $p{'fatal'}, $p{'debug'} );

    if ( !-d $package ) {
        print "source_warning: $package sources not present.\n" if $debug;
        return 1;
    }

    if ( -e $package ) {
        print "
	$package sources are already present, indicating that you've already
	installed $package. If you want to reinstall it, remove the existing
	sources (rm -r $src/$package) and re-run this script\n\n";
        return 0 unless $clean;
    }

    if (
        !$self->yes_or_no(
            question => "\n\tWould you like me to remove the sources for you?",
            timeout  => $timeout,
        )
      )
    {
        return 0;
    }

    print "wd: " . cwd . "\n";
    print "Deleting $src/$package...";

    if ( !rmtree "$src/$package" ) {
        print "FAILED to delete $package: $OS_ERROR";
        croak if $fatal;
        return 0;
    }
    print "done.\n";

    return 1;
}

sub sudo {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    # if we are running as root via $<
    if ( $REAL_USER_ID == 0 ) {
        print "sudo: you are root, sudo isn't necessary.\n" if $debug;
        return "";    # return an empty string for $sudo
    }

    my $sudo;
    my $path_to_sudo =
      $self->find_the_bin( program => "sudo", debug => $debug, fatal => 0 );

    # sudo is installed
    if ( -x $path_to_sudo ) {
        print "sudo: sudo is set using $path_to_sudo.\n" if $debug;
        return "$path_to_sudo -p 'Password for %u@%h:'";
    }

    print
"\n\n\tWARNING: Couldn't find sudo. This may not be a problem but some features require root permissions and will not work without them. Having sudo can allow legitimate and limited root permission to non-root users. Some features of Mail::Toaster may not work as expected without it.\n\n";

    # try installing sudo
    unless (
        $self->yes_or_no(
            question => "sudo is not installed, shall I try to install it?"
        )
      )
    {
        print "very well then, skipping along.\n";
        return "";
    }

    if ( $OSNAME eq "freebsd" ) {
        eval { require Mail::Toaster::FreeBSD };
        if ($EVAL_ERROR) {
            print "couldn't load Mail::Toaster::FreeBSD!: $@\n";
            print "skipping port install attempt\n";
        }
        else {
            my $freebsd = Mail::Toaster::FreeBSD->new();
            $freebsd->port_install( "sudo", "security" );
        }
    }

    if ( !-x $self->find_the_bin( bin => "sudo", debug => $debug, fatal => 0 ) )
    {
        $self->install_from_source(
            package => 'sudo-1.6.8p2',
            site    => 'http://www.courtesan.com',
            url     => '/sudo/',
            targets => [ './configure', 'make', 'make install' ],
            patches => '',
            debug   => 1,
        );
    }

    # can we find it now?
    $path_to_sudo = $self->find_the_bin( bin => "sudo", debug=>$debug );

    if ( !-x $path_to_sudo ) {
        carp "sudo installation failed!";
        return "";
    }

    return "$path_to_sudo -p 'Password for %u@%h:'";
}

sub syscmd {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'command' => { type=>SCALAR,  optional=>1, },
            'cmd'     => { type=>SCALAR,  optional=>1, },   # finger friendly
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $command_to_execute, $fatal, $debug )
        = ( $p{'command'}, $p{'fatal,'}, $p{'debug'} );

    # expand the alias so that either one works
    if ( ! $command_to_execute && defined $p{'cmd'} ) {
        $command_to_execute = $p{'cmd'};
    }

    my $result_code;
    my $status_message = "syscmd: invalid parameters! See perldoc Apache::Logmonster::Utility for correct usage.";

    unless ($command_to_execute) {
        croak $status_message if $fatal;
        $self->_formatted($status_message) if $debug;
        return 0;
    }
    
    print "syscmd, preparing command: $command_to_execute\n" if $debug;

    # separate the program to run from its arguments, if we can
    my ( $is_safe, $tainted, $bin, $args);

    # is it a two part command, space separated
    if ( $command_to_execute =~ m/\s+/xm ) {
        $is_safe++;
#        $command_to_execute =~ m{\A (.*?) \s+ (.*) \z}xms;
        $command_to_execute =~ m/^ \s* ([^\s]*) (.*) $/xms;
            # \A   start of string
            # \s*  any leading whitespace
            # ([^\s]*) capture all non-whitespace chars
            # (.*) then the rest of characters
            # \z   to the end of string
        $bin = $1; $args = $2;
        carp "syscmd: program is: $bin, args are: $args" if $debug;
    }
    else {
        # a one part command (ie, no args)
        # make sure it does not not contain a ./ pattern
        if ( $command_to_execute !~ m{\./} ) {
            $bin = $command_to_execute;
            $is_safe++;
        }
    }

    $status_message = "syscmd: bin is <$bin>";
    $status_message .= " (safe)" if  $is_safe;
    
    $self->_formatted($status_message) if $debug;

    if ( $is_safe && !$bin ) {
        $self->_formatted("\tcommand is not safe! BAILING OUT!");
        return;
    }

    if ( $bin && -e $bin && ! -x $bin ) {
        $err = "I found $bin but it's not executable!";
        croak $err if $fatal;
        carp $err;
        return 0;
    };

    if ( $bin && !-e $bin ) {
        # $bin is set, but we haven't found it yet

        # check all the normal places
        my $found_bin = $self->find_the_bin( bin => $bin, fatal => 0, debug => $debug );
        if ( $found_bin && -x $found_bin ) {
            $bin = $found_bin;
        }
        else {
            # check our current working directory
            if ( -e cwd . "/" . $bin ) {
                $bin = cwd . "/" . $bin;
            };
        }

        if ( !-x $bin ) {
            carp "\t cmd: $command_to_execute \t bin: $bin is not found (improper commnd format?)"
              if $debug;
            $self->_invalid_params( sub => 'syscmd', fatal => $fatal );
        }
    }

### TODO
    # we could also do some argument testing here.
    #   check for ; to make sure commands are not stacked?

    $status_message = "checking for tainted data in string";
    require Scalar::Util;
    if ( Scalar::Util::tainted($command_to_execute) ) {
        $tainted++;
    }

    my $before_path = $ENV{PATH};

    if ($tainted && ! $is_safe) {

        # instead of croaking, maybe try setting a
        # very restrictive PATH?  I'll err on the side of 
        # safety for now.
        # $ENV{PATH} = '';

        croak "$status_message ...TAINTED!" if $fatal;
        carp "$status_message ...TAINTED!" if $debug;
        return 0;
    }

    if ($is_safe) {
        # reassemble it with the fully qualified path to the program
        $command_to_execute = $bin;
        $command_to_execute .= $args if $args;

        # restrict the path
        my $prefix = "/usr/local";
        if ( -d "/opt/local" ) { $prefix = "/opt/local"; };
        $ENV{PATH} = "/bin:/sbin:/usr/bin:/usr/sbin:$prefix/bin:$prefix/sbin";
    }

    print "syscmd: running $command_to_execute\n" if $debug;
    $result_code = system $command_to_execute;
    
    if ( $CHILD_ERROR == -1 ) {    # check $? for "normal" errors
        carp "syscmd: $command_to_execute" . "\nfailed to execute: $!"
          if $debug;
    }
    elsif ( $CHILD_ERROR & 127 ) {    # check for core dump
        if ($debug) {
            carp "syscmd: $command_to_execute";
            printf "child died with signal %d, %s coredump\n", ( $? & 127 ),
              ( $? & 128 ) ? 'with' : 'without';
        }
    }
    else {                            # all is likely well
        if ($debug) {
            printf "\tchild exited with value %d\n", $? >> 8;
        }
    }

    # set it back to what it was before we started
    $ENV{PATH} = $before_path;

    # in perl < 6, system commands return zero on success. Check to see that
    # the result of the command was zero, and warn (or die) otherwise.
    if ( $result_code != 0 ) {
        $self->_formatted("syscmd: $command_to_execute", "FAILED") if $debug;
        $err = "syscmd: program exited: $result_code";
        croak $err if $fatal;
        carp $err if $debug;
    }

    $result_code ? return 0: return 1;
}

sub validate_params {

=begin validate_params

This was a great idea and it mostly works. Part way through writing this I found Params::Validate. I still don't like Params::Validate because I cannot cleanly use it without depending on it. Its API requires that if you use it, it must be installed on every system upon which your software runs. I work very hard to make my software work without dependency chains as they always create problems for users, particularly ones that don't know a lot about Perl. I wanted a solution that I could use if present, but continued to work just as well (albeit minus the extra tests). After conversing with the author Params::Validate I determined what I wanted was not possible. 

I then tried out Getargs::Long but the error message yielded up when invalid params are passed were abyssmal. Just like the man page says, it does return errors from the perspective of the caller. Well, that's only partly true, it returns them from the perspective of the callers caller, which is a pain. You know which sub/function your error is in, but then you have to guess which function within that, or call tripped it. Blech. It required far too much use of the perl debugger to track down simple errors. 

So, for now I use Params::Validate and I expect it will be a good solution. I just have to live with the fact that I am dependent on it and hope that causes me less trouble than maintaining my own solution.

=cut

    my ( $self, $args ) = @_;

    # this sub should only ever be passed two parameters
    if ( @_ != 2 ) {
        return $self->_invalid_params(
            sub      => 'validate_params',
            errormsg => 'incorrect number of arguments',
            fatal    => 0,
        );
    }

    # make sure the second parameter is a hashref
    if ( !$self->is_hashref($args) ) {
        return $self->_invalid_params( sub => 'validate_params', fatal => 0 );
    }

    my $fatal++;    # default behavior is to die on errors.
                    # but caller can override the default
    $fatal = $args->{'fatal'} if ( defined $args->{'fatal'} );

    my $debug++;    # defaults to print messages
    $debug = $args->{'debug'} if ( defined $args->{'debug'} );

    my $sub      = $args->{'sub'};
    my $min      = $args->{'min'};
    my $max      = $args->{'max'};
    my $params   = $args->{'params'};
    my $required = $args->{'required'};
    my $optional = $args->{'optional'};

    # if $required is provided, make sure it is an arrayref
    if ($required) {
        if ( !$self->is_arrayref($required) ) {
            return $self->_invalid_params(
                sub      => 'validate_params',
                errormsg => '$required needs to be an arrayref!',
                debug    => $debug,
                fatal    => $fatal
            );
        }
    }

    # if $optional is provided, make sure it is an arrayref
    if ($optional) {
        if ( !$self->is_arrayref($optional) ) {
            return $self->_invalid_params(
                sub      => 'validate_params',
                errormsg => '$optional needs to be an arrayref!',
                debug    => $debug,
                fatal    => $fatal
            );
        }
    }

    # $params is required, and it must be an arrayref
    if ( !$self->is_arrayref($params) ) {
        return $self->_invalid_params(
            sub      => 'validate_params',
            errormsg => '$params is required and must be an arrayref!',
            debug    => $debug,
            fatal    => $fatal
        );
    }

    # verify the minimum number of params
    my $i;
    foreach (@$params) { $i++ }
    if ( $i < $min ) {
        return $self->_invalid_params(
            sub      => 'validate_params',
            errormsg => '@params does not have the required elements!',
            debug    => $debug,
            fatal    => $fatal
        );
    }

    # verify the maximum number of params
    if ( $i > $min ) {
        return $self->_invalid_params(
            sub      => 'validate_params',
            errormsg => '@params has too many elements!',
            debug    => $debug,
            fatal    => $fatal
        );
    }

    # verify all required params are defined
    if ($required) {

        # we can only test if the first element of params is a hashref
        if ( $self->is_arrayref($params) ) {
            print "checking for required parameters.\n" if $debug;
            $i = 0;

            # iterate through each required field
            foreach (@$required) {

                # and verify it exists within $params
                $i++ unless defined $params->[0]->{$_};
                print "\t $_ \n" if $debug;
            }
            if ($i) {
                croak "a required parameter is missing!\n" if $fatal;
                return 0;
            }
        }
    }

    # make sure no extra params are defined
    if ( $optional && $required ) {

        my %all;    # a hash to put all the fields into

        # put all the optional and required params into the hash
        foreach ( @$optional, @$required ) { $all{$_} = 1; }

        my $param = $params->[0];
        $i = 0;

        # iterate through the keys in param
        foreach ( keys %$param ) {

            # increment $i unless the key is in the %all hash
            $i++ unless ( $all{$_} );
            print "\t key: $_ \n" if $debug;
        }
        if ($i) {
            croak if $fatal;
            return 0;
        }
    }

    return 1;
}

sub yes_or_no {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'question' => { type=>SCALAR, optional=>1 },
            'q'        => { type=>SCALAR, optional=>1 },
            'timeout'  => { type=>SCALAR, optional=>1 },
            'fatal'    => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'    => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $question, $timer ) = ( $p{'question'}, $p{'timeout'} );

    # q is an alias for question
    if ( !defined $question && defined $p{'q'} ) { $question = $p{'q'}; }

    # this sub is useless without a question.
    unless ($question) {
        croak "question called incorrectly. RTFM. \n";
    };
 
    # for 'make test' testing
    return 1 if ( $question eq "test" );

    unless ( $self->is_interactive ) {
        carp "not running interactively, can't prompt!";
        return;
    }
    
    my ($response);
    
    print "\nYou have $timer seconds to respond.\n" if $timer;
    print "\n\t\t$question";

    # should check for Term::Readkey and use it
    # I wish I knew why this is not working correctly
    #	eval { local $SIG{__DIE__}; require Term::ReadKey };
    #	if ($@) { #
    #		require Term::ReadKey;
    #		Term::ReadKey->import();
    #		print "yay, Term::ReadKey is present! Are you pleased? (y/n):\n";
    #		use Term::Readkey;
    #		ReadMode 4;
    #		while ( not defined ($key = ReadKey(-1)))
    #		{ # no key yet }
    #		print "Got key $key\n";
    #		ReadMode 0;
    #	};

    if ($timer) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timer;
            do {
                print "(y/n): ";
                $response = lc(<STDIN>);
                chomp($response);
            } until ( $response eq "n" || $response eq "y" );
            alarm 0;
        };

        if ($@) {
            ( $@ eq "alarm\n" )
              ? print "timed out!\n"
              : carp;    # propagate unexpected errors
        }

        $response && $response eq "y" ? return 1 : return 0;
    }

    do {
        print "(y/n): ";
        $response = lc(<STDIN>);
        chomp($response);
    } until ( $response eq "n" || $response eq "y" );

    $response eq "y" ? return 1 : return 0;
}

sub _incomplete_feature {

    my ( $self, $args ) = @_;

    my $mess   = $args->{'mess'};
    my $action = $args->{'action'};

    print
"\n    My apologies, but I do not know how to $mess. $action If you would like to see this feature developed, consider contributing time or money towards it. See http://mail-toaster.org/intro/contribute.shtml for details.\n";

}

sub _invalid_params {


=begin _invalid_params

prints out an error message and exits. 

  required arguments:
    sub - the name of the calling subroutine

  optional arguments:
    errormsg - a helpful error message
    fatal 
    debug

  result:
    0 - failure


=end _invalid_params

=cut


    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'sub'      => { type=>SCALAR },
            'errormsg' => { type=>SCALAR,  optional=>1, },
            'fatal'    => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'    => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $sub, $error, $fatal, $debug )
        = ( $p{'sub'}, $p{'error'}, $p{'fatal'}, $p{'debug'} );

    print "\t FATAL: $sub was passed an invalid argument(s).\n" if $debug;

    if ( $error && $debug ) { print "\n\t $error \n"; }

    croak if $fatal;
    return 0;
}

sub _formatted {

############################################
# Usage      : $utility->_formatted( "tried this", "ok");
# Purpose    : print nicely formatted status messages
# Returns    : tried this...............................ok
# Parameters : message - what your are reporting on
#              result  - the status to report
# See Also   : n/a

    my ( $self, $mess, $result ) = @_;

    my $dots = '...';
    my $length_of_mess = length($mess);

    if ( $length_of_mess < 65 ) {
        until ( $length_of_mess == 65 ) { $dots .= "."; $length_of_mess++ }
    }

    print $mess if $mess;
    if ($result) {
        print $dots . $result;
    }
    print "\n";

    #print "$mess $dots $result\n";
}

sub _progress {
    my ($self, $mess) = @_;
    print {*STDERR} "$mess.\n";
    return;
};
sub _progress_begin {
    my ($self, $phase) = @_;
    print {*STDERR} "$phase...";
    return;
};
sub _progress_continue {
    print {*STDERR} '.';
    return;
};
sub _progress_end {
    my ($self,$mess) = @_;
    if ( $mess ) {
        print {*STDERR} "$mess\n";
    }
    else {
        print {*STDERR} "done\n";
    };
    return;
};

1;
__END__


=head1 NAME

Apache::Logmonster::Utility - a collection of utility subroutines for sysadmin tasks


=head1 SYNOPSIS

  use Apache::Logmonster::Utility;
  my $utility = Apache::Logmonster::Utility->new;

  $utility->file_write($file, @lines);

This is just one of the many handy little methods I have amassed here. Rather than try to remember all of the best ways to code certain functions and then attempt to remember them, I have consolidated years of experience and countless references from Learning Perl, Programming Perl, Perl Best Practices, and many other sources into these subroutines.


=head1 DESCRIPTION

This Apache::Logmonster::Utility package is my most frequently used one. Peruse through the list of methods and surely you too can find something of use. Each method has its own documentation but in general, all methods accept as input a hashref with at least one required argument and a number of optional arguments. 


=head1 DIAGNOSTICS

All methods set and return error codes (0 = fail, 1 = success) unless otherwise stated. 

Unless otherwise mentioned, all methods accept two additional parameters:

  debug - to print status and verbose error messages, set debug=>1.
  fatal - die on errors. This is the default, set fatal=>0 to override.


=head1 DEPENDENCIES

  Perl.
  Scalar::Util -  built-in as of perl 5.8

Almost nothing else. A few of the methods do require certian things, like archive_expand requires tar and file. But in general, this package (Apache::Logmonster::Utility) should run flawlessly on any UNIX-like system. Because I recycle this package in other places (not just Apache::Logmonster), I avoid creating dependencies here.

=head1 METHODS

=over


=item new

To use any of the methods below, you must first create a utility object. The methods can be accessed via the utility object.

  ############################################
  # Usage      : use Apache::Logmonster::Utility;
  #            : my $utility = Apache::Logmonster::Utility->new;
  # Purpose    : create a new Apache::Logmonster::Utility object
  # Returns    : a bona fide object
  # Parameters : none
  ############################################


=item answer


Get a response from the user. If the user responds, their response is returned. If not, then the default response is returned. If no default was supplied, 0 is returned.

  ############################################
  # Usage      :  my $answer = $utility->answer(
  #  		           question => "Would you like fries with that",
  #  		           default  => "SuperSized!",
  #  		           timeout  => 30  
  #               );
  # Purpose    : prompt the user for information
  #
  # Returns    : S - the users response (if not empty) or
  #            : S - the default answer or
  #            : S - an empty string
  #
  # Parameters
  #   Required : S - question - what to ask
  #            : S - q        - a programmer friendly alias for question
  #   Optional : S - default  - a default answer
  #            : I - timeout  - how long to wait for a response
  # Throws     : no exceptions
  # See Also   : yes_or_no


=item archive_expand


Decompresses a variety of archive formats using your systems built in tools.

  ############### archive_expand ##################
  # Usage      : $utility->archive_expand(
  #            :     archive => 'example.tar.bz2' );
  # Purpose    : test the archiver, determine its contents, and then
  #              use the best available means to expand it.
  # Returns    : 0 - failure, 1 - success
  # Parameters : S - archive - a bz2, gz, or tgz file to decompress


=item chdir_source_dir


Changes the current working directory to the supplied one. Creates it if it does not exist. Tries to create the directory using perl's builtin mkdir, then the system mkdir, and finally the system mkdir with sudo. 

  ############ chdir_source_dir ###################
  # Usage      : $utility->chdir_source_dir( dir=>"/usr/local/src" );
  # Purpose    : prepare a location to build source files in
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - dir - a directory to build programs in


=item check_homedir_ownership 

Checks the ownership on all home directories to see if they are owned by their respective users in /etc/password. Offers to repair the permissions on incorrectly owned directories. This is useful when someone that knows better does something like "chown -R user /home /user" and fouls things up.

  ######### check_homedir_ownership ############
  # Usage      : $utility->check_homedir_ownership();
  # Purpose    : repair user homedir ownership
  # Returns    : 0 - failure,  1 - success
  # Parameters :
  #   Optional : I - auto - no prompts, just fix everything
  # See Also   : sysadmin

Comments: Auto mode should be run with great caution. Run it first to see the results and then, if everything looks good, run in auto mode to do the actual repairs. 


=item check_pidfile

see pidfile_check

=item chown_system

The advantage this sub has over a Pure Perl implementation is that it can utilize sudo to gain elevated permissions that we might not otherwise have.


  ############### chown_system #################
  # Usage      : $utility->chown_system( dir=>"/tmp/example", user=>'matt' );
  # Purpose    : change the ownership of a file or directory
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - dir    - the directory to chown
  #            : S - user   - a system username
  #   Optional : S - group  - a sytem group name
  #            : I - recurse - include all files/folders in directory?
  # Comments   : Uses the system chown binary
  # See Also   : n/a


=item clean_tmp_dir


  ############## clean_tmp_dir ################
  # Usage      : $utility->clean_tmp_dir( dir=>$dir );
  # Purpose    : clean up old build stuff before rebuilding
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - $dir - a directory or file. 
  # Throws     : die on failure
  # Comments   : Running this will delete its contents. Be careful!


=item drives_get_mounted

  ############# drives_get_mounted ############
  # Usage      : my $mounts = $utility->drives_get_mounted();
  # Purpose    : Uses mount to fetch a list of mounted drive/partitions
  # Returns    : a hashref of mounted slices and their mount points.


=item file_archive


  ############### file_archive #################
  # Purpose    : Make a backup copy of a file by copying the file to $file.timestamp.
  # Usage      : my $archived_file = $utility->file_archive( file=>$file );
  # Returns    : the filename of the backup file, or 0 on failure.
  # Parameters : S - file - the filname to be backed up
  # Comments   : none


=item file_chmod

Set the permissions (ugo-rwx) of a file. Will use the native perl methods (by default) but can also use system calls and prepend sudo if additional permissions are needed.

  $utility->file_chmod(
		file_or_dir => '/etc/resolv.conf',
		mode => '0755',
		sudo => $sudo
  )

 arguments required:
   file_or_dir - a file or directory to alter permission on
   mode   - the permissions (numeric)

 arguments optional:
   sudo  - the output of $utility->sudo
   fatal - die on errors? (default: on)
   debug

 result:
   0 - failure
   1 - success


=item file_chown

Set the ownership (user and group) of a file. Will use the native perl methods (by default) but can also use system calls and prepend sudo if additional permissions are needed.

  $utility->file_chown(
		file_or_dir => '/etc/resolv.conf',
		uid => 'root',
		gid => 'wheel',
		sudo => 1
  );

 arguments required:
   file_or_dir - a file or directory to alter permission on
   uid   - the uid or user name
   gid   - the gid or group name

 arguments optional:
   file  - alias for file_or_dir
   dir   - alias for file_or_dir
   sudo  - the output of $utility->sudo
   fatal - die on errors? (default: on)
   debug

 result:
   0 - failure
   1 - success


=item file_delete

  ############################################
  # Usage      : $utility->file_delete( file=>$file );
  # Purpose    : Deletes a file.
  # Returns    : 0 - failure, 1 - success
  # Parameters 
  #   Required : file - a file path
  # Comments   : none
  # See Also   : 

 Uses unlink if we have appropriate permissions, otherwise uses a system rm call, using sudo if it is not being run as root. This sub will try very hard to delete the file!


=item file_get

   $utility->file_get( url=>$url, debug=>1 );

Use the standard URL fetching utility (fetch, curl, wget) for your OS to download a file from the $url handed to us.

 arguments required:
   url - the fully qualified URL

 arguments optional:
   timeout - the maximum amount of time to try
   fatal
   debug

 result:
   1 - success
   0 - failure


=item file_is_newer

compares the mtime on two files to determine if one is newer than another. 

=item file_read

Reads in a file, and returns it in an array. All lines in the array are chomped.

   my @lines = $utility->file_read( file=>$file, max_lines=>100 )

 arguments required:
   file - the file to read in

 arguments optional:
   max_lines  - integer - max number of lines
   max_length - integer - maximum length of a line
   fatal
   debug

 result:
   0 - failure
   success - returns an array with the files contents, one line per array element


=item file_write

 usage:
   my @lines = "1", "2", "3";  # named array
   $utility->file_write ( file=>"/tmp/foo", lines=>\@lines );   
        or
   $utility->file_write ( file=>"/tmp/foo", lines=>['1','2','3'] );  # anon arrayref

 required arguments:
   file - the file path you want to write to
   lines - an arrayref. Each array element will be a line in the file

 arguments optional:
   fatal
   debug

 result:
   0 - failure
   1 - success


=item files_diff

Determine if the files are different. $type is assumed to be text unless you set it otherwise. For anthing but text files, we do a MD5 checksum on the files to determine if they are different or not.

   $utility->files_diff( f1=>$file1,f2=>$file2,type=>'text',debug=>1 );

   if ( $utility->files_diff( f1=>"foo", f2=>"bar" ) )
   {
       print "different!\n";
   };

 required arguments:
   f1 - the first file to compare
   f2 - the second file to compare

 arguments optional:
   type - the type of file (text or binary)
   fatal
   debug

 result:
   0 - files are the same
   1 - files are different
  -1 - error.


=item find_config

This sub is called by several others to determine which configuration file to use. The general logic is as follows:

  If the etc dir and file name are provided and the file exists, use it.

If that fails, then go prowling around the drive and look in all the usual places, in order of preference:

  /opt/local/etc/
  /usr/local/etc/
  /etc

Finally, if none of those work, then check the working directory for the named .conf file, or a .conf-dist. 

Example:
  my $twconf = $utility->find_config (
	  file   => 'toaster-watcher.conf', 
	  etcdir => '/usr/local/etc',
	)

 arguments required:
   file - the .conf file to read in

 arguments optional:
   etcdir - the etc directory to prefer
   debug
   fatal

 result:
   0 - failure
   the path to $file  


=item find_the_bin

Check all the "normal" locations for a binary that should be on the system and returns the full path to the binary.

   $utility->find_the_bin( program=>'dos2unix', dir=>'/opt/local/bin' );

Example: 

   my $apachectl = $utility->find_the_bin( program=>"apachectl", dir=>"/usr/local/sbin" );


 arguments required:
   program - the name of the program (its filename)

 arguments optional:
   dir - a directory to check first
   fatal
   debug

 results:
   0 - failure
   success will return the full path to the binary.


=item get_file

an alias for file_get for legacy purposes. Do not use.

=item get_my_ips

returns an arrayref of IP addresses on local interfaces. 

=item is_process_running

Verify if a process is running or not.

   $utility->is_process_running($process) ? print "yes" : print "no";

$process is the name as it would appear in the process table.



=item is_readable


  ############################################
  # Usage      : $utility->is_readable( file=>$file );
  # Purpose    : ????
  # Returns    : 0 = no (not reabable), 1 = yes
  # Parameters : S - file - a path name to a file
  # Throws     : no exceptions
  # Comments   : none
  # See Also   : n/a

  result:
     0 - no (file is not readable)
     1 - yes (file is readable)



=item is_writable

If the file exists, it checks to see if it is writable. If the file does not exist, it checks to see if the enclosing directory is writable. 

  ############################################
  # Usage      : $utility->is_writable(file =>"/tmp/boogers");
  # Purpose    : make sure a file is writable
  # Returns    : 0 - no (not writable), 1 - yes (is writeable)
  # Parameters : S - file - a path name to a file
  # Throws     : no exceptions


=item fstab_list


  ############ fstab_list ###################
  # Usage      : $utility->fstab_list;
  # Purpose    : Fetch a list of drives that are mountable from /etc/fstab.
  # Returns    : an arrayref
  # Comments   : used in backup.pl
  # See Also   : n/a


=item get_dir_files

   $utility->get_dir_files( dir=>$dir, debug=>1 )

 required arguments:
   dir - a directory

 optional arguments:
   fatal
   debug

 result:
   an array of files names contained in that directory.
   0 - failure


=item get_the_date

Returns the date split into a easy to work with set of strings. 

   $utility->get_the_date( bump=>$bump, debug=>$debug )

 required arguments:
   none

 optional arguments:
   bump - the offset (in days) to subtract from the date.
   debug

 result: (array with the following elements)
	$dd = day
	$mm = month
	$yy = year
	$lm = last month
	$hh = hours
	$mn = minutes
	$ss = seconds

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = $utility->get_the_date();


=item graceful_exit

do not use, legacy sub

=item install_if_changed

Compares two text files. If the newer file is different than the existing one, it installs it.

  $utility->install_if_changed(
		newfile  => '/etc/resolv.conf.new';
		existing => '/etc/resolv.conf';
		mode     => '0755',
		uid      => 89,
        gid      => 89,
	);

 arguments required
   newfile
   existing

 arguments optional
   uid   -
   gid   -
   mode  - file permissions mode (numeric: 0755)
   debug - 
   clean - int - delete the newfile after installing it?
   notify- int - send notification upon updates?
   email - email address to send notifications (default: root)

 results:
   0 = error (failure)
   1 = success
   2 = success, no update required


=item install_from_source

  usage:

	$utility->install_from_source(
		package => 'simscan-1.07',
   	    site    => 'http://www.inter7.com',
		url     => '/simscan/',
		targets => ['./configure', 'make', 'make install'],
		patches => '',
		debug   => 1,
	);

Downloads and installs a program from sources.

 required arguments:
    conf    - hashref - mail-toaster.conf settings.
    site    - 
    url     - 
    package - 

 optional arguments:
    targets - arrayref - defaults to [./configure, make, make install].
    patches - arrayref - patch(es) to apply to the sources before compiling
    patch_args - 
    source_sub_dir - a subdirectory within the sources build directory
    bintest - check the usual places for an executable binary. If found, it will assume the software is already installed and require confirmation before re-installing.
    debug
    fatal

 result:
   1 - success
   0 - failure


=item install_from_source_php

Downloads a PHP program and installs it. This function is not completed due to lack o interest.

=item is_arrayref

Checks whatever object is passed to it to see if it is an arrayref.

   $utility->is_arrayref($testme, $debug);

Enable debugging to see helpful error messages.


=item is_hashref

Most methods pass parameters around inside hashrefs. Unfortunately, if you try accessing a hashref method and the object isn't a hashref, it generates a fatal exception. This traps that exception and prints a useful error message.

   $utility->is_hashref($hashref, $debug);


=item is_interactive

tests to determine if the running process is attached to a terminal.


=item logfile_append

   $utility->logfile_append( file=>$file, lines=>\@lines )

Pass a filename and an array ref and it will append a timestamp and the array contents to the file. Here's a working example:

   $utility->logfile_append( file=>$file, prog=>"proggy", lines=>["Starting up", "Shutting down"] )

That will append a line like this to the log file:

   2004-11-12 23:20:06 proggy Starting up
   2004-11-12 23:20:06 proggy Shutting down

 arguments required:
   file  - the log file to append to
   prog  - the name of the application
   lines - arrayref - elements are events to log.

 arguments optional:
   fatal
   debug

 result:
   1 - success
   0 - failure


=item mailtoaster

   $utility->mailtoaster();

Downloads and installs Mail::Toaster.


=item make_safe_for_shell

A good idea, poorly implemented.

=item mkdir_system

creates a directory using the system mkdir binary. Can also make levels of directories (-p) and utilize sudo if necessary to escalate.

=item parse_line

parses a conf file line and returns the key and value.

=item path_parse

   my ($up1dir, $userdir) = $utility->path_parse($dir)

Takes a path like "/usr/home/matt" and returns "/usr/home" and "matt"

You (and I) should be using File::Basename instead as it is more portable.


=item parse_config

 Example:
   my $tconf = $utility->parse_config( file=>'toaster.conf' );

 required parameters:
   file   - a configuration file to load settings from
   etcdir - where to look for $file - defaults to /usr/local/etc
            also checks the current working directory. 

 optional parameters:
   debug
   fatal

 result: 
   a hashref with the key/value pairs.
   0 - failure


=item pidfile_check

pidfile_check is a process management method. It will check to make sure an existing pidfile does not exist and if not, it will create the pidfile.

   $pidfile = $utility->pidfile_check( pidfile=>"/var/run/program.pid" );

The above example is all you need to do to add process checking (avoiding multiple daemons running at the same time) to a program or script. This is used in toaster-watcher.pl and rrdutil. toaster-watcher normally completes a run in a few seconds and is run every 5 minutes. 

However, toaster-watcher can be configured to do things like expire old messages from maildirs and feed spam through a processor like sa-learn. This can take a long time on a large mail system so we don't want multiple instances of toaster-watcher running.

 result:
   the path to the pidfile (on success).

Example:

	my $pidfile = $utility->pidfile_check( pidfile=>"/var/run/changeme.pid" );
	unless ($pidfile) {
		warn "WARNING: couldn't create a process id file!: $!\n";
		exit 0;
	};

	do_a_bunch_of_cool_stuff;
	unlink $pidfile;


=item regexp_test

Prints out a string with the regexp match bracketed. Credit to Damien Conway from Perl Best Practices.

 Example:
    $utility->regexp_test( 
		exp    => 'toast', 
		string => 'mailtoaster rocks',
	);

 arguments required:
   exp    - the regular expression
   string - the string you are applying the regexp to

 result:
   printed string highlighting the regexp match


=item source_warning

Checks to see if the old build sources are present. If they are, offer to remove them.

 Usage:

   $utility->source_warning( 
		package => "Mail-Toaster-4.10", 
		clean   => 1, 
		src     => "/usr/local/src" 
   );

 arguments required:
   package - the name of the packages directory

 arguments optional:
   src     - the source directory to build in (/usr/local/src)
   clean   - do we try removing the existing sources? (enabled)
   timeout - how long to wait for an answer (60 seconds)

 result:
   1 - removed
   0 - failure, package exists and needs to be removed.


=item sources_get

Tries to download a set of sources files from the site and url provided. It will try first fetching a gzipped tarball and if that files, a bzipped tarball. As new formats are introduced, I will expand the support for them here.

  usage:
	$self->sources_get( 
		conf    => $conf, 
		package => 'simscan-1.07', 
		site    => 'http://www.inter7.com',
		url     => '/simscan/',
	)

 arguments required:
   package - the software package name
   site    - the host to fetch it from
   url     - the path to the package on $site

 arguments optional:
   conf    - hashref - values from toaster-watcher.conf
   debug

This sub proved quite useful during 2005 as many packages began to be distributed in bzip format instead of the traditional gzip.


=item sudo

   my $sudo = $utility->sudo();

   $utility->syscmd( command=>"$sudo rm /etc/root-owned-file" );

Often you want to run a script as an unprivileged user. However, the script may need elevated privileges for a plethora of reasons. Rather than running the script suid, or as root, configure sudo allowing the script to run system commands with appropriate permissions.

If sudo is not installed and you're running as root, it'll offer to install sudo for you. This is recommended, as is properly configuring sudo.

 arguments required:

 arguments optional:
   debug

 result:
   0 - failure
   on success, the full path to the sudo binary


=item syscmd

   Just a little wrapper around system calls, that returns any failure codes and prints out the error(s) if present. A bit of sanity testing is also done to make sure the command to execute is safe. 

      my $r = $utility->syscmd( command=>"gzip /tmp/example.txt" );
      $r ? print "ok!\n" : print "not ok.\n";

    arguments required:
      command - the command to execute
      cmd     - alias of command

    arguments optional:
      debug
      fatal

    result
      the exit status of the program you called.


=item try_mkdir

try creating a directory using perl's builtin mkdir.

=item validate_params

Validates that the values passed into a subroutine are:
  a. expected
  b. the right type

If you set 'required' and 'optional', it will also check to verify no additional parameters have been provided. This is an excellent way to catch typos and miscreants attempting to circumvent security measures.

 arguments required:
   sub  - the name of the subroutine whose arguments we are parsing
   min  - the minimum number of arguments expected
   max  - the maximum number of arguments expected
   params - the arguments (an arrayref)

 arguments optional:
   fatal    - die on errors (default)
   required - arguments that must be passed (arrayref)
   optional - arguments that are optional (arrayref)
   debug    - enables status messages

 result:
   0 - failure
   1 - success


=item yes_or_no

  my $r = $utility->yes_or_no( 
      question => "Would you like fries with that?",
      timeout  => 30
  );

	$r ? print "fries are in the bag\n" : print "no fries!\n";

 arguments required:
   none.

 arguments optional:
   question - the question to ask
   timeout  - how long to wait for an answer (in seconds)

 result:
   0 - negative (or null)
   1 - success (affirmative)


=back

=head1 AUTHOR

Matt Simerson (matt@tnpi.net)


=head1 BUGS

None known. Report any to author.


=head1 TODO

  make all errors raise exceptions
  write test cases for every method
  comments. always needs more comments.


=head1 COPYRIGHT

Copyright (c) 2003-2006, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
