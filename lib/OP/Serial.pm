#
# File: OP/Serial.pm
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

OP::Serial - Auto incrementing integer primary key

=head1 DESCRIPTION

Extends L<OP::Int>.

=head1 SYNOPSIS

  use OP qw| :all |;

  create "YourApp::Example" => {
    id => OP::Serial->assert,

  };

=head1 SEE ALSO

L<OP::ID>

This file is part of L<OP>.

=cut

package OP::Serial;

use strict;
use warnings;

use OP::Enum::Bool;

use base qw| OP::Int |;

sub new {
  my $class = shift;
  my $value = shift || 0;

  return bless \$value, $class;
}

sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs(
    OP::Type::isInt, @rules
  );

  $parsed{serial} = true;
  $parsed{optional} = true;
  $parsed{columnType} ||= 'INTEGER';

  return $class->__assertClass()->new(%parsed);
}

true;
