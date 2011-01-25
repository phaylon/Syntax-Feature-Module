use strictures 1;

# ABSTRACT: Provides a module keyword

package Syntax::Feature::Module;

use Carp                                qw( croak );
use B::Hooks::EndOfScope    0.09;
use Params::Classify        0.011       qw( is_ref is_string );
use Sub::Install            0.925       qw( install_sub );
use Devel::Declare          0.006000    ();
use Data::Dump                          qw( pp );

use syntax 0.002 ();

use aliased 'Devel::Declare::Context::Simple', 'Context';

use namespace::clean 0.18;

$Carp::Internal{ +__PACKAGE__ }++;


=method import

    $class->import( %options );

Can be used to directly setup a module keyword via

    use Syntax::Feature::Module -as => 'my_name';

See L</OPTIONS> for a list of available options.

=cut

sub import {
    my ($class, %options) = @_;
    return $class->install(
        into    => scalar( caller ),
        options => \%options,
    );
}


=method install

    $class->install( \%arguments )

Used by the L<syntax> framework to install this extension. The
C<\%arguments> must contain the target package as C<into> and the options
that were given to the extension as C<options>.

=cut

sub install {
    my ($class, %args) = @_;
    my $target  = $args{into};
    my $options = $class->_prepare_options($args{options});
    my $name    = $options->{ -as };
    Devel::Declare->setup_for(
        $target => {
            $name => {
                const => sub {
                    my $ctx = Context->new;
                    $ctx->init(@_);
                    return $class->_transform($ctx, $options);
                },
            },
        },
    );
    install_sub {
        into    => $target,
        as      => $name,
        code    => $class->get_runtime_callback($target),
    };
    on_scope_end {
        namespace::clean->clean_subroutines($target, $name);
    };
    return 1;
}


=method get_default_name

    $class->get_default_name()

Returns the default keyword name. Override this in specialized subclasses.

=cut

sub get_default_name { 'module' }


=method get_default_preamble

    $class->get_default_preamble( \%arguments )

Combines L</get_package_preamble>, L</get_version_preamble> and
L</get_propagation_preamble> into a single call. It will return Perl
statements to be placed at the beginning of the module block. You can
extend this method if you want to automatically load additional
modules.

The C<\%arguments> will be passed on to the specific preamble generators.
It will contain values for the C<name> of the module, its C<version> and
the (normalized) C<options> that were passed to the extension.

=cut

sub get_default_preamble {
    my ($class, $args) = @_;
    return(
        $class->get_package_preamble($args),
        $class->get_version_preamble($args),
        $class->get_propagation_preamble($args),
    );
}


=method get_propagation_preamble

    $class->get_propagation_preamble( \%arguments )

This will provide the statements necessary to install syntax extensions
specified via L</-inner>, and to make sure the current extension is
available inside as well.

=cut

sub get_propagation_preamble {
    my ($class, $args) = @_;
    my $options = $args->{options};
    my $inner   = $options->{-inner} || [];
    return(
        sprintf('use %s %s',
            $class,
            join ', ', map pp($_), %$options,
        ),
        @$inner ? sprintf('use syntax %s',
            join ', ', map pp($_), @$inner
        ) : (),
    );
}


=method get_package_preamble

    $class->get_package_preamble( \%arguments )

Returns a Perl package declaration statement. The C<name> of the package
is taken from the C<\%arguments>.

=cut

sub get_package_preamble {
    my ($class, $args) = @_;
    return sprintf 'package %s', $args->{name};
}


=method get_version_preamble

    $class->get_version_preamble( \%arguments )

Returns a Perl package version declaration statement in the form

    our $VERSION = <your-version>;

The C<version> value for the variable is taken from the C<\%arguments>.

=cut

sub get_version_preamble {
    my ($class, $args) = @_;
    return () unless defined $args->{version};
    return sprintf 'our $VERSION = %s', $args->{version};
}


=method get_runtime_callback

    $class->get_runtime_callback( $target )

This method returns a function that will be invoked for every instance
of the keyword. The callback will receive the name of the package, and
the result of the last evaluated expression in the block.

The default callback simply returns the name of the declared package.

=cut

sub get_runtime_callback {
    my ($class, $target) = @_;
    return sub {
        my ($module, $result) = @_;
        return $module;
    };
}


#
#   private methods
#

sub _transform {
    my ($class, $ctx, $options) = @_;
    $ctx->skip_declarator;
    my $seen = 'keyword';
    $ctx->skipspace;
    $class->_advance($ctx, $class->_inject($ctx, '('));
    my $module_name = $class->_strip_module_name($ctx);
    $seen = 'namespace'
        if defined $module_name;
    $module_name = Devel::Declare::get_curstash_name()
        unless defined $module_name;
    $class->_advance($ctx, $class->_inject($ctx, pp($module_name)));
    $class->_advance($ctx, $class->_inject($ctx, ', do '));
    my $module_version = $class->_strip_module_version($ctx);
    $seen = 'version'
        if defined $module_version;
    my $module_preamble = sprintf '%s; ();', join(';',
        $class->get_default_preamble({
            name    => $module_name,
            version => $module_version,
            options => $options,
        }),
        @{ $options->{ -preamble } },
    );
    croak sprintf q{Expected a block after %s %s, not: %s},
            $ctx->declarator,
            $seen,
            $class->_get_reststr($ctx)
        unless $class->_check_next($ctx, qr/ \{ /x);
    my $scope_callback = $class->_render_scope_callback;
    $class->_advance($ctx, $class->_inject($ctx, $scope_callback, 1));
    $class->_advance($ctx, $class->_inject($ctx, $module_preamble));
}

sub _normalise_options {
    my ($class, $options) = @_;
    return(
        is_ref($options, 'ARRAY')
            ? { -inner => $options }
            :
        is_ref($options, 'HASH')
            ? $options
            :
        defined($options)
            ? croak(qq{Options for $class expected to be array or hash ref})
            : {}
    );
}

sub _normalise_preamble_option {
    my ($class, $options) = @_;
    $options->{ -preamble } = []
        unless defined $options->{ -preamble };
    croak q{The -preamble option only accepts array refs}
        unless is_ref $options->{ -preamble }, 'ARRAY';
    return 1;
}

sub _normalise_inner_option {
    my ($class, $options) = @_;
    $options->{ -inner } = []
        unless defined $options->{ -inner };
    croak q{The -inner option only accepts array refs}
        unless is_ref $options->{ -inner }, 'ARRAY';
    return 1;
}

sub _normalise_as_option {
    my ($class, $options) = @_;
    $options->{ -as } = $class->get_default_name
        unless defined $options->{ -as };
    croak q{The -as option only accepts strings}
        unless is_string $options->{ -as };
    croak sprintf q{The string '%s' cannot be used as keyword for %s syntax},
            $options->{ -as },
            $class,
        unless $options->{ -as } =~ m{ \A [a-z_] [a-z0-9_]* \Z }xi;
    return 1;
}

sub _prepare_options {
    my ($class, $options) = @_;
    $options = $class->_normalise_options($options);
    $class->can("_normalise_${_}_option")->($class, $options) for qw(
        inner
        as
        preamble
    );
    return $options;
}

sub _render_scope_callback {
    my ($class) = @_;
    return sprintf 'BEGIN { %s->_scope_end };', $class;
}

sub _scope_end {
    my ($class) = @_;
    on_scope_end {
        my $linestr = Devel::Declare::get_linestr;
        my $offset  = Devel::Declare::get_linestr_offset;
        substr($linestr, $offset + 1, 0) = '';
        substr($linestr, $offset, 0)     = ')';
        Devel::Declare::set_linestr($linestr);
    };
}

sub _inject {
    my ($class, $ctx, $code, $skip) = @_;
    my $reststr = $class->_get_reststr($ctx);
    $skip = 0 unless defined $skip;
    substr($reststr, $skip, 0) = $code;
    $class->_set_reststr($ctx, $reststr);
    return $skip + length $code;
}

sub _advance {
    my ($class, $ctx, $num) = @_;
    $ctx->inc_offset($num);
    return 1;
}

sub _check_next {
    my ($class, $ctx, $rx) = @_;
    $ctx->skipspace;
    return $class->_get_reststr($ctx) =~ m{ \A $rx }x;
}

sub _get_reststr {
    my ($class, $ctx) = @_;
    return substr($ctx->get_linestr, $ctx->offset);
}

sub _set_reststr {
    my ($class, $ctx, $reststr) = @_;
    my $linestr = $ctx->get_linestr;
    substr($linestr, $ctx->offset) = $reststr;
    $ctx->set_linestr($linestr);
    return 1;
}

my $rxVersion = qr{
    [0-9]               # 2
    (?:                 # 23_17
        [0-9_]*
        [0-9]
    )?
    (?:                 # 23_17.9
        \.
        [0-9]
        (?:             # 23_17.94_77
            [0-9_]*
            [0-9]
        )?
    )*
}x;

sub _strip_module_version {
    my ($class, $ctx) = @_;
    $ctx->skipspace;
    my $reststr     = $class->_get_reststr($ctx);
    if ($reststr =~ s{ \A ($rxVersion) }{}x) {
        my $version = $1;
        $class->_set_reststr($ctx, $reststr);
        return $version;
    }
    else {
        return undef;
    }
}

sub _strip_module_name {
    my ($class, $ctx) = @_;
    return undef
        unless $class->_check_next($ctx, qr{ [^0-9] }x);
    return $ctx->strip_name;
}

1;

__END__

=head1 SYNOPSIS

    use syntax qw( module );

    module Foo::Bar 1.23 {
        sub baz { 45 }
    };

=head1 DESCRIPTION

This syntax extension provides a declarative way to enclose a block of
code in a package namespace.

Note that the keyword is implemented as expression. This means it will not
automatically terminate the statement after the block. It behaves this way
for one out of consistency (since it returns the name of the package) and
to make it available for extended expressions by embedding the declaration
inside a function call and using the returned package name.

Since the keyword returns the name of the package at runtime, you don't
need to follow your declaration up with C<1;>, unless your package name is
false.

=head1 SYNTAX

A full module declaration looks like the following:

    use syntax qw( module );
    module Foo::Bar 2.34 { ... };

This will evaluate the block contents marked with C<...> inside a package
namespace named C<Foo::Bar>. It will also set the C<$VERSION> of C<Foo::Bar>
to C<2.34>.

The version specification is optional, so if you want you can declare the
module like this:

    use syntax qw( module );
    module Foo::Bar { ... };

and the C<$VERSION> won't be touched.

You can go even further and omit the namespace as well. In this case, the
namespace will be inherited from the outside:

    package Foo::Bar;
    use syntax qw( module );
    module { ... };

Of course you can also include a version without giving a namespace:

    package Foo::Bar;
    use syntax qw( module );
    module 2.34 { ... };

This might seem rather pointless with this specific module. But keep in
mind that extensions of the module syntax might automatically provide
other libraries and extensions. This shortcut simply makes you not type
the package name twice if you want both: A short invocation of package
syntax extensions, and not upsetting anything in the CPAN toolchain.

=head1 OPTIONS

=head2 -inner

    use syntax module => { -inner => [qw( function )] };
    module Foo::Bar 2.34 {
        fun baz { 56 }
    };

This option configures the syntax extensions that should be available
inside the block. The above example uses L<Syntax::Feature::Function> as
demonstration.

As a shortcut, you can supply an array reference instead of a hash
reference as argument to set the value of C<-inner>. With this in mind,
the above can be written more easily as

    use syntax module => [qw( function )];
    module Foo::Bar 2.34 {
        fun baz { 56 }
    };

Extensions of this module might choose to provide a default set of inner
syntax features.

=head2 -as

    use syntax module => { -as => 'namespace' };
    namespace Foo::Bar 2.34 {
        sub baz { 56 }
    };

Allows you to override the default keyword name.

=head2 -preamble

    use syntax module => { -preamble => ['use Moose'] };
    module Foo::Bar 2.34 {
        has baz => (is => 'rw');
    };

This option can be used to extend the statements that are included at
the top of the block.

=head1 SEE ALSO

=over

=item * L<syntax>

=item * L<Syntax::Feature::Function>

=item * L<Devel::Declare>

=back

=cut
