use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.


sub MY::postamble 
{

'LOGMONSTER = /Users/matt/Sites/www.tnpi.biz/internet/www/logmonster

docs:
	pod2text logmonster.pl   > README
	pod2text logmonster.pl   > doc/README
	pod2text doc/FAQ.pod     > FAQ
	pod2text doc/FAQ.pod     > doc/FAQ
 
web:
	pod2html --title="logmonster README" logmonster.pl > doc/README.html
	pod2html --title="logmonster FAQ"    doc/FAQ.pod   > doc/FAQ.html
	rm pod2htm*
	install -m 0644 doc/README.html   $(LOGMONSTER)/README.html
	install -m 0644 doc/FAQ.html      $(LOGMONSTER)/FAQ.html
	install -m 0644 Changes           $(LOGMONSTER)/changelog.txt
	install -m 0644 logmonster.pl     $(LOGMONSTER)/logmonster.pl
	install -m 0644 logmonster.conf   $(LOGMONSTER)/logmonster.conf
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
	'VERSION_FROM'  => 'logmonster.pl', # finds $VERSION
	'EXE_FILES'     => [ 'logmonster.pl' ],
	'INSTALLSCRIPT' => '/usr/local/sbin',
	'PREREQ_PM'     => {
			'Compress::Zlib' => 0, 
			'Date::Parse'    => 0 
		}, # e.g., Module::Name => 1.1
	'AUTHOR'         => 'Matt Simerson <matt@tnpi.biz>',
	'ABSTRACT'       => 'log processor utility for merging, sorting, and analyzing Apache logs',
);

