#
# File: OP/Recur/Each.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Recur::Each;

use strict;
use warnings;

use base qw| OP::Array |;

use OP::Enum::Bool;

#
# each(Sunday)
# each(Monday, March);
# each(Thursday, November, 2000);
#

sub wday  { return $_[0]->[0]; }
sub month { return $_[0]->[1]; }
sub year  { return $_[0]->[2]; }

1;
__END__
=pod

=head1 NAME

OP::Recur::Each - Time specification object class

=head1 SYNOPSIS

This module should not be used directly. See L<OP::Recur>.

=head1 SEE ALSO

This file is part of L<OP>.

=cut 
