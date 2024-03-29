#
# File: OP/Utility.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Utility;

=pod

=head1 NAME

OP::Utility - System functions required globally by OP

=head1 SYNOPSIS

  use OP::Utility;

=head1 ENVIRONMENT

Using this module will enable backtraces for all warns and fatals. The
messages are informative and nicely formatted, but can be quite
verbose. To disable them, set the environment variable C<OP_QUIET>
to C<1>.

=head1 FUNCTIONS

=cut

use strict;

use Carp;
use Data::GUID;
use Error qw| :try |;
use File::Path;
use IO::File;
use Net::Syslog;
use POSIX qw| strftime |;
use Scalar::Util qw| blessed |;
use YAML::Syck;

use OP::Constants qw| yamlRoot scratchRoot syslogHost |;
use OP::Exceptions;

my $logger =
  syslogHost
  ? Net::Syslog->new(
  Facility   => 'local1',
  Priority   => 'info',
  SyslogHost => syslogHost,
  )
  : undef;

our $longmess = 1;    # Carp.pm long messages - 0 = no, 1 = yes

#
# Install WARN/DIE signal handlers:
#
my ( $ORIGWARN, $ORIGDIE );

if ( !$ENV{OP_QUIET} ) {
  $ORIGWARN = $SIG{__WARN__};
  $ORIGDIE  = $SIG{__DIE__};

  $SIG{__WARN__} = \&OP::Utility::warnHandler;
  $SIG{__DIE__}  = \&OP::Utility::dieHandler;
}

#
# Human-readable sizes
#
use constant Kilo => 1024;
use constant Mega => Kilo * 1024;
use constant Giga => Mega * 1024;
use constant Tera => Giga * 1024;

#
# Human-readable times
#
use constant Millisecond => .001;
use constant Second      => 1;
use constant Minute      => 60;
use constant Hour        => Minute * 60;
use constant Day         => Hour * 24;
use constant Week        => Day * 7;
use constant Month       => Day * 30;
use constant Year        => Day * 365.25;
use constant Decade      => Year * 10;

=pod

=over 4

=item * humanSize($seconds, [$optionalSuffix]);

Convert the received byte count to something more human-readable (eg
Kilo, Mega, Giga). Optionally acceps a second argument to use as a
"suffix" to the label, otherwise the word "Bytes" is used.

=cut

# sub humanSize(Int $int, Str $label) {
sub humanSize {
  my $int   = shift;
  my $label = shift;

  $label ||= "Bytes";

  if ( $label eq 'timeticks' ) {
    return Net::SNMP::ticks_to_time($int);
  }

  my $str;

  if ( $int >= Tera ) {
    $str = sprintf( "\%.02f T$label", $int / Tera );
  } elsif ( $int >= Giga ) {
    $str = sprintf( "\%.02f G$label", $int / Giga );
  } elsif ( $int >= Mega ) {
    $str = sprintf( "\%.02f M$label", $int / Mega );
  } elsif ( $int >= Kilo ) {
    $str = sprintf( "\%.02f K$label", $int / Kilo );
  } else {
    $str = sprintf( "\%.02f $label", $int );
  }

  return $str;
}

=pod

=item * humanTime($seconds);

Convert the received number of seconds into something more human-readable 
(eg Minutes, Hours, Years)

=cut

# sub humanTime(Num $num) {
sub humanTime {
  my $num = shift;

  my $str;

  my $sign = ( $num < 0 ) ? '-' : '';

  $num =~ s/^-// if $sign;

  if ( $num >= Year ) {
    $str = sprintf( '%.02f years', $num / Year );
  } elsif ( $num >= Month ) {
    $str = sprintf( '%.02f months', $num / Month );
  } elsif ( $num >= Week ) {
    $str = sprintf( '%.02f weeks', $num / Week );
  } elsif ( $num >= Day ) {
    $str = sprintf( '%.02f days', $num / Day );
  } elsif ( $num >= Hour ) {
    $str = sprintf( '%.02f hours', $num / Hour );
  } elsif ( $num >= Minute ) {
    $str = sprintf( '%.02f mins', $num / Minute );
  } elsif ( $num >= Second ) {
    $str = sprintf( '%.02f secs', $num / Second );
  } else {
    $str = sprintf( '%.02f ms', $num / Millisecond );
  }

  return join( '', $sign, $str );
}

=pod

=item * loadYaml($path);

Load the YAML file at the specified path into a native Perl data structure.

=cut

# sub loadYaml(Str $path) {
sub loadYaml {
  my $path = shift;

  return undef unless -e $path;

  my $yaml;

  open( YAML, "< $path" );
  while (<YAML>) { $yaml .= $_ }
  close(YAML);

  return YAML::Syck::Load($yaml);
}

=pod

=item * randstr()

Return a random 6-byte alphabetic string

=cut

sub randstr {

  # my @chars=('a'..'z','A'..'Z', 0..9);

  my @chars = ( 'A' .. 'F', 0 .. 9 );

  my $id;

  for ( 1 .. 6 ) { $id .= $chars[ rand @chars ]; }

  return $id;
}

=pod

=item * timestamp([$time])

Return the received unix epoch seconds as YYYY-MM-DD HH:MM:DD. Uses the
current time if none is provided.

=cut

# sub timestamp(Num ?$unix) {
sub timestamp {
  my $unix = shift;

  $unix ||= CORE::time();

  my @localtime = localtime($unix);

  return sprintf(
    '%i-%02d-%02d %02d:%02d:%02d %s',
    $localtime[5] + 1900,
    $localtime[4] + 1,
    $localtime[3], $localtime[2], $localtime[1], $localtime[0],
    strftime( '%Z', @localtime )
  );
}

=pod

=item * date([$time]);

Return the received unix epoch seconds as YYYY-MM-DD. Uses the current
time if none is provided.

=cut

# sub date(Num ?$unix) {
sub date {
  my $unix = shift;

  $unix ||= CORE::time();

  my @localtime = localtime($unix);

  return sprintf( '%i-%02d-%02d',
    $localtime[5] + 1900,
    $localtime[4] + 1,
    $localtime[3],
  );
}

=pod

=item * time([$time]);

Return the received unix epoch seconds as hh:mm:ss. Uses the current
time if none is provided.

=cut

# sub time(Num ?$unix) {
sub time {
  my $unix = shift;

  $unix ||= CORE::time();

  my @localtime = localtime($unix);

  return
    sprintf( '%02d:%02d:%02d', $localtime[2], $localtime[1], $localtime[0] );
}

=pod

=item * hour([$time]);

Return the received unix epoch seconds as the current hour of the day.
Uses the current time if none is provided.

=cut

# sub hour(Num ?$unix) {
sub hour {
  my $unix = shift;

  $unix ||= CORE::time();

  my @localtime = localtime($unix);

  return $localtime[2];
}

=pod

=item * decodeExitStatus($status);

Decodes the status ($?) from running perl's system(). Returns exit code,
signal, and core dump true/false

=cut

sub decodeExitStatus {
  my $status = shift;

  my $exit   = $status >> 8;
  my $signal = $status & 127;
  my $core   = $status & 128;

  return ( $exit, $signal, $core );
}

=pod

=item * newId();

Return a new alpha-numeric ID (GUID).

=cut

sub newId {
  return Data::GUID->new();

  # return Data::GUID->new()->as_string();
}

=pod

=item * warnHandler([$exception])

Pretty-print a warning to STDERR

=cut

sub warnHandler {
  my $timestamp = OP::Utility::timestamp();

  my $caller = caller();

  # my $message = $longmess
  # ? Carp::longmess(@_)
  # : Carp::shortmess(@_);

  my $message = Carp::shortmess(@_);

  $message = formatErrorString($message);

  my $errStr = "- Warning from $caller:\n  $message\n";

  print STDERR $errStr;

  if ($logger) {
    $errStr =~ s/\s+/ /g;
    $logger->send($errStr);
  }
}

=pod

=item * dieHandler([$exception])

Pretty-print a fatal error to STDERR

=cut

sub dieHandler {
  my ($exception) = @_;

  die @_ if $^S;    # Only die for *unhandled* exceptions. It's Magic!
                    # See also: Error.pm

  my $timestamp = OP::Utility::timestamp();

  my $type = ref($exception);

  my ( $firstLine, $message );

  if ( $type && ref($exception) && blessed($exception) ) {

    #
    # throw Error(message) was called:
    #
    $firstLine = "- Unhandled $type Exception:\n";

    $message =
      $longmess
      ? Carp::longmess( $exception->stacktrace() )
      : Carp::shortmess( $exception->stacktrace() );
  } else {

    #
    # die($string) was called:
    #
    $firstLine = "- Fatal error:\n";

    $message =
      $longmess
      ? Carp::longmess($exception)
      : Carp::shortmess($exception);
  }

  my $errStr;

  if ( $message =~ /Fatal error:/ ) {
    $errStr =
      $message
      ? formatErrorString($message)
      : $exception;
  } else {
    $errStr =
      $message
      ? join( "  ", $firstLine, formatErrorString($message) )
      : join( "  ", $firstLine, $exception );
  }

  if ($logger) {
    my $singleLine = $errStr;
    $singleLine =~ s/\s+/ /g;
    $logger->send($singleLine);
  }

  die "$errStr";
}

=pod

=item * formatErrorString($errStr)

Backtrace formatter called by error printing functions.

=cut

sub formatErrorString($) {
  my $errStr = shift;

  my $time = OP::Utility::timestamp();

  $errStr =~ s/ (at .*?)\.\n/\n  ... $1\n  ... at $time\n\n/m;
  $errStr =~ s/^ at .*?\n//m;
  $errStr =~ s/ called at/,\n   /gm;
  $errStr =~ s/ at line/:/gm;
  $errStr =~ s/^\t/  /gm;
  $errStr =~ s/\s*$/\n/s;

  return $errStr;
}

=pod

=back

=head1 SEE ALSO

This file is part of L<OP>.

=cut

1;
