package OP::Runtime;

use strict;
use warnings;

our $Backends;

sub import {
  my $class = shift;
  my $path  = shift;

  my $caller = caller;

  my $temprc = join("/", $path, ".oprc");

  return __setenv($caller, $path) if -e $temprc;

  if ( !-d $path ) {
    die "$path is not a directory (weird)";
  } elsif ( !-w $path ) {
    die "$path is not writable (can't make a temp .oprc)";
  }

  if ( !open(OPRC, ">", $temprc) ) {
    my $reason = $! || "Unusable filesystem ($temprc unwritable)";

    die($reason);
  }

  print OPRC qq|
--- 
dbPass: ~
dbHost: localhost
dbPort: 3306
dbUser: op
memcachedHosts: 
  - 127.0.0.1:31337
rcsBindir: /usr/bin
rcsDir: RCS
scratchRoot: $path/scratch
sqliteRoot: $path/sqlite
syslogHost: ~
yamlRoot: $path/yaml
|;
  close(OPRC);

  __setenv($caller, $path);

  $Backends = OP::Hash->new;

  eval {
    require DBD::SQLite;

    $Backends->{"SQLite"}++;
  };

  my $dbdMysqlIsInstalled;

  eval {
    require DBD::mysql;

    $dbdMysqlIsInstalled++;
  };

  if ( $dbdMysqlIsInstalled ) {
    eval {
      my $dbname = 'op';

      my $dsn = sprintf('DBI:mysql:database=%s;host=%s;port=%s',
        $dbname, 'localhost', 3306
      );

      my $dbh = DBI->connect( $dsn, $dbname, '', { RaiseError => 1 } )
        || die DBI->errstr;

      my $sth = $dbh->prepare("show tables") || die $dbh->errstr;

      $sth->execute || die $sth->errstr;

      my $worked = $sth->fetchall_arrayref() || die $sth->errstr;

      $Backends->{"MySQL"}++;
    };
  }

  if (
    $dbdMysqlIsInstalled && !$Backends->{"MySQL"}
  ) {
    print "----------------------------------------------------------\n";
    print "If you would like to enable DB tests for OP, please remedy the\n";
    print "issue shown in the diagnostic message below. You will need to\n";
    print "create a local MySQL DB named 'op', and grant access, ie:\n";
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
  }

  $Backends->{"Memcached"} = scalar(
    keys %{ $OP::Persistence::memd->server_versions }
  );

  return 1;
}

sub __setenv {
  my $caller = shift;
  my $path = shift;

  $ENV{OP_HOME} = $path;

  eval q| use OP qw(:all) |;

  for ( @OP::EXPORT ) {
    do {
      no warnings "once";
      no strict "refs";

      *{"$caller\::$_"} = *{"OP::$_"};
    };
  }

  return 1;
}

1;
__END__
=pod

=head1 NAME

OP::Runtime - Initialize OP at runtime instead of compile time

=head1 SYNOPSIS

  #
  # Set up a self-destructing OP environment which evaporates
  # when the process exits:
  #
  use strict;
  use warnings;

  use vars qw| $tempdir $path |;

  BEGIN: {
    $tempdir = File::Tempdir->new;

    $path = $tempdir->name;
  };

  require OP::Runtime;

  OP::Runtime->import($path);

=head1 DESCRIPTION

Enables the creation of temporary or sandboxed OP environments.
Allows loading of the OP framework at runtime.

Good for testing, and not much else.

=head1 SEE ALSO

This file is part of L<OP>.

=cut
