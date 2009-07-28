#
# File: OP/Name.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Name;

use strict;
use warnings;

use base qw| OP::Str |;

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs(
    OP::Type::isStr, @rules
  );

  if ( !$parsed{columnType} ) {
    $parsed{columnType} = 'VARCHAR(128)';
    $parsed{maxSize}    = 128;
  }

  #
  # Name must always be unique, one way or another...
  #
  if ( !$parsed{unique} ) {
    $parsed{unique} = 1;
  }

  return $class->__assertClass()->new(%parsed);
}

1;
__END__
=pod

=head1 NAME

OP::Name - A unique secondary key

=head1 SYNOPSIS

  use OP;

  #
  # Permit NULL values for "name":
  #
  create "YourApp::Example" => {
    name => OP::Name->assert(
      subtype(
        optional => true
      )
    ),

    # ...
  };

=head1 DESCRIPTION

OP uses "named objects". By default, C<name> is a human-readable
unique secondary key. It's the name of the object being saved.
Like all attributes, C<name> must be defined when saved, unless asserted
as C<::optional> (see "C<undef> Requires Assertion" in L<OP>.).

The value for C<name> may be changed (as opposed to C<id>, which should
not be tinkered with), as long as the new name does not conflict with
any objects in the same class when saved. Since OP objects refer
to one another by GUID, names can be changed freely without impacting
dependent objects.

Objects may be loaded by name using the C<loadByName> class method.

  #
  # Rename an object
  #
  my $person = YourApp::Person->loadByName("Bob");

  $person->setName("Jim");

  $person->save(); # Bob is now Jim.


C<name>, or any attribute type in OP, may be may be keyed in
combination with multiple attributes via the C<::unique> L<OP::Subtype>
argument, which adds InnoDB reference options to the schema. Provide
the names of the attributes which you are uniquely keying with as
arguments to the ::unique subtype constructor.

At the time of this writing, total column length for keys in InnoDB
(regardless of if you're using singular or combinatorial keys) may
not exceed 255 bytes (when using UTF8 encoding, as OP does).

  #
  # Key using a combination of name + other attributes
  #
  create "YourApp::Example" => {
    name => OP::Name->assert(
      subtype(
        unique => "parentId"
      )
    ),

    parentId => OP::ExtID->assert("YourApp::Example"),

    # ...
  };


C<name>'s typing rules may be altered in the class prototype to use
OP classes other than OP::Name. Subtyping rules for uniqueness are not
provided by default for other OP classes, though, so this should
be included by the developer when implementing the class, for example:

  #
  # Make sure that all names are unique, fully qualified hostnames:
  #
  create "YourApp::Example" => {
    name => OP::Domain->assert(
      subtype(
        unique => true
      ),
    ),

    # ...
  };


=head1 SEE ALSO

This file is part of L<OP>.

=cut
