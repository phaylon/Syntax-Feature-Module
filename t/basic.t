use strictures 1;
use Test::More  0.96;
use Test::Fatal 0.003;
use FindBin     qw( $Bin );
use lib "$Bin/lib";

subtest 'basic' => sub {
    package TestA;
    use syntax qw( module );
    my $ret = module Foo::Bar 1.23 {
        sub foo { __PACKAGE__ }
    };
    ::is $ret,          'Foo::Bar', 'package name returned';
    ::is $ret->foo,     $ret,       'subroutine';
    ::is $ret->VERSION, 1.23,       'module version';
    my $no_version = module Foo::NoV { 23 };
    ::is $no_version,   'Foo::NoV', 'without version';
    my $no_package = module 2.34 {
        sub foo { __PACKAGE__ }
    };
    ::is $no_package,       'TestA', 'no package';
    ::is $no_package->foo,  'TestA', 'resolution with no package';
    my $nothing = module {
        sub bar { __PACKAGE__ }
    };
    ::is $nothing,      'TestA', 'no package and no version';
    ::is $nothing->bar, 'TestA', 'resolution with no package and no version';
    ::done_testing;
};

subtest 'inner syntax declaration' => sub {
    package TestB;
    use syntax module => [module => { -as => 'mod' }];
    my $ret_foo = module Foo 1.23 {
        my $ret_bar = mod Bar 2.34 {
            ::is __PACKAGE__, 'Bar', 'inner package';
        };
        my $ret_repeat = module Baz 3.45 {
            ::is __PACKAGE__, 'Baz', 'repeated declaration';
        };
        ::is __PACKAGE__, 'Foo', 'outer package';
        ::is $ret_bar,    'Bar', 'inner package return';
        ::is $ret_repeat, 'Baz', 'repeated declaration return';
    };
    ::is $ret_foo, 'Foo', 'outer package return';
    ::done_testing;
};

subtest 'inline packages' => sub {
    package TestC;
    use syntax qw( module );
    my ($m, $n) = (module Foo 2.34 { }, module Bar 3.45 { });
    ::is $m, 'Foo', 'first package in list';
    ::is $n, 'Bar', 'second package in list';
    ::done_testing;
};

subtest 'multiple' => sub {
    package TestD;
    BEGIN {
        Syntax::Feature::Module->install_multiple(
            into    => 'TestD',
            blocks => {
                class => {
                    -inner      => [module => { -as => 'in_class' }],
                    -preamble   => ['my $FOO = 23'],
                },
                role => {
                    -inner      => [module => { -as => 'in_role' }],
                    -preamble   => ['my $BAR = 17'],
                },
            },
            options => {
                -inner => [module => { -as => 'in_both' }],
            },
        );
    }
    my $class_ret = class Foo::Class {
        my $inner_ret = in_class Foo::Class::Inner {
            ::is __PACKAGE__, 'Foo::Class::Inner', 'class inner package';
        };
        ::is $inner_ret, 'Foo::Class::Inner', 'class inner return';
        ::is $FOO, 23, 'class preamble';
    };
    my $role_ret = role Foo::Role {
        my $inner_ret = in_role Foo::Role::Inner {
            ::is __PACKAGE__, 'Foo::Role::Inner', 'role inner package';
        };
        ::is $inner_ret, 'Foo::Role::Inner', 'role inner return';
        ::is $BAR, 17, 'role preamble';
    };
    ::is $class_ret, 'Foo::Class', 'class return';
    ::is $role_ret,  'Foo::Role',  'role return';
};

subtest 'errors' => sub {
    like(
        exception { require MY::Invalid::Semicolon },
        qr{
            \A expected \s+ a \s+ block
            .+ after \s+ module \s+ version
        }xi,
        'semicolon instead of block',
    );
    like(
        exception { require MY::Invalid::SemicolonNoVersion },
        qr{
            \A expected \s+ a \s+ block
            .+ after \s+ module \s+ namespace
        }xi,
        'semicolon instead of block without version',
    );
    like(
        exception { require MY::Invalid::SemicolonNothing },
        qr{
            \A expected \s+ a \s+ block
            .+ after \s+ module \s+ keyword
        }xi,
        'semicolon instead of block with empty declaration',
    );
    package TestErrors;
    use syntax;
    ::like(
        ::exception { syntax->import(module => \'foo') },
        qr{ array \s+ or \s+ hash \s+ ref }xi,
        'wrong option type',
    );
    ::like(
        ::exception { syntax->import(module => { -as => [] }) },
        qr{ -as \s+ option .* only \s+ accepts \s+ strings }xi,
        'non-string name',
    );
    ::like(
        ::exception { syntax->import(module => { -as => 23 }) },
        qr{ string .* 23 .* cannot .* keyword }xi,
        'invalid name for identifier',
    );
    ::like(
        ::exception { syntax->import(module => { -inner => 23 }) },
        qr{ -inner \s+ option \s+ only \s+ accepts \s+ array \s+ refs }xi,
        'wrong type for -inner',
    );
    ::like(
        ::exception { syntax->import(module => { -preamble => 23 }) },
        qr{ -preamble \s+ option \s+ only \s+ accepts \s+ array \s+ refs }xi,
        'wrong type for -preamble',
    );
};

done_testing;
