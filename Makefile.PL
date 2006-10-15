use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.


sub MY::postamble 
{

'LOGMONSTER = /Users/Shared/Sites/www.tnpi.biz/internet/www/logmonster

docs:
	pod2text logmonster.pl             > README
	pod2text doc/FAQ.pod               > FAQ
	pod2text doc/Changes.pod           > Changes
	pod2html --noindex logmonster.pl   > doc/README.html
	pod2html doc/FAQ.pod               > doc/FAQ.html
	pod2html --noindex doc/Changes.pod > doc/Changes.html
 
web:
	install -m 0644 logmonster.pl     $(LOGMONSTER)/logmonster.pl
	install -m 0644 logmonster.conf   $(LOGMONSTER)/logmonster.conf
	install -m 0644 doc/Changes.html  $(LOGMONSTER)/changes.html
	install -m 0644 doc/FAQ.html      $(LOGMONSTER)/faq.html
	install -m 0644 doc/README.html   $(LOGMONSTER)/README.html
	mv Apache-Logmonster-$(VERSION).tar.gz $(LOGMONSTER)/Logmonster.tar.gz

conf:
	install -d /usr/local
	install -d /usr/local/etc
	install -m 0644 logmonster.conf /usr/local/etc/logmonster.conf-dist

newconf:
	install -d /usr/local
	install -d /usr/local/etc
	install -m 0644 logmonster.conf /usr/local/etc/logmonster.conf

';

};


WriteMakefile(
	'NAME'	        => 'Apache::Logmonster',
	'VERSION_FROM'  => 'logmonster.pl',
	'EXE_FILES'     => [ 'logmonster.pl' ],
	'INSTALLSCRIPT' => '/usr/local/sbin',
	'PREREQ_PM'     => {
                            'Compress::Zlib' => 0, 
                            'Date::Parse'    => 0 
                        },
	'AUTHOR'         => 'Matt Simerson (matt@tnpi.net)',
	'ABSTRACT'       => 'Apache log utility for merging, sorting, and processing web logs',
	clean            => {
                            FILES => [  "t/trash",
                                        "pod2htm*",
                                        "t/tmp_*",
                                    ],
                        },
);

