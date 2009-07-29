package OP::Redefines;

#
# File: OP/Redefines.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

$Carp::Internal{"OP::Redefines"}++;

do {
  #
  # Override looks_like_number to recognize Num objects as numbers
  #
  no strict "refs";
  no warnings "redefine";

  *{"Scalar::Util::looks_like_number"} = sub($){
    local $_ = shift;

    return 0 if !defined($_);

    return 1 if "$_" =~ (/^[+-]?\d+$/); # is a +/- integer
    return 1 if "$_" =~ (/^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/); # a C float
    return 1 if ($] >= 5.008 and /^(Inf(inity)?|NaN)$/i) or ($] >= 5.006001 and /^Inf$/i);

    0;
  }
};

1;
__END__
=pod

=head1 NAME

OP::Redefines - Runtime overrides for OP

=head1 SYNOPSIS

This module should not be used directly. OP uses it at load time.

=head1 SEE ALSO

This file is part of L<OP>.

=cut
