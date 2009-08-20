package OP::Runtime;

our $Backends;

package main;

use strict;
use diagnostics;

use Test::More qw| no_plan |;

use File::Tempdir;

use constant false => 0;
use constant true  => 1;

use vars qw| $tempdir $path $nofs |;

BEGIN: {
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

SKIP: {
  skip($nofs, 2) if $nofs;

  my $class = "OP_YAMLTest::YAMLTest01";
  ok(
    testCreate($class => {
      __useDbi  => false,
      __useYaml => true,
      __useMemcached => 5,
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
      id => OP::Serial->assert,
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
    my $reason = "DBD::mysql is not installed";

    skip($reason, 2);
  }

  my $class = "OP::MySQLTest01";
  ok(
    testCreate($class => {
      __dbiType => 0,
      __useMemcached => 5,
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
}

SKIP: {
  if ( $nofs ) {
    skip($nofs, 2);
  } elsif ( !$OP::Runtime::Backends->{"MySQL"} ) {
    my $reason = "DBD::mysql is not installed";

    skip($reason, 2);
  }

  my $class = "OP::MySQLTest02";
  ok(
    testCreate($class => {
      __dbiType => 0,
      __useMemcached => 5,
      id => OP::Serial->assert,
    }),
    "Class allocate, table create"
  );

  kickClassTires($class);
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
        name => OP::Utility::randstr()
      ),
      $class
    );
    ok( $obj->save, "Save to backing store" );
    ok( $obj->exists, "Exists in backing store" );

    $asserts->each( sub {
      my $key = shift;
      my $type = $asserts->{$key};

      isa_ok(
        $obj->{$key}, $type->objectClass, 
        sprintf('%s "%s"', $class->pretty($key), $obj->{$key})
      );
    } );
  };

  $class->allIds->each( sub {
    my $id = shift;

    my $obj;
    isa_ok(
      $obj = $class->load($id),
      $class,
      "Object retrieved from backing store"
    );

    $asserts->each( sub {
      my $key = shift;
      my $type = $asserts->{$key};

      isa_ok(
        $obj->{$key}, $type->objectClass, 
        sprintf('%s "%s"', $class->pretty($key), $obj->{$key})
      );
    } );

    ok( $obj->remove, "Remove from backing store" );

    ok( !$obj->exists, "Object was removed" );
  } );

  if ( $class->__useDbi ) {
    ok( $class->__dropTable, "Drop table");
  }
}

#
#
#
sub testCreate {
  my $class = shift;
  my $prototype = shift;

  eval {
    OP::create($class, $prototype);
  };

  return $class->isa($class);
}
