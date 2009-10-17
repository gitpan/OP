#
# File: OP/Persistence/SQLite.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Persistence::SQLite;

=pod

=head1 NAME

OP::Persistence::SQLite - Vendor-specific overrides for SQLite

=head1 FUNCTION

=over 4

=item * C<connect(%args)>

Constructor for a SQLite GlobalDBI object.

C<%args> is a hash with a key for C<database> (database name), which
in SQLite is really a local filesystem path (/path/to/db).

Returns a new L<GlobalDBI> instance.
   
=back

=cut

use strict;
use warnings;

use File::Path;
use OP::Enum::Bool;
use OP::Constants qw| sqliteRoot |;

use base qw| OP::Persistence::Generic |;

sub connect {
  my %args = @_;

  my $dsn = sprintf( 'DBI:SQLite:dbname=%s', $args{database} );

  $GlobalDBI::CONNECTION{ $args{database} } ||=
    [ $dsn, '', '', { RaiseError => 1 } ];

  return GlobalDBI->new( dbname => $args{database} );
}

=pod

=head1 SEE ALSO

L<GlobalDBI>, L<DBI>, L<DBD::SQLite>

L<OP::Persistence>

This file is part of L<OP>.

=cut

########
######## The remainder of this module contains vendor-specific overrides
########

sub __wrapWithReconnect {
  my $class = shift;
  my $sub   = shift;

  return &$sub(@_);
}

sub __init {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  if ( !-e sqliteRoot ) {
    mkpath(sqliteRoot);
  }

  $class->write('PRAGMA foreign_keys = ON');

  my $sth = $class->query('select tbl_name from sqlite_master');

  my %tables;
  while ( my ($table) = $sth->fetchrow_array() ) {
    $tables{$table}++;
  }

  $sth->finish();

  if ( !$tables{ $class->tableName() } ) {
    $class->__createTable();
  }

  return true;
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

  return sprintf( 'datetime(%i, "unixepoch")', $value->escape );
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return "strftime('\%s', $attr) AS $attr";
}

sub __useForeignKeys {
  my $class = shift;

  my $use = $class->get("__useForeignKeys");

  if ( !defined $use ) {
    $use = false;

    $class->set("__useForeignKeys", $use);
  }

  return $use;
}

true;
