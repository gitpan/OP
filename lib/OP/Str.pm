#
# File: OP/Str.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
=pod

=head1 NAME

OP::Str - Overloaded object class for strings

=head1 DESCRIPTION

Extends L<OP::Scalar>, L<Mime::Base64>, and L<Unicode::String>.

=head1 SYNOPSIS

  use OP::Str;

  my $string = OP::Str->new("Lorem Ipsum");

  #
  # Overloaded to work like a native string
  #
  print "$string\n";

  if ( $string =~ /Ipsum/ ) {
    print "Word\n";
  }

=head1 PUBLIC INSTANCE METHODS

=over 4

=item * $self->split($splitRegex)

Object wrapper for Perl's built-in C<split()> function. Functionally the
same as C<split($splitStr, $self)>.

Returns a new OP::Array containing the split elements.

  my $scalar = OP::Scalar->new("Foo, Bar, Rebar, D-bar");

  my $array  = $scalar->split(qr/, */);

  $array->each( sub {
    print "Have item: $_\n";
  } );

  # Have item: Foo
  # Have item: Bar
  # Have item: Rebar
  # Have item: D-bar

=item * chomp, chop, chr, crypt, eval, index, lc, lcfirst, length, rindex, substr, uc, ucfirst

These object methods are wrappers to built-in Perl functions. See
L<perlfunc>.

=back

=head1 SEE ALSO

This file is part of L<OP>.

=cut

package OP::Str;

use strict;
use warnings;

use base qw| Unicode::String OP::Scalar MIME::Base64 |;

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs(
    OP::Type::isStr, @rules
  );

  $parsed{columnType}  ||= 'VARCHAR(1024)';
  $parsed{maxSize} ||= 1024;

  return $class->__assertClass()->new(%parsed);
}

# method split(Rule $regex) {
sub split {
  my $self = shift;
  my $regex = shift;

  return OP::Array->new( CORE::split($regex, $self) );
}

# method chomp() { CORE::chomp($self) }
sub chomp {
  my $self = shift;

  return CORE::chomp($self)
}

# method chop() { CORE::chop($self) }
sub chop {
  my $self = shift;

  return CORE::chop($self);
}

# method chr() { CORE::chr($self) }
sub chr {
  my $self = shift;

  return CORE::chr($self);
}

# method crypt(Str $salt) { CORE::crypt($self, $salt) }
sub crypt {
  my $self = shift;
  my $salt = shift;

  return CORE::crypt($self, $salt);
}

# method eval() { CORE::eval($self) }
sub eval {
  my $self = shift;

  return CORE::eval($self);
}

# method index(Str $substr, Int $pos) { CORE::index($self, $substr, $pos) }
sub index {
  my $self = shift;
  my $substr = shift;
  my $pos = shift;

  return CORE::index($self, $substr, $pos);
}

# method lc() { CORE::lc($self) }
sub lc {
  my $self = shift;

  return CORE::lc($self);
}

# method lcfirst() { CORE::lcfirst($self) }
sub lcfirst {
  my $self = shift;

  return CORE::lcfirst($self);
}

# method length() { CORE::length($self) }
sub length {
  my $self = shift;

  return CORE::length($self);
}

# method rindex(Str $substr, Int $pos) { CORE::rindex($self, $substr, $pos) }
sub rindex {
  my $self = shift;
  my $substr = shift;
  my $pos = shift;

  return CORE::rindex($self, $substr, $pos);
}

# method substr(Int $offset, Int $len) { CORE::substr($self, $offset, $len) }
sub substr {
  my $self = shift;
  my $offset = shift;
  my $len = shift;

  return CORE::substr($self, $offset, $len);
}

# method uc() { CORE::uc($self) }
sub uc {
  my $self = shift;

  return CORE::uc($self);
}

# method ucfirst() { CORE::ucfirst($self) }
sub ucfirst {
  my $self = shift;

  return CORE::ucfirst($self);
}

1;
