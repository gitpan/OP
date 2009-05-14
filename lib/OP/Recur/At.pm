#
# File: OP/Recur/At.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Recur::At;

use strict;
use warnings;

use base qw| OP::Array |;

sub new {
  my $class = shift;

  if ( @_ == 1 && UNIVERSAL::isa($_[0],"OP::Array") ) {
    return $class->SUPER::new(@{$_[0]});
  } else {
    my @self = reverse( pop, pop, pop, pop, pop, pop );

    return $class->SUPER::new(@self);
  }
}

sub year   { return $_[0]->[0]; }
sub month  { return $_[0]->[1]; }
sub day    { return $_[0]->[2]; }
sub hour   { return $_[0]->[3]; }
sub minute { return $_[0]->[4]; }
sub second { return $_[0]->[5]; }

1;
__END__
=pod

=head1 NAME

OP::Recur::At - Time specification object class

=head1 SYNOPSIS

This module should not be used directly. See L<OP::Recur>.

=head1 SEE ALSO

This file is part of L<OP>.

=cut
