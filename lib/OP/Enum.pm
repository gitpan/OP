#
# File: OP/Enum.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Enum;

=pod

=head1 NAME

OP::Enum

=head1 DESCRIPTION

C style enumerated types in Perl.

This module emulates the interface of L<enum>.pm, sans support for
bitmasks. Unlike enum.pm, the symbols generated by this module are actual
Perl constants, and may be imported and exported as such by external
modules.

=head1 ENUMERATIONS

=over 4

=item * L<OP::Enum::Bool>

Provide C<false> and C<true> enumerated constants

=item * L<OP::Enum::Consol>

Constant enumeration of supported series consolidation methods

=item * L<OP::Enum::DBIType>

Constant enumeration of supported database types

=item * L<OP::Enum::Inter>

Constant enumeration of supported series interpolation methods

=item * L<OP::Enum::State>

Criticality enumeration. Exports "Nagios-style" states: OK (0), Warn
(1), and Crit (2)

=item * L<OP::Enum::StatType>

Constant enumeration of supported series statistic handling methods
(gauge, counter, derivative)

=back

=head1 SYNOPSIS

The following is borrowed from the perldoc for L<enum>.pm:

  use OP::Enum qw(Sun Mon Tue Wed Thu Fri Sat);
  # Sun == 0, Mon == 1, etc

  use OP::Enum qw(Forty=40 FortyOne Five=5 Six Seven);
  # Yes, you can change the start indexs at any time as in C

  use OP::Enum qw(:Prefix_ One Two Three);
  ## Creates Prefix_One, Prefix_Two, Prefix_Three

  use OP::Enum qw(:Letters_ A..Z);
  ## Creates Letters_A, Letters_B, Letters_C, ...

  use OP::Enum qw(
      :Months_=0 Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
      :Days_=0   Sun Mon Tue Wed Thu Fri Sat
      :Letters_=20 A..Z
  );
  ## Prefixes can be changed mid list and can have index changes too

Bitmask support is not currently implemented.

=head2 Basic Usage

Create a quick package of enumerated constants:

  #
  # File: Month.pm
  #
  package Month;

  use OP::Enum qw|
    jan feb mar apr may jun jul aug sep oct nov dec
  |;

  1;

Meanwhile, in caller:

  #
  # File: hangover.pl
  #
  use Month;

  ...

  my $month = getMonth();

  if ( $month == Month::jan ) {
    print "Happy New Year\n";
  }

=head2 Auto Export

Same usage as the Month.pm example above, with an extra block of
code eval'd for Exporter.

  #
  # File: DayOfWeek.pm
  #
  package DayOfWeek;

  use OP::Enum qw| sun mon tue wed thu fri sat |;

  eval { @EXPORT = @EXPORT_OK };

  1;

Meanwhile, in caller:

  #
  # File: pizza-reminder.pl
  #
  use DayOfWeek;

  ...

  my $day = getDayOfWeek();

  if ( $day == fri ) {
    print "It's pizza day!\n";
  }

=cut

use strict;
use warnings;

use Error qw| :try |;

use OP::Exceptions;

sub import {
  my $class = shift;

  my @vars = @_;

  my $caller = caller();

  #
  # deep magics
  #
  # allow caller to export named enums as constants when used
  # eg. use PackageName qw| Foo Bar |;
  # exports Foo and Bar into caller's namespace
  #
  eval qq/
    package $caller;

    #
    # The "use vars" pragma is supposedly depracated, but using
    # "our" in an eval doesn't seem to do the right thing.
    #
    # So, "use vars" it is, for now.
    #
    # # our \@EXPORT_OK;
    # # our \@LIST;
    #
    use vars qw| \@EXPORT_OK \@LIST |;

    use base qw| Exporter |;

    sub list { return \@LIST }
  /;

  throw OP::RuntimeError($@) if $@;

  my $index = 0;
  my $prefix = '';

  #
  # emulates the interface of enum.pm
  # use OP::Enum qw(:Prefix_ One Two Three);
  # Creates Prefix_One, Prefix_Two, Prefix_Three
  #
  if ( $vars[0] && $vars[0] =~ /^:(.*)/ ) {
    $prefix = $1;
    shift @vars;
  }

  #
  # emulates the interface of enum.pm
  # use OP::Enum qw|:Foo_=20 Whiskey Tango Foxtrot |
  # Sets prefix to Foo_ and index to 20; entries will begin with value of 20
  #
  if ( $prefix && $prefix =~ /^(\w+)=(\d+)$/ ) {
    $prefix = $1;
    $index = $2;
  }

  for my $var ( @vars ) {
    #
    # emulates the interface of enum.pm
    # use OP::Enum qw|Foo Bar Baz=20 Bario|
    # Creates Baz with index of 20, next will be 21 etc
    # "Yes, you can change the start index at any time as in C"
    #
    if ( $var && $var =~ /^(\w+)=(\d+)$/ ) {
      $var = $1;
      $index = $2;
    }

    #
    # prepend the prefix if one was provided
    #
    if ( $prefix ) {
      $var = join('', $prefix, $var);
    }

    #
    # more deep magics
    #
    eval qq/
      package $caller;

      push \@EXPORT_OK, \$var;
      push \@LIST, \$index;

      use constant $var => \$index;
    /;

    throw OP::RuntimeError($@) if $@;

    $index++;
  }

  return 1;
}

=pod

=head1 REVISION

$Id: //depotit/tools/snitchd/OP-0.20/lib/OP/Enum.pm#1 $

=head1 SEE ALSO

L<Exporter>, L<constant>, L<enum>

This file is part of L<OP>.

=cut

1;
