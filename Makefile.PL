use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

use lib 'lib';

sub MY::postamble 
{

'LOGMONSTER = /Users/Shared/Sites/www.tnpi.net/internet/www/logmonster

docs:
	pod2text bin/logmonster.pl         > README
	pod2text doc/FAQ.pod               > FAQ
	pod2text doc/Changes.pod           > Changes
	pod2html --noindex bin/logmonster.pl   > doc/README.html
	pod2html doc/FAQ.pod               > doc/FAQ.html
	pod2html --noindex doc/Changes.pod > doc/Changes.html
	rm pod2htm*
 
web:
	install -m 0644 bin/logmonster.pl $(LOGMONSTER)/logmonster.pl
	install -m 0644 logmonster.conf   $(LOGMONSTER)/logmonster.conf
	install -m 0644 doc/Changes.html  $(LOGMONSTER)/changes.html
	install -m 0644 doc/FAQ.html      $(LOGMONSTER)/faq.html
	install -m 0644 doc/README.html   $(LOGMONSTER)/README.html
	cp Apache-Logmonster-$(VERSION).tar.gz $(LOGMONSTER)/Logmonster.tar.gz
	mv Apache-Logmonster-$(VERSION).tar.gz $(LOGMONSTER)/Apache-Logmonster.tar.gz

conf:
	install -d /usr/local
	install -d /usr/local/etc
	install -m 0644 logmonster.conf /usr/local/etc/logmonster.conf-dist

newconf:
	install -d /usr/local
	install -d /usr/local/etc
	install -m 0644 logmonster.conf /usr/local/etc/logmonster.conf

deps:
	perl bin/install_deps.pl

';

};

WriteMakefile(
	'NAME'	        => 'Apache::Logmonster',
	'VERSION_FROM'  => 'bin/logmonster.pl',
	'EXE_FILES'     => [ 'bin/logmonster.pl' ],
	'INSTALLSCRIPT' => '/usr/local/sbin',
	'PREREQ_PM'     => {
                            'Params::Validate' => .8,
                            'Compress::Zlib'   => 2, 
                            'Date::Parse'      => 2,
                            'Regexp::Log'      => .04,
                            'Mail::Send'       => 0,
                            'URI'              => 1,
                        },
	'AUTHOR'         => 'Matt Simerson (msimerson@cpan.org)',
	'ABSTRACT'       => 'Apache log utility for merging, sorting, and processing web logs',
	'LICENSE'	 => 'bsd',
	clean            => {
                            FILES => [  "t/trash",
                                        "pod2htm*",
                                        "t/tmp_*",
                                    ],
                        },
);

