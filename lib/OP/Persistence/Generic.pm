package OP::Persistence::Generic;

use strict;
use warnings;

use Error qw| :try |;

use OP::Enum::Bool;
use OP::Enum::DBIType;

use GlobalDBI;

sub columnNames {
  my $class = shift;
  my $raw = shift;

  my $asserts = $class->asserts();

  return $asserts->collect( sub {
    my $attr = shift;

    my $type = $asserts->{$attr};

    my $objectClass = $type->objectClass;

    return if $objectClass->isa("OP::Array");
    return if $objectClass->isa("OP::Hash");

    OP::Array::yield($attr);
  } );
}

sub __doesIdExistStatement {
  my $class = shift;
  my $id = shift;

  return( sprintf q|
      SELECT count(*) FROM %s WHERE id = %s
    |,
    $class->tableName,
    $class->quote($id)
  );
}

sub __doesNameExistStatement {
  my $class = shift;
  my $name = shift;

  return( sprintf q|
      SELECT count(*) FROM %s WHERE name = %s
    |,
    $class->tableName,
    $class->quote($name),
  );
}

sub __idForNameStatement {
  my $class = shift;
  my $name = shift;

  return( sprintf q|
      SELECT %s FROM %s WHERE name = %s
    |,
    $class->__primaryKey(),
    $class->tableName(),
    $class->quote($name)
  );
}

sub __nameForIdStatement {
  my $class = shift;
  my $id = shift;

  return( sprintf q|
      SELECT name FROM %s WHERE %s = %s
    |,
    $class->tableName(),
    $class->__primaryKey(),
    $class->quote($id),
  );
}

sub __beginTransaction {
  my $class = shift;

  if ( !$OP::Persistence::transactionLevel ) {
    $class->write(
      $class->__beginTransactionStatement()
    );
  }

  $OP::Persistence::transactionLevel++;

  return $@ ? false : true;
}


sub __rollbackTransaction {
  my $class = shift;

  $class->write(
    $class->__rollbackTransactionStatement()
  );

  return $@ ? false : true;
}


sub __commitTransaction {
  my $class = shift;

  if ( !$OP::Persistence::transactionLevel ) {
    throw OP::TransactionFailed(
      "$class->__commitTransaction() called outside of transaction!!!"
    );
  } elsif ( $OP::Persistence::transactionLevel == 1 ) {
    $class->write(
      $class->__commitTransactionStatement()
    );
  }

  $OP::Persistence::transactionLevel--;

  return $@ ? false : true;
}


sub __beginTransactionStatement {
  my $class = shift;

  return "BEGIN;\n";
}


sub __commitTransactionStatement {
  my $class = shift;

  return "COMMIT;\n";
}


sub __rollbackTransactionStatement {
  my $class = shift;

  return "ROLLBACK;\n";
}


sub __schema {
  my $class = shift;

  #
  # Make sure the specified primary key is valid
  #
  my $primaryKey = $class->__primaryKey();

  throw OP::PrimaryKeyMissing(
    "$class has no __primaryKey set, please fix"
  ) if !$primaryKey;

  my $asserts = $class->asserts();

  throw OP::PrimaryKeyMissing(
    "$class did not assert __primaryKey $primaryKey"
  ) if !exists $asserts->{$primaryKey};

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

  my $inlineAttribs = OP::Array->new();

  for my $attribute ( sort $class->attributes() ) {
    my $type = $asserts->{$attribute};

    next if !$type;

    my $statement = $class->__statementForColumn(
      $attribute, $type, $foreign, $unique
    );

    $inlineAttribs->push( sprintf('  %s', $statement) )
      if $statement;
  }

  $schema->push( $inlineAttribs->join(",\n") );
  $schema->push(");");
  $schema->push('');

  return $schema->join("\n");
}


sub __concatNameStatement {
  my $class = shift;

  my $asserts = $class->asserts();

  my $uniqueness = $class->asserts()->{name}->unique();

  my $concatAttrs = OP::Array->new();

  my @uniqueAttrs;

  if ( ref $uniqueness ) {
    @uniqueAttrs = @{ $uniqueness };
  } elsif ( $uniqueness && $uniqueness ne '1' ) {
    @uniqueAttrs = $uniqueness;
  } else {
    return join(".", $class->tableName, "name") . " as __name";

    # @uniqueAttrs = "name";
  }

  #
  # For each attribute that "name" is keyed with, include the
  # value in a display name. If the value is an ID, look up the name.
  #
  for my $extAttr ( @uniqueAttrs ) {
    #
    # Get the class
    #
    my $type = $asserts->{ $extAttr };

    if ( $type->objectClass()->isa("OP::ExtID") ) {
      my $extClass = $type->memberClass();

      my $tableName = $extClass->tableName();

      #
      # Method calls itself-- 
      #
      # I don't think this will ever infinitely loop,
      # since we use constraints (see query)
      #
      my $subSel = $extClass->__concatNameStatement()
        || sprintf('%s.name', $tableName);

      $concatAttrs->push( sprintf q|
          ( SELECT %s FROM %s WHERE %s.id = %s )
        |,
        $subSel, $tableName, $tableName, $extAttr
      );

    } else {
      $concatAttrs->push($extAttr);
    }
  }

  $concatAttrs->push(join(".", $class->tableName, "name"));

  return if $concatAttrs->isEmpty();

  my $select = sprintf
    'concat(%s) as __name', $concatAttrs->join(', " / ", ');

  return $select;
}

sub __serialType {
  my $class = shift;

  return "INTEGER PRIMARY KEY AUTOINCREMENT";
}

sub __statementForColumn {
  my $class = shift;
  my $attribute = shift;
  my $type = shift;
  my $foreign = shift; # Not handled by Generic
  my $unique = shift;  # Not handled by Generic - see $uniqueInline instead

  if (
    $type->objectClass()->isa("OP::Hash")
     || $type->objectClass()->isa("OP::Array")
  ) {
    #
    # Value lives in a link table, not in this class's table
    #
    return "";
  }

  #
  # Using this key as an AUTO_INCREMENT primary key?
  #
  return join(" ", $attribute, $class->__serialType)
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
  my $primaryInline = ( $class->__primaryKey eq $attribute )
    ? "PRIMARY KEY" : "";

  #
  # Permitting NULL/undef values for this key?
  #
  my $notNull = !$type->optional && !$primaryInline ? 'NOT NULL' : '';

  my $fragment = OP::Array->new();

  if (
    defined $type->default
    && $datatype !~ /^text/i
    && $datatype !~ /^blob/i
  ) {
    #
    # A "default" value was specified by a subtyping rule,
    # so plug it in to the database table schema:
    #
    my $quotedDefault = $class->quote($type->default);

    $fragment->push( $attribute, $datatype, 'DEFAULT', $quotedDefault );
  } else {
    #
    # No default() was specified:
    #
    $fragment->push( $attribute, $datatype );
  }

  $fragment->push($notNull) if $notNull;
  $fragment->push($uniqueInline) if $uniqueInline;
  $fragment->push($primaryInline) if $primaryInline;

  return $fragment->join(" ");
}

sub __dropTable {
  my $class = shift;

  my $table = $class->tableName();

  my $query = "DROP TABLE $table;\n";

  return $class->write($query);
}


sub __createTable {
  my $class = shift;

  my $query = $class->__schema();

  return $class->write($query);
}


sub __selectRowStatement {
  my $class = shift;
  my $id = shift;

  return sprintf(q| SELECT %s FROM %s WHERE %s = %s |,
    $class->__selectColumnNames->join(", "),
    $class->tableName(),
    $class->__primaryKey(),
    $class->quote($id)
  );
}


sub __allNamesStatement {
  my $class = shift;

  return sprintf(q| SELECT name FROM %s |, $class->tableName());
}


sub __allIdsStatement {
  my $class = shift;

  return sprintf( q|
      SELECT %s FROM %s ORDER BY name
    |,
    $class->__primaryKey(),
    $class->tableName(),
  );
}

sub __wrapWithReconnect {
  my $class = shift;
  my $sub = shift;

  warn "$class\::__wrapWithReconnect not implemented";

  return &$sub(@_);
}

sub __init {
  my $class = shift;

  if ( $class =~ /::Abstract/ ) {
    return false;
  }

  #
  #
  #
  warn "$class\::__init not implemented";

  return true;
}

sub __updateColumnNames {
  my $class = shift;

  return $class->columnNames;
}

sub __insertColumnNames {
  my $class = shift;

  my $priKey = $class->__primaryKey;

  #
  # Omit "id" from the SQL statement if we're using auto-increment
  #
  if ( $class->asserts->{$priKey}->isa("OP::Type::Serial") ) {
    return $class->columnNames->collect( sub {
      my $name = shift;

      return if $name eq $priKey;

      OP::Array::yield($name);
    } );

  } else {
    return $class->columnNames;
  }
}

sub __selectColumnNames {
  my $class = shift;

  my $asserts = $class->asserts();

  return $class->columnNames->collect( sub {
    my $attr = shift;

    my $type = $asserts->{$attr};

    my $objectClass = $type->objectClass;

    return if $objectClass->isa("OP::Array");
    return if $objectClass->isa("OP::Hash");

    if (
      $objectClass->isa("OP::DateTime")
       && ( $type->columnType eq 'DATETIME' )
    ) {
      # OP::Array::yield("UNIX_TIMESTAMP($attr) AS $attr");
      OP::Array::yield( $class->__quoteDatetimeSelect($attr) );

    } else {
      OP::Array::yield($attr);
    }
  } );
}

sub __quoteDatetimeInsert {
  my $class = shift;
  my $value = shift;

die;
  return $value;
}

sub __quoteDatetimeSelect {
  my $class = shift;
  my $attr = shift;

die;
  return $attr;
}

#
#
#
sub _quotedValues {
  my $self = shift;
  my $isUpdate = shift;

  my $class = $self->class();

  my $values = OP::Array->new();

  my $asserts = $class->asserts();

  my $columns = $isUpdate ?
    $class->__updateColumnNames : $class->__insertColumnNames;

  $columns->each( sub {
    my $key = shift;

    my $value = $self->get($key);

    my $quotedValue;

    my $type = $asserts->{$key};
    return if !$type;

    if ( $type->sqlInsertValue && $OP::Persistence::ForceInsertSQL ) {
      $quotedValue = $type->sqlInsertValue;

    } elsif ( $type->sqlUpdateValue && $OP::Persistence::ForceUpdateSQL ) {
      $quotedValue = $type->sqlUpdateValue;

    } elsif ( $type->sqlValue() ) {
      $quotedValue = $type->sqlValue();

    } elsif ( $type->optional() && !defined($value) ) {
      $quotedValue = 'NULL';

    } elsif ( !defined($value) || ( !ref($value) && $value eq '' ) ) {
      $quotedValue = "''";

    } elsif (
      !ref($value) || ( ref($value) && overload::Overloaded($value) )
    ) {
      if ( !UNIVERSAL::isa($value, $type->objectClass) ) {
        #
        # Sorry, but you're an object now.
        #
        $value = $type->objectClass->new( Clone::clone($value) );
      }

      if (
        $type->objectClass->isa("OP::DateTime")
          && $type->columnType eq 'DATETIME'
      ) {
        $quotedValue = $class->__quoteDatetimeInsert($value);
      } else {
        $quotedValue = $class->quote($value);
      }
    } elsif ( ref($value) ) {
      my $dumpedValue =
        UNIVERSAL::can($value, "toYaml")
        ? $value->toYaml
        : YAML::Syck::Dump($value);

      chomp($dumpedValue);

      $quotedValue = $class->quote($dumpedValue);
    }

    if ( $isUpdate ) {
      $values->push( "  $key = $quotedValue" )
    } else { # Is Insert
      $values->push( $quotedValue );
    }
  } );

  return $values;
}

sub _updateRowStatement {
  my $self = shift;

  my $class = $self->class();

  my $statement = sprintf( q| UPDATE %s SET %s WHERE %s = %s; |,
    $class->tableName(),
    $self->_quotedValues(true)->join(",\n"),
    $class->__primaryKey(),
    $class->quote( $self->key() )
  );

  return $statement;
}

sub _insertRowStatement {
  my $self = shift;

  my $class = $self->class();

  return sprintf( q| INSERT INTO %s (%s) VALUES (%s); |,
    $class->tableName(),
    $class->__insertColumnNames->join(', '),
    $self->_quotedValues(false)->join(', '),
  );
}

sub _deleteRowStatement {
  my $self = shift;

  my $idKey = $self->class()->__primaryKey();

  unless ( defined $self->{$idKey} ) {
    throw OP::ObjectIsAnonymous( "Can't delete an object with no ID" );
  }

  my $class = $self->class();

  return sprintf( q| DELETE FROM %s WHERE %s = %s |,
    $class->tableName(),
    $idKey,
    $class->quote($self->{$idKey})
  );
}

true;
