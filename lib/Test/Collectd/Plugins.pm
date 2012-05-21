package Test::Collectd::Plugins;

use 5.006;
use strict;
use warnings;
use Carp qw(croak cluck);
use DDP;
use POSIX qw/isdigit/;

=head1 NAME

Test::Collectd::Plugins - Common out-of-band collectd plugin test suite

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.1001';

use Package::Alias Collectd => "FakeCollectd";
use base 'Test::Builder::Module';
use IO::File;

our @EXPORT = qw(load_ok read_ok read_values $typesdb);

our $typesdb;

sub import_extra {
	my $class = shift;
	my $list = shift;
	my $args;
	$args = @$list == 1 ? $list->[0] : {@$list};
	@$list = ();
	croak __PACKAGE__." can receive either a hash or a hash reference."
		unless ref $args and ref $args eq "HASH";
	for (keys %$args) {
		if (/^typesdb$/i) {
			$typesdb = $args->{$_};
		}
	}
	return;
}

=head1 SYNOPSIS

    use Test::Collectd::Plugins typesdb => ["/usr/share/collectd/types.db"];

		load_ok ("Collectd::Plugins::Test::Read", "load plugin");
		read_ok ("Collectd::Plugins::Some::Plugin", "plugin_register_values");
    my $config = {
		  Iterval => 60,
			SomeOption => "true",
    };
		read_config_ok ("Collectd::Plugins::Some::Plugin", $config, "plugin_register_values");

		done_testing;

Testing collectd modules outside of collectd's perl interpreter is tedious, as you cannot
simply 'use' them. In fact you can't even 'use Collectd', try it and come back.
This module lets you test collectd plugins outside of the collectd daemon. It is supposed
to be the first step in testing plugins, detecting syntax errors and common mistakes. 
There are some caveats (see dedicated section), and you should use the usual collectd testing
steps afterwards e.g. enabling debug at compile time, then running the collectd binary in
the foreground while using some logging plugin plus some write plugin. I usually use logfile
to STDOUT and csv plugin.

=head1 SUBROUTINES/METHODS

The following methods just reimplement stuff from the collectd perl interpreter.

=head2 load_ok $plugin_module

Tries to load the plugin module and intercepts all calls to L<Collectd/plugin_register> in order to store the arguments in the %FakeCollectd hash. See L</EXAMPLES> section.

=cut

sub load_ok ($;$) {
	my $module = shift;
	my $msg = shift || "load OK";
	_load_module($module);
	__PACKAGE__->builder->is_eq($@, "", $msg);
}

sub _load_module ($) {
	my $module = shift;
	eval "require $module";
}

=head2 read_ok $plugin_module, $plugin_name

First does the same as L</load_ok> then tries to fire up the registered read callback, while intercepting all calls to L<Collectd/plugin_dispatch_values>, storing its arguments into the %FakeCollectd hash. The latter are checked against the following rules:

=over 2

=cut

sub read_ok ($$;$) {
	my $module = shift;
	my $plugin = shift;
	my $msg = shift || "read OK";

	my $tb = __PACKAGE__->builder;

$tb -> subtest($msg, sub {

	$tb->ok(_load_module($module), "load plugin module");

	$tb->ok(defined $FakeCollectd{$plugin}->{Callback}->{Read}, "read callback defined");
	my $reader = $FakeCollectd{$plugin}->{Callback}->{Read};
	eval "$reader()";
	$tb->is_eq($@,"","reader returned");
	my @values;
	if (exists $FakeCollectd{$plugin}->{Values}) {
		@values = @{$FakeCollectd{$plugin}->{Values}};
	} else {
		die $@;
	}
	$tb->ok(scalar @values, "dispatch called");
	for (@values) {
		$tb->is_eq(ref $_,"ARRAY","value is array");

=item * There shall be only one and only one hashref argument

=cut

		$tb->ok(scalar @$_, "plugin called dispatch with arguments");
		$tb->cmp_ok (@$_, '>', 1, "only one value_list expected");
		my $ref = ref $_->[0];
		$tb->is_eq($ref, "HASH", "value is HASH"); # this should be handled already earlier
		my %dispatch = %{$_->[0]};

=item * The following keys are mandatory: plugin, type, values

=cut

		for (qw(plugin type values)) {
			$tb->ok(exists $dispatch{$_}, "key '$_' exists") or return undef;
		}

=item * Only the following keys are valid: plugin, type, values, time, interval, host, plugin_instance, type_instance.

=cut

		for (keys %dispatch) {
			$tb->like ($_, qr/^(plugin|type|values|time|interval|host|plugin_instance|type_instance)$/, "key $_ is valid");
		}

=item * The key C<type> must be present in the C<types.db> file.

=cut

		my @type = _get_type($dispatch{type});
		$tb->ok (@type, "type $dispatch{type} matches " . join (", ", @$typesdb));

=item * The key C<values> must be an array reference and the number of elements must match its data type in module's configuration option C<types.db>.

=cut

		my $vref = ref $dispatch{values};
		$tb->is_eq ($vref, "ARRAY", "values is ARRAY");
		$tb -> is_eq(scalar @{$dispatch{values}}, scalar @type, "number of dispatched 'values' matches type spec for '$dispatch{type}'");

=item * All other keys must be scalar strings with at most 63 characters: C<plugin>, C<type>, C<host>, C<plugin_instance> and C<type_instance>.

=cut

		for (qw(plugin type host plugin_instance type_instance)) {
			if (exists $dispatch{$_}) {
				my $ref = ref $dispatch{$_};
				$tb->is_eq ($ref, "", "$_ is SCALAR");
				$tb->cmp_ok(length $dispatch{$_}, '<', 63, "$_ is valid");
			}
		}

=item * The keys C<time> and C<interval> must be a positive integers.

=cut

		for (qw(time interval)) {
			if (exists $dispatch{$_}) {
				$tb->cmp_ok($dispatch{$_},'>',0,"$_ is valid");
			}
		}

=item * The keys C<host>, C<plugin_instance> and C<type_instance> may use all ASCII characters except "/".

=cut

		for (qw/host plugin_instance type_instance/) {
			if (exists $dispatch{$_}) {
				$tb->unlike($dispatch{$_}, qr/\//, "$_ valid");
			}
		}

=item * The keys C<plugin> and C<type> may use all ASCII characters except "/" and "-".

=cut

		for (qw/plugin type/) {
			if (exists $dispatch{$_}) {
				$tb->unlike($dispatch{$_}, qr/[\/-]/, "$_ valid");
			}
		}

=back

=cut

	}

	$tb -> ok(@values);
}); # end subtest
}

=head2 read_values (module, plugin)

Returns arrayref containing the list of arguments passed to L<Collectd/plugin_dispatch_values>. Example:

	[
		# first call to L<Collectd/plugin_dispatch_values>
		[
			{ plugin => "myplugin", type => "gauge", values => [ 1 ] },
		],
		# second call to L<Collectd/plugin_dispatch_values>
		[
			{ plugin => "myplugin", type => "gauge", values => [ 2 ] },
		],
	]

=cut

sub read_values {
	my $module = shift;
	my $plugin = shift;
	_load_module($module);
	if (exists $FakeCollectd{$plugin}->{Values}) {
		@{$FakeCollectd{$plugin}->{Values}};
	} else {
		return;
	}
}

sub _get_type {
	my $type = shift;
	if ($typesdb) {
		my $ref = ref $typesdb;
		if ($ref eq "HASH") {
			warn "typesdb is a hash, discarding its keys";
			$typesdb = [values %$typesdb];
		} elsif ($ref eq "") {
			$typesdb = [ $typesdb ];
		}
	} else {
		warn "empty typesdb! using builtin";
		require File::ShareDir;
		$typesdb = [ File::ShareDir::module_file(__PACKAGE__, "types.db") ];
	}
	for my $file (@$typesdb) {
		my $fh = IO::File -> new($file, "r");
		unless ($fh) {
			cluck "Error opening types.db: $!";
			return undef;
		}
		while (<$fh>) {
			my ($t, @ds) = split /\s+/, $_;
			if ($t eq $type) {
				my @ret;
				for (@ds) {
					my @stuff = split /:/;
					push @ret, {
						ds   => $stuff[0],
						type => $stuff[1],
						min  => $stuff[2],
						max  => $stuff[3],
					};
				}
				return @ret;
			}
		}
	}
	return ();
}

=head1 CAVEATS

=head2 methods

Replacements for most common L<Collectd::Plugins> methods are implemented, as well as constants. We may have missed some or many, and as new ones are added to the main collectd tree, we will have to keep up to date.

=head2 config

There's no straightforward way for testing plugin configuration files
as these are being parsed by liboconfig which is part of collectd. This
is why you need to pass the configuration to the constructor.

=head2 types.db

If no types.db list is being specified during construction, the object will try to use the shipped version.
Also, if a list is given, the first appearance of the type will be used; this may differ from collectd's mechanism.

=head1 AUTHOR

Fabien Wernli, C<< <wernli_workingat_in2p3.fr> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-test-collectd-plugins at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Test-Collectd-Plugins>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Test::Collectd::Plugins


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-Collectd-Plugins>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Test-Collectd-Plugins>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Test-Collectd-Plugins>

=item * Search CPAN

L<http://search.cpan.org/dist/Test-Collectd-Plugins/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Fabien Wernli.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Test::Collectd::Plugins

