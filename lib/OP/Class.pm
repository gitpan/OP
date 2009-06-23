#
# File: OP/Class.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Class;

##
## Pragma
##

use strict;
use warnings;
# use diagnostics;
#
# gentle stern harsh cruel brutal
#
# use criticism 'cruel';
use base qw| Exporter |;

##
## Package Constants
##

use constant DefaultSubclass => 'OP::Node';

##
## Import Libraries
##

use Error qw| :try |;
use OP::Enum::Bool;
use OP::Utility;
use Scalar::Util qw| blessed reftype |;

##
## Class Vars & Exports
##

our @EXPORT_OK = (
  qw|
    true false

    create
    |,
);


##
## Private Class Methods
##

#
#
#
# method __checkVarName (OP::Class $class: Str $varName) {
sub __checkVarName {
  my $class = shift;
  my $varName = shift;

  if ( $varName !~ /^[\w\_]{1,64}$/xsm ) {
    throw OP::InvalidArgument(
      "Bad class var name \"$varName\" specified" );
  }

  return true;
};

#
#
#
# method __init (OP::Class $class:) {
sub __init {
  my $class = shift;

  return true;
};

##
## Public Class Methods
##

#
#
#
# method create (Str $class: Hash $args) {
sub create {
  my $class = shift;
  my $args = shift;

  my $reftype = reftype( $args );

  if ( !$reftype ) {
    throw OP::InvalidArgument(
      "create() needs a HASH ref for an argument" );
  }

  if ( $reftype ne 'HASH' ) {
    throw OP::InvalidArgument(
      "create() needs a HASH ref for an argument, got: " . $reftype );
  }

  $args->{__BASE__} ||= DefaultSubclass;

  my $basereftype = reftype( $args->{__BASE__} );

  my @base;

  if ( $basereftype ) {
    if (
      ( $basereftype eq 'SCALAR' )
        && overload::Overloaded($args->{__BASE__})
    ) {
      @base = "$args->{__BASE__}"; # Stringify
    } elsif ( $basereftype eq 'ARRAY' ) {
      @base = @{$args->{__BASE__}};
    } else {
      throw OP::InvalidArgument(
        "__BASE__ must be a string or ARRAY reference, not $basereftype" );
    }

  } else {
    @base = $args->{__BASE__};
  }

  #
  # Remove from list of actual class members:
  #
  delete $args->{__BASE__};

  for my $base ( @base ) {
    my $baselib = $base;
    $baselib =~ s/::/\//gxms;
    $baselib .= ".pm";

    eval { require $baselib };

    $base->import();
  }

  #
  # Stealth package allocation! This is about the same as:
  #
  #   eval "package $class; use base @base;"
  #
  # But does so without an eval.
  #
  do {
    no strict "refs";

    @{"$class\::ISA"} = @base;
  };

  for my $key ( keys %{$args} ) {
    my $arg = $args->{$key};

    if ( $key !~ /^__/xsm
      && blessed( $arg )
      && $arg->isa( "OP::Type" ) )
    {

      #
      # Asserting an instance variable
      #
      # e.g. foo => Str(...)
      #
      $class->asserts()->{$key} = $arg;

    } elsif ( ref( $arg ) && reftype( $arg ) eq 'CODE' ) {

      #
      # Defining a method
      #
      # e.g. foo => sub { ... }
      #
      do {
        no strict "refs";

        *{"$class\::$key"} = $arg;
      };

    } elsif ( $key =~ /^__\w+$/xsm ) {

      #
      # Setting a class variable
      #
      # e.g. __foo => "Bario"
      #
      $class->set( $key, $arg );

    } else {
      throw OP::ClassAllocFailed(
"$class member $key needs to be an OP::Type instance or CODE ref"
      );
    }
  }

  $class->__init();

  return $class;
};

#
#
#
# method get (OP::Class $class: Str $key) {
sub get {
  my $class = shift;
  my $key = shift;

  $class->__checkVarName( $key );

  my @value;

  do {
    no strict "refs";
    no warnings "once";

    @value = @{"$class\::$key"};
  };

  return wantarray() ? @value : $value[0];
};

#
#
#
# method members (OP::Class $class:) {
sub members {
  my $class = shift;

  my @members;

  do {
    no strict 'refs';

    @members =
      grep { defined &{"$class\::$_"} } sort keys %{"$class\::"};
  };

  return \@members;
};

#
#
#
# method membersHash (OP::Class $class:) {
sub membersHash {
  my $class = shift;

  my %members;

  for my $key ( @{$class->members()} ) {
    $members{$key} = \&{"$class\::$key"};
  }

  return \%members;
};

#
#
#
# method pretty (OP::Class $class: Str $key) {
sub pretty {
  my $class = shift;
  my $key = shift;

  my $pretty = $key;

  $pretty =~ s/(.)([A-Z])/$1 $2/gxsm;

  return ucfirst $pretty;
};

#
#
#
# method set (OP::Class $class: Str $key, *@value) {
sub set {
  my $class = shift;
  my $key = shift;
  my @value = @_;

  $class->__checkVarName( $key );

  do {
    no strict "refs";
    no warnings "once";

    @{"$class\::$key"} = @value;
  };

  return true;
};

##
## End of package
##

true;

__END__

=pod

=head1 NAME

OP::Class - Root-level "Class" class


=head1 VERSION

$Id: //depotit/tools/source/snitchd-0.20/lib/OP/Class.pm#9 $


=head1 SYNOPSIS

=head2 Class Allocation

  #
  # File: OP/Example.pm
  #

  use OP qw| create true false |;

  create "OP::Example" => {
    #
    # This is an empty class prototype
    #
  };

=head2 Class Consumer

  #
  # File: testscript.pl
  #

  use strict;
  use warnings;

  use OP::Example;

  my $exa = OP::Example->new();

  $exa->setName("My First OP Object");

  $exa->save("This is a checkin comment");

  say "Saved object:";

  $exa->print();


=head1 DESCRIPTION

OP::Class is the root-level parent class in OP, and also provides the class
prototyping function C<create()>.


=head1 METHODS

=head2 Public Class Methods

=over 4

=item * C<get(OP::Class $class: Str $key)>

Get the named class variable

  my $class = "OP::Example";

  my $scalar = $class->get($key);

  my @array = $class->get($key);

  my %hash = $class->get($key);


=item * C<set(OP::Class $class: Str $key, *@value)>

Set the named class variable to the received value

  my $class = "OP::Example";

  $class->set($key, $scalar);

  $class->set($key, @array);

  $class->set($key, %hash);


=item * C<pretty(OP::Class $class: Str $key)>

Transform camelCase to Not Camel Case

  my $class = "OP::Example";

  my $uglyStr = "betterGetThatLookedAt";

  my $prettyStr = $class->pretty($uglyStr);


=item * C<members(OP::Class $class:)>

Class introspection method.

Return an array ref of all messages supported by this class.

Does not include messages from superclasses.

  my $members = OP::Example->members();


=item * C<membersHash(OP::Class $class:)>

Class introspection method.

Return a hash ref of all messages supported by this class.

Does not include messages from superclasses.

  my $membersHash = OP::Example->membersHash();


=back

=head2 Private Class Methods

=over 4

=item * C<init(OP::Class $class:)>

Abstract callback method invoked immediately after a new class is
allocated via create().

Override in subclass with additional logic, if necessary.


=item * C<__checkVarName(OP::Class $class: Str $varName)>

Checks the "safeness" of a class variable name before eval'ing it.


=back


=head1 PROTOTYPE COMPONENTS

=head2 Class (Package) Name

The B<name> of the class being created is the first argument sent to
C<create()>.

  use OP qw| create |;

  #
  # The class name will be "OP::Example":
  #
  create "OP::Example" => {

  };

=head2 Class Prototype

A B<class prototype> is a hash describing all fundamental
characteristics of an object class. It's the second argument sent
to C<create()>.

  create "OP::Example" => {
    #
    # This is an empty prototype (perfectly valid)
    #
  };

=head2 Instance Variables

Instance variables are declared with the C<assert> class method:

  create "YourApp::Example" => {
    favoriteNumber => OP::Int->assert(
      ::optional
    ),

    favoriteColor  => OP::Str->assert(
      qw| red green blue |,
      ::optional
    ),
  };


=head2 Instance Methods

Instance methods are declared as keys in the class prototype. The name
of the method is the key, and its value in the prototype is a Perl 5
C<sub{}>.

  create "OP::Example" => {
    #
    # Add a public instance method, $self->handleFoo()
    #
    handleFoo => sub {
      my $self = shift;

      printf 'The value of foo is %s', $self->foo();
      print "\n";

      return true;
    }
  }

  my $exa = OP::Example->new();

  $exa->setFoo("Bar");

  $exa->handleFoo();

  #
  # Expected output:
  #
  # The value of foo is Bar
  #

The OP convention for private or protected instance methods is
to prefix them with a single underscore.

  create "OP::Example" => {
    #
    # private instance method
    #
    _handleFoo => sub {
      my $self = shift;

      say "The value of foo is $self->{foo}";
    }
  };

=head2 Class Variables

Class variables are declared as keys in the class prototype. They should
be prepended with double underscores (__). The value in the prototype is
the literal value to be used for the class variable.

  use OP qw| create true false |;

  create "OP::Example" => {
    #
    # Override a few class variables
    #
    __useYaml => false,
    __dbiType => OP::DBIType::MySQL
  };

OP class variables are just Perl package variables, scoped in a list
using C<our>.

  package OP::Example;

  use OP qw| true false |;

  use base qw| OP::Node |;

  our @__useYaml = false;
  our @__dbiType = OP::DBIType::MySQL;

  true;

=head2 Class Methods

Class methods are declared in the same manner as instance methods. The
only difference is that the class will be the receiver.

  create "OP::Example" => {
    #
    # Add a public class method
    #
    loadXml => sub {
      my $class = shift;
      my $xml = shift;

      # ...
    }
  };

The OP convention for private or protected class methods is
to prefix them with double underscores.

  create "OP::Example" => {
    #
    # Override a private class method
    #
    __basePath => sub {
      my $class = shift;

      return join('/', '/tmp', $class);
    }
  };

=head2 Inheritance

By default, classes created with C<create()> inherit from L<OP::Node>. To
override this, include a C<__BASE__> attribute, specifying the parent
class name.

  create "OP::Example" => {
    #
    # Override parent class
    #
    __BASE__ => "Acme::CustomClass"
  };


=head1 OPTIONAL EXPORTS

=head2 Constants

=over 4

=item * C<true>, C<false>

Constants provided by L<OP::Enum::Bool>

  use OP qw| true false |;

=back

=head2 Functions

=over 4

=item * C<create(Str $class: Hash $prototype)>

  use OP qw| create |;

Allocate a new OP-derived class.

Objects instantiated from classes allocated with C<create()> have
built-in runtime assertions-- simple but powerful rules in the
class prototype which define runtime and schema attributes. See the
L<OP::Type> module for more about assertions.

OP classes are regular old Perl packages. C<create()> is just a wrapper
to the C<package> keyword, with some shortcuts thrown in.

  use OP qw| create true false |;

  create "OP::Example" => {
    __someClassVar => true,

    someInstanceVar => OP::Str->assert(),

    anotherInstanceVar => OP::Str->assert(),

    publicInstanceMethod => sub {
      my $self = shift;

      # ...
    },

    _privateInstanceMethod => sub {
      my $self = shift;

      # ...
    },

    publicClassMethod => sub {
      my $class = shift;

      # ...
    },

    __privateClassMethod => sub {
      my $class = shift;

      # ...
    },
  };


=back


=head1 DIAGNOSTICS

XXX TODO Figure out what to put in this section.


=head1 CONFIGURATION AND ENVIRONMENT

OP looks for the C<.oprc> configuration file under the location specified
by C<$OP_HOME>. See L<OP::Constants> for details.

=head2 OP under mod_perl/mod_perl2

OP classes should be precompiled under mod_perl by referencing them in
the Apache instance's C<startup.pl> script. OP_HOME must be set in a
BEGIN block.

  #
  # File: startup.pl
  #
  BEGIN {
    $ENV{OP_HOME} = '/home/user/op'; # Directory with the .oprc
  }

  #
  # Load any OP-derived packages at startup:
  #
  use MyApp::Component;
  use MyApp::OtherComponent;

  1;

=head2 OP under HTML::Mason

OP classes should be preloaded by C<startup.pl>, as in the above example.

B<If (and only if) you are not using a startup.pl>: Mason loads packages
outside the context of package C<main>, but OP must currently be
bootstrapped from package C<main>, so one must explicitly drop back into
C<main> before consuming OP-derived classes. Do this in a C<do> block.

  <%init>

    do {
      package main;

      use MyApp::Component;
    }

  </%init>
  <%perl>

    $m->print( MyApp::Component->sayHello() );

  </%perl>

It is highly recommended that startup.pl be used in production
environments, so the initial requests to the webserver are not delayed
by the lengthy source filtering and compilation steps.

  #
  # File: httpd.conf
  #
  PerlModule HTML::Mason::ApacheHandler
  PerlRequire /opt/op/bin/startup.pl

  <LocationMatch "/.*\.html$">
    SetHandler perl-script

    PerlHandler HTML::Mason::ApacheHandler
  </LocationMatch>

=head1 DEPENDENCIES

OP's dependencies are numerous, and subject to change while the API is
ironed out. See the Makefile.PL which accompanied this distribution for
a current list of prerequisites.

=head1 INCOMPATIBILITIES

Probably.

=head1 BUGS AND LIMITATIONS

Likely.

Test suite is currently incomplete.

=head1 SEE ALSO

L<OP::Type>, L<OP::Subtype>

This file is part of L<OP>.

=cut
