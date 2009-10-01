#
# File: OP/Hash.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Hash;

use strict;
use warnings;

use OP::Array qw| yield |;
use OP::Class qw| true false |;

use base qw| OP::Class::Dumper OP::Object |;

use Error qw| :try |;

=pod

=head1 NAME

OP::Hash - Hashtable object

=head1 DESCRIPTION

Extends L<OP::Object> to handle Perl HASH refs as OP Objects. Provides
constructor, getters, setters, "Ruby-esque" collection, and other methods
which one might expect a Hash table object to respond to.

=head1 INHERITANCE

This class inherits additional class and object methods from the
following packages:

L<OP::Class> > L<OP::Object> > OP::Hash

=head1 SYNOPSIS

  use OP::Hash;

  my $hash = OP::Hash->new();

  my $hashFromNonRef = OP::Hash->new(%hash); # Makes new ref

  my $hashFromRef = OP::Hash->new($hashref); # Keeps orig ref

=head1 PUBLIC CLASS METHODS

=over 4

=item * $class->assert(*@rules)

Returns an OP::Type::Hash instance encapsulating the received
subtyping rules.

Really, don't do this. If you think you need to assert a Hash,
please see "AVOIDING HASH ASSERTIONS" at the end of this document for
an alternative approach.

=cut

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs( OP::Type::isHash, @rules );

  $parsed{default} ||= {};
  $parsed{columnType} ||= 'TEXT';

  return $class->__assertClass()->new(%parsed);
}

=pod

=back

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $hash->collect($sub), yield(item, [item, ...]), emit(item, [item...])

Ruby-esque key iterator method. Returns a new L<OP::Array>, containing
the yielded results of calling the received sub for each key in $hash.

$hash->collect is shorthand for $hash->keys->collect, so you're really
calling C<collect> in L<OP::Array>. C<yield> and C<emit> are exported
by L<OP::Array>. Please see the documentation for OP::Array regarding
usage of C<collect>, C<yield>, and C<emit>.

  #
  # For example, quickly wrap <a> tags around array elements:
  #
  my $tagged = $object->collect( sub {
    my $key = shift;

    print "Key $key is $object->{$key}\n";

    emit "<a name=\"$key\">$object->{$key}</a>";
  } );

=cut

# method collect(Code $sub) {
sub collect {
  my $self = shift;
  my $sub  = shift;

  return $self->keys()->collect($sub);
}

=pod

=item * $self->each($sub)

List iterator method. Runs $sub for each element in self; returns true
on success.

  my $hash = OP::Hash->new(
    foo => "uno",
    bar => "dos",
    rebar => "tres"
  );

  $hash->each( sub {
    my $key = shift;

    print "Have key: $key, value: $hash->{$key}\n";
  } );

  #
  # Expected output:
  #
  # Have key: foo, value: uno
  # Have key: bar, value: dos
  # Have key: rebar, value: tres
  #

=cut

# method each(Code $sub) {
sub each {
  my $self = shift;
  my $sub  = shift;

  return $self->keys()->each($sub);
}

=pod

=item * $self->keys()

Returns an L<OP::Array> object containing self's alpha sorted keys.

  my $hash = OP::Hash->new(foo=>'alpha', bar=>'bravo');

  my $keys = $hash->keys();

  print $keys->join(','); # Prints out "bar,foo"

=cut

# method keys() {
sub keys {
  my $self = shift;

  return OP::Array->new( sort keys %{$self} );
}

=pod

=item * $self->values()

Returns an L<OP::Array> object containing self's values, alpha sorted by key.

  my $hash = OP::Hash->new(foo=>'alpha', bar=>'bravo');

  my $values = $hash->values();

  print $values->join(','); # Prints out "bravo,alpha"

=cut

# method values() {
sub values {
  my $self = shift;

  return $self->keys()->collect(
    sub {
      my $key = shift;

      yield( $self->{$key} );
    }
  );
}

=pod

=item * $self->set($key,$value);

Set the received instance variable. Extends L<OP::Object>::set to always
use OP::Hash and L<OP::Array> when it can.

  my $hash = OP::Hash->new(foo=>'alpha', bar=>'bravo');

  $hash->set('bar', 'foxtrot'); # bar was "bravo", is now "foxtrot"

=cut

# method set(Str $key, *@value) {
sub set {
  my $self  = shift;
  my $key   = shift;
  my @value = @_;

  my $class = $self->class();

  #
  # Call set() as a class method if $self was a class
  #
  return $self->SUPER::set( $key, @value )
    if !$class;

  my $type = $class->asserts()->{$key};

  return $self->SUPER::set( $key, @value )
    if !$type;

  throw OP::InvalidArgument(
    "Too many args received by set(). Usage: set(\"$key\", VALUE)" )
    if @value > 1;

  my $value = $value[0];

  my $valueType = ref($value);

  my $attrClass = $type->class()->get("objectClass");

  if ( defined($value)
    && ( !$valueType || !UNIVERSAL::isa( $value, $attrClass ) ) )
  {
    $value = $attrClass->new($value);
  }

  return $self->SUPER::set( $key, $value );
}

=pod

=item * $self->size()

Returns the number of key/value pairs in self

=cut

### imported function size() is redef'd
no warnings "redefine";

# method size() {
sub size {
  my $self = shift;

  return scalar( CORE::keys( %{$self} ) );
}

use warnings "redefine";
###

=pod

=item * $self->isEmpty()

Returns true if self's size is 0, otherwise false.

=cut

# method isEmpty() {
sub isEmpty {
  my $self = shift;

  return $self->size() ? false : true;
}

=pod

=back

=head1 AVOIDING HASH ASSERTIONS

One might think to assert the Hash type in order to store hashtables
inside of objects in a free-form manner.

OP could technically do this, but this documentation is here to tell
you not to. A recommended approach to associating arbitrary key/value
pairs with database-backed OP objects is provided below.

Do not do this:

  #
  # File: Example.pm
  #
  use OP qw| :all |;

  create "YourApp::Example" => {
    someInlineHash => OP::Hash->assert()
  };

Rather, explicitly create a main class, and also an extrinsics class
which handles the association of linked values. Manually creating
linked classes in this manner is not as quick to code for or represent
in object form, but it mitigates the creation of deeply nested,
complex objects and "sprawling" sets of possible values which may
arise from systems with lots of users populating data. Something
akin to the following is the recommended approach:

  #
  # File: Example.pm
  #
  # This is the main class:
  #
  create "YourApp::Example" => {
    #
    # Assertions and methods here...
    #
  };

  #
  # File: Example/Attrib.pm
  #
  # This is where we tuck extrinsic attributes:
  #
  use OP qw| :all |;
  use YourApp::Example;

  create "YourApp::Example::Attrib" => {
    exampleId => OP::ExtID->assert( "YourApp::Example" ),

    elementKey => OP::Str->assert(
      #
      # ...
      #
    ),

    elementValue => OP::Str->assert(
      # Assert any vector or scalar OP object class, as needed.
      #
      # OP::Str can act as a catch-all for scalar values.
      #
      # ...
    ),
  }

An extension of this approach is to create multiple extrinsincs
classes, providing specific subtyping rules for different kinds of
key/value pairs. For example, one might create a table of linked
values which are always either true or false:

  #
  # File: Example: BoolAttrib.pm
  #

  use OP qw| :all |;
  use YourApp::Example;

  create "YourApp::Example::BoolAttrib" => {
    exampleId => OP::ExtId->assert( "YourApp::Example" ),

    elementKey => OP::Str->assert( ),

    elementValue => OP::Bool->assert( ),
  };
  
=head1 SEE ALSO

This file is part of L<OP>.

=cut

1;
