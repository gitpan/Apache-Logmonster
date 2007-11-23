#!/bin/sh

INSTALLED=`/usr/sbin/pkg_info | grep Compress-Zlib`
if [ -z "$INSTALLED" ]; then
	echo "installing p5-Compress-Zlib"
	cd /usr/ports/archivers/p5-Compress-Zlib
	make install distclean
else
    echo "Compress::Zlib is installed."
fi

INSTALLED=`/usr/sbin/pkg_info | grep TimeDate`
if [ -z "$INSTALLED" ]; then
	echo "installing p5-TimeDate"
	cd /usr/ports/devel/p5-TimeDate
	make install distclean
else
    echo "TimeDate is installed."
fi

INSTALLED=`/usr/sbin/pkg_info | grep Params`
if [ -z "$INSTALLED" ]; then
	echo "installing p5-Params-Validate"
	cd /usr/ports/devel/p5-Params-Validate
	make install distclean
else
    echo "Params::Validate is installed."
fi

INSTALLED=`/usr/sbin/pkg_info | grep Regexp`
if [ -z "$INSTALLED" ]; then
	echo "installing p5-Regexp-Log"
	cd /usr/ports/textproc/p5-Regexp-Log
	make install distclean
else
    echo "Regexp::Log is installed."
fi
