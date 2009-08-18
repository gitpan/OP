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

our $VERSION = '0.310_001';

use strict;
use diagnostics;

#
# Abstract classes
#
use OP::Class qw| create true false |;
use OP::Type qw| subtype |;
use OP::Subtype;
use OP::Object;
use OP::Node;

#
# Core object classes
#
use OP::Array qw| yield emit break |;
use OP::Bool;
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
use OP::Rule;
use OP::Scalar;
use OP::Serial;
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
  # From OP::Type:
  #
  "subtype",
);

our @EXPORT_OK = (
  #
  # From OP::Array:
  #
  "yield", "emit", "break"
);

true;
__END__
=pod

=head1 NAME

OP - Compact prototyping of InnoDB-backed object classes

=head1 VERSION

This documentation is for version B<0.310_001> of OP.

=head1 STATUS

The usual pre-1.0 warnings apply. Consider this alpha code. It does what
we currently ask of it, and maybe a little more, but it is a work in
progress.

=head1 SYNOPSIS

  use strict;
  use warnings;

  use OP;

  create "YourApp::YourClass" => { };

See PROTOTYPE COMPONENTS in L<OP::Class> for detailed examples.

A cheat sheet, C<ex/cheat.html>, is included with this distribution.

=head1 DESCRIPTION

OP is a Perl 5 framework for prototyping InnoDB-backed object classes.

This document covers the high-level concepts implemented in OP.

=head1 FRAMEWORK ASSUMPTIONS

When using OP, as with any framework, a number of things "just happen"
by design. Trying to go against the flow of any of these base assumptions
is not recommended.

=head2 Configuration

See CONFIGURATION AND ENVIRONMENT in this document.

=head2 Classes Make Tables

The core function of OP is to derive database tables from the
assertions contained in object classes. OP creates the tables that
it needs.

If, rather, you need to derive object classes from a database schema,
you may want to take a look at L<Class::DBI> and other similar
packages on the CPAN, which specialize in doing just that.

L<OP::ForeignTable> may be used to work with external datasources
as if they were OP classes, but this functionality is quite limited.

=head2 Default Base Attributes

Database-backed OP objects B<always> have "id", "name", "ctime",
and "mtime".

=over 4

=item * C<id> => L<OP::ID>

C<id> is the primary key at the database table level. The gets used
in database table indexes, and should generally not be altered once
assigned.

Base64-encoded Globally Unique IDs are used by default, though it
is possible to assert any scalar OP object class for the C<id>
column. See L<OP::ID>, L<OP::Serial>.

=item * C<name> => L<OP::Name>

C<name> is a secondary human-readable key.

The assertions for the name attribute may be changed to suit a
class's requirements, and the name value for any object may be
freely changed.

For more information on named objects, see L<OP::Name>.

=item * C<ctime> => L<OP::DateTime>

C<ctime> is the Unix timestamp representing the object's creation
time. OP sets this when saving an object for the first time.

For more information on timestamps, see L<OP::DateTime>.

=item * C<mtime> => L<OP::DateTime>

C<mtime> is the Unix timestamp representing the object's last
modified time. OP updates this each time an object is saved.

=back

=head2 C<undef> Requires Assertion

Undefined values in objects translate to NULL in the database, and
OP does not permit this to happen by default.

Instance variables may not be undef, (and the corresponding table
column may not be NULL), unless the instance variable was explicitly
asserted as B<optional> in the class prototype. To do so, provide
"optional" as an assertion argument, as in the following example:

  create "YourApp::Example" => {
    ### Do not permit NULL:
    someMandatoryDate => OP::DateTime->assert,

    ### Permit NULL:
    someOptionalDate => OP::DateTime->assert(
      subtype(
        optional => true,
      )
    ),

    # ...
  };

=head2 Namespace Matters

OP's core packages live under the OP:: namespace. Your classes should
live in their own top-level namespace, e.g. "YourApp::". This will translate
(in lower case) to the name of the app's database. The database name may be
overridden by implementing class method C<databaseName>.

Namespace elements beyond the top-level translate to lower case table
names. In cases of nested namespaces, Perl's "::" delineator is
swapped out for an underscore (_). The table name may be overriden
by implementing class method C<tableName>.

  create "YourApp::Example::Foo" => {
    # overrides default value of "yourapp"
    databaseName => sub {
      my $class = shift;

      return "some_legacy_db";
    },

    # overrides default value of "example_foo"
    tableName => sub {
      my $class = shift;

      return "some_legacy_table";
    },

    # ...
  };

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

=item * L<OP::Persistence::Generic> - Base for vendor-specific DBI modules

=item * L<OP::Persistence::MySQL> - MySQL/InnoDB-specific runtime overrides

=item * L<OP::Persistence::SQLite> - SQLite-specific runtime overrides

=item * L<OP::Node> - Abstract stored object class

=item * L<OP::Type> - Instance variable typing

=item * L<OP::Scalar> - Base class for scalar values

=item * L<OP::Subtype> - Instance variable subtyping

=back

=head1 OBJECT TYPES

The basic types listed here may be instantiated as objects, or asserted
as inline attributes.

=over 4

=item * L<OP::Array> - List

=item * L<OP::Bool> - Overloaded boolean

=item * L<OP::DateTime> - Overloaded time object

=item * L<OP::Domain> - Overloaded domain name

=item * L<OP::Double> - Overloaded double-precision number

=item * L<OP::EmailAddr> - Overloaded email address

=item * L<OP::ExtID> - Overloaded foreign key

=item * L<OP::Float> - Overloaded floating point number

=item * L<OP::Hash> - Hashtable

=item * L<OP::ID> - Overloaded GUID primary key

=item * L<OP::Int> - Overloaded integer

=item * L<OP::IPv4Addr> - Overloaded IPv4 address

=item * L<OP::Name> - Unique secondary key

=item * L<OP::Num> - Overloaded number

=item * L<OP::Rule> - Regex reference (qr/ /)

=item * L<OP::Serial> - Auto-incrementing primary key

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

=item * C<bin/opconf> - Generate an .oprc on the local machine

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

=head1 CONFIGURATION AND ENVIRONMENT

=head2 OP_HOME + .oprc

OP needs to be able to find a valid .oprc file in order to bootstrap
itself. This lives under $ENV{OP_HOME}, which defaults to the current
user's home directory.

To generate a first-time config for the local machine, copy the
.oprc (included with this distribution) to the proper location, or
run C<bin/opconf> (also included with this distribution) as the
user who will be running OP. This is a post-install step which is
not currently handled by C<make install>.

See L<OP::Constants> for information regarding customizing and
extending the local rc file.

=head2 OP + mod_perl

OP-based classes used in a mod_perl app should be preloaded by a
startup script. OP_HOME must be set in the script's BEGIN block.

For example, in a file C<startup.pl>:

  use strict;
  use warnings;

  BEGIN {
    $ENV{OP_HOME} = '/home/user/op'; # Directory with the .oprc
  }

  use MyApp::Component;
  use MyApp::OtherComponent;

  1;

And in your C<httpd.conf>:

  PerlRequire /path/to/your/startup.pl

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
