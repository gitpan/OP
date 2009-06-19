#
# File: OP/Recur.pm
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

OP::Recur - Object class to represent recurring points in time

=head1 SYNOPSIS

  use OP;

  my $recur = OP::Recur->new();

  #
  # every:
  #
  # Every X UNITS ie "every 3 minutes"
  #
  $recur->every(3, MIN); # Time::Consts constant
  $recur->every(180);    # Implicit UNITS is Seconds (1)

  #
  # at, exceptAt:
  #
  # At [Year]/[Month]/[Day] [Hour]:[Minute]:Seconds
  #
  # Except At [Year]/[Month]/[Day] [Hour]:[Minute]:Seconds
  #
  $recur->at(*YYYY,*MM,*DD,*hh,*mm,ss);
  $recur->exceptAt(*YYYY,*MM,*DD,*hh,*mm,ss);

  #
  # on, exceptOn:
  #
  # On Nth [Weekday] [in Month] [of Year]
  #
  # Except On Nth [Weekday] [in Month] [of Year]
  #
  $recur->on(Nth,*WDAY,*MM,*YYYY);
  $recur->exceptOn(Nth,*WDAY,*MM,*YYYY);

  #
  # each, exceptEach:
  #
  # Each [Weekday] [in Month] [of Year]
  #
  # Except Each [Weekday] [in Month] [of Year]
  #
  $recur->each(*WDAY,*MM,*YYYY);
  $recur->exceptEach(*WDAY,*MM,*YYYY);

  #
  # C<loop> and C<coloop> will execute code at the specified
  # intervals, in blocking or non-blocking fashion. See examples.
  #

The methods C<every>, C<at>/C<exceptAt>, C<on>/C<exceptOn>, and
C<each>/C<exceptEach> may be called as many times as needed, overlaying
rules to create complex recurrence loops. If called without any arguments,
these methods return an L<OP::Array> instance containing the specific
Recur:: helper instances which were added.

=head1 INSTANCE GETTERS

=over 4

=item * $recur->every();

Called with no arguments, returns an L<OP::Array> of all
L<OP::Recur::Every> inclusion rules in self.

=item * $recur->at();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::At>
inclusion rules in self.

=item * $recur->exceptAt();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::At>
I<exclusion> rules in self.

=item * $recur->on();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::On>
inclusion rules in self.

=item * $recur->exceptOn();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::On>
I<exclusion> rules in self.

=item * $recur->each();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::Each>
inclusion rules in self.

=item * $recur->exceptEach();

Called with no arguments, returns an L<OP::Array> of all L<OP::Recur::Each>
I<exclusion> rules in self.

=back

=head1 INSTANCE SETTERS

=over 4

=item * $recur->every(X,[UNITS]);

The C<every> method adds a new L<OP::Recur::Every> instance,
which represents a recurring fixed time interval.

UNITS may be any number where 1 is equal to 1 second. The constants
available in the L<Time::Consts> module work well for this. Sub-second
or floating point values for either argument are acceptable.

Omitting a UNITS argument implies Seconds (1) as a base unit.

  #
  # Fixed interval, eg every 3 minutes:
  #
  my $recur = every(3,MIN); # See Time::Consts

  #
  # Another example; every 500 milliseconds:
  #
  $recur->every(500,MSEC); # See Time::Consts


=item * $recur->at([YYYY],[MM],[DD],[hh],[mm],ss)

=item * $recur->exceptAt([YYYY],[MM],[DD],[hh],[mm],ss)

The C<at> method adds a new L<OP::Recur::At> instance, which
represents an interval bound to calendar time.

The C<exceptAt> method follows the same pattern, but is used to declare
excluded times rather than included ones.

The magic constant "LAST" may be used for DD to indicate the final day
in a given month. LAST only works this way for C<at> and C<exceptAt>
rules.

A field may be wildcarded by providing C<undef> in its place, but note
that C<at> consumes args in a non-traditional reverse order, and also
acts like a I<multi-method> where the number of arguments determines
the most significant base value (examples below).

The C<at> constructor supports 1-6 arguments, always ordered from most
significant (ie Year) to least significant (Seconds). The different
possible modes of usage are shown here:

  #
  # at(YYYY,MM,DD,hh,mm,ss)
  #
  # Describes a one-time occurrence,
  # eg December 21 2012 at midnight:
  #
  $recur->at(2012,12,21,00,00,00);

  #
  # at(MM,DD,hh,mm,ss)
  #
  # Describes a yearly recurrence,
  # eg Every day in January at midnight:
  #
  $recur->at(01,undef,00,00,00);

  #
  # at(DD,hh,mm,ss)
  #
  # Describes a monthly recurrence,
  # eg Last day of each month at midnight:
  #
  $recur->at(LAST,00,00,00);

  #
  # Describes a daily recurrence,
  # at(hh,mm,ss)
  #
  # eg Every day at noon:
  #
  $recur->at(12,00,00);

  #
  # at(mm,ss)
  #
  # Describes an hourly recurrence,
  # eg Every hour at :45 after:
  #
  $recur->at(45,00);

  #
  # at(ss)
  #
  # Describes an every-minute recurrence,
  # eg Every minute at 30 seconds:
  #
  $recur->at(30);

Hopefully, the above examples illustrate a usage pattern for C<at>.


=item * $recur->on(Nth,WDAY,*MM,*YYYY)

=item * $recur->exceptOn(Nth,WDAY,*MM,*YYYY)

The C<on> method adds a new L<OP::Recur::On> instance, which
represents an ordinal weekday in an optional month/year, ie "The second
Thursday [in June] [2010]". MM and YYYY are wild if C<undef>.

WDAY is a day 1-7 where monday = 1, and MM is a month between 1 and
12. YYYY is the actual year, such as "2009". The constants available in
L<OP::Enum::DaysOfWeek> and L<OP::Enum::WeeksOfMonth> are suitable for
WDAY and MM, respectively.

The C<exceptOn> method follows the same pattern, but is used to declare
excluded times rather than included ones.

  use OP::Enum::DaysOfWeek;
  use OP::Enum::WeeksOfMonth;

  #
  # Recur on the 1st monday of january, 2010
  #
  $recur->on(1,MON,JAN,2010);

  #
  # Recur every first monday in january
  #
  $recur->on(1,MON,JAN);

  #
  # Recur every first monday
  #
  $recur->on(1,MON);

  #
  # Recur every first day
  #
  $recur->on(1);


=item * $recur->each(*WDAY,*MM,*YYYY)

=item * $recur->exceptEach(*WDAY,*MM,*YYYY)

C<each> is just like C<on>, but without ordinality.

The C<each> method adds a new L<OP::Recur::Each> instance, which
represents a recurring weekday, optionally within a month/year, ie "Each
Thursday [in June] [2010]". WDAY, MM, and YYYY are optional args, but
should be given as undef.

WDAY is a day 1-7 where monday = 1, and MM is a month between 1 and
12. YYYY is the actual year, such as "2009". The constants available in
L<OP::Enum::DaysOfWeek> and L<OP::Enum::WeeksOfMonth> are suitable for
WDAY and MM, respectively.

The C<exceptEach> method follows the same pattern, but is used to declare
excluded times rather than included ones.


  use OP::Enum::DaysOfWeek;
  use OP::Enum::WeeksOfMonth;

  #
  # Recur each monday in january 2010
  #
  $recur->on(MON,JAN,2010);

  #
  #
  # Recur each monday in january
  #
  $recur->on(MON,JAN);

  #
  # Recur each monday
  #
  $recur->on(MON);

=back

=head1 BLOCKING LOOP

=over 4

=item * $recur->loop($sub), break

Execute the received sub at the defined time interval, within a loop.

To exit the loop from within the sub, call C<OP::Recur::break>.

  use OP;

  use Time::Consts qw| :ALL |;

  my $recur = OP::Recur->new();

  #
  # Mix n match
  #
  $recur->every(5,SEC);
  $recur->every(2,SEC);

  $recur->loop( sub {
    my $now = shift;

    print "Doing something at $now...\n";

    break if $now > BEDTIME;
  } );


=back

=head1 NON-BLOCKING LOOP

Non-blocking loops utilize L<Coro>, and are compatible with L<POE>
(see notes below).

=over 4

=item * $recur->coloop($sub), snooze($secs), break

C<coloop> executes the received sub at the defined time interval,
within a cooperative L<Coro> thread. It does not wait for the loop
to return; you must call C<snooze($secs)> or C<Coro::cede> to yield
interpreter control back to the loop, and likewise from within the loop
to yield control back to any waiting threads.

C<snooze> is like Perl's C<sleep>, except that C<$secs> may be a floating
point value, and C<snooze> doesn't block Coro threads. In the context of
a coroutine, C<snooze> cedes control of the interpreter back to any
threads which need to do work, and they will do the same in turn. When
the specified time has elapsed, the thread will stop ceding and resume
work. C<snooze> otherwise just works like a hi-res version of C<sleep>.

C<break> breaks the loop, invoking Perl's C<last>.


  use OP;

  use Time::Consts qw| :ALL |;

  my $beep = OP::Recur->new();

  #
  # Start beeping in thread A
  #
  $beep->every(4.2,SEC);

  $beep->coloop( sub {
    my $now = shift;

    print "Beep at $now...\n";

    break if $now > BEDTIME;
  } );

  #
  # Start booping in thread B
  #
  my $boop = OP::Recur->new();

  $boop->every(2.5,SEC);

  $boop->coloop( sub {
    my $now = shift;

    print "Boop at $now.. boop boop!\n";

    break if $now > DOOMSDAY
  } );

  #
  # Insert your main loop here:
  #
  while(1) {
    snooze(.001);
  }

=back

=head2 POE Compatibility

In addition to invoking C<cede> in L<Coro>, C<snooze> invokes
L<POE::Kernel>'s C<run_one_timeslice> method at each time tick, allowing
the developer to interlace POE and Coro threads.

=over 4

  $recur->coloop( sub {
    #
    # Non-blocking action based on a POE::Component:
    #
    POE::Session->create( ... );
  } );

  #
  # Insert your main loop here:
  #
  while(1) {
    ##### XXX This is now handled by snooze().
    ##### POE::Kernel->run_one_timeslice;

    snooze(.001);
  }

=back

=head1 SEE ALSO

This file is part of L<OP>.

=cut

use strict;
use warnings;

use OP::Array qw| yield |;
use OP::Class qw| create true false |;
use OP::DateTime;
use OP::Double;
use OP::Hash;
use OP::Name;
use OP::Num;

use OP::Type;

use OP::Recur::At;
use OP::Recur::Break;
use OP::Recur::Each;
use OP::Recur::Every;
use OP::Recur::On;

use Date::Calc;
use Date::Manip;
use Time::HiRes;
use Time::Local;
use POE;

use Coro;

#
# Set up a POE Kernel so snooze() won't confuse
#
POE::Session->create(
  inline_states => {
    _start => sub { },
  }
);

do {
  package OP::Recur;

  our @EXPORT = qw| break snooze |;

  our $TIME = 0;

  use constant LAST => -1;
};

create "OP::Recur" => {
  __BASE__ => [ "Exporter", "OP::Hash" ],

  name => OP::Name->assert(
    OP::Type::optional
  ),

  _every => OP::Array->assert(
    OP::Recur::Every->assert(
      OP::Double->assert(OP::Type::optional),
    )
  ),

  _at => OP::Array->assert(
    OP::Recur::At->assert(
      OP::Num->assert(OP::Type::optional),
    ),
  ),

  _exceptAt => OP::Array->assert(
    OP::Recur::At->assert(
      OP::Num->assert(OP::Type::optional),
    )
  ),

  _on => OP::Array->assert(
    OP::Recur::On->assert(
      OP::Num->assert(OP::Type::optional),
    )
  ),

  _exceptOn => OP::Array->assert(
    OP::Recur::On->assert(
      OP::Num->assert(OP::Type::optional),
    )
  ),

  _each => OP::Array->assert(
    OP::Recur::Each->assert(
      OP::Num->assert(OP::Type::optional),
    )
  ),

  _exceptEach => OP::Array->assert(
    OP::Recur::Each->assert(
      OP::Num->assert(OP::Type::optional),
    )
  ),

  _planAhead => OP::TimeSpan->assert(
    OP::Type::default(10),
  ),

  _lastPlanTime => OP::DateTime->assert,

  # every => method(*@args) {
  every => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_every}->push( OP::Recur::Every->new(@args) );
    } else {
      return $self->{_every};
    }
  },

  # at => method(*@args) {
  at => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_at}->push( OP::Recur::At->new(@args) );
    } else {
      return $self->{_at};
    }
  },

  # exceptAt => method(*@args) {
  exceptAt => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_exceptAt}->push( OP::Recur::At->new(@args) );
    } else {
      return $self->{_exceptAt};
    }
  },

  # on => method(*@args) {
  on => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_on}->push( OP::Recur::On->new(@args) );
    } else {
      return $self->{_on};
    }
  },

  # exceptOn => method(*@args) {
  exceptOn => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_exceptOn}->push( OP::Recur::On->new(@args) );
    } else {
      return $self->{_exceptOn};
    }
  },

  # each => method(*@args) {
  each => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      #
      # Multi-method - allow iterator usage like other OP classes
      #
      if ( @args == 1 && UNIVERSAL::isa($args[0], "CODE") ) {
        return OP::Hash::collect($self, @args);
      }

      $self->{_each}->push( OP::Recur::Each->new(@args) );
    } else {
      return $self->{_each};
    }
  },

  # exceptEach => method(*@args) {
  exceptEach => sub {
    my $self = shift;
    my @args = @_;

    if ( @args ) {
      $self->{_exceptEach}->push( OP::Recur::Each->new(@args) );
    } else {
      return $self->{_exceptEach};
    }
  },

  break => sub {
    OP::Recur::Break->throw();
  },

  snooze => sub {
    my $amt = shift;

    my $until = Time::HiRes::time() + $amt;

    while(1) {
      if ( Time::HiRes::time() >= $until ) {
        last;
      }
      select(undef,undef,undef,.001);

      cede;

      $poe_kernel->run_one_timeslice;
    }
  },

  # coloop => method(Code $sub) {
  coloop => sub {
    my $self = shift;
    my $sub = shift;

    async {
      $self->_loop($sub);
    };
  },

  # loop => method(Code $sub) {
  loop => sub {
    my $self = shift;
    my $sub = shift;

    $self->coloop($sub);

    while(1) {
      OP::Recur::snooze(.001);
    }
  },

  # _loop => method(Code $sub) {
  _loop => sub {
    my $self = shift;
    my $sub = shift;

    $OP::Recur::TIME = OP::DateTime->new(
      sprintf('%.03f', Time::HiRes::time())
    );
    my $now = $OP::Recur::TIME;

    my $plan = $self->makePlan;

    while(1) {
      $OP::Recur::TIME = OP::DateTime->new(
        sprintf('%.03f', Time::HiRes::time())
      );
      $now = $OP::Recur::TIME;
      #
      # Figure out if it's time to run
      #
      if ( !$plan->isEmpty && $now >= $plan->first ) {
        $plan->shift;

        #
        #
        #
        local $Error::THROWN = undef;

        eval { &$sub($now) };

        if ( $@ ) {
          my $thrown = $Error::THROWN;

          if ( $thrown && UNIVERSAL::isa($thrown, "OP::Recur::Break") ) {
            last;
          } elsif ( $thrown ) {
            #
            # Rethrow
            #
            $thrown->throw();
          } elsif ( !$thrown ) {
            #
            # Normal error encountered, just die
            #
            die $@;
          }
        }
      } elsif ( !$plan->isEmpty ) {
        OP::Recur::snooze($plan->first - $now);
      }

      #
      # Update the plan
      #
      my $nextPlanTime = $self->_lastPlanTime + $self->_planAhead;

      if ( $now >= $nextPlanTime ) {
        $self->{_lastPlanTime} = $now;

        $plan->clear;
        undef $plan;

        $plan = $self->makePlan;

        OP::Recur::snooze(.001);
      }

      #
      # Big snoozer if there's nothing to do
      #
      if ( $plan->isEmpty ) {
        my $wakeIn = $nextPlanTime - $now;
        if ( $wakeIn > 0 ) {
          OP::Recur::snooze($wakeIn);
        } else {
          OP::snooze(.001);
        }
      }
    }
  },

  # updatePlanForEvery => method(OP::Hash $plan, Num $ustart) {
  updatePlanForEvery => sub {
    my $self = shift;
    my $plan = shift;
    my $ustart = shift;

    my $ulen = $self->_planAhead * 1.5 * 1000;

    #
    # Add to schedule from the "every" rules:
    #
    # $self->every->each( sub(OP::Recur::Every $every) {
    $self->every->each( sub {
      my $every = shift;

      my $uint = $every * 1000;

      for (
        my $utime = $ustart; $utime < ( $ustart + $ulen ); $utime++
      ) {
        next if $utime % $uint;

        my $time = $utime / 1000;

        $plan->{$time}++;
      }
    } );
  },

  # updatePlanForAt => method(OP::Hash $plan, Num $start) {
  updatePlanForAt => sub {
    my $self = shift;
    my $plan = shift;
    my $start = shift;

    my $len = $self->_planAhead * 1.5;

    #
    # Add to schedule from "at" rules:
    #
    # $self->at->each( sub(OP::Recur::At $at) {
    $self->at->each( sub {
      my $at = shift;

      my $year   = $at->year;
      my $month  = $at->month;
      my $day    = $at->day;
      my $hour   = $at->hour;
      my $minute = $at->minute;
      my $second = $at->second;

      if ( $year && $month && $day == -1 ) {
        $day = Date::Calc::Days_in_Month($year,$month);
      }

      for (
        my $time = $start; $time < ( $start + $len ); $time++
      ) {
        my @time = localtime($time);

        my $thisYear   = defined($year)   ? $year   : $time[5] + 1900;
        my $thisMonth  = defined($month)  ? $month  : $time[4] + 1;
        my $thisDay    = defined($day)    ? $day    : $time[3];
        my $thisHour   = defined($hour)   ? $hour   : $time[2];
        my $thisMinute = defined($minute) ? $minute : $time[1];
        my $thisSecond = defined($second) ? $second : $time[0];

        my $thisKey = Time::Local::timelocal(
          $thisSecond, $thisMinute, $thisHour,
          $thisDay, $thisMonth - 1, $thisYear - 1900
        );

        $plan->{$thisKey}++;
      }
    } );
  },

  # updatePlanForOn => method(OP::Hash $plan) {
  updatePlanForOn => sub {
    my $self = shift;
    my $plan = shift;

    #
    # Add "on" rules:
    #
    # $self->on->each( sub(OP::Recur::On $on) {
    $self->on->each( sub {
      my $on = shift;

      # $plan->each( sub( Num $time ) {
      $plan->each( sub {
        my $time = shift;

        my @time = localtime($time);

        my ( $wantYear, $wantMonth, $wantDay ) =
          Date::Calc::Nth_Weekday_of_Month_Year(
            ( defined $on->year  ? $on->year  : ( $time[5] + 1900 ) ),
            ( defined $on->month ? $on->month : ( $time[4] + 1 ) ),
            ( defined $on->wday  ? $on->wday  : ( $time[6] ) ),
            $on->n,
          );

        my $haveYear  = $time[5] + 1900;
        my $haveMonth = $time[4] + 1;
        my $haveDay   = $time[3];

        if (
          ( $haveYear != $wantYear )
          || ( $haveMonth != $wantMonth )
          || ( $haveDay != $wantDay )
        ) {
          delete $plan->{$time};
        }
      } );
    } );
  },

  # updatePlanForExceptOn => method(OP::Hash $plan) {
  updatePlanForExceptOn => sub {
    my $self = shift;
    my $plan = shift;

    #
    # Subtract "exceptOn" rules:
    #
    # $self->exceptOn->each( sub(OP::Recur::On $on) {
    $self->exceptOn->each( sub {
      my $on = shift;

      # $plan->each( sub( Num $time ) {
      $plan->each( sub {
        my $time = shift;

        my @time = localtime($time);

        my ( $wantYear, $wantMonth, $wantDay ) =
          Date::Calc::Nth_Weekday_of_Month_Year(
            ( defined $on->year  ? $on->year  : ( $time[5] + 1900 ) ),
            ( defined $on->month ? $on->month : ( $time[4] + 1 ) ),
            ( defined $on->wday  ? $on->wday  : ( $time[6] ) ),
            $on->n,
          );

        my $haveYear  = $time[5] + 1900;
        my $haveMonth = $time[4] + 1;
        my $haveDay   = $time[3];

        if (
          ( $haveYear == $wantYear )
          || ( $haveMonth == $wantMonth )
          || ( $haveDay == $wantDay )
        ) {
          delete $plan->{$time};
        }
      } );
    } );
  },

  # updatePlanForExceptAt => method(OP::Hash $plan, Num $start) {
  updatePlanForExceptAt => sub {
    my $self = shift;
    my $plan = shift;
    my $start = shift;

    my $len = $self->_planAhead * 1.5;

    #
    # Subtract "exceptAt" rules:
    #
    # $self->exceptAt->each( sub(OP::Recur::At $at) {
    $self->exceptAt->each( sub {
      my $at = shift;

      my $year   = $at->year;
      my $month  = $at->month;
      my $day    = $at->day;
      my $hour   = $at->hour;
      my $minute = $at->minute;
      my $second = $at->second;

      if ( $year && $month && $day == -1 ) {
        $day = Date::Calc::Days_in_Month($year,$month);
      }

      for (
        my $time = $start; $time < ( $start + $len ); $time++
      ) {
        my @time = localtime($time);

        my $thisYear   = defined($year) ? $year : $time[5] + 1900;
        my $thisMonth  = defined($month) ? $month : $time[4] + 1;
        my $thisDay    = defined($day) ? $day : $time[3];
        my $thisHour   = defined($hour) ? $hour : $time[2];
        my $thisMinute = defined($minute) ? $minute : $time[1];
        my $thisSecond = defined($second) ? $second : $time[0];

        my $thisKey = Time::Local::timelocal(
          $thisSecond, $thisMinute, $thisHour,
          $thisDay, $thisMonth - 1, $thisYear - 1900
        );

        delete $plan->{$thisKey};
      }
    } );
  },

  # makePlan => method() {
  makePlan => sub {
    my $self = shift;

    my $planKeys = OP::Hash->new;

    #
    #
    #
    my $start = int(time);

    my $ustart = $start * 1000;

    #
    # Additive
    #
    $self->updatePlanForEvery($planKeys, $ustart);

    $self->updatePlanForAt($planKeys, $start);

    #
    # Limiting
    #
    $self->updatePlanForOn($planKeys);

    #
    # Subtractive
    #
    $self->updatePlanForExceptAt($planKeys, $start);

    $self->updatePlanForExceptOn($planKeys);

    my $plan = OP::Array->new;

    my $now = time;

    $planKeys->keys->reversed->each( sub {
      return if $_ <= $now;
      
      $plan->unshift( OP::DateTime->new($_) );
    } );

    $self->{_lastPlanTime} = $start;

    return $plan;
  },

};
