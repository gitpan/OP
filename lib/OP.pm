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

#
# Add any cleanup/shutdown items to the DESTROY method below.
#
# Right now, this just flushes any pending POE Sessions.
#
package OP::Cleanup;

sub new {
  my $class = shift;

  return bless { }, $class;
}

sub DESTROY {
  POE::Kernel->run;
}

package OP;

our $VERSION = '0.212';

use strict;
use diagnostics;

use Filter::Simple; # Force stricture and diagnostics in caller...
                    # because that's just the way it's going to be.

FILTER {
  my $filterText = q[ use strict; use diagnostics; use Perl6::Subs; ];

  s/^/$filterText/s;
};

do {
  #
  # Workaround for AutoLoader: Using Coro with OP makes AutoLoader throw
  # undef warnings in the context of a "require" statement when objects
  # without an explicit DESTROY method are culled.
  #
  # To work around this, OP adds an abstract DESTROY method to the the
  # UNIVERSAL package, which all objects in Perl inherit from. The DESTROY
  # method may be overridden as usual on a per-class basis.
  #
  no strict "refs";

  *{"UNIVERSAL::DESTROY"} = sub { };
};

use Encode; # Load this legacy module before all else...
            # or suffer the undefined consequences!

use Error qw| :try |;

#
# Abstract classes
#
use OP::Class qw| create true false |;
use OP::Type;
use OP::Subtype;
use OP::Object;
use OP::Node;

#
# Async functionality
#
use OP::Persistence::Async qw| finish transmit convey |;

#
# Core object classes
#
use OP::Any;
use OP::Array qw| yield emit |;
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
use OP::Recur qw| snooze break |;
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
  "yield", "emit",
  #
  # From OP::Recur:
  #
  "snooze", "break",
  #
  # From OP::Persistence::Async:
  #
  "finish", "transmit", "convey",
  #
  # From Error:
  #
  "try", "catch", "with", "finally",
  #
  # Subtyping functions:
  #
  keys %OP::Type::RULES
);

my $cleanup = OP::Cleanup->new;

true;
__END__
=pod

=head1 NAME

OP - Compact Perl 5 class prototyping with object persistence

=head1 VERSION

This documentation is for version B<0.212> of OP.

=head1 STATUS

The usual pre-1.0 warnings apply. Consider this alpha code. It does what
we currently ask of it, and maybe a little more, but it is a work in
progress.

=head1 SYNOPSIS

  use OP;

Using the OP module initializes all built-in object types, and causes
L<strict>, L<diagnostics>, L<OP::Class>, L<OP::Type>, L<Perl6::Subs>,
and L<Error> to be imported by the caller. These may alternately be
imported individually.

A cheat sheet, C<cheat.html>, is included with this distribution.

=head1 DESCRIPTION

Compact and concise class prototyping, with object persistence.

OP is a Perl 5 dialect for deriving object classes and database
schemas. Apps developed and executed under OP have a greater degree of
formality and consistency than one may be accustomed to seeing in Perl.

This document covers the high-level concepts implemented in OP.

=head1 FEATURES

=head2 Class Prototyping with Transparent Persistence

Inspired by I<Prototype.js> in the JavaScript world, L<OP::Class>
provides the C<create> function, enabling developers to craft
database-backed Perl 5 classes in a compact and concise manner.

Database tables are derived from object classes. By default, new
classes include methods to C<save> to and C<load> from persistent
backing stores. Complex schemas may be quickly modeled in code and
put to use.

=head2 Instance Variable Assertions

Mitigate garbage input through the use of typing and subtype
rules (L<OP::Type>). Enforce strict control of instance variables,
table column behavior, and automatically derive database constraints.

=head2 List Collectors

Inspired by language features in Ruby and Python, OP implements list
collection methods, complemented by a set of functions which may be used
to finely control the flow of execution.

=head2 Formal Methods & Exceptions

Exception handling is brought in from the L<Error> module. C<try>,
C<throw>, and C<catch> are first-class citizens in the OP runtime.

Perl 6-style method support is provided by the L<Perl6::Subs> source
filter, and is used extensively throughout OP source and its examples. OP
also implements a generalized subset of Perl 6-derived object types.

=head2 Async-Ready

OP provides first-class support for L<Coro> and L<POE>. See L<OP::Recur>
and L<OP::Persistence::Async>.

=head1 FRAMEWORK ASSUMPTIONS

When using OP, a number of things "just happen" by design. Trying
to go against the flow of any of these base assumptions is not
recommended.

=head2 Default Modules

L<strict>, L<warnings>, L<Error>, and L<Perl6::Subs> are on by default.

=head2 Persistent Objects Extend L<OP::Node>

Classes allocated with C<create> will receive an InnoDB backing store,
by virtue of being a subclass of L<OP::Node>. This can be overridden if
needed, see the subclassing examples in this document, as well as
"Inheritance" in L<OP::Class>, for details.

Various backing store options are covered in the L<OP::Persistence>
module.

=head2 Default Base Attributes

Unless overridden in C<__baseAsserts>, L<OP::Node> subclasses have
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

OP uses "named objects". By default, C<name> is a human-readable
unique secondary key. It's the name of the object being saved.
Like all attributes, C<name> must be defined when saved, unless asserted
as C<::optional> (see "C<undef> Requires Assertion").

The value for C<name> may be changed (as opposed to C<id>, which should
not be tinkered with), as long as the new name does not conflict with
any objects in the same class when saved.

C<name> may be may be keyed in combination with multiple attributes via
the C<::unique> L<OP::Subtype> argument, which adds InnoDB reference
options to the schema.

  create "YourApp::Class" => {
    #
    # Don't require named objects:
    #
    name => OP::Name->assert(::optional),

    # ...
  };

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
live in their own top-level namespace, e.g. "YourApp::".

=head1 OBJECT TYPES

OP implements the same object class types referred to in L<Perl6::Subs>,
several others which are specific to dealing with a SQL backing store
(e.g. Double, ExtId), as well as datatypes commonly used in network
operations (e.g. EmailAddr, IPv4Addr, URI).

OP object types are used when asserting attributes within a class, and are
also suitable for instantiation or subclassing in a self-standing manner.

The usage of these types is not mandatory outside the context of creating
a new class-- OP always returns data in object form, but these object
types are not a replacement for Perl's native data types in general usage,
unless the developer wishes them to be.

These modes of usage are shown below, and covered in greater detail
in specific object class docs.

=head2 DECLARING AS SUBCLASS

By default, a superclass of L<OP::Node> is used for new classes. This
may be overridden using __BASE__:

  use OP;

  create "YourApp::Example" => {
    __BASE__ => "OP::Hash",

  };

or

  package YourApp::Example;

  use strict;
  use warnings;

  use base qw| OP::Hash |;

  1;

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

To ensure method arguments are always of the appropriate type, specify
the desired type(s) in a L<Perl6::Subs> prototype.

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

Native types are OK for setters:

  $example->setSomeInt(456);

  say $example->someInt->class;
  # "OP::Int"


=head1 ABSTRACT CLASSES & MIX-INS

=over 4

=item * L<OP::Class> - B<Abstract "Class" class>

=item * L<OP::Class::Dumper> - B<Introspection mix-in>

=item * L<OP::Object> - B<Abstract object class>

=item * L<OP::Persistence> - B<Storage and retrieval mix-in>

=item * L<OP::Persistence::Async> - B<Async DB access mix-in>

=item * L<OP::Node> - B<Abstract stored object class>

=item * L<OP::Type> - B<Instance variable typing>

=item * L<OP::Subtype> - B<Instance variable subtyping>

=back

=head1 OBJECT TYPES

These Perl 5 classes represent a generalization of their Perl 6
counterparts, at best, also introducing several object types specific
to dealing with a SQL backing store. OP is not intended to be a Perl
6 implementation at all; there are inconsistencies and cut corners in
the usage of these classes, compared to what Perl 6 will look like. OP
borrows many of these class names for consistency with L<Perl6::Subs>,
and to have less things to remember when coding.

The basic types listed here may be instantiated as objects, or asserted
as inline attributes.

=over 4

=item * L<OP::Any> - B<Wrapper for any type of variable>

=item * L<OP::Array> - B<List>

=item * L<OP::Bool> - B<Overloaded boolean>

=item * L<OP::Code> - B<Any CODE reference>

=item * L<OP::DateTime> - B<Overloaded time object>

=item * L<OP::Domain> - B<Overloaded domain name>

=item * L<OP::Double> - B<Overloaded double-precision number>

=item * L<OP::EmailAddr> - B<Overloaded email address>

=item * L<OP::ExtID> - B<Overloaded foreign GUID>

=item * L<OP::Float> - B<Overloaded floating point number>

=item * L<OP::Hash> - B<Hashtable>

=item * L<OP::ID> - B<Overloaded GUID>

=item * L<OP::Int> - B<Overloaded integer>

=item * L<OP::IPv4Addr> - B<Overloaded IPv4 address>

=item * L<OP::Name> - B<Unique secondary key>

=item * L<OP::Num> - B<Overloaded number>

=item * L<OP::Ref> - B<Any reference value>

=item * L<OP::Rule> - B<Regex reference (qr/ /)>

=item * L<OP::Scalar> - B<Any Perl 5 scalar>

=item * L<OP::Str> - B<Overloaded unicode string>

=item * L<OP::TimeSpan> - B<Overloaded time range object>

=item * L<OP::URI> - B<Overloaded URI>

=back

=head1 CONSTANTS & ENUMERATIONS

=over 4

=item * L<OP::Constants> -  B<"dot rc" values as constants> 

=item * L<OP::Enum> - B<C-style enumerated types as constants>

=back

=head1 HELPER MODULES

=over 4

=item * L<OP::Utility> - B<System functions required globally by OP>

=item * L<OP::Exceptions> - B<Errors thrown by OP>

=back

=head1 EXPERIMENTAL*: INFOMATICS

Experimental classes are subject to radical upheaval, questionable
documentation, and unexplained disappearances. They represent proof of
concept in their respective areas, and may move out of experimental status
at some point.

=over 4

=item * L<OP::Log> - B<OP::RRNode factory class>

=item * L<OP::RRNode> - B<Round Robin Database Table>

=item * L<OP::Series> - B<Cooked OP::RRNode Series Data>

=back

=head1 EXPERIMENTAL: SCHEDULING

=over 4

=item * L<OP::Recur> - B<Recurring time specification>

=back

=head1 EXPERIMENTAL: FOREIGN DB ACCESS

=over 4

=item * L<OP::ForeignRow> - B<Non-OP Database Access>

=item * L<OP::ForeignTable> - B<ForeignRow class factory>

=back

=head1 EXPERIMENTAL: INTERACTIVE SHELL

=over 4

=item * L<OP::Shell> - B<Persistent Perl Shell>

=back

=head1 EXPERIMENTAL: BULK TABLE WRITER

=over 4

=item * L<OP::Persistence::Bulk> - B<Deferred fast bulk table writes>

=back

=head1 SEE ALSO

L<Perl6::Subs>, L<OP::Class>, L<OP::Type>

Perl6 Synopsis 02: Bits and Pieces (Object Types)
  - http://svn.pugscode.org/pugs/docs/Perl6/Spec/S02-bits.pod

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
