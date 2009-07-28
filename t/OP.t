use strict;
use diagnostics;

my $basetests;
my $dbitests;
my $total;

BEGIN {
  $basetests = 26;
  $dbitests  = 2;

  $total = ( $basetests + $dbitests );
}

use Test::More tests => $total;

my $reason;
my $tempdir;
my $dirname;
my $temprc;

SKIP: {
  my $hasFileTempdir;

  eval {
    require File::Tempdir;

    $hasFileTempdir++;
  };

  if ( $hasFileTempdir ) {
    eval qq{
      use File::Tempdir;
    };
  } else {
    $reason = "File::Tempdir not installed";

    skip($reason, $basetests) if $reason;
  }

  if ( !$reason ) {
    eval {
      $tempdir = File::Tempdir->new;

      $dirname = $tempdir->name;
    };
  } else {
    $reason  = "Unusable filesystem (can't make tempdir)";
  }

  if ( !$reason && !$dirname ) {
    $reason = "Unable to get name for temp directory";
  }

  if ( !$reason ) {
    $temprc = join("/", $dirname, ".oprc");

    if ( !-d $dirname ) {
      $reason = "$dirname is not a directory (weird)";
    } elsif ( !-w $dirname ) {
      $reason = "$dirname is not writable (can't make a temp .oprc)";
    }

    skip($reason, $basetests) if $reason;
  }

  if ( !$reason ) {
    #
    # OP will not compile without a valid .oprc.
    #
    # Set up a fake .oprc so testing may proceed.
    #
    # The fake .oprc gets removed when testing is complete.
    #
    # Tests will fail if $dirname is not writable :-/
    #
    if ( !open(OPRC, ">", $temprc) ) {
      $reason = $! || "Unusable filesystem ($temprc unwritable)";

      skip($reason, $basetests);
    }

    print OPRC q|
---
yamlRoot: $dirname/yaml
sqliteRoot: $dirname/sqlite
scratchRoot: $dirname/scratch
dbHost: localhost
dbPass: ~
dbPort: 3306
dbUser: op
rcsBindir: /usr/bin
rcsDir: RCS
memcachedHosts: ~
syslogHost: ~
|;
    close(OPRC);

    $ENV{OP_HOME} = $dirname;
  }

  ###
  ### Class prototyping tests
  ###
  use_ok("OP");

  my $testClass = "OP::TestHash";

  is( createTestHashClass($testClass), $testClass );

  isa_ok( createTestHash($testClass), $testClass );

  is( testSetter($testClass), 1 );

  is( testGetter($testClass), "Bar" );

  is( testDeleter($testClass), undef );

  ###
  ### Object Constructor tests
  ###

  #
  # SCALARS
  #
  isa_ok( OP::Bool->new(1), "OP::Bool" );
  isa_ok( OP::Bool->new(0), "OP::Bool" );

  isa_ok( OP::Domain->new( "example.com" ), "OP::Domain" );

  isa_ok( OP::Double->new( 22/7 ), "OP::Double" );

  my $id = OP::ID->new;
  isa_ok( $id, "OP::ID");
  isa_ok( OP::ExtID->new($id), "OP::ExtID");

  isa_ok( OP::Float->new( 22/7 ), "OP::Float" );

  isa_ok( OP::Int->new(10), "OP::Int");

  isa_ok( OP::IPv4Addr->new("127.0.0.1"), "OP::IPv4Addr" );

  isa_ok( OP::Name->new("Nom"), "OP::Name" );

  isa_ok( OP::Num->new(42), "OP::Num");

  isa_ok( OP::Rule->new(qr/example/), "OP::Rule");

  isa_ok( OP::Scalar->new(42), "OP::Scalar");

  isa_ok( OP::Str->new("String Theory"), "OP::Str");

  isa_ok( OP::TimeSpan->new(42), "OP::TimeSpan");

  isa_ok( OP::URI->new("http://www.example.com/"), "OP::URI");

  #
  # ARRAYS
  #
  isa_ok( OP::Array->new("123", "456", "abc", "def"), "OP::Array");

  isa_ok( OP::DateTime->new(time), "OP::DateTime" );

  isa_ok( OP::EmailAddr->new('root@example.com'), "OP::EmailAddr");

  #
  # HASHES
  #
  isa_ok( OP::Hash->new, "OP::Hash");
}

my $hasDBDMysql;
my $hasOPDB;

if ( !$reason ) {
  eval {
    require DBD::mysql;

    $hasDBDMysql++;

    my $dbname = 'op';

    my $dsn = sprintf('DBI:mysql:database=%s;host=%s;port=%s',
      $dbname, 'localhost', 3306
    );

    my $dbh = DBI->connect( $dsn, $dbname, '', { RaiseError => 1 } )
      || die DBI->errstr;

    my $sth = $dbh->prepare("show tables") || die $dbh->errstr;

    $sth->execute || die $sth->errstr;

    my $worked = $sth->fetchall_arrayref() || die $sth->errstr;

    $hasOPDB++;
  };
}

if ( !$reason && !$hasDBDMysql ) {
  $reason = "DBD::mysql is not installed";
} elsif ( !$reason && !$hasOPDB ) {
  $reason = "MySQL DB 'op' is not accessible";
}

SKIP: {
  if ( $reason ) {
    print "----------------------------------------------------------\n";
    print "Skipping DB tests because $reason\n";
    print "\n";
    print "If you would like to enable DB tests for OP, please remedy\n";
    print "the environmental issue shown in the diagnostic output below,\n";
    print "create a local MySQL DB named 'op', and grant access to\n";
    print "op\@localhost, ie:\n";
    print "\n";
    print "> mysql -u root -p\n";
    print "> create database op;\n";
    print "> grant all on op.* to op\@localhost;\n";

    if ( $@ ) {
      my $error = $@;
      chomp $error;

      print "\n";
      print "Diagnostic message:\n";
      print $error;
      print "\n";
    }

    print "----------------------------------------------------------\n";

    skip($reason, $dbitests);
  } else {
    print "Testing creation and destruction of DB schema and objects...\n";
  }

  my $testClass = "OP::TestNode";

  is( createTestNodeClass($testClass), $testClass );

  isa_ok( createAndDestroyTestNode($testClass), $testClass );
}


#
# Remove the tempfile
#
if ( $temprc ) {
  unlink $temprc;
}

sub createTestHashClass {
  my $class = shift;

  return create( $class => {
    __BASE__ => "OP::Hash"
  } );
}

sub createTestNodeClass {
  my $class = shift;

  return create( $class => { } );
}

sub createTestHash {
  my $class = shift;

  return $class->new;
}

sub createAndDestroyTestNode {
  my $class = shift;

  my $name = "Testing123";

  do {
    my $object = $class->new(
      name => $name
    );

    $object->save;

    return if !$object->exists;
  };

  my $object;

  do {
    $object = $class->loadByName($name);

    return if !$object->exists;

    $object->remove;

    return if $object->exists;
  };

  $class->__dropTable;

  return $object;
}

sub testSetter {
  my $class = shift;

  my $self = $class->new;

  return $self->setFoo("Bar");
}

sub testGetter {
  my $class = shift;

  my $self = $class->new;

  $self->setFoo("Bar");

  return $self->foo;
}

sub testDeleter {
  my $class = shift;

  my $self = $class->new;

  $self->setFoo("Bar");

  $self->deleteFoo("Bar");

  return $self->foo;
}
