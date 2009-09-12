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
  skip($nofs, 2) if $nofs;

  require_ok("OP::Runtime");
  ok( OP::Runtime->import($path), 'setup environment' );
}

do {
  %classPrototype = (
    testBool      => OP::Bool->assert(),
    testDouble    => OP::Double->assert(),
    testFloat     => OP::Float->assert(),
    testInt       => OP::Int->assert(),
    testNum       => OP::Num->assert(),
    testRule      => OP::Rule->assert(),
    testStr       => OP::Str->assert(),
    testTimeSpan  => OP::TimeSpan->assert(),
  );

  %instancePrototype = (
    testBool      => true,
    testDouble    => "1234.5678901",
    testFloat     => 22/7,
    testInt       => 23,
    testNum       => 42,
    testRule      => qr/foo/,
    testStr       => "example",
    testTimeSpan  => 60*24,
  );
};

SKIP: {
  skip($nofs, 2) if $nofs;

  my $class = "OP_YAMLTest::YAMLTest01";
  ok(
    testCreate($class => {
      __useDbi => false,
      __useYaml => true,
      __useMemcached => 5,
      __useRcs => true,
      %classPrototype
    }),
    "Class allocate"
  );

  kickClassTires($class);
}

#####
##### SQLite Tests
#####

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  } elsif ( !$OP::Runtime::Backends->{"SQLite"} ) {
    my $reason = "DBD::SQLite is not installed";

    skip($reason, 2);
  }

  my $class = "OP_SQLiteTest::SQLiteTest01";
  ok(
    testCreate($class => {
      __dbiType => 1,
      __useMemcached => 5,
      __useRcs  => true,
      __useYaml => true,
      %classPrototype
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
}

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  } elsif ( !$OP::Runtime::Backends->{"SQLite"} ) {
    my $reason = "DBD::SQLite is not installed";

    skip($reason, 2);
  }

  my $class = "OP_SQLiteTest::SQLiteTest02";
  ok(
    testCreate($class => {
      __dbiType => 1,
      __useMemcached => 5,
      __useRcs  => true,
      __useYaml => true,
      id => OP::Serial->assert,
      %classPrototype
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
}

#####
##### MySQL/InnoDB Tests
#####

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  } elsif ( !$OP::Runtime::Backends->{"MySQL"} ) {
    my $reason = "DBD::mysql not installed or 'op' db not ready";

    skip($reason, 2);
  }

  my $class = "OP::MySQLTest01";
  ok(
    testCreate($class => {
      __dbiType => 0,
      __useMemcached => 5,
      __useRcs  => true,
      __useYaml => true,
      %classPrototype
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
}

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  } elsif ( !$OP::Runtime::Backends->{"MySQL"} ) {
    my $reason = "DBD::mysql is not installed or 'op' db not ready";

    skip($reason, 2);
  }

  my $class = "OP::MySQLTest02";
  ok(
    testCreate($class => {
      __dbiType => 0,
      __useMemcached => 5,
      __useRcs  => true,
      __useYaml => true,
      id => OP::Serial->assert,
      %classPrototype
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
}

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  }

  my $arr;

  isa_ok( $arr = OP::Array->new(qw| foo bar baz wang chung |), "OP::Array",
    "Instanted array"
  );

  my $new;

  isa_ok(
    $new = $arr->collect(sub {
      my $item = shift;

      OP::Array::break() if $item eq 'wang';
      OP::Array::emit($item);
      return if $item eq 'baz';
      OP::Array::yield($item);
    }),
    "OP::Array",
    "collect() returns"
  );

  is($new->size, 5, "Compare element count");

  my $count;

  ok(
    $arr->each(sub {
      my $item = shift;
      $count++;

      OP::Array::break() if $count == 3;
    } ),
    "each() returns"
  );

  is($count, 3, "Compare element count");
}

#####
#####
#####

sub kickClassTires {
  my $class = shift;

  return if $nofs;

  return if !UNIVERSAL::isa($class, "OP::Object");

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
    ok( $obj->exists, "Exists in backing store" );

    kickObjectTires($obj);
  };

  my $ids = $class->allIds;

  $ids->each( sub {
    my $id = shift;

    my $obj;
    isa_ok(
      $obj = $class->load($id),
      $class,
      "Object retrieved from backing store"
    );

    kickObjectTires($obj);

    ok( $obj->remove, "Remove from backing store" );

    ok( !$obj->exists, "Object was removed" );

    undef $obj;

    if ( $class->__useRcs ) {
      isa_ok(
        $obj = $class->restore($id, '1.1'),
        $class,
        "Object restored from RCS archive"
      );

      kickObjectTires($obj);
    }
  } );

  if ( $class->__useDbi ) {
    ok( $class->__dropTable, "Drop table");
  } 
}

sub kickObjectTires {
  my $obj = shift;

  my $class = $obj->class;
  my $asserts = $class->asserts;

  $asserts->each( sub {
    my $key = shift;
    my $type = $asserts->{$key};

    isa_ok(
      $obj->{$key}, $type->objectClass, 
      sprintf('%s "%s"', $class->pretty($key), $obj->{$key})
    );
  } );
}


#
#
#
sub testCreate {
  my $class = shift;
  my $classPrototype = shift;

  eval {
    OP::create($class, $classPrototype);
  };

  return $class->isa($class);
}
