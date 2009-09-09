#
# File: OP/DateTime.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#

#
# Time::Piece overrides localtime/gmtime in caller, which breaks assumptions
#
# Override Time::Piece to not override:
#
package OP::DateTime;

use strict;
use warnings;

do {
  package Time::Piece::Nonpolluting;

  use strict;
  use warnings;

  use base qw| Time::Piece |;

  our @EXPORT = qw| |;

  sub import { }

  sub export { }
};

use OP::Class qw| true false |;
use OP::Num;
use Scalar::Util qw| blessed |;
use Time::Local;

use base qw| Time::Piece::Nonpolluting OP::Array |;

use overload
  %OP::Num::overload,
  '""'  => '_sprint',
  '<=>' => '_compare';

our $datetimeRegex = qr/^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/;

# method assert(OP::Class $class: *@rules) {
sub assert {
  my $class = shift;
  my @rules = @_;

  my %parsed = OP::Type::__parseTypeArgs(
    sub {
      my $time = $_[0];

      if ( $time && $time =~ $datetimeRegex ) {
        $time = $class->newFrom($1, $2, $3, $4, $5, $6);
      }

      UNIVERSAL::isa($time, "Time::Piece")
       || Scalar::Util::looks_like_number($time)
       || OP::AssertFailed->throw("Received value is not a time");
    }, @rules
  );

  $parsed{min} = 0 if !defined $parsed{min};
  $parsed{max} = 2**32 if !defined $parsed{max};
  $parsed{columnType} ||= 'DOUBLE(15,4)';
  $parsed{optional} = true if !defined $parsed{optional};

  return $class->__assertClass()->new(%parsed);
}

sub new {
  my $class = shift;
  my $time = shift;

  if ( $time && $time =~ /$datetimeRegex/ ) {
    return $class->newFrom($1, $2, $3, $4, $5, $6);
  }

  my $epoch = 0;

  my $blessed = blessed($time);

  if ( $blessed && $time->can("epoch") ) {
    $epoch = $time->epoch();
  } elsif ( $blessed && overload::Overloaded($time) ) {
    $epoch = "$time";
  } else {
    $epoch = $time;
  }

  OP::Type::insist($epoch, OP::Type::isFloat);

  my $self = Time::Piece::Nonpolluting->new($epoch);

  return bless $self, $class;
}

# method newFrom(OP::Class $class:
#   Num $year, Num $month, Num $day, Num $hour, Num $minute, Num $sec
sub newFrom {
  my $class = shift;
  my $year = shift;
  my $month = shift;
  my $day = shift;
  my $hour = shift;
  my $minute = shift;
  my $sec = shift;

  return $class->new(
    Time::Local::timelocal(
      $sec, $minute, $hour,
      $day, $month - 1, $year - 1900
    )
  );
}

#
# Allow comparison of DateTime, Time::Piece, overloaded scalar,
# and raw number values.
#
# Overload is retarded for sometimes reversing these, what the actual hell
#
sub _compare {
  my $date1 = $_[2] ? $_[1] : $_[0];
  my $date2 = $_[2] ? $_[0] : $_[1];

  if ( blessed($date1) && $date1->can("epoch") ) {
    $date1 = $date1->epoch();
  }

  if ( blessed($date2) && $date2->can("epoch") ) {
    $date2 = $date2->epoch();
  }

  return $date1 <=> $date2;
}

sub _sprint {
  return shift->epoch()
}

#
# Deny all knowledge of being OP::Array-like.
#
# DateTime wants to be treated like a scalar when it comes to just about
# everything.
#
sub isa {
  my $recv = shift;
  my $what = shift;

  return false if $what eq 'OP::Array';

  return UNIVERSAL::isa($recv,$what);
}

true;

__END__

=pod

=head1 NAME

OP::DateTime - Overloaded Time object class

=head1 SYNOPSIS

  use OP::DateTime;

From Epoch:

  my $time = OP::DateTime->new( time() );

From YYYY MM DD hh mm ss:

  my $time = OP::DateTime->newFrom(1999,12,31,23,59,59);

=head1 DESCRIPTION

Time object.

Extends L<OP::Object>, L<Time::Piece>. Overloaded for numeric comparisons,
stringifies as unix epoch seconds unless overridden.

=head1 PUBLIC CLASS METHODS

=over 4

=item * C<assert(OP::Class $class: *@rules)>

Returns a new OP::Type::DateTime instance which encapsulates the received
L<OP::Subtype> rules.

With exception to C<ctime> and C<mtime>, which default to DATETIME,
DOUBLE(15,4) is the default column type for OP::DateTime. This is
done in order to preserve sub-second time resolution. This may be
overridden as needed on a per-attribute bases.

To use DATETIME as the column type, specify it as the value to the
C<columnType> subtype arg. When using a DATETIME column, OP will
automatically ask the database to handle any necessary conversion.

  create "OP::Example" => {
    someTimestamp  => OP::DateTime->assert(
      subtype(
        columnType => "DATETIME",
      )
    ),

    # ...
  };

=item * C<new(OP::Class $class: Num $epoch)>

Returns a new OP::DateTime instance which encapsulates the received value.

  my $object = OP::DateTime->new($epoch);

=back

=head1 SEE ALSO

See the L<Time::Piece> module for time formatting and manipulation
methods inherited by this class.

This file is part of L<OP>.

=cut
