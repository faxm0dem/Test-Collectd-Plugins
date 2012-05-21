use inc::Module::Install;

name     'Test-Collectd-Plugins';
all_from 'lib/Test/Collectd/Plugins.pm';
author   q{Fabien Wernli <wernli_workingat_in2p3.fr>};
license  'perl';

build_requires 'Test::More';

requires 'Package::Alias';

install_share 'share';

auto_install;

WriteAll;

