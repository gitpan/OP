#
# File: OP/Enum/StatType.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Enum::StatType;

use OP::Enum qw| Gauge Counter Derivative |;

=head1 NAME

OP::Enum::StatType - Series statistic type enumeration

=head1 DESCRIPTION

Specifies a statistic type for series data. For more information,
see RRDTool's explanation of GAUGE, COUNTER, and DERIVE types:

  http://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html

=head1 SYNOPSIS

  use OP::Enum::StatType;

  my $type = OP::Enum::Inter::Counter;

=head1 CONSTANTS

=over 4

=item * OP::Enum::StatType::Gauge

Specifies a constant and absolute value, such as temperature or
speed at a given point in time (e.g. a Thermometer, Speedometer)

=item * OP::Enum::StatType::Counter

Specifies a constantly increasing value, such as distance traveled
(e.g. an Odometer). Counter values sampled at regular intervals may
be used to compute a gauge-style "rate over time" metric.

=item * OP::Enum::StatType::Derivative

Specifies a constantly increasing value, with interpolation across
premature counter resets.

=back

=head1 SEE ALSO

L<OP::Series>, L<OP::Enum>, L<OP::Persistence>

This file is part of L<OP>.

=cut

1;
