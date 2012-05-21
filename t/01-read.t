#!/usr/bin/perl

use strict;
use warnings;
use lib "t/lib";
require File::Spec;
use Test::Collectd::Plugins typesdb => File::Spec->catfile($ENV{PWD}, 'share', 'types.db');
use Data::Dumper;
use Test::More;
use Module::Find;
use FindBin;

my @found = findsubmod "Collectd::Plugins::OK";
plan tests => @found * 3;

for (@found) {
	my $module = $_;
	(my $modulepath = $module) =~ s/::/\//g;
	(my $plugin = $module) =~ s/^Collectd::Plugins:://;

	load_ok ($module);
	read_ok ($module, $plugin);
	my @val = read_values ($module, $plugin);
	my $expected = do "$FindBin::Bin/dat/$modulepath.dat";
	is_deeply(\@val, $expected, "data matches");
}

1;

