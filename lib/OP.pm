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

our $VERSION = '0.320';

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
use OP::Double;
use OP::ExtID;
use OP::Float;
use OP::Hash;
use OP::ID;
use OP::Int;
use OP::Name;
use OP::Num;
use OP::Rule;
use OP::Scalar;
use OP::Serial;
use OP::Str;
use OP::TimeSpan;

use base qw| Exporter |;

our @EXPORT_OK = (

  #
  # From OP::Class:
  #
  "create", "true", "false",

  #
  # From OP::Type:
  #
  "subtype",

  #
  # From OP::Array:
  #
  "yield", "emit", "break"
);

our %EXPORT_TAGS = (
  create => [qw| create subtype |],
  bool   => [qw| true false |],
  yield  => [qw| yield emit break |],
  all    => \@EXPORT_OK,
);

true;
__END__

=pod

=head1 NAME

OP - Compact prototyping of schema-backed object classes

=head1 NEW NAME

Oct 19 2009 - Please be advised that this distribution will be
moving to a new name, L<Devel::Ladybug>. The OP distribution will
be removed from CPAN shortly. Sincere apologies for any inconvenience
this may cause.

=head1 SYNOPSIS

  use strict;
  use warnings;

  use OP qw| :all |;

  create "YourApp::YourClass" => { };

See PROTOTYPE COMPONENTS in L<OP::Class> for detailed examples.

A cheat sheet, C<ex/cheat.html>, is included with this distribution.

=head1 DESCRIPTION

OP is a Perl 5 framework for prototyping schema-backed object
classes.

Using OP's C<create()> function, the developer asserts rules for
object classes. OP's purpose is to automatically derive a database
schema, handle object-relational mapping, and provide input validation
for classes created in this manner.

OP works with MySQL/InnoDB, PostgreSQL, SQLite, and YAML flatfile.
If the backing store type for a class is not specified, OP will try
to automatically determine an appropriate type for the local system.
If memcached is available, OP will use it in conjunction with the
permanent backing store.

=head1 VERSION

This documentation is for version B<0.320> of OP.

=head1 EXPORT TAGS

All exports are optional. Specify a tag or symbol by name to import
it into your caller's namespace.

  use OP qw| :all |;

=over 4

=item * :all

This imports each of the symbols listed below.

=item * :create

This imports the C<create> and C<subtype> class prototyping functions;
see L<OP::Class>, L<OP::Subtype>, and examples in this document.

=item * :bool

This imports C<true> and C<false> boolean constants.

=item * :yield

This imports the C<yield>, C<emit>, and C<break> functions for array
collectors; see L<OP::Array>.

=back

=head1 FRAMEWORK ASSUMPTIONS

When using OP, as with any framework, a number of things "just happen"
by design. Trying to go against the flow of any of these base assumptions
is not recommended.

=head2 Configuration

See CONFIGURATION AND ENVIRONMENT in this document.

=head2 Classes Make Tables

OP derives database schemas from the assertions contained in object
classes, and creates the tables that it needs.

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

C<ctime> is an object's creation timestamp. OP sets this when saving
an object for the first time.

This is not the same as, and should not be confused with, the
C<st_ctime> filesystem attribute returned by the C<fstat> system
call, which represents inode change time for files. If this ends
up being too confusing or offensive, OP may use a name other than
C<ctime> for creation time in a future version. It is currently
being left alone.

For more information on timestamps, see L<OP::DateTime>.

=item * C<mtime> => L<OP::DateTime>

C<mtime> is the Unix timestamp representing an object's last
modified time. OP updates this each time an object is saved.

Again, this is an object attribute, and is unrelated to the C<st_mtime>
filesystem attribute returned by the C<fstat> system call. OP may
use a different name in a future version.

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

  use OP qw| :all |;

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
  use OP qw| :all |;

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

  $example->save;

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


=head1 CORE OBJECT TYPES

The basic types listed here may be instantiated as objects, and asserted
as inline attributes.

=over 4

=item * L<OP::Array> - List

=item * L<OP::Bool> - Overloaded boolean

=item * L<OP::DateTime> - Overloaded time object

=item * L<OP::Double> - Overloaded double-precision number

=item * L<OP::ExtID> - Overloaded foreign key

=item * L<OP::Float> - Overloaded floating point number

=item * L<OP::Hash> - Hashtable

=item * L<OP::ID> - Overloaded GUID primary key

=item * L<OP::Int> - Overloaded integer

=item * L<OP::Name> - Unique secondary key

=item * L<OP::Num> - Overloaded number

=item * L<OP::Rule> - Regex reference (qr/ /)

=item * L<OP::Serial> - Auto-incrementing primary key

=item * L<OP::Str> - Overloaded unicode string

=item * L<OP::TimeSpan> - Overloaded time range object

=back

=head1 CONSTANTS & ENUMERATIONS

=over 4

=item * L<OP::Constants> -  "dot rc" values as constants 

=item * L<OP::Enum> - C-style enumerated types as constants

=back

=head1 ABSTRACT CLASSES & MIX-INS

=over 4

=item * L<OP::Class> - Abstract "Class" class

=item * L<OP::Class::Dumper> - Introspection mix-in

=item * L<OP::Object> - Abstract object class

=item * L<OP::Persistence> - Storage and retrieval mix-in

=item * L<OP::Persistence::Bulk> - Deferred fast bulk table writes

=item * L<OP::Persistence::Generic> - Base for vendor-specific DBI modules

=item * L<OP::Persistence::MySQL> - MySQL/InnoDB runtime overrides

=item * L<OP::Persistence::PostgreSQL> - PostgreSQL runtime overrides

=item * L<OP::Persistence::SQLite> - SQLite runtime overrides

=item * L<OP::Node> - Abstract stored object class

=item * L<OP::Type> - Instance variable typing

=item * L<OP::Scalar> - Base class for scalar values

=item * L<OP::Subtype> - Instance variable subtyping

=back

=head1 HELPER MODULES

=over 4

=item * L<OP::Utility> - System functions required globally by OP

=item * L<OP::Exceptions> - Errors thrown by OP

=back

=head1 TOOLS

=over 4

=item * C<opconf> - Generate an .oprc on the local machine

=item * C<oped> - Edit OP objects using VIM and YAML

=item * C<opid> - Dump OP objects to STDOUT in various formats

=back

=head1 CONFIGURATION AND ENVIRONMENT

=head2 OP and your DBA

If using MySQL or PostgreSQL, your app's database and the "op"
database should exist with the proper access prior to use - see
L<OP::Persistence::MySQL>, L<OP::Persistence::PostgreSQL>.

=head2 OP_HOME and .oprc

OP looks for its config file, C<.oprc>, under $ENV{OP_HOME}. OP_HOME
defaults to the current user's home directory.

To generate a first-time config for the local machine, copy the
.oprc (included with this distribution as C<oprc-dist>) to the
proper location, or run C<opconf> (also included with this distribution)
as the user who will be running OP.

See L<OP::Constants> for information regarding customizing and
extending the local rc file.

=head2 OP and mod_perl

OP-based classes used in a mod_perl app should be preloaded by a
startup script. OP_HOME must be set in the script's BEGIN block.

For example, in a file C<startup.pl>:

  use strict;
  use warnings;

  BEGIN {
    $ENV{OP_HOME} = '/home/user/op'; # Directory with the .oprc
  }

  use YourApp::Component;
  use YourApp::OtherComponent;

  1;

And in your C<httpd.conf>:

  PerlRequire /path/to/your/startup.pl

=head1 SEE ALSO

L<OP::Class>, C<ex/cheat.html>

OP is on GitHub: http://github.com/aayars/op

=head1 POSTAMBLE

OP could be an acronym for Objective Perl, or Object Persistence,
or Overpowered, or all of those things, or none of them, or something
completely different. You are encouraged to come up with your own
meaning, but please be kind. I'll admit the currently chosen name
isn't great. It's an unregistered namespace, it conveys little
meaning, and will probably offend the sensibilities of anyone who
works with optree packages. The project's name may change eventually,
but not today.

OP was specifically written as an object persistence layer. Its
purpose is focused to the task of letting developers save and
retrieve objects to/from a backing store without incurring a lot
of legwork, and its usage reflects this.

Thanks to all who have provided feedback and testing. My aim is
to make this software as good and as useful as possible. I welcome
suggestions, contributions, and input.

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
