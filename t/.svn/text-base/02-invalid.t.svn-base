#!/usr/bin/perl

use strict;
use warnings;
use lib "t/lib";
use Test::More;
use Test::Collectd::Plugins typesdb => File::Spec->catfile($ENV{PWD}, 'share', 'types.db');
use Module::Find;

my @module = findsubmod "Collectd::Plugins::NOK";
plan tests => @module * 2;
for (@module) {
	my $module = $_;
	(my $plugin = $module) =~ s/^Collectd::Plugins:://;
	load_ok($module);
	ok (! read_values ($module,$plugin), "plugin $plugin can't read");
}

1;

