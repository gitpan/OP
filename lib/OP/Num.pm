#
# File: OP/Num.pm
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

OP::Num - Overloaded object class for numbers

=head1 DESCRIPTION

Extends L<OP::Scalar>.

=head1 SYNOPSIS

  use OP::Num;

  my $num = OP::Num->new(12345);

=head1 SEE ALSO

This file is part of L<OP>.

=cut

package OP::Num;

use strict;
use warnings;

use OP::Enum::Bool;

use base qw| OP::Scalar |;

# + - * / % ** << >> x
# <=> cmp
# & | ^ ~
# atan2 cos sin exp log sqrt int

our %overload = (
  '++'  => sub { ++$ {$_[0]} ; shift }, # from overload.pm
  '--'  => sub { --$ {$_[0]} ; shift },
  '+'   => sub { "$_[0]" + "$_[1]" },
  '-'   => sub { "$_[0]" - "$_[1]" },
  '*'   => sub { "$_[0]" * "$_[1]" },
  '/'   => sub { "$_[0]" / "$_[1]" },
  '%'   => sub { "$_[0]" % "$_[1]" },
  '**'  => sub { "$_[0]" ** "$_[1]" },
  '=='  => sub { "$_[0]" == "$_[1]" },
  'eq'  => sub { "$_[0]" eq "$_[1]" },
  '!='  => sub { "$_[0]" != "$_[1]" },
  'ne'  => sub { "$_[0]" ne "$_[1]" },
);

use overload fallback => true, %overload;

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs(
    OP::Type::isFloat, @rules
  );

  $parsed{maxSize} ||= 11;
  $parsed{columnType} ||= 'INT(11)';

  return $class->__assertClass()->new(%parsed);
}

# method abs() { CORE::abs(${ $self }) }
sub abs {
  my $self = shift;

  return CORE::abs(${ $self })
}

# method atan2(Num $num) { CORE::atan2(${ $self }, $num) }
sub atan2 {
  my $self = shift;
  my $num = shift;

  return CORE::atan2(${ $self }, $num);
}

# method cos() { CORE::cos(${ $self }) }
sub cos {
  my $self = shift;

  return CORE::cos(${ $self });
}

# method exp() { CORE::exp(${ $self }) }
sub exp {
  my $self = shift;

  return CORE::exp(${ $self });
}

# method int() { CORE::int(${ $self }) }
sub int {
  my $self = shift;

  CORE::int(${ $self });
}

# method log() { CORE::log(${ $self }) }
sub log {
  my $self = shift;

  return CORE::log(${ $self });
}

# method rand() { CORE::rand(${ $self }) }
sub rand {
  my $self = shift;

  return CORE::rand(${ $self });
}

# method sin() { CORE::sin(${ $self }) }
sub sin {
  my $self = shift;

  return CORE::sin(${ $self });
}

# method sqrt() { CORE::sqrt(${ $self }) }
sub sqrt {
  my $self = shift;

  return CORE::sqrt(${ $self });
}

true;
