#
# File: OP/Rule.pm
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

OP::Rule - Object class for regular expressions

=head1 DESCRIPTION

Extends L<OP::Str>

=head1 SYNOPSIS

  use OP::Rule;

=head1 SEE ALSO

This file is part of L<OP>.

=cut

package OP::Rule;

use strict;
use warnings;

use OP::Enum::Bool;

use overload '=~' => sub {
  my $self  = shift;
  my $value = shift;
  my $reg   = qr/$self/x;

  return $value =~ /$reg/;
};

use base qw| OP::Str |;

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs( OP::Type::isRule, @rules );

  return $class->__assertClass()->new(%parsed);
}

# method isa(OP::Class $class: Str $what) {
sub isa {
  my $class = shift;
  my $what  = shift;

  if ( $what eq 'Regexp' ) {
    return true;
  }

  return UNIVERSAL::isa( $class, $what );
}

# method sprint() {
sub sprint {
  my $self = shift;

  return "$self";
}

true;
