package OP::Runtime;

our $Backends;

package main;

use strict;
use diagnostics;

use Test::More qw| no_plan |;

use File::Tempdir;

use constant false => 0;
use constant true  => 1;

use vars qw| $tempdir $path $nofs %classPrototype %instancePrototype |;

BEGIN {
  $tempdir = File::Tempdir->new;

  $path = $tempdir->name;

  if ( !-d $path ) {
    $nofs = "Couldn't find usable tempdir for testing";
  }
}

#####
##### Set up environment
#####

SKIP: {
  skip( $nofs, 2 ) if $nofs;

  require_ok("OP::Runtime");
  ok( OP::Runtime->import($path), 'setup environment' );
}

do {
  %classPrototype = (
    testArray    => OP::Array->assert( OP::Str->assert() ),
    testBool     => OP::Bool->assert(),
    testDouble   => OP::Double->assert(),
    testFloat    => OP::Float->assert(),
    testInt      => OP::Int->assert(),
    testNum      => OP::Num->assert(),
    testRule     => OP::Rule->assert(),
    testStr      => OP::Str->assert(),
    testTimeSpan => OP::TimeSpan->assert(),
  );

  %instancePrototype = (
    testArray    => [ "foo", "bar", "baz", "rebar", "rebaz" ],
    testBool     => true,
    testDouble   => "1234.5678901",
    testFloat    => 22 / 7,
    testInt      => 23,
    testNum      => 42,
    testRule     => qr/foo/,
    testStr      => "example",
    testTimeSpan => 60 * 24,
  );
};

#####
##### Test auto-detected backing store type
#####

SKIP: {
  skip( $nofs, 2 ) if $nofs;

  my $class = "OP::AutoTest01";
  ok(
    testCreate( $class => { %classPrototype } ),
    "Class allocate w/ auto-detected backing store"
  );

  kickClassTires($class);
}

#####
##### Test YAML flatfile backing store
#####

SKIP: {
  skip( $nofs, 3 ) if $nofs;

  my $class = "OP_YAMLTest::YAMLTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => false,
        __useYaml      => true,
        __useMemcached => 5,
        __useRcs       => true,
        %classPrototype
      }
    ),
    "Class allocate w/ YAML"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "OP_YAMLTest::ExtIDTest",
      {
        __useDbi  => false,
        __useYaml => true,
      }
    ),
    "ExtID support for YAML"
  );
}

#####
##### SQLite Tests
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$OP::Runtime::Backends->{"SQLite"} ) {
    my $reason = "DBD::SQLite not installed";

    skip( $reason, 5 );
  }

  my $class = "OP_SQLiteTest::SQLiteTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 1,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ SQLite (1)"
  );

  kickClassTires($class);

  $class = "OP_SQLiteTest::SQLiteTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 1,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        id             => OP::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ SQLite (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "OP_SQLiteTest::ExtIDTest",
      {
        __useDbi  => true,
        __dbiType => 1
      }
    ),
    "ExtID support for SQLite"
  );
}

#####
##### MySQL/InnoDB Tests
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$OP::Runtime::Backends->{"MySQL"} ) {
    my $reason = "DBD::mysql not installed or 'op' db not ready";

    skip( $reason, 5 );
  }

  my $class = "OP::MySQLTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 0,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ MySQL (1)"
  );

  kickClassTires($class);

  $class = "OP::MySQLTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 0,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        id             => OP::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ MySQL (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "OP::MySQL::ExtIDTest",
      {
        __useDbi  => true,
        __dbiType => 0
      }
    ),
    "ExtID support for MySQL"
  );
}

#####
##### PostgreSQL
#####

SKIP: {
  if ($nofs) {
    skip( $nofs, 5 );
  } elsif ( !$OP::Runtime::Backends->{"PostgreSQL"} ) {
    my $reason = "DBD::Pg not installed or 'op' db not ready";

    skip( $reason, 5 );
  }

  my $class = "OP::PgTest01";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 2,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ PostgreSQL (1)"
  );

  kickClassTires($class);

  $class = "OP::PgTest02";
  ok(
    testCreate(
      $class => {
        __useDbi       => true,
        __dbiType      => 2,
        __useMemcached => 5,
        __useRcs       => true,
        __useYaml      => true,
        id             => OP::Serial->assert,
        %classPrototype
      }
    ),
    "Class allocate + table create w/ PostgreSQL (2)"
  );

  kickClassTires($class);

  ok(
    testExtID(
      "OP::PgSQL::ExtIDTest",
      {
        __useDbi  => true,
        __dbiType => 2
      }
    ),
    "ExtID support for PostgreSQL"
  );
}

#####
#####
#####

sub kickClassTires {
  my $class = shift;

  return if $nofs;

  return if !UNIVERSAL::isa( $class, "OP::Object" );

  if ( $class->__useDbi ) {

    #
    # Just in case there was already a table, make sure the schema is fresh
    #
    ok( $class->__dropTable, "Drop existing table" );

    ok( $class->__createTable, "Re-create table" );
  }

  my $asserts = $class->asserts;

  do {
    my $obj;
    isa_ok(
      $obj = $class->new(
        name => OP::Utility::randstr(),
        %instancePrototype
      ),
      $class
    );
    ok( $obj->save, "Save to backing store" );

    my $success;

    ok( $success = $obj->exists, "Exists in backing store" );

    #
    # If the above test failed, then we know the rest will too.
    #
    if ($success) {
      kickObjectTires($obj);
    }
  };

  my $ids = $class->allIds;

  $ids->each(
    sub {
      my $id = shift;

      my $obj;
      isa_ok( $obj = $class->load($id),
        $class, "Object retrieved from backing store" );

      kickObjectTires($obj);

      ok( $obj->remove, "Remove from backing store" );

      ok( !$obj->exists, "Object was removed" );

      undef $obj;

      if ( $class->__useRcs ) {
        isa_ok( $obj = $class->restore( $id, '1.1' ),
          $class, "Object restored from RCS archive" );

        kickObjectTires($obj);
      }
    }
  );

  if ( $class->__useDbi ) {
    ok( $class->__dropTable, "Drop table" );
  }
}

sub kickObjectTires {
  my $obj = shift;

  my $class   = $obj->class;
  my $asserts = $class->asserts;

  $asserts->each(
    sub {
      my $key  = shift;
      my $type = $asserts->{$key};

      isa_ok( $obj->{$key}, $type->objectClass,
        sprintf( '%s "%s"', $class->pretty($key), $obj->{$key} ) );

      if ( $obj->{$key}->isa("OP::Array") ) {
        is( $obj->{$key}->size(), 5, "Compare element count" );
      }
    }
  );
}

#
#
#
sub testCreate {
  my $class          = shift;
  my $classPrototype = shift;

  $OP::Persistence::dbi = {};

  eval { OP::create( $class, $classPrototype ); };

  return $class->isa($class);
}

sub testExtID {
  my $class     = shift;
  my $prototype = shift;

  $OP::Persistence::dbi = {};

  ok( testCreate( $class => $prototype ), "Allocate parent class" );

  my $childClass = join( "::", $class, "Child" );

  ok(
    testCreate(
      $childClass => {
        %{$prototype},

        parentId => OP::ExtID->assert($class),
      }
    ),
    "Allocate child class"
  );

  if ( $class->__useDbi ) {
    ok( $childClass->__dropTable(), "Drop " . $childClass->tableName );
    ok( $class->__dropTable(),      "Drop " . $class->tableName );

    ok( $class->__createTable(),      "Create " . $class->tableName );
    ok( $childClass->__createTable(), "Create " . $childClass->tableName );
  }

  my $parent = $class->new( name => "Parent" );

  ok( $parent->save(), "Save parent object" );

  my $child = $childClass->new(
    name     => "Child",
    parentId => $parent->id
  );

  ok( $child->save(), "Save child object" );

  ok( $child->remove(),  "Remove child object" );
  ok( $parent->remove(), "Remove parent object" );

  my $worked;

  eval {
    $child->setParentId("garbageIn");
    $child->save();

    $child->remove;
  };

  if ($@) {

    #
    # This means the operation failed because constraints worked
    #
    $worked++;
  }

  if ( $class->__useDbi ) {
    ok( $childClass->__dropTable(), "Drop " . $childClass->tableName );
    ok( $class->__dropTable(),      "Drop " . $class->tableName );
  }

  return $worked;
}
