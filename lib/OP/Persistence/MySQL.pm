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
package OP::Persistence::MySQL;

=pod

=head1 NAME

OP::Persistence::MySQL - Vendor-specific overrides for MySQL/InnoDB

=head1 FUNCTION

=over 4

=item * C<connect(%args)>

Constructor for a MySQL GlobalDBI object.

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

use constant RefOpts => [ "CASCADE", "SET NULL", "RESTRICT", "NO ACTION" ];

sub connect {
  my %args = @_;

  my $dsn = sprintf( 'DBI:mysql:database=%s;host=%s;port=%s',
    $args{database}, $args{host}, $args{port} );

  $GlobalDBI::CONNECTION{ $args{database} } ||=
    [ $dsn, $args{user}, $args{pass}, { RaiseError => 1 } ];

  return GlobalDBI->new( dbname => $args{database} );
}

=pod

=head1 SEE ALSO

L<GlobalDBI>, L<DBI>, L<DBD::mysql>

L<OP::Persistence>

This file is part of L<OP>.

=cut

########
######## The remainder of this module contains vendor-specific overrides
########

sub __schema {
  my $class = shift;

  #
  # Make sure the specified primary key is valid
  #
  my $primaryKey = $class->__primaryKey();

  throw OP::PrimaryKeyMissing( "$class has no __primaryKey set, please fix" )
    if !$primaryKey;

  my $asserts = $class->asserts();

  throw OP::PrimaryKeyMissing(
    "$class did not assert __primaryKey $primaryKey" )
    if !exists $asserts->{$primaryKey};

  #
  # Tack on any UNIQUE secondary keys at the end of the schema
  #
  my $unique = OP::Hash->new();

  #
  # Tack on any FOREIGN KEY constraints at the end of the schema
  #
  my $foreign = OP::Array->new();

  #
  # Start building the CREATE TABLE statement:
  #
  my $schema = OP::Array->new();

  my $table = $class->tableName();

  $schema->push("CREATE TABLE $table (");

  for my $attribute ( sort $class->attributes() ) {
    my $type = $asserts->{$attribute};

    next if !$type;

    my $statement =
      $class->__statementForColumn( $attribute, $type, $foreign, $unique );

    $schema->push( sprintf( '  %s,', $statement ) )
      if $statement;
  }

  my $dbiType = $class->__dbiType();

  if ( $unique->isEmpty() ) {
    $schema->push( sprintf( '  PRIMARY KEY(%s)', $primaryKey ) );
  }
  else {
    $schema->push( sprintf( '  PRIMARY KEY(%s),', $primaryKey ) );

    my $uniqueStatement = $unique->collect(
      sub {
        my $key       = $_;
        my $multiples = $unique->{$key};

        my $item;

        #
        # We can't reliably key on multiple columns if any of them are NULL.
        # MySQL permits this as per the SQL spec, allowing duplicate values,
        # because the statement ( NULL == NULL ) is always false.
        #
        # Basically, this check prevents OP class definitions from trying
        # to key on something which might be undefined.
        #
        # This unfortunately prevents keying on multiple items within
        # the same class, limiting this functionality to ExtID pointers
        # only. I'm not sure how else to deal with this as of MySQL 5.
        #
        if ( ref $multiples ) {
          for ( @{$multiples} ) {
            if ( !$asserts->{$_} ) {
              throw OP::AssertFailed(
                "Can't key on non-existent attribute '$_'" );
            }
            elsif ( $asserts->{$_}->optional() ) {
              throw OP::AssertFailed(
                "Can't reliably key on ::optional column '$_'" );
            }
          }

          $item = sprintf '  UNIQUE KEY (%s)',
            join( ", ", $key, @{$multiples} );
        }
        elsif ( $multiples && $multiples ne '1' ) {
          $item = "  UNIQUE KEY($key, $multiples)";
        }
        elsif ($multiples) {
          $item = "  UNIQUE KEY($key)";
        }

        if ($item) {
          OP::Array::yield($item);
        }
      }
    );

    $schema->push( $uniqueStatement->join(",\n") );
  }

  if ( !$foreign->isEmpty() ) {
    $schema->push("  ,");

    $schema->push(
      $foreign->collect(
        sub {
          my $key  = $_;
          my $type = $asserts->{$key};

          my $foreignClass = $type->memberClass();

          my $deleteRefOpt = $type->onDelete() || 'RESTRICT';
          my $updateRefOpt = $type->onUpdate() || 'CASCADE';

          my $template = join( "\n",
            '  FOREIGN KEY (%s) REFERENCES %s (%s)',
            "    ON DELETE $deleteRefOpt",
            "    ON UPDATE $updateRefOpt" );

          OP::Array::yield(
            sprintf( $template,
              $_,
              $foreignClass->tableName(),
              $foreignClass->__primaryKey() )
          );
        }
        )->join(",\n")
    );
  }

  $schema->push(") ENGINE=INNODB DEFAULT CHARACTER SET=utf8;");
  $schema->push('');

  return $schema->join("\n");
}

sub __serialType {
  my $class = shift;

  return "AUTO_INCREMENT";
}

sub __statementForColumn {
  my $class     = shift;
  my $attribute = shift;
  my $type      = shift;
  my $foreign   = shift;
  my $unique    = shift;

  if ( $type->objectClass()->isa("OP::Hash")
    || $type->objectClass()->isa("OP::Array") )
  {

    #
    # Value lives in a link table, not in this class's table
    #
    return "";
  }

  if ( $type->objectClass->isa("OP::ExtID") ) {

    #
    # Value references a foreign key
    #
    $foreign->push($attribute);
  }

  my $uniqueness = $type->unique();

  $unique->{$attribute} = $uniqueness;

  #
  #
  #
  my $datatype;

  if ( $type->columnType() ) {
    $datatype = $type->columnType();
  }
  else {
    $datatype = 'TEXT';
  }

  #
  # Using this key as an AUTO_INCREMENT primary key?
  #
  my $serial = $type->serial() ? $class->__serialType : '';

  #
  # Permitting NULL/undef values for this key?
  #
  my $notNull =
    $type->optional()
    ? ''
    : 'NOT NULL';

  my $attr = OP::Array->new();

  if ( defined $type->default()
    && $datatype !~ /^text/i
    && $datatype !~ /^blob/i )
  {

    #
    # A default() modifier was provided in the assertion,
    # so plug it in to the database table schema:
    #
    my $quotedDefault = $class->quote( $type->default() );

    $attr->push( $attribute, $datatype, 'DEFAULT', $quotedDefault );
  }
  else {

    #
    # No default() was specified:
    #
    $attr->push( $attribute, $datatype );
  }

  $attr->push($notNull) if $notNull;
  $attr->push($serial)  if $serial;

  return $attr->join(" ");
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

      if ( $error =~ /server has gone away|can't connect|unable to connect/is )
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
      }
      else {

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

sub __init {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  my $sth = $class->query('show tables');

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

  return sprintf( 'FROM_UNIXTIME(%i)', $value->escape );
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr  = shift;

  return "UNIX_TIMESTAMP($attr) AS $attr";
}

true;
