use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Posy::Plugin::EntryTitles',
    license             => 'perl',
    dist_author         => 'Kathryn Andersen',
    dist_version_from   => 'lib/Posy/Plugin/EntryTitles.pm',
	requires            => {
	'Posy' => 0.90,
	},
    build_requires => {
        'Test::More' => 0,
    },
);

$builder->create_build_script();
