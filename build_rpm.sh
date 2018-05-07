#!/bin/sh

SPECFILE=perl-Test-Collectd-Plugins.spec
RPMBUILD_TOPDIR=$PWD/rpmbuild

mkdir -p $RPMBUILD_TOPDIR/SPECS -p $RPMBUILD_TOPDIR/SOURCES
#spectool -C $RPMBUILD_TOPDIR/SOURCES -g $SPECFILE
yum-builddep -y $SPECFILE
perl Makefile.PL
make dist
make test
mv Test-Collectd-Plugins-*.tar.gz $RPMBUILD_TOPDIR/SOURCES

rpmbuild --define "_topdir $RPMBUILD_TOPDIR" -ba $SPECFILE

