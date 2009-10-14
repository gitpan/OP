#
# File: OP/Constants.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Constants;

use strict;
use warnings;

use File::HomeDir;
use IO::File;
use Sys::Hostname;
use YAML::Syck;

use Error qw| :try |;

use OP::Exceptions;

require Exporter;

use base qw( Exporter );

our @EXPORT_OK;

sub init {
  my $RC     = shift;
  my $caller = caller;

  $ENV{OP_HOME} ||= File::HomeDir->my_home;

  OP::RuntimeError->throw("Could not determine home directory for current user")
    if !$ENV{OP_HOME};

  #
  #
  #
  my $rc;

  my $path = join( '/', $ENV{OP_HOME}, $RC );

  my $override = join( '/', $ENV{OP_HOME}, join( "-", $RC, hostname() ) );

  if ( $ENV{OP_HOME} && -f $path ) {
    my $file = IO::File->new( $path, 'r' )
      || throw OP::FileAccessError("Could not read $path: $@");

    my @yaml;

    while (<$file>) { push @yaml, $_ }

    $file->close();

    eval {
      $rc = YAML::Syck::Load( join( '', @yaml ) );

      die $@ if $@;
    };

    throw OP::RuntimeError($@) if $@;

    throw OP::RuntimeError("Unexpected format in $path: Should be a HASH")
      if !ref($rc) || ref($rc) ne 'HASH';

    if ( -f $override ) {
      my $file = IO::File->new( $override, 'r' )
        || throw OP::FileAccessError("Could not read $override: $@");

      my @overrideYAML;

      while (<$file>) { push @overrideYAML, $_ }

      $file->close();

      my $overlay;

      eval {
        $overlay = YAML::Syck::Load( join( '', @overrideYAML ) ) || die $@;
      };

      throw OP::RuntimeError($@) if $@;

      throw OP::RuntimeError("Unexpected format in $override: Should be a HASH")
        if !ref($overlay) || ref($overlay) ne 'HASH';

      for my $key ( keys %{$overlay} ) {
        $rc->{$key} = $overlay->{$key};
      }
    }
  } elsif ( $RC eq '.oprc' ) {

    #
    # Use what are hopefully reasonable defaults.
    #
    $rc = {
      yamlHost       => undef,
      yamlRoot       => join( '/', $ENV{OP_HOME}, 'yaml' ),
      sqliteRoot     => join( '/', $ENV{OP_HOME}, 'sqlite' ),
      scratchRoot    => '/tmp',
      dbHost         => 'localhost',
      dbPass         => undef,
      dbPort         => 3306,
      dbUser         => 'op',
      memcachedHosts => [ '127.0.0.1:31337', ],
      rcsBindir      => '/usr/bin',
      rcsDir         => 'RCS',
      syslogHost     => undef,
    };
  } else {
    print STDERR q(!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    _  _____ _____ _____ _   _ _____ ___ ___  _   _ 
   / \|_   _|_   _| ____| \ | |_   _|_ _/ _ \| \ | |
  / _ \ | |   | | |  _| |  \| | | |  | | | | |  \| |
 / ___ \| |   | | | |___| |\  | | |  | | |_| | |\  |
/_/   \_\_|   |_| |_____|_| \_| |_| |___\___/|_| \_|
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
);

    my $current = $ENV{OP_HOME} || "";

    print STDERR "\n";
    print STDERR "\"$0\" needs some help finding a file.\n";
    print STDERR "\n";
    print STDERR "HERE'S WHAT'S WRONG:\n";
    print STDERR "  OP can't find a valid constants file, \"$RC\"!\n";
    print STDERR "  $RC lives under OP_HOME (currently: \"$current\").\n";
    print STDERR "\n";
    print STDERR "HOW TO FIX THIS:\n";
    print STDERR "  Set OP_HOME to the location of a valid $RC, in the\n";
    print STDERR "  shell environment or calling script. For example:\n";
    print STDERR "\n";
    print STDERR "  In bash:\n";
    print STDERR "    export OP_HOME=\"/path/to\"\n";
    print STDERR "\n";
    print STDERR "  Or in $0:\n";
    print STDERR "    \$ENV{OP_HOME} = \"/path/to\";\n";
    print STDERR "\n";
    print STDERR "This must be corrected before proceeding.\n";
    print STDERR "\n";
    print STDERR "A starter .oprc should have accompanied this\n";
    print STDERR "distribution as \"oprc-dist\". An example is\n";
    print STDERR "also given on the OP::Constants manual page.\n";
    print STDERR "\n";

    exit(2);
  }

  do {
    no strict "refs";

    @{"$caller\::EXPORT_OK"} = ();
  };

  for my $key ( keys %{$rc} ) {
    do {
      no strict "refs";
      no warnings "once";

      push @{"$caller\::EXPORT_OK"}, $key;
    };

    eval qq|
      package $caller;

      use constant \$key => \$rc->{$key};
    |;

    throw OP::RuntimeError($@) if $@;
  }
}

init '.oprc';

=pod

=head1 NAME

OP::Constants - Loads .oprc values as Perl constants

=head1 DESCRIPTION

Loads C<.oprc> values as Perl constants, with optional export.
Easily extended to support other named rc files.

C<.oprc> is a YAML file containing constant values used by OP. It should
be located under C<$ENV{OP_HOME}>, which defaults to the current
user's home directory ($ENV{HOME} on Unix platforms)

An example C<.oprc> is included in the top level directory of this
distribution as C<oprc-dist>, and also given later in this document.
Copy this file to the proper location, or just run C<bin/opconf>
(also included with this distribution) to generate this for your
local system and current user.

=head1 SECURITY

The C<.oprc> file represents the keys to the kingdom.

Treat your C<.oprc> file with the same degree of lockdown as you would
with system-level executables and their associated configuration
files. It should not be kept in a location where untrusted parties
can write to it, or where any unaudited changes can occur.

=head1 SYNOPSIS

To import constants directly, just specify them when using OP::Constants:

 use OP::Constants qw| dbUser dbPass |;

 my $dbUser = dbUser;
 my $dbPass = dbPass;

To access the constants without importing them into the caller's
namespace, just fully qualify them:

 use OP::Constants;

 my $dbUser = OP::Constants::dbUser;
 my $dbPass = OP::Constants::dbPass;

=head1 EXAMPLE

The following is an example of an .oprc file. The file contents must be
valid YAML:

  ---
  yamlRoot: /opt/op/yaml
  yamlHost: ~
  sqliteRoot: /opt/op/sqlite
  scratchRoot: /tmp
  dbHost: localhost
  dbPass: ~
  dbPort: 3306
  dbUser: op
  memcachedHosts:
    - 127.0.0.1:31337
  rcsBindir: /usr/bin
  rcsDir: RCS
  syslogHost: ~


=head1 HOST-SPECIFIC OVERLAYS

After loading .oprc, OP::Constants checks for the presence of a
file named C<.oprc-HOSTNAME>, where HOSTNAME is the name of localhost
as per Sys::Hostname. If the file is found, its values are added
as constants, stomping any values of the same key which were loaded
from the "global" rc.

For example, the host-specific configuration below would force
hypothetical host foo.example.com to connect to a different database
than the one specified in .oprc.

  > hostname
  foo.example.com

  > cat $OP_HOME/.oprc-foo.example.com
  ---
  dbHost: stgdb.example.com


=head1 CUSTOM RC FILES

Developers may create self-standing rc files for application-specific
consumption. Just use OP::Constants as a base, and invoke C<init> for the
named rc file.

Just as C<.oprc>, the custom rc file must contain valid YAML, and it lives
under C<$ENV{OP_HOME}>.

For example, in a hypothetical <.myapprc>:

  ---
  hello: howdy

Hypothetical package MyApp/Constants.pm makes any keys available
as Perl constants:

  package MyApp::Constants;

  use base qw| OP::Constants |;

  OP::Constants::init(".myapprc");

  1;

Callers may consume the constants package, requesting symbols for export:

  use MyApp::Constants qw| hello |;

  say hello;

  #
  # Prints "howdy"
  #

Host-specific overlays work with custom RC files as well.

  > hostname
  foo.example.com

  > cat $OP_HOME/.myapprc-foo.example.com
  ---
  dbHost: stgdb.example.com

  > perl -e 'use MyApp::Constants qw| dbHost |; say dbHost'
  stgdb.example.com


=head1 DIAGNOSTICS

=over 4

=item * No .oprc found

C<.oprc> needs to exist in order for OP to compile and run.  In the
event that an C<.oprc> was not found, OP will exit with an instructive
message. Read and follow the provided steps when this occurs.

=item * Some symbol not exported

  Uncaught exception from user code:
        "______" is not exported by the OP::Constants module
  Can't continue after import errors ...

This is a compile error. A module asked for a non-existent constant
at compile time.

The most likely cause is that OP found an C<.oprc>, but the required
symbol wasn't in the file. To fix this, add the missing named
constant to your C<.oprc>. This typically happens when the C<.oprc>
which was loaded is for an older version of OP than is actually
installed.

This error may also be thrown when the C<.oprc> is malformed.
If the named constant is present in the file, but this error is still
occurring, check for broken syntax within the file. Missing ":"
seperators between key and value pairs, or improper levels of
indenting are likely culprits.

=item * Host-specific overlay not working

Verify that the name of the host-specific overlay matches the local
host's "hostname" value, including fully-qualified-ness.

  > hostname
  foo

In the case of non-FQ hostnames, as above, the overlay rc is named
C<.oprc-foo>, whereas:

  > hostname
  foo.example.com

In the fully qualified example above, the overlay rc would be named
C<.oprc-foo.example.com>.


=back

=head1 SEE ALSO

L<File::HomeDir>, L<Sys::Hostname>, L<YAML::Syck>, L<constant>

This file is part of L<OP>.

=cut

1;
