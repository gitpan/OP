#
# File: OP.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

package OP;

our $VERSION = '0.304';

use strict;
use diagnostics;

#
# Abstract classes
#
use OP::Class qw| create true false |;
use OP::Type;
use OP::Subtype;
use OP::Object;
use OP::Node;

#
# Core object classes
#
use OP::Any;
use OP::Array qw| yield emit break |;
use OP::Bool;
use OP::Code;
use OP::DateTime;
use OP::Domain;
use OP::Double;
use OP::EmailAddr;
use OP::ExtID;
use OP::Float;
use OP::Hash;
use OP::ID;
use OP::Int;
use OP::IPv4Addr;
use OP::Name;
use OP::Num;
use OP::Ref;
use OP::Rule;
use OP::Scalar;
use OP::Str;
use OP::TimeSpan;
use OP::URI;

use base qw| Exporter |;

our @EXPORT = (
  #
  # From OP::Class:
  #
  "create", "true", "false",
  #
  # From OP::Array:
  #
  "yield", "emit", "break",
  #
  # From Error:
  #
  # "try", "catch", "with", "finally",
  #
  # Subtyping functions:
  #
  keys %OP::Type::RULES
);

#
#
#

do {
  #
  # Workaround for AutoLoader: AutoLoader emits undef warnings in the
  # context of a "require" statement, when objects without an explicit
  # DESTROY method are culled.
  #
  # To work around this, OP adds an abstract DESTROY method to the the
  # UNIVERSAL package, which all objects in Perl inherit from. The DESTROY
  # method may be overridden as usual on a per-class basis.
  #
  no strict "refs";

  *{"UNIVERSAL::DESTROY"} = sub { };
};

true;
__END__
=pod

=head1 NAME

OP - Compact prototyping of InnoDB-backed object classes

=head1 VERSION

This documentation is for version B<0.304> of OP.

=head1 STATUS

The usual pre-1.0 warnings apply. Consider this alpha code. It does what
we currently ask of it, and maybe a little more, but it is a work in
progress.

=head1 SYNOPSIS

  use OP;

A cheat sheet, C<ex/cheat.html>, is included with this distribution.

=head1 DESCRIPTION

OP is a Perl 5 framework for prototyping InnoDB-backed object classes.

This document covers the high-level concepts implemented in OP.

=head1 FRAMEWORK ASSUMPTIONS

When using OP, as with any framework, a number of things "just happen"
by design. Trying to go against the flow of any of these base assumptions
is not recommended.

=head2 Default Base Attributes

Unless overridden in C<__baseAsserts>, OP classes always have
the following baseline attributes:

=over 4

=item * C<id> => L<OP::ID>

C<id> is the primary key at the database table level.

Objects will use a GUID (globally unique identifier) for their id,
unless this behavior is overridden in the instance method C<_newId()>,
and C<__baseAsserts()> overridden to use a non-GUID data type such
as L<OP::Int>.

C<id> is automatically set when saving an object to its backing
store for the time. Modifying C<id> manually is not recommended.

=item * C<name> => L<OP::Name>

C<name> is a unique, secondary, human-readable key.

For more information on named objects, see L<OP::Name>.

=item * C<ctime> => L<OP::DateTime>

C<ctime> is the Unix timestamp representing the object's creation
time. OP sets this when saving an object for the first time.

=item * C<mtime> => L<OP::DateTime>

C<mtime> is the Unix timestamp representing the object's last
modified time. OP updates this each time an object is saved.

=back

=head2 C<undef> Requires Assertion

Instance variables may not be C<undef>, unless asserted as
C<::optional>.

Object instances in OP may not normally be C<undef>. Generally, if
a value is not defined, OP currently returns C<undef> rather than an
undefined object instance. This may change at some point.

=head2 Namespace Matters

OP's core packages live under the OP:: namespace. Your classes should
live in their own top-level namespace, e.g. "YourApp::". This will translate
to the name of the app's database, unless overridden.

=head1 OBJECT TYPES

OP object types are used when asserting attributes within a class, and are
also suitable for instantiation or subclassing in a self-standing manner.

The usage of these types is not mandatory outside the context of creating
a new class-- OP always returns attributes from the database in
object form, but these object types are not a replacement for Perl's
native data types in general usage, unless the developer wishes
them to be.

These modes of usage are shown below, and covered in greater detail
in specific object class docs.

=head2 DECLARING AS SUBCLASS

By default, a superclass of L<OP::Node> is used for new classes. This
may be overridden using __BASE__:

  use OP;

  create "YourApp::Example" => {
    __BASE__ => "OP::Hash",

    # ...
  };

=head2 ASSERTING AS ATTRIBUTES

When defining the allowed instance variables for a class, the C<assert()>
method is used:

  #
  # File: Example.pm
  #
  use OP;

  create "YourApp::Example" => {
    someString => OP::Str->assert,
    someInt    => OP::Int->assert,

  };

=head2 INSTANTIATING AS OBJECTS

When instantiating, the class method C<new()> is used, typically with
a prototype object for its argument.

  #
  # File: somecaller.pl
  #
  use strict;
  use warnings;

  use YourApp::Example;

  my $example = YourApp::Example->new(
    name       => "Hello",
    someString => "foo",
    someInt    => 12345,
  );

  $example->save("Saving my first object");

  $example->print;

=head2 IN METHODS

Constructors and setter methods accept both native Perl 5 data
types and their OP object class equivalents. The setters will
automatically handle any necessary conversion, or throw an exception if
the received arg doesn't quack like a duck.

To wit, native types are OK for constructors:

  my $example = YourApp::Example->new(
    someString => "foo",
    someInt    => 123,
  );

  #
  # someStr became a string object:
  #
  say $example->someString->class;
  # "OP::Str"

  say $example->someString->size;
  # "3"

  say $example->someString;
  # "foo"

  #
  # someInt became an integer object:
  #
  say $example->someInt->class;
  # "OP::Int"

  say $example->someInt->sqrt;
  # 11.0905365064094

  say $example->someInt;
  # 123

Native types are OK for setters:

  $example->setSomeInt(456);

  say $example->someInt->class;
  # "OP::Int"


=head1 ABSTRACT CLASSES & MIX-INS

=over 4

=item * L<OP::Class> - Abstract "Class" class

=item * L<OP::Class::Dumper> - Introspection mix-in

=item * L<OP::Object> - Abstract object class

=item * L<OP::Persistence> - Storage and retrieval mix-in

=item * L<OP::Node> - Abstract stored object class

=item * L<OP::Type> - Instance variable typing

=item * L<OP::Subtype> - Instance variable subtyping

=back

=head1 OBJECT TYPES

The basic types listed here may be instantiated as objects, or asserted
as inline attributes.

=over 4

=item * L<OP::Any> - Wrapper for any type of variable

=item * L<OP::Array> - List

=item * L<OP::Bool> - Overloaded boolean

=item * L<OP::Code> - Any CODE reference

=item * L<OP::DateTime> - Overloaded time object

=item * L<OP::Domain> - Overloaded domain name

=item * L<OP::Double> - Overloaded double-precision number

=item * L<OP::EmailAddr> - Overloaded email address

=item * L<OP::ExtID> - Overloaded foreign GUID

=item * L<OP::Float> - Overloaded floating point number

=item * L<OP::Hash> - Hashtable

=item * L<OP::ID> - Overloaded GUID

=item * L<OP::Int> - Overloaded integer

=item * L<OP::IPv4Addr> - Overloaded IPv4 address

=item * L<OP::Name> - Unique secondary key

=item * L<OP::Num> - Overloaded number

=item * L<OP::Ref> - Any reference value

=item * L<OP::Rule> - Regex reference (qr/ /)

=item * L<OP::Scalar> - Any Perl 5 scalar

=item * L<OP::Str> - Overloaded unicode string

=item * L<OP::TimeSpan> - Overloaded time range object

=item * L<OP::URI> - Overloaded URI

=back

=head1 CONSTANTS & ENUMERATIONS

=over 4

=item * L<OP::Constants> -  "dot rc" values as constants 

=item * L<OP::Enum> - C-style enumerated types as constants

=back

=head1 HELPER MODULES

=over 4

=item * L<OP::Utility> - System functions required globally by OP

=item * L<OP::Exceptions> - Errors thrown by OP

=back

=head1 TOYS & TOOLS

=over 4

=item * C<bin/oped> - Edit OP objects using VIM and YAML

=item * C<bin/opid> - Dump OP objects to STDOUT in various formats

=item * C<bin/opsh> - Interactive and persistent Perl 5 shell

=back

=head1 EXPERIMENTAL

Experimental classes are subject to radical upheaval, questionable
documentation, and unexplained disappearances. They represent proof of
concept in their respective areas, and may move out of experimental status
at some point.

=head2 INFOMATICS

The infomatics classes are an attempt to replicate certain functionality
of RRD using SQL and Perl.

=over 4

=item * L<OP::Log> - OP::RRNode class factory

=item * L<OP::RRNode> - Round Robin Database Table

=item * L<OP::Series> - Cooked OP::RRNode Series Data

=item * L<OP::SeriesChart> - Image-based Series Visualizer

=back

=head2 FOREIGN DB ACCESS

Foreign DB access classes are similar in function to Class::DBI,
in that they are used to derive object classes from existing schemas.
This is an inversion of how OP normally functions, since OP was
designed to derive schemas from classes.

=over 4

=item * L<OP::ForeignRow> - Non-OP Database Access

=item * L<OP::ForeignTable> - ForeignRow class factory

=back

=head2 BULK TABLE WRITER

The Bulk writer provides an alternate method for saving objects,
utilizing MySQL's LOAD FILE syntax.

=over 4

=item * L<OP::Persistence::Bulk> - Deferred fast bulk table writes

=back

=head1 SEE ALSO

L<OP::Class>, C<ex/cheat.html>

OP is on GitHub: http://github.com/aayars/op

=head1 AUTHOR

  Alex Ayars <pause@nodekit.org>

=head1 COPYRIGHT

  File: OP.pm
 
  Copyright (c) 2009 TiVo Inc.
 
  All rights reserved. This program and the accompanying materials
  are made available under the terms of the Common Public License v1.0
  which accompanies this distribution, and is available at
  http://opensource.org/licenses/cpl1.0.txt

=cut
