#
# File: OP/Persistence/MySQL.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Persistence::PostgreSQL;

=pod

=head1 NAME

OP::Persistence::PostgreSQL - Vendor-specific overrides for PostgreSQL

=head1 DESCRIPTION

Enables the PostgreSQL backing store.

When using PostgreSQL, you must create and grant access to your
application's database and the "op" database prior to use.

=head1 FUNCTION

=over 4

=item * C<connect(%args)>

Constructor for a PostgreSQL GlobalDBI object.

C<%args> is a hash with keys for C<database> (database name), C<host>,
C<port>, C<user>, and C<pass>.

Returns a new L<GlobalDBI> instance.

=back

=cut

use strict;
use warnings;

use Error qw| :try |;
use OP::Enum::Bool;

use base qw| OP::Persistence::Generic |;

sub connect {
  my %args = @_;

  my $dsn = sprintf( 'dbi:Pg:database=%s;host=%s;port=%s',
    $args{database}, $args{host}, $args{port} );

  $GlobalDBI::CONNECTION{ $args{database} } ||=
    [ $dsn, $args{user}, $args{pass}, { RaiseError => 1 } ];

  return GlobalDBI->new( dbname => $args{database} );
}

=pod

=head1 SEE ALSO

L<GlobalDBI>, L<DBI>, L<DBD::Pg>

L<OP::Persistence>

This file is part of L<OP>.

=cut

########
######## The remainder of this module contains vendor-specific overrides
########

sub __init {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  my $sth = $class->query( q|
    select table_name from information_schema.tables
  | );

  my %tables;
  while ( my ($table) = $sth->fetchrow_array() ) {
    $tables{lc $table}++;
  }

  $sth->finish();

  if ( !$tables{ lc $class->tableName() } ) {
    $class->__createTable();
  }

  return true;
}

sub __datetimeColumnType {
  my $class = shift;

  return "FLOAT";
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

  return $value->escape;
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return $attr;
}

sub __wrapWithReconnect {
  my $class = shift;
  my $sub   = shift;

  my $return;

  while (1) {
    try {
      $return = &$sub;
    }
    catch Error with {
      my $error = shift;

      if ( $error =~ /Is the server running/is )
      { 
        my $dbName = $class->databaseName;

        my $sleepTime = 1;

        #
        # Try to reconnect on failure...
        #
        print STDERR "Lost connection - PID $$ re-connecting to "
          . "\"$dbName\" database.\n";

        sleep $sleepTime;

        $class->__dbi->db_disconnect;

        delete $OP::Persistence::dbi->{$dbName}->{$$};
        delete $OP::Persistence::dbi->{$dbName};
      } else {

        #
        # Rethrow
        #
        throw $error;
      }
    };

    last if $return;
  }

  return $return;
}

sub __statementForColumn {
  my $class     = shift;
  my $attribute = shift;
  my $type      = shift;

  if ( $type->objectClass()->isa("OP::Hash")
    || $type->objectClass()->isa("OP::Array") )
  {

    #
    # Value lives in a link table, not in this class's table
    #
    return "";
  }

  #
  # Using this key as an AUTO_INCREMENT primary key?
  #
  return join( " ", $attribute, $class->__serialType )
    if $type->serial;

  #
  #
  #
  my $datatype = $type->columnType || 'TEXT';

  #
  # Some database declare UNIQUE constraints inline with the column
  # spec, not later in the table def like mysql does. Handle that
  # case here:
  #
  my $uniqueInline = $type->unique ? 'UNIQUE' : '';

  #
  # Same with PRIMARY KEY, MySQL likes them at the bottom, other DBs
  # want it to be inline.
  #
  my $primaryInline =
    ( $class->__primaryKey eq $attribute ) ? "PRIMARY KEY" : "";

  #
  # Permitting NULL/undef values for this key?
  #
  my $notNull = !$type->optional && !$primaryInline ? 'NOT NULL' : '';

  my $fragment = OP::Array->new();

  if ( defined $type->default
    && $datatype !~ /^text/i
    && $datatype !~ /^blob/i )
  {

    #
    # A "default" value was specified by a subtyping rule,
    # so plug it in to the database table schema:
    #
    my $quotedDefault = $class->quote( $type->default );

    $fragment->push( $attribute, $datatype, 'DEFAULT', $quotedDefault );
  } else {

    #
    # No default() was specified:
    #
    $fragment->push( $attribute, $datatype );
  }

  $fragment->push($notNull)       if $notNull;
  $fragment->push($uniqueInline)  if $uniqueInline;
  $fragment->push($primaryInline) if $primaryInline;

  if ( $type->objectClass->isa("OP::ExtID") ) {
    my $memberClass = $type->memberClass();

    #
    # Value references a foreign key
    #
    $fragment->push( sprintf('references %s(%s)',
      $memberClass->tableName,
      $memberClass->__primaryKey
    ) );
  }

  return $fragment->join(" ");
}

sub __serialType {
  my $class = shift;

  return "SERIAL";
}

sub __useForeignKeys {
  my $class = shift;

  return true;
}

1;
