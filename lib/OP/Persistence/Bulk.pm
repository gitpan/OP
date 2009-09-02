package OP::Persistence::Bulk;

use strict;
use warnings;

use Error qw| :try |;
use File::Path;

use OP::Array qw| yield emit |;
use OP::Bool;
use OP::Constants qw| scratchRoot |;
use OP::Enum::Bool;
use OP::Hash;
use OP::Persistence;

use OP::Redefines;

use constant DeferredSaveDir => "Defer";

#
#
#
# method flushStash(OP::Class $class: Str ?$path) {
sub flushStash {
  my $class = shift;
  my $path = shift;

  $path ||= $class->__bulkPath;

  return if !-e $path;

  $class->write('SET FOREIGN_KEY_CHECKS = 0');

  my $rows = $class->write( sprintf q|
      LOAD DATA INFILE %s
        REPLACE INTO TABLE %s.%s ( %s )
    |,
    $class->quote($path),
    $class->databaseName,
    $class->tableName,
    $class->__bulkColumns->join(",")
  );

  $class->write('SET FOREIGN_KEY_CHECKS = 1');

  unlink $path;

  #
  # Flush for linked tables
  #
  my $asserts = $class->asserts;

  my $stashedIds = $class->get("__stashedIds");

  $asserts->each( sub {
    my $key = shift;

    my $type = $asserts->{$key};

    my $oClass = $type->objectClass;

    if (
      $oClass->isa('OP::Array') || $oClass->isa('OP::Hash')
    ) {
      my $elementClass = $class->elementClass($key);

      if ( $stashedIds ) {
        $stashedIds->each( sub {
          my $key = shift;

          $elementClass->write( sprintf q|
              delete from %s where parentId = %s
            |,
            $elementClass->tableName,
            $elementClass->quote( $key )
          );
        } );

        $stashedIds->clear;
      }
      
      $elementClass->flushStash;
    }
  } );

  return $rows;
};

#
#
#
# method stash() {
sub stash {
  my $self = shift;

  $self->_prestash;

  my $class = $self->class;

  my $stashedIds = $class->get("__stashedIds");

  if ( !$stashedIds ) {
    $stashedIds = OP::Hash->new;

    $class->set("__stashedIds", $stashedIds);
  }

  my $now = time;

  $self->{$class->__primaryKey} ||= $self->_newId;
  $self->{ctime} ||= $now;
  $self->{mtime} = $now;

  $stashedIds->{ $self->key }++;

  #
  # Stash for linked tables
  #
  my $asserts = $class->asserts;

  $asserts->each( sub {
    my $key = shift;

    my $type = $asserts->{$key};

    my $oClass = $type->objectClass;

    if ( $oClass->isa('OP::Array') ) {
      my $elementClass = $class->elementClass($key);

      my $i = 0;

      for my $value ( @{ $self->{$key} } ) {
        my $element = $elementClass->new(
          parentId => $self->key(),
          elementIndex => $i,
          elementValue => $value,
        );

        $element->stash;

        $i++;
      }
    } elsif ( $oClass->isa('OP::Hash') ) {
      my $elementClass = $class->elementClass($key);

      for my $elementKey ( keys %{ $self->{$key} } ) {
        my $value = $self->{$key}->{$elementKey};

        my $element = $elementClass->new(
          parentId => $self->key(),
          elementKey => $elementKey,
          elementValue => $value,
        );

        $element->stash;
      }
    }
  } );

  my $path = $class->__bulkPath;

  open(LOG, ">>", $path) || die $@;
  print LOG $self->_toBulk;
  close(LOG);
};

#
#
#
# method _prestash() {
sub _prestash {
  my $self = shift;

  #
  # Abstract method, override if needed
  #
};

#
# Returns the name of the scratch directory where deferred saves are stashed
#
# method __bulkRoot(OP::Class $class:) {
sub __bulkRoot {
  my $class = shift;

  return join("/", scratchRoot, DeferredSaveDir);
};

#
# Returns the full path to this process's deferred save stash
#
# method __bulkPath(OP::Class $class:) {
sub __bulkPath {
  my $class = shift;

  my $filename = join(".", $class, $$, "log");

  my $root = $class->__bulkRoot;

  mkpath $root if !-d $root;

  return join("/", $root, $filename);
};

#
# http://dev.mysql.com/doc/refman/5.1/en/load-data.html
#
# Use "\" to escape instances of tab, newline, or "\"
#
# method __escapeBulkValue(OP::Class $class: $value) {
sub __escapeBulkValue {
  my $class = shift;
  my $value = shift;

  return '\N' if !defined $value;

  $value =~ s/\t/\\\t/gs;
  $value =~ s/\n/\\\n/gs;
  $value =~ s/\\/\\\\/gs;

  return $value;
};

#
# Return the names of the columns used for bulk insert
#
# method __bulkColumns(OP::Class $class:) {
sub __bulkColumns {
  my $class = shift;

  my $asserts = $class->asserts;

  return $asserts->collect( sub {
    my $key = shift;

    my $type = $asserts->{$key};
    my $oClass = $type->objectClass;

    #
    #
    #
    return if $oClass->isa("OP::Hash") || $oClass->isa("OP::Array");

    yield $key;
  } );
};

#
# Return a tab-delimited row which will be written into the defer stash
#
# method _toBulk() {
sub _toBulk {
  my $self = shift;

  my $class = $self->class;
  my $asserts = $class->asserts;

  my $row = $asserts->collect( sub {
    my $key = shift;

    my $type = $asserts->{$key};
    my $oClass = $type->objectClass;

    #
    #
    #
    return if $oClass->isa("OP::Hash") || $oClass->isa("OP::Array");

    my $value = $self->{$key};

    yield $class->__escapeBulkValue($value);

  } )->join("\t");

  return "$row\n";
};

package OP::Persistence;

use strict;
use warnings;

do {
  no warnings "once";

  *flushStash = \&OP::Persistence::Bulk::flushStash;
  *stash      = \&OP::Persistence::Bulk::stash;

  *__bulkRoot        = \&OP::Persistence::Bulk::__bulkRoot;
  *__bulkPath        = \&OP::Persistence::Bulk::__bulkPath;
  *__bulkColumns     = \&OP::Persistence::Bulk::__bulkColumns;
  *__escapeBulkValue = \&OP::Persistence::Bulk::__escapeBulkValue;

  *_prestash         = \&OP::Persistence::Bulk::_prestash;
  *_toBulk           = \&OP::Persistence::Bulk::_toBulk;
};

true;
__END__
=pod

=head1 NAME

OP::Persistence::Bulk - Deferred fast bulk table writes

=head1 SYNOPSIS

  use OP qw| :all |;
  use OP::Persistence::Bulk;

  use YourApp::Example;

  #
  # Queue up a bunch of objects for save:
  #
  for ( ... ) {
    my $exa = YourApp::Example->new(...);

    #
    # Queue object in the currently active scratch file:
    #
    $exa->stash;
  }

  #
  # Write any deferred saves to the database with blazing speed:
  #
  YourApp::Example->flushStash;

=head1 DESCRIPTION

Experimental mix-in module to enable the saving of many objects to the
database at once, using MySQL's LOAD FILE syntax, which is extremely fast.

Saving objects in this manner will bypass many application and db-level
constraints, which can result in disasterous consequences if the objects
contain garbage data. This is a very sharp knife.

=head1 BUGS

Using this mix-in with classes that have attributes possessing
C<sqlValue> insert/update overrides, such as those descended from
L<OP::RRNode>, will probably not work as-is. Any necessary logic for
handling insert/update value overrides may be defined in a class's
C<_prestash> method, which is called prior to stashing.

=head1 SEE ALSO

This file is part of L<OP>.

=cut
