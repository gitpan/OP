#
# File: OP/Persistence.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
package OP::Persistence;

=pod

=head1 NAME

OP::Persistence - Serialization mix-in

=head1 DESCRIPTION

Configurable class mix-in for storable OP objects.

Provides transparent support for various serialization methods.

=head1 SYNOPSIS

This package should not typically be used directly. Subclasses created
with OP's C<create> function will respond to these methods by default.

See __use<Feature>() and C<__dbiType()>, under the Class Callback Methods
section, for directions on how to disable or augment backing store options
when subclassing.

=cut

use strict;
use warnings;

#
# Third-party packages
#
use Cache::Memcached::Fast;
use Clone qw| clone |;
use Digest::SHA1 qw| sha1_hex |;
use Error qw| :try |;
use File::Copy;
use File::Path;
use File::Find;
use IO::File;
use JSON::Syck;
use Rcs;
use Time::HiRes qw| time |;
use URI::Escape;
use YAML::Syck;

#
# OP
#
use OP::Class qw| create true false |;
use OP::Constants qw|
  yamlRoot scratchRoot sqliteRoot
  dbHost dbPass dbPort dbUser
  memcachedHosts
  rcsBindir rcsDir
|;
use OP::Enum::DBIType;
use OP::Exceptions;
use OP::Utility;
use OP::Persistence::MySQL;
use OP::Persistence::SQLite;

#
# OP Object Classes
#
use OP::Array;
use OP::ID;
use OP::Str;
use OP::Int;
use OP::DateTime;
use OP::Name;

use OP::Type;

#
# RCS setup
#
Rcs->bindir(rcsBindir);
Rcs->quiet(true);

#
# Class variable and memcached setup
#
our ( $dbi, $memd, $transactionLevel, $errstr );

if (
  memcachedHosts && ref(memcachedHosts)
  && ref(memcachedHosts) eq 'ARRAY'
) {
  $memd = Cache::Memcached::Fast->new( {
    servers => memcachedHosts
  } );

  # $Storable::Deparse = true;
}

#
# Package constants
#
use constant DefaultPrimaryKey => "id";

=pod

=head1 PUBLIC CLASS METHODS

=head2 General

=over 4

=item * $class->load($id)

Retrieve an object by ID from the backing store.

This method will delegate to the appropriate private backend method. It
returns the requested object, or throws an exception if the object was
not found.

  my $object;

  try {
    $object = $class->load($id);
  } catch Error with {
    # ...

  };

=cut

# method load(OP::Class $class: Str $id) {
sub load {
  my $class = shift;
  my $id = shift;

  return $class->__localLoad($id);
}


=pod

=back

=head2 Database I/O

=over 4

=item * $class->query($query)

Runs the received query, and returns a statement handle which may be
used to iterate through the query's result set.

Reconnects to database, if necessary.

  sub($) {
    my $class = shift;

    my $query = sprintf(
      q| SELECT * FROM %s |,
      $class->tableName()
    );

    my $sth = $class->query($query);

    while ( my $object = $sth->fetchrow_hashref() ) {
      $class->__marshal($object);

      # Stuff ...
    }

    $sth->finish();
  }

=cut

# method query(OP::Class $class: Str $query) {
sub query {
  my $class = shift;
  my $query = shift;

  return $class->__wrapWithReconnect(
    sub { return $class->__query($query) }
  );
}


=pod

=item * $class->write()

Runs the received query against the reporting database, using the
DBI do() method. Returns number of rows updated.

Reconnects to database, if necessary.

  sub($$) {
    my $class = shift;
    my $value = shift;

    my $query = sprintf('update %s set foo = %s',
      $class->tableName(), $class->quote($value)
    )

    return $class->write($query);
  }

=cut

# method write(OP::Class $class: Str $query) {
sub write {
  my $class = shift;
  my $query = shift;

  return $class->__wrapWithReconnect(
    sub { return $class->__write($query) }
  );
}


=pod

=item * $class->allIds()

Returns an OP::Array of all object ids in the receiving class.

  my $ids = $class->allIds();

  #
  # for loop way
  #
  for my $id ( @{ $ids } ) {
    my $object = $class->load($id);

    # Stuff ...
  }

  #
  # collector way
  #
  $ids->each( sub {
    my $object = $class->load($_);

    # Stuff ...
  } );

=cut

# method allIds(OP::Class $class:) {
sub allIds {
  my $class = shift;

  if ( $class->__useYaml() && !$class->__useDbi() ) {
    return $class->__fsIds();
  }

  my $sth = $class->__allIdsSth();

  my $ids = OP::Array->new();

  while ( my ( $id ) = $sth->fetchrow_array() ) {
    $ids->push( $id );
  }

  $sth->finish();

  return $ids;
}


=pod

=item * $class->memberClass($attribute)

Only applicable for attributes which were asserted as L<OP::ExtID()>.

Returns the class of object referenced by the named attribute.

Example A:

  #
  # In a class prototype, there was an ExtID assertion:
  #
  create "OP::Example" => {
    userId => OP::ExtID->assert( "OP::Example::User" ),

    # Stuff ...
  };

  #
  # Hypothetical object "Foo" has a "userId" attribute,
  # which specifies an ID in a user table:
  #
  my $exa = OP::Example->spawn("Foo");

  #
  # Retrieve the external object by ID:
  #
  my $userClass = OP::Example->memberClass("userId");

  my $user = $userClass->load($exa->userId());

=cut

# method memberClass(OP::Class $class: Str $key) {
sub memberClass {
  my $class = shift;
  my $key = shift;

  throw OP::AssertFailed("$key is not a member of $class")
    if !$class->isAttributeAllowed($key);

  my $asserts = $class->asserts();

  my $type = $asserts->{$key};

  # if ( $type->objectClass()->isa('OP::Array') ) {
    # $type = $type->memberType();
  # }

  return $type->memberClass();
}


=pod

=item * $class->doesIdExist($id)

Returns true if the received ID exists in the receiving class's table.

=cut

sub doesIdExist {
  my $class = shift;
  my $id = shift;

  return $class->__selectBool(
    $class->__doesIdExistStatement($id)
  );
}


=pod

=item * $class->doesNameExist($name)

Returns true if the received ID exists in the receiving class's table.

  my $name = "Bob";

  my $object = $class->doesNameExist($name)
    ? $class->loadByName($name)
    : $class->new( name => $name, ... );

=cut

sub doesNameExist {
  my $class = shift;
  my $name = shift;

  return $class->__selectBool(
    $class->__doesNameExistStatement($name)
  );
}


#
# Overrides
#
# method pretty (OP::Class $class: Str $key) {
sub pretty {
  my $class = shift;
  my $key = shift;

  my $pretty = $key;

  $pretty =~ s/(.)([A-Z])/$1 $2/gxsm;

  $pretty =~ s/(\s|^)Id(\s|$)/${1}ID${2}/gxsmi;
  $pretty =~ s/(\s|^)Ids(\s|$)/${1}IDs${2}/gxsmi;
  $pretty =~ s/^Ctime$/Creation Time/gxsmi;
  $pretty =~ s/^Mtime$/Modified Time/gxsmi;

  return ucfirst $pretty;
}

=pod

=item * $class->loadByName($name)

Loader for named objects. Works just as load().

  my $object = $class->loadByName($name);

=cut

# method loadByName(OP::Class $class: Str $name) {
sub loadByName {
  my $class = shift;
  my $name = shift;

  if ( !$name ) {
    my $caller = caller();

    throw OP::InvalidArgument(
      "BUG (Check $caller): empty name sent to loadByName(\$name)"
    );
  }

  my $id = $class->idForName($name);

  if ( defined $id ) {
    return $class->load($id);
  } else {
    my $table = $class->tableName();
    my $db = $class->databaseName();

    ### old way
    # warn "Object name \"$name\" does not exist in table $db.$table";
    # return undef;

    throw OP::ObjectNotFound(
      "Object name \"$name\" does not exist in table $db.$table"
    );
  }
}


=pod

=item * $class->spawn($name)

Loader for named objects. Works just as load(). If the object does not
exist on backing store, a new object with the received name is returned.

  my $object = $class->spawn($name);

=cut

# method spawn(OP::Class $class: Str $name) {
sub spawn {
  my $class = shift;
  my $name = shift;

  my $id = $class->idForName($name);

  if ( defined $id ) {
    return $class->load($id);
  } else {
    my $self = $class->proto;

    $self->setName($name);

    # $self->save(); # Let caller do this

    my $key = $class->__primaryKey();

    return $self;
  }
}


=pod

=item * $class->idForName($name)

Return the corresponding row id for the received object name.

  my $id = $class->idForName($name);

=cut

sub idForName {
  my $class = shift;
  my $name = shift;

  return $class->__selectSingle(
    $class->__idForNameStatement($name)
  )->shift;
}


=pod

=item * $class->nameForId($id)

Return the corresponding name for the received object id.

  my $name = $class->nameForId($id);

=cut

sub nameForId {
  my $class = shift;
  my $id = shift;

  return $class->__selectSingle(
    $class->__nameForIdStatement($id)
  )->shift;
}

=pod

=item * $class->allNames()

Returns a list of all object ids in the receiving class. Requires DBI.

  my $names = $class->allNames();

  $names->each( sub {
    my $object = $class->loadByName($_);

    # Stuff ...
  } );

=cut

# method allNames(OP::Class $class:) {
sub allNames {
  my $class = shift;

  if ( !$class->__useDbi() ) {
    throw OP::MethodIsAbstract(
      "Sorry, allNames() requires a DBI backing store"
    );
  }

  my $sth = $class->__allNamesSth();

  my $names = OP::Array->new();

  while ( my ( $name ) = $sth->fetchrow_array() ) {
    $names->push($name);
  }

  $sth->finish();

  return $names;
}


=pod

=item * $class->quote($value)

Returns a DBI-quoted (escaped) version of the received value. Requires DBI.

  my $quoted = $class->quote($hairy);

=cut

# method quote(OP::Class $class: Str $value) {
sub quote {
  my $class = shift;
  my $value = shift;

  return $class->__dbh()->quote($value);
}


=pod

=item * $class->databaseName()

Returns the name of the receiving class's database. Corresponds to 
the lower-cased first-level Perl namespace, unless overridden in subclass.

  my $dbname = OP::Example->databaseName(); # returns "op"

  $dbname = Foo::Bar->databaseName(); # returns "foo"

=cut

# method databaseName(OP::Class $class:) {
sub databaseName {
  my $class = shift;

  my $dbName = lc($class);
  $dbName =~ s/:.*//;

  return $dbName;
}


=pod

=item * $class->tableName()

Returns the name of the receiving class's database table. Corresponds to
the second-and-higher level Perl namespaces, using an underscore delimiter.

Will probably want to override this, if subclass lives in a deeply nested
namespace.

  my $table = OP::Example->tableName(); # returns "example"

  $table = Foo::Bar->tableName(); # returns "bar"

  $table = OP::Job::Example->tableName(); # returns "job_example"

=cut

# method tableName(OP::Class $class:) {
sub tableName {
  my $class = shift;

  my $tableName = $class->get("__tableName");

  if ( !$tableName ) {
    $tableName = lc($class);
    $tableName =~ s/.*?:://;
    $tableName =~ s/::/_/g;

    $class->set("__tableName", $tableName);
  }

  return $tableName;
}


=pod

=item * $class->columnNames()

Returns an OP::Array of all column names in the receiving class's table.

This will be the same as the list returned by attributes(), minus any
attributes which were asserted as Array or Hash and therefore live in
a seperate linked table.

=cut

# method columnNames(OP::Class $class:) {
sub columnNames {
  my $class = shift;

  return $class->__dispatch('columnNames');
}


=pod

=back

=head2 YAML Input

=over 4

=item * $class->loadYaml($string)

Load the received string containing YAML into an instance of the
receiving class.

Warns and returns undef if the load fails.

  my $string = q|---
  foo: alpha
  bar: bravo
  |;

  my $object = $class->loadYaml($string);

=cut

# method loadYaml(OP::Class $class: Str $yaml) {
sub loadYaml {
  my $class = shift;
  my $yaml = shift;

  throw OP::InvalidArgument( "Empty YAML stream received" )
    if !$yaml;

  my $hash = YAML::Syck::Load($yaml);

  throw OP::DataConversionFailed($@) if $@;

  return $class->new($hash);
}


=pod

=item * $class->loadJson($string)

Load the received string containing JSON into an instance of the
receiving class.

Warns and returns undef if the load fails.

=cut

# method loadJson(OP::Class $class: Str $json) {
sub loadJson {
  my $class = shift;
  my $json = shift;

  throw OP::InvalidArgument( "Empty YAML stream received" )
    if !$json;

  my $hash = JSON::Syck::Load($json);

  throw OP::DataConversionFailed($@) if $@;

  return $class->new($hash);
}


=pod

=back

=head1 PRIVATE CLASS METHODS

=head2 Class Callback Methods

Callback methods should be overridden when allocating a class with
C<create()> or C<package>, but only if the defaults are not what the
developer desires. Callback methods typically won't be used by external
callers. This section documents the default behavior of OP::Persistence
class callbacks, and provides override examples.

For ease of use, most of these methods can be overridden simply by
setting a class variable with the same name, as the examples illustrate.

=over 4

=item * $class->__useYaml()

Return a true value to maintain a YAML backend for all saved objects. If
you want to skip YAML and use a database exclusively, this method should
return a false value.

Default inherited value is false. Set class variable to override.

  create "OP::Example" => {
    __useYaml => false
  };

=cut

# method __useYaml(OP::Class $class:) {
sub __useYaml {
  my $class = shift;

  if ( !defined $class->get("__useYaml") ) {
    $class->set("__useYaml", false);
  }

  return $class->get("__useYaml");
}


=pod

=item * $class->__useRcs()

Returns a true value if the current class keeps revision history with
its YAML backend, otherwise false.

Default inherited value is false. Set class variable to override.

  create "OP::Example" => {
    __useRcs => false
  };

=cut

# method __useRcs(OP::Class $class:) {
sub __useRcs {
  my $class = shift;

  if ( !defined $class->get("__useRcs") ) {
    $class->set("__useRcs", false);
  }

  return $class->get("__useRcs");
}


=pod

=item * $class->__useDbi()

Returns a true value if the current class uses a SQL backing store,
otherwise false.

If __useDbi() returns true, the database type specified by
__dbiType() (MySQL, SQLite) will be used.  See __dbiType() for how to
override the class's database type.

Default inherited value is true. Set class variable to override.

  create "OP::Example" => {
    __useDbi => false
  };

=cut

# method __useDbi(OP::Class $class:) {
sub __useDbi {
  my $class = shift;

  my $useDbi = $class->get("__useDbi");

  if ( !defined $useDbi ) {
    $useDbi = true;

    $class->set("__useDbi", $useDbi);
  }

  return $useDbi;
}


=pod

=item * $class->__useMemcached()

Returns a TTL in seconds, if the current class should attempt to use
memcached to minimize database load.

Returns a false value if this class should bypass memcached.

If the memcached server can't be reached at package load time, callers
will load from the physical backing store.

Default inherited value is 300 seconds (5 minutes). Set class variable
to override.

  create "OP::CachedExample" => {
    #
    # Ten minute TTL on cached objects:
    #
    __useMemcached => 600
  };

Set to C<false> or 0 to disable caching.

  create "OP::NeverCachedExample" => {
    #
    # No caching in play:
    #
    __useMemcached => false
  };

=cut

# method __useMemcached(OP::Class $class:) {
sub __useMemcached {
  my $class = shift;

  if ( !defined $class->get("__useMemcached") ) {
    $class->set("__useMemcached", 120);
  }

  return $class->get("__useMemcached");
}


=pod

=item * $class->__dbiType()

This method is unused if C<__useDbi> returns false.

Returns the constant of the DBI adapter to be used. Applies only if
$class->__useDbi() returns a true value. Override in subclass to
specify the desired backing store.

Returns a constant from the L<OP::Enum::DBIType> enumeration. Currently,
valid return values are OP::Enum::DBIType::MySQL and
OP::Enum::DBIType::SQLite.

Default inherited value is OP::Enum::DBIType::MySQL. Set class variable
to override.

  create "OP::Example" => {
    __dbiType => OP::Enum::DBIType::SQLite
  };

=cut

# method __dbiType(OP::Class $class:) {
sub __dbiType {
  my $class = shift;

  if ( !defined $class->get("__dbiType") ) {
    $class->set("__dbiType", OP::Enum::DBIType::MySQL);
  }

  return $class->get("__dbiType");
}


=pod

=item * $class->__baseAsserts()

Assert base-level inherited assertions for objects. These include: id,
name, mtime, ctime.

  __baseAsserts => sub($) {
    my $class = shift;

    my $base = $class->SUPER::__baseAsserts();

    $base->{parentId} ||= Str();

    return $base;
  }

=cut

# method __baseAsserts(OP::Class $class:) {
sub __baseAsserts {
  my $class = shift;

  my $asserts = $class->get("__baseAsserts");

  if ( !defined $asserts ) {
    $asserts = OP::Hash->new(
      id    => OP::ID->assert(
        OP::Type::subtype(
          descript => "The primary GUID key of this object"
        )
      ),
      name  => OP::Name->assert(
        OP::Type::subtype(
          descript => "A human-readable secondary key for this object",
        )
      ), 
      mtime => OP::DateTime->assert(
        OP::Type::subtype(
          descript   => "The last modified timestamp of this object",
          columnType => "DATETIME"
        )
      ),
      ctime => OP::DateTime->assert(
        OP::Type::subtype(
          descript   => "The creation timestamp of this object",
          columnType => "DATETIME"
        )
      ),
    );

    $class->set("__baseAsserts", $asserts);
  }

  return( clone $asserts );
}

=pod

=item * $class->__basePath()

Return the base filesystem path used to store objects of the current class.

By default, this method returns a directory named after the current class,
under the directory specified by C<yamlRoot> in the local .oprc file.

  my $base = $class->__basePath();

  for my $path ( <$base/*> ) {
    print $path;
    print "\n";
  }

To override the base path in subclass if needed:

  __basePath => sub($) {
    my $class = shift;

    return join( '/', customPath, $class );
  }

=cut

# method __basePath(OP::Class $class:) {
sub __basePath {
  my $class = shift;

  return join( '/', yamlRoot, $class );
}


=pod

=item * $class->__baseRcsPath()

Returns the base filesystem path used to store revision history files.

By default, this just tucks "RCS" onto the end of C<__basePath()>.

=cut

# method __baseRcsPath(OP::Class $class:) {
sub __baseRcsPath {
  my $class = shift;

  return join('/', $class->__basePath(), rcsDir);
}


=pod

=back

=head2 General

=over 4

=item * $class->__primaryKey()

Returns the name of the attribute representing this class's primary
ID. Unless overridden, this method returns the string "id".

=cut

# method __primaryKey(OP::Class $class:) {
sub __primaryKey {
  my $class = shift;

  my $key = $class->get("__primaryKey");

  if ( !defined $key ) {
    $key = DefaultPrimaryKey;

    $class->set("__primaryKey", $key);
  }

  return $key;
}


=pod

=item * $class->__localLoad($id)

Load the object with the received ID from the backing store.

  my $object = $class->__localLoad($id);

=cut

# method __localLoad(OP::Class $class: Str $id) {
sub __localLoad {
  my $class = shift;
  my $id = shift;

  if ( $class->__useDbi() ) {
    return $class->__loadFromDatabase($id);
  } elsif ( $class->__useYaml() ) {
    return $class->__loadYamlFromId($id);
  } else {
    throw OP::MethodIsAbstract(
      "Backing store not implemented for $class"
    );
  }
}

=pod

=item * $class->__loadFromMemcached($id)

Retrieves an object from memcached by ID. Returns nothing if the
object wasn't there.

=cut

sub __loadFromMemcached {
  my $class = shift;
  my $id = shift;

  my $cacheTTL = $class->__useMemcached();

  if ( $memd && $cacheTTL ) {
    my $cachedObj = $memd->get( $class->__cacheKey($id) );

    if ( $cachedObj ) {
      return $class->new($cachedObj);
    }
  }

  return;
}

=pod

=back

=head2 Database I/O

=over 4

=item * $class->__loadFromDatabase($id)

Instantiates an object by id, from the reporting database rather than
the YAML backing store.

  my $object = $class->__loadFromDatabase($id);

=cut

# method __loadFromDatabase(OP::Class $class: Str $id) {
sub __loadFromDatabase {
  my $class = shift;
  my $id = shift;

  my $cachedObj = $class->__loadFromMemcached($id);

  return $cachedObj if $cachedObj;

  my $query = $class->__selectRowStatement($id);

  my $self = $class->__loadFromQuery($query);

  if ( !$self || !$self->exists() ) {
    my $table = $class->tableName();
    my $db = $class->databaseName();

    throw OP::ObjectNotFound(
      "Object id \"$id\" does not exist in table $db.$table"
    );
  }

  return $self;
}


=pod

=item * $class->__marshal($hash)

Loads any complex datatypes which were dumped to the database when
saved, and blesses the received hash as an instance of the receiving
class.

Returns true on success, otherwise throws an exception.

  while ( my $object = $sth->fetchrow_hashref() ) {
    $class->__marshal($object);
  }

=cut

# method __marshal(OP::Class $class: Hash $self) {
sub __marshal {
  my $class = shift;
  my $self = shift;

  bless $self, $class;

  #
  # Catch fire and explode on unexpected input.
  #
  # None of these things should ever happen:
  #
  if ( !$self ) {
    my $caller = caller();

    throw OP::InvalidArgument(
      "BUG: (Check $caller): ".
      "$class->__marshal() received an undefined or false arg"
    );
  }

  my $refType = ref($self);

  if ( !$refType ) {
    my $caller = caller();

    throw OP::InvalidArgument(
      "BUG: (Check $caller): ".
      "$class->__marshal() received a non-reference arg ($self)"
    );
  }

  if ( !UNIVERSAL::isa($self,'HASH') ) {
    my $caller = caller();

    throw OP::InvalidArgument(
      "BUG: (Check $caller): ".
      "$class->__marshal() received a non-HASH arg ($refType)"
    );
  }

  my $asserts = $class->asserts();

  #
  # Re-assemble complex structures using data from linked tables.
  #
  # For arrays, "elementIndex" is the array index, and "elementValue"
  # is the actual element value. Each element is a row in the linked table.
  #
  # For hashes, "elementKey" is the key, and "elementValue" is the value.
  # Each key/value pair is a row in the linked table.
  #
  # The parent object is referenced by id in parentId.
  #
  $asserts->each( sub {
    my $key = $_;

    my $type = $asserts->{$key};

    if ( $type ) {
      if ( $type->objectClass()->isa('OP::Array') ) {
        my $elementClass = $class->elementClass($key);

        my $array = $type->objectClass()->new();

        $array->clear();

        my $sth = $elementClass->query( sprintf q|
            SELECT %s FROM %s
              WHERE parentId = %s
              ORDER BY elementIndex + 0
          |,
          $elementClass->columnNames()->join(", "),
          $elementClass->tableName(),
          $elementClass->quote($self->{ $class->__primaryKey() })
        );

        while ( my $element = $sth->fetchrow_hashref() ) {
          if ( $element->{elementValue}
            && $element->{elementValue} =~ /^---\s/
          ) {
            $element->{elementValue} = YAML::Syck::Load(
              $element->{elementValue}
            );
          }

          $element = $elementClass->__marshal($element);

          $array->push($element->elementValue());
        }
          
        $sth->finish();

        $self->{$key} = $array;

      } elsif ( $type->objectClass()->isa('OP::Hash') ) {
        my $elementClass = $class->elementClass($key);

        my $hash = $type->objectClass()->new();

        my $sth = $elementClass->query( sprintf q|
            SELECT %s FROM %s WHERE parentId = %s
          |,
          $elementClass->columnNames()->join(", "),
          $elementClass->tableName(),
          $elementClass->quote($self->{ $class->__primaryKey() })
        );

        while ( my $element = $sth->fetchrow_hashref() ) {
          if ( $element->{elementValue}
            && $element->{elementValue} =~ /^---\s/
          ) {
            $element->{elementValue} = YAML::Syck::Load(
              $element->{elementValue}
            );
          }

          $element = $elementClass->__marshal($element);

          $hash->{ $element->elementKey() } = $element->elementValue();
        }

        $sth->finish();

        $self->{$key} = $hash
      }
    }
  } );

  #
  # Piggyback on this class's new() method to sanity-check the
  # input which was received, and to load any default instance
  # variables.
  #
  $self = $class->new($self);

  my $newRefType = ref($self);

  #
  # If we got this far, we're probably good... but here are a couple
  # more checks as a developer's safety net.
  #
  throw OP::DataConversionFailed(
    "Couldn't bless $self into $class- did new() reject input?"
  ) if !$newRefType;

  throw OP::DataConversionFailed(
    "Couldn't bless $self into $class- got $newRefType instead (weird)"
  ) if $newRefType ne $class;

  return $self;
}

# method elementClass(OP::Class $class: Str $key) {
sub elementClass {
  my $class = shift;
  my $key = shift;

  my $elementClasses = $class->get("__elementClasses");

  if ( !$elementClasses ) {
    $elementClasses = OP::Hash->new();

    $class->set("__elementClasses", $elementClasses);
  }

  if ( $elementClasses->{$key} ) {
    return $elementClasses->{$key};
  }

  my $asserts = $class->asserts();

  my $type = $asserts->{$key};

  my $elementClass;

  if ( $type ) {
    my $base = $class->__baseAsserts();
    delete $base->{name};

    if ( $type->objectClass()->isa('OP::Array') ) {
      $elementClass = join("::", $class, $key);

      create $elementClass => {
        name          => OP::Name->assert(
          OP::Type::subtype(
            optional => true
          )
        ),
        parentId      => OP::ExtID->assert( $class ),
        elementIndex  => OP::Int->assert(),
        elementValue  => $type->memberType()
      };

    } elsif ( $type->objectClass()->isa('OP::Hash') ) {
      $elementClass = join("::", $class, $key);

      my $memberClass = $class->memberClass($key);

      create $elementClass => {
        name          => OP::Name->assert(
          OP::Type::subtype(
            optional => true
          )
        ),
        parentId      => OP::ExtID->assert( $class ),
        elementKey    => OP::Str->assert(),
        elementValue  => OP::Str->assert(),
      };
    }
  }

  $elementClasses->{$key} = $elementClass;

  return $elementClass;
}


=pod

=item * $class->__allIdsSth()

Returns a statement handle to iterate over all ids. Requires DBI.

  my $sth = $class->__allIdsSth();

  while ( my ( $id ) = $sth->fetchrow_array() ) {
    my $object = $class->load($id);

    # Stuff ...
  }

  $sth->finish();

=cut

# method __allIdsSth(OP::Class $class:) {
sub __allIdsSth {
  my $class = shift;

  throw OP::MethodIsAbstract(
    "$class->__allIdsSth() requires DBI in class"
  ) if !$class->__useDbi();

  return $class->query(
    $class->__allIdsStatement()
  );
}


=pod

=item * $class->__allNamesSth()

Returns a statement handle to iterate over all names in class. Requires DBI.

  my $sth = $class->__allNamesSth();

  while ( my ( $name ) = $sth->fetchrow_array() ) {
    my $object = $class->loadByName($name);

    # Stuff ...
  }

  $sth->finish();

=cut

# method __allNamesSth(OP::Class $class:) {
sub __allNamesSth {
  my $class = shift;

  throw OP::MethodIsAbstract(
    "$class->__allNamesSth() requires DBI in class"
  ) if !$class->__useDbi();

  return $class->query(
    $class->__allNamesStatement()
  );
}


=pod

=item * $class->__beginTransaction();

Begins a new SQL transation.

=cut

# method __beginTransaction(OP::Class $class:) {
sub __beginTransaction {
  my $class = shift;

  return $class->__dispatch('__beginTransaction');
}


=pod

=item * $class->__rollbackTransaction();

Rolls back the current SQL transaction.

=cut

# method __rollbackTransaction(OP::Class $class:) {
sub __rollbackTransaction {
  my $class = shift;

  return $class->__dispatch('__rollbackTransaction');
}


=pod

=item * $class->__commitTransaction();

Commits the current SQL transaction.

=cut

# method __commitTransaction(OP::Class $class:) {
sub __commitTransaction {
  my $class = shift;

  return $class->__dispatch('__commitTransaction');
}


=pod

=item * $class->__beginTransactionStatement();

Returns the SQL used to begin a SQL transaction

=cut

# method __beginTransactionStatement(OP::Class $class:) {
sub __beginTransactionStatement {
  my $class = shift;

  return $class->__dispatch('__beginTransactionStatement');
}


=pod

=item * $class->__commitTransactionStatement();

Returns the SQL used to commit a SQL transaction

=cut

# method __commitTransactionStatement(OP::Class $class:) {
sub __commitTransactionStatement {
  my $class = shift;

  return $class->__dispatch('__commitTransactionStatement');
}


=pod

=item * $class->__rollbackTransactionStatement();

Returns the SQL used to rollback a SQL transaction

=cut

# method __rollbackTransactionStatement(OP::Class $class:) {
sub __rollbackTransactionStatement {
  my $class = shift;

  return $class->__dispatch('__rollbackTransactionStatement');
}


=pod

=item * $class->__schema()

Returns the SQL used to construct the receiving class's table.

=cut

# method __schema(OP::Class $class:) {
sub __schema {
  my $class = shift;

  OP::AssertFailed->throw("'name' must be asserted as unique")
    if !$class->asserts->{name} || !$class->asserts->{name}->unique;

  my $schema = $class->__dispatch('__schema');

  return $schema;
}


=pod

=item * $class->__concatNameStatement()

Return the SQL used to look up name concatenated with the
other attributes which it is uniquely keyed with.

=cut

# method __concatNameStatement(OP::Class $class:) {
sub __concatNameStatement {
  my $class = shift;

  return $class->__dispatch('__concatNameStatement');
}


=pod

=item * $class->__statementForColumn($attr, $type, $foreign, $unique)

Returns the chunk of SQL used for this attribute in the CREATE TABLE
syntax.

=cut

# method __statementForColumn(OP::Class $class:
#   Str $attribute, OP::Type $type, OP::Array $foreign, OP::Hash $unique
# ) {
sub __statementForColumn {
  my $class = shift;

  return $class->__dispatch('__statementForColumn', @_);
}


=pod

=item * $class->__cacheKey($id)

Returns the key for storing and retrieving this record in Memcached.

  #
  # Remove a record from the cache:
  #
  my $key = $class->__cacheKey($object->get($class->__primaryKey()));

  $memd->delete($key);

=cut

# method __cacheKey(OP::Class $class: Str $id) {
sub __cacheKey {
  my $class = shift;
  my $id = shift;

  if ( !defined($id) ) {
    my $caller = caller();

    throw OP::InvalidArgument(
      "BUG (Check $caller): $class->__cacheKey(\$id) received undef for \$id"
    );
  }

  my $qid = join('/', $class, $id);

  my $key = sha1_hex($qid);
  chomp($key);

  return $key;
}


=pod

=item * $class->__dropTable()

Drops the receiving class's database table.

  use OP::Example;

  OP::Example->__dropTable();

=cut

# method __dropTable(OP::Class $class:) {
sub __dropTable {
  my $class = shift;

  return $class->__dispatch('__dropTable');
}


=pod

=item * $class->__createTable()

Creates the receiving class's database table

  use OP::Example;

  OP::Example->__createTable();

=cut

# method __createTable(OP::Class $class:) {
sub __createTable {
  my $class = shift;

  return $class->__dispatch('__createTable');
}


=pod

=item * $class->__selectRowStatement($id)

Returns the SQL used to select a record by id.

=cut

# method __selectRowStatement(OP::Class $class: Str $id) {
sub __selectRowStatement {
  my $class = shift;
  my $id = shift;

  return $class->__dispatch('__selectRowStatement', $id);
}


=pod

=item * $class->__allNamesStatement()

Returns the SQL used to generate a list of all record names

=cut

# method __allNamesStatement(OP::Class $class:) {
sub __allNamesStatement {
  my $class = shift;

  return $class->__dispatch('__allNamesStatement');
}


=pod

=item * $class->__allIdsStatement()

Returns the SQL used to generate a list of all record ids

=cut

# method __allIdsStatement(OP::Class $class:) {
sub __allIdsStatement {
  my $class = shift;

  return $class->__dispatch('__allIdsStatement');
}

# method __write(OP::Class $class: Str $query) {
sub __write {
  my $class = shift;
  my $query = shift;

  my $rows;

  eval {
    $rows = $class->__dbh()->do($query);
  };

  if ( $@ ) {
    my $err = $class->__dbh()->errstr() || $@;

    OP::DBQueryFailed->throw( join(': ', $class, $err, $query) );
  }

  return $rows;
}

# method __wrapWithReconnect(OP::Class $class: Code $sub) {
sub __wrapWithReconnect {
  my $class = shift;

  return $class->__dispatch('__wrapWithReconnect', @_);
}

# method __query(OP::Class $class: Str $query) {
sub __query {
  my $class = shift;
  my $query = shift;

  my $dbh = $class->__dbh()
    || throw OP::DBConnectFailed "Unable to connect to database";

  my $sth;

  eval { 
    $sth = $dbh->prepare($query) || die $@;
  };

  if ( $@ ) {
    throw OP::DBQueryFailed($dbh->errstr || $@);
  }

  eval {
    $sth->execute() || die $@;
  };

  if ( $@ ) {
    throw OP::DBQueryFailed($sth->errstr || $@);
  }

  return $sth;
}


=pod

=item * $class->__selectBool($query)

Returns the results of the received query, as a binary true or false value.

=cut

# method __selectBool(OP::Class $class: Str $query) {
sub __selectBool {
  my $class = shift;
  my $query = shift;

  return $class->__selectSingle($query)->shift ? true : false;
}


=pod

=item * $class->__selectSingle($query)

Returns the first row of results from the received query, as a
one-dimensional OP::Array.

  sub($$) {
    my $class = shift;
    my $name = shift;

    my $query = sprintf( q|
        SELECT mtime, ctime FROM %s WHERE name = %s
      |,
      $class->tableName(), $class->quote($name)
    );

    return $class->__selectSingle($query);
  }

  #
  # Flat array of selected values, ie:
  #
  #   [ *userId, *ctime ]
  #

=cut

# method __selectSingle(OP::Class $class: Str $query) {
sub __selectSingle {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query);

  my $out = OP::Array->new();

  while ( my @row = $sth->fetchrow_array() ) {
    $out->push(@row);
  }

  $sth->finish();

  return $out;
}


=pod

=item * $class->__selectMulti($query)

Returns each row of results from the received query, as a one-dimensional
OP::Array.

  my $query = "SELECT userId FROM session";

  #
  # Flat array of User IDs, ie:
  #
  #   [
  #     *userId,
  #     *userId,
  #     ...
  #   ]
  #
  my $userIds = $class->__selectMulti($query);


Returns a two-dimensional OP::Array of OP::Arrays, if * or multiple
columns are specified in the query.

  my $query = "SELECT userId, mtime FROM session";

  #
  # Array of arrays, ie:
  #
  #   [
  #     [ *userId, *mtime ],
  #     [ *userId, *mtime ],
  #     ...
  #   ]
  #
  my $idsWithTime = $class->__selectMulti($query);

=cut

# method __selectMulti(OP::Class $class: Str $query) {
sub __selectMulti {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query);

  my $results = OP::Array->new();

  while ( my @row = $sth->fetchrow_array() ) {
    $results->push( @row > 1 ? OP::Array->new(@row) : $row[0] );
  }

  $sth->finish();

  return $results;
}

=pod

=item * $class->__loadFromQuery($query)

Returns the first row of results from the received query, as an instance
of the current class. Good for simple queries where you don't want to
have to deal with while().

  sub($$) {
    my $class = shift;
    my $id = shift;

    my $query = $class->__selectRowStatement($id);

    my $object = $class->__loadFromQuery($query) || die $@;

    # Stuff ...
  }

=cut

# method __loadFromQuery(OP::Class $class: Str $query) {
sub __loadFromQuery {
  my $class = shift;
  my $query = shift;

  my $sth = $class->query($query)
    || throw OP::DBQueryFailed($@);

  my $self;

  while ( my $row = $sth->fetchrow_hashref() ) {
    $self = $row;

    last;
  }

  $sth->finish();

  return ( $self && ref($self) )
    ? $class->__marshal($self)
    : undef;
}


=pod

=item * $class->__dbh()

Creates a new DB connection, or returns the one which is currently active.

  sub($$) {
    my $class = shift;
    my $query = shift;

    my $dbh = $class->__dbh();

    my $sth = $dbh->prepare($query);

    while ( my $hash = $sth->fetchrow_hashref() ) {
      # Stuff ...
    }

    $sth->finish();
  }

=cut

# method __dbh(OP::Class $class:) {
sub __dbh {
  my $class = shift;

  my $dbName = $class->databaseName();

  $dbi ||= OP::Hash->new();
  $dbi->{$dbName} ||= OP::Hash->new();

  if ( !$dbi->{$dbName}->{$$} ) {
    my $dbiType = $class->__dbiType();

    if ( $dbiType == OP::Enum::DBIType::MySQL ) {
      my %creds = (
        database => $dbName,
        host => dbHost,
        pass => dbPass,
        port => dbPort,
        user => dbUser
      );

      $dbi->{$dbName}->{$$} = OP::Persistence::MySQL::connect(%creds)
    } elsif ( $dbiType == OP::Enum::DBIType::SQLite ) {
      my %creds = (
        database => join('/', sqliteRoot, $dbName)
      );

      $dbi->{$dbName}->{$$} = OP::Persistence::SQLite::connect(%creds);
    } else {
      throw OP::InvalidArgument(
        sprintf('Unknown DBI Type %s returned by class %s',
          $dbiType, $class
        )
      );
    }
  }

  my $err = $dbi->{$dbName}->{$$}->{_lastErrorStr};

  if ( $err ) {
    throw OP::DBConnectFailed($err);
  }

  return $dbi->{$dbName}->{$$}->get_dbh();
}


=pod

=item * $class->__dbi()

Returns the currently active L<GlobalDBI> object, or C<undef> if there
isn't one.

=cut

# method __dbi(OP::Class $class:) {
sub __dbi {
  my $class = shift;

  my $dbName = $class->databaseName();

  if ( !$dbi || !$dbi->{$dbName} || !$dbi->{$dbName}->{$$} ) {
    #
    # Create a GlobalDBI instance for this process
    #
    $class->__dbh();
  }

  if ( !$dbi || !$dbi->{$dbName} ) {
    return;
  }

  return $dbi->{$dbName}->{$$};
}


=pod

=item * $class->__doesIdExistStatement($id)

Returns the SQL used to look up the presence of an ID in the current table

=cut

sub __doesIdExistStatement {
  my $class = shift;
  my $id = shift;

  return $class->__dispatch('__doesIdExistStatement', $id);
}


=pod

=item * $class->__doesNameExistStatement($name)

Returns the SQL used to look up the presence of a name in the current table

=cut

sub __doesNameExistStatement {
  my $class = shift;
  my $name = shift;

  return $class->__dispatch('__doesNameExistStatement', $name);
}


=pod

=item * $class->__nameForIdStatement($id)

Returns the SQL used to look up the name for a given ID

=cut

sub __nameForIdStatement {
  my $class = shift;
  my $id = shift;

  return $class->__dispatch('__nameForIdStatement', $id);
}


=pod

=item * $class->__idForNameStatement($name)

Returns the SQL used to look up the ID for a given name

=cut

sub __idForNameStatement {
  my $class = shift;
  my $name = shift;

  return $class->__dispatch('__idForNameStatement', $name);
}


=pod

=item * $class->__serialType()

Returns the database column type used for auto-incrementing IDs.

=cut

sub __serialType {
  my $class = shift;

  return $class->__dispatch('__serialType');
}


=pod

=item * $class->__updateColumnNames();

Returns an OP::Array of the column names to include with UPDATE statements.

=cut

sub __updateColumnNames {
  my $class = shift;

  return $class->__dispatch('__updateColumnNames');
}


=pod

=item * $class->__selectColumnNames();

Returns an OP::Array of the column names to include with SELECT statements.

=cut

sub __selectColumnNames {
  my $class = shift;

  return $class->__dispatch('__selectColumnNames');
}


=pod

=item * $class->__insertColumnNames();

Returns an OP::Array of the column names to include with INSERT statements.

=cut

sub __insertColumnNames {
  my $class = shift;

  return $class->__dispatch('__insertColumnNames');
}


=pod

=item * $class->__quoteDatetimeInsert();

Returns the SQL fragment used for unixtime->datetime conversion

=cut

sub __quoteDatetimeInsert {
  my $class = shift;

  return $class->__dispatch('__quoteDatetimeInsert', @_);
}


=pod

=item * $class->__quoteDatetimeSelect();

Returns the SQL fragment used for datetime->unixtime conversion

=cut

sub __quoteDatetimeSelect {
  my $class = shift;

  return $class->__dispatch('__quoteDatetimeSelect', @_);
}


=pod

=item * $receiver->__dispatch($methodName, @args)

Delegate the received class or instance method and arguments to the
appropriate database-specific persistence module (ie
OP::Persistence::MySQL, OP::Persistence::SQLite).

=cut

sub __dispatch {
  my $receiver = shift;
  my $method = shift;

  my $module;

  my $class = $receiver->class || $receiver;

  if ( $class->__dbiType == OP::Enum::DBIType::MySQL ) {
    $module = "OP::Persistence::MySQL";
  } elsif ( $class->__dbiType == OP::Enum::DBIType::SQLite ) {
    $module = "OP::Persistence::SQLite";
  }

  do {
    no strict "refs";

    if ( !defined( *{"$module\::$method"} ) ) {
      $module = "OP::Persistence::Generic";
    }

    my $results = &{"$module\::$method"}($receiver, @_);

    return $results;
  };
}


=pod

=back

=head2 Flatfile I/O

=over 4

=item * $class->__loadYamlFromId($id)

Return the instance with the received id (returns new instance if the
object doesn't exist on disk yet)

  my $object = $class->__loadYamlFromId($id);

=cut

# method __loadYamlFromId(OP::Class $class: Str $id) {
sub __loadYamlFromId {
  my $class = shift;
  my $id = shift;

  if ( UNIVERSAL::isa($id, "Data::GUID") ) {
    $id = $id->as_string();
  }

  my $joinStr = ( $class->__basePath() =~ /\/$/ )
    ? '' : '/';

  my $self = $class->__loadYamlFromPath(
    join($joinStr, $class->__basePath(), $id)
  );

  # $self->set( $class->__primaryKey(), $id );

  return $self;
}


=pod

=item * $class->__loadYamlFromPath($path)

Return an instance from the YAML at the received filesystem path

  my $object = $class->__loadYamlFromPath('/tmp/foobar.123');

=cut

# method __loadYamlFromPath(OP::Class $class: Str $path) {
sub __loadYamlFromPath {
  my $class = shift;
  my $path = shift;

  if (-e $path) {
    my $yaml = $class->__getSourceByPath($path);

    return $class->loadYaml($yaml);
  } else {
    throw OP::FileAccessError( "Path $path does not exist on disk" );
  }
}


=pod

=item * $class->__getSourceByPath($path)

Quickly return the file contents for the received path. Basically C<cat>
a file into memory.

  my $example = $class->__getSourceByPath("/etc/passwd");

=cut

# method __getSourceByPath(OP::Class $class: Str $path) {
sub __getSourceByPath {
  my $class = shift;
  my $path = shift;

  return undef unless -e $path;

  my $lines = OP::Array->new();

  my $file = IO::File->new($path, 'r');

  while (<$file>) { $lines->push($_) }

  return $lines->join("");
}


=pod

=item * $class->__fsIds()

Return the id of all instances of this class on disk.

  my $ids = $class->__fsIds();

  $ids->each( sub {
    my $object = $class->load($_);

    # Stuff ...
  } );

=cut

# method __fsIds(OP::Class $class:) {
sub __fsIds {
  my $class = shift;

  my $basePath = $class->__basePath();

  my $ids = OP::Array->new();

  return $ids unless -d $basePath;

  find( sub {
    my $id = $File::Find::name;

    my $shortId = $id;
    $shortId =~ s/$basePath\///;

    if (
      -f $id &&
      !($id =~ /,v$/) &&
      !($id =~ /\~$/)
    ) {
      $ids->push($shortId);
    }
  }, $basePath );

  return $ids;
}


=pod

=item * $class->__init()

Override OP::Class->__init() to automatically create any missing
tables in the database.

Callers should invoke this at some point, if overriding in superclass.

=cut

# method __init(OP::Class $class:) {
sub __init {
  my $class = shift;

  if ( $class->__useMemcached
    && ( !$memd || !%{ $memd->server_versions } )
  ) {
    warn "No memcached servers found for $class to use\n";
  }

  if ( $class->__useDbi ) {
    $class->__dispatch('__init');
  }

  #
  # Initialize classes for inline elements
  #
  my $asserts = $class->asserts;

  $asserts->each( sub {
    my $key = shift;
    my $assert = $asserts->{$key};

    return if !$assert->isa("OP::Type::Array")
      && !$assert->isa("OP::Type::Hash");

    $class->elementClass($key);
  } );

  return true;
}


=pod

=back

=head1 PUBLIC INSTANCE METHODS

=head2 General

=over 4

=item * $self->save($comment)

Saves self to all appropriate backing stores.

  $object->save("This is a checkin comment");

=cut

# method save(Str ?$comment) {
sub save {
  my $self = shift;
  my $comment = shift;

  my $class = $self->class();

  #
  # new() does value sanity tests and data normalization nicely:
  #
  # %{ $self } = %{ $class->new($self) };

  $class->new($self);

  $self->presave();

  return $self->_localSave($comment);
}


=pod

=item * $self->presave();

Abstract callback method invoked just prior to saving an object.

Implement this method in subclass, if additional object sanity tests
are needed.

=cut

# method presave() {
sub presave {
  my $self = shift;

  #
  # Abstract method
  #
  return true;
}


=pod

=item * $self->remove()

Remove self's DB record, and unlink the YAML backing store if present.

Does B<not> delete RCS history, if present.

  $object->remove();

=cut

# method remove(Str ?$reason) {
sub remove {
  my $self = shift;
  my $reason = shift;

  my $class = $self->class();

  my $asserts = $class->asserts;

  if ( $class->__useDbi() ) {
    my $began = $class->__beginTransaction();

    if ( !$began ) {
      throw OP::TransactionFailed($@);
    }

    #
    # Purge multi-value elements residing in linked tables
    #
    for ( keys %{ $asserts } ) {
      my $key = $_;
    
      my $type = $asserts->{$_};
      
      next if !$type->objectClass->isa("OP::Array")
        && !$type->objectClass->isa("OP::Hash");

      my $elementClass = $class->elementClass($key);

      next if !$elementClass;
    
      $elementClass->write(  
        sprintf 'DELETE FROM %s WHERE parentId = %s',
        $elementClass->tableName,
        $class->quote($self->key)
      );
    }

    #
    # Try to run a 'delete' on an existing row
    #
    $class->write(
      $self->_deleteRowStatement()
    );

    my $committed = $class->__commitTransaction();

    if ( !$committed ) {
      #
      # If this happens, freak out.
      #
      throw OP::TransactionFailed("COMMIT failed on remove");
    }
  }

  if ( $memd && $class->__useMemcached() ) {
    my $key = $class->__cacheKey($self->key());

    $memd->delete($key);
  }

  if ( $class->__useYaml() ) {
    $self->_fsDelete();
  }

  $self->clear();

  return true;
}


=pod

=item * $self->revert($version)

Reverts self to the received version, which must be in the object's RCS
file. This method is not usable unless __useRcs in the object's class
is true.

=cut

# method revert(Num $version) {
sub revert {
  my $self = shift;
  my $version = shift;

  my $class = $self->class();

  if ( !$class->__useRcs() ) {
    throw OP::RuntimeError("Can't revert $class instances");
  }

  my $rcs = $self->_rcs();

  $rcs->co("-r$version", $self->_path());

  %{ $self } = %{ $class->__loadYamlFromId($self->id()) };

  $self->save("Reverting to version $version");

  return $self;
}

=pod

=item * $self->exists()

Returns true if this object has ever been saved.

  my $object = OP::Example->new();

  my $false = $object->exists();

  $object->save();

  my $true = $object->exists();

=cut

# method exists() {
sub exists {
  my $self = shift;

  return false if !defined( $self->{id} );

  my $class = $self->class;

  return $class->__useDbi
    ? $self->class->doesIdExist($self->id)
    : -e $self->_path;
}

=pod

=item * $self->key()

Returns the value for this object's primary database key, since the
primary key may not always be "id".

Equivalent to:

  $self->get( $class->__primaryKey() );

Which, in most cases, yields the same value as:

  $self->id();

=cut

# method key() {
sub key {
  my $self = shift;

  my $class = $self->class();

  return $self->get( $class->__primaryKey() );
}


=pod

=item * $self->memberInstances($key)

Only applicable for attributes which were asserted as C<ExtID()>.

Returns an OP::Array of objects referenced by the named attribute.

Equivalent to using C<load()> on the class returned by class method
C<memberClass()>, for each ID in the relationship.

  my $exa = OP::Example->spawn("Foo");

  my $users = $exa->memberInstances("userId");

=cut

# method memberInstances(Str $key) {
sub memberInstances {
  my $self = shift;
  my $key = shift;

  my $instances = OP::Array->new();

  my $memberClass = $self->class()->memberClass($key);

  return $instances if !defined $memberClass;

  my $extId = $self->get($key);

  return $instances if !defined $extId;

  my $type = $self->class()->asserts()->{$key};

  if ( $type && ref($type) eq 'OP::Type::Array' ) {
    for ( @{ $self->{$key} } ) {
      $instances->push( $memberClass->load($_) );
    }
  } else {
    $instances->push( $memberClass->load($extId) );
  }

  return $instances;
}


=pod

=item * $self->setIdsFromNames($attr, @names)

Convenience setter for attributes which contain either an ExtID or an
Array of ExtIDs.

Sets the value for the received attribute name in self to the IDs of
the received names. If a name is provided which does not correspond to
a named object in the foreign table, a new object is created and saved,
and the new ID is used.

If the named objects do not yet exist, and have other required attributes
other than "name", then this method will raise an exception. The
referenced object will need to be explicitly saved before the referent.

  #
  # Set "parentId" in self to the ID of the object named "Mom":
  #
  $obj->setIdsFromNames("parentId", "Mom");

  #
  # Set "categoryIds" in self to the ID of the objects
  # named "Blue" and "Red":
  #
  $obj->setIdsFromNames("categoryIds", "Blue", "Red");

=cut

# method setIdsFromNames(Str $attr, *@names) {
sub setIdsFromNames {
  my $self = shift;
  my $attr = shift;
  my @names = @_;

  my $class = $self->class;
  my $asserts = $class->asserts;

  my $type = $asserts->{$attr}
    || OP::InvalidArgument->throw("$attr is not an attribute of $class");

  if ( $type->isa("OP::Type::ExtID") ) {
    OP::InvalidArgument->throw("Too many names received")
      if @names > 1;

  } elsif (
    $type->isa("OP::Type::Array")
    && $type->memberType->isa("OP::Type::ExtID")
  ) {
    #
    #
    #

  } else {
    OP::InvalidArgument->throw("$attr does not represent an ExtID");
  }

  my $names = OP::Array->new(@names);

  my $extClass = $type->externalClass;

  my $newIds = $names->collect( sub {
    my $obj = $extClass->spawn($_);

    if ( !$obj->exists ) {
      $obj->save;
    }

    OP::Array::yield( $obj->id );
  } );

  my $currIds = $self->get($attr);

  if ( !$currIds ) {
    $currIds = OP::Array->new;
  } elsif ( !$currIds->isa("OP::Array") ) {
    $currIds = OP::Array->new($currIds);
  }

  if ( $type->isa("OP::Type::ExtID") ) {
    $self->set($attr, $newIds->shift);
  } else {
    $self->set($attr, $newIds);
  }

  return true;
}

=pod

=back

=head2 YAML Output

Methods for YAML output may be found in L<OP::Hash>.

=head2 RCS Output

=over 4

=item * $self->revisions()

Return an array of all of this object's revision numbers

=cut

# method revisions() {
sub revisions {
  my $self = shift;

  return $self->_rcs()->revisions();
}


=pod

=item * $self->revisionInfo()

Return a hash of info for this file's checkins

=cut

# method revisionInfo() {
sub revisionInfo {
  my $self = shift;

  my $rcs = $self->_rcs();

  my $loghead;

  my $revisionInfo = OP::Hash->new();

  for my $line ( $rcs->rlog() ) {
    next if $line =~ /----------/;

    last if $line =~ /==========/;

    if ($line =~ /revision (\d+\.\d+)/) {
      $loghead = $1;

      next;
    }

    next unless $loghead;

    $revisionInfo->{$loghead} = '' unless $revisionInfo->{$loghead};

    $revisionInfo->{$loghead} .= $line;
  }

  return $revisionInfo;
}


=pod

=item * $self->head()

Return the head revision number for self's backing store.

=cut

# method head() {
sub head {
  my $self = shift;

  return $self->_rcs()->head();
}


=pod

=back

=head1 PRIVATE INSTANCE METHODS

=head2 General

=over 4

=item * $self->_newId()

Generates a new ID for the current object. Default is GUID-style.

  _newId => sub {
    my $self = shift;

    return OP::Utility::newId();
  }

=cut

# method _newId() {
sub _newId {
  my $self = shift;

  my $class = $self->class;

  my $assert = $class->asserts->{ $class->__primaryKey };

  return $assert->objectClass->new();
}

=pod

=item * $self->_localSave($comment)

Saves self to all applicable backing stores.

=cut

# method _localSave(Str $comment) {
sub _localSave {
  my $self = shift;
  my $comment = shift;

  my $class = $self->class();
  my $now = time();

  #
  # Will restore original object values if any part of the
  # save doesn't work out.
  #
  my $orig_id = $self->key();
  my $orig_ctime = $self->{ctime};
  my $orig_mtime = $self->{mtime};

  my $idKey = $class->__primaryKey();

  $self->{$idKey} ||= $self->_newId();

  if ( !defined($self->{ctime}) || $self->{ctime} == 0 ) {
    $self->setCtime($now);
  }

  $self->setMtime($now);

  my $useDbi = $class->__useDbi();

  if ( $useDbi ) {
    my $began = $class->__beginTransaction();

    if ( !$began ) {
      throw OP::TransactionFailed($@);
    }
  }

  my $saved;

  try {
    $saved = $self->_localSaveInsideTransaction($comment);

    $self->_saveToMemcached;

  } catch Error with {
    $OP::Persistence::errstr = $_[0];

    warn $errstr;

    undef $saved;

  } finally {
    if ( $saved ) {
      #
      # If using DBI, commit the transaction or die trying:
      #
      if ( $useDbi ) {
        my $committed = $class->__commitTransaction();

        if ( !$committed ) {
          #
          # If this happens, freak out.
          #
          throw OP::TransactionFailed(
            "Could not COMMIT! Check DB and compare history for ".
            "$idKey $self->{$idKey} in class $class"
          );
        }
      }
    } else {
      $self->{$idKey} = $orig_id;
      $self->{ctime} = $orig_ctime;
      $self->{mtime} = $orig_mtime;

      if ( $useDbi ) {
        my $rolled = $class->__rollbackTransaction();

        if ( !$rolled ) {
          my $quotedID = $class->quote($self->{$idKey});

          #
          # If this happens, superfreak out.
          #
          throw OP::TransactionFailed(
            "ROLLBACK FAILED!!! Check DB and compare history for "
              . "$idKey $quotedID in class $class: "
              . $OP::Persistence::errstr
          );
        } else {
          throw OP::TransactionFailed(
            "Transaction failed: "
              . $OP::Persistence::errstr
          );
        }
      }
    }
  };

  return $saved;
}

=pod

=item * $self->_localSaveInsideTransaction($comment);

Private backend method called by _localSave() when inside of a
database transaction.

=cut

# method _localSaveInsideTransaction(Str $comment) {
sub _localSaveInsideTransaction {
  my $self = shift;
  my $comment = shift;

  my $class = $self->class();

  my $path = $self->_path();

  my $idKey = $class->__primaryKey();

  my $useDbi = $class->__useDbi();

  my $saved;

  #
  # Update the DB row, if using DBI.
  #
  if ( $useDbi ) {
    $saved = $self->_updateRecord();

    if ( $saved ) {
      my $asserts = $class->asserts();

      #
      # Save complex objects to their respective tables
      #
      for ( keys %{ $asserts } ) {
        my $key = $_;

        my $type = $asserts->{$_};

        next if !$type->objectClass->isa("OP::Array")
          && !$type->objectClass->isa("OP::Hash");

        my $elementClass = $class->elementClass($key);

        $elementClass->write( 
          sprintf 'DELETE FROM %s WHERE parentId = %s',
          $elementClass->tableName(),
          $class->quote($self->key())
        );

        next if !defined $self->{$key};

        if ( $type->objectClass->isa('OP::Array') ) {
          my $i = 0;

          for my $value ( @{ $self->{$key} } ) {
            my $element = $elementClass->new(
              parentId => $self->key(),
              elementIndex => $i,
              elementValue => $value,
            );

            $saved = $element->save($comment);

            return if !$saved;

            $i++;
          }
        } elsif ( $type->objectClass->isa('OP::Hash') ) {
          for my $elementKey ( keys %{ $self->{$key} } ) {
            my $value = $self->{$key}->{$elementKey};

            my $element = $elementClass->new(
              parentId => $self->key(),
              elementKey => $elementKey,
              elementValue => $value,
            );

            $saved = $element->save($comment);

            return if !$saved;
          }
        }
      }
    }

    return if !$saved;

    $self->{$idKey} ||= $saved;
  }
  
  #
  # Remove the cached object, if using Memcached
  #
  if ( $class->__useMemcached() && $memd ) {
    my $key = $class->__cacheKey($self->key());

    $memd->delete($key);
  }

  #
  # Update the YAML backing store if using YAML
  #
  if ( $class->__useYaml() ) {
    my $useRcs = $class->__useRcs();

    my $rcs;

    #
    # Update the RCS history file if using RCS
    #
    # Initial checkout:
    #
    if ( $useRcs ) {
      $rcs = Rcs->new();

      $path =~ /(.*)\/(.*)/;

      my $directory = $1;
      my $filename = $2;

      my $rcsBase = $class->__baseRcsPath();

      if ( !-d $rcsBase ) {
        eval { mkpath($rcsBase) };
        if ($@) {
          throw OP::FileAccessError($@);
        }
      }

      $rcs->file($filename);
      $rcs->rcsdir($rcsBase);
      $rcs->workdir($directory);

      $self->_checkout($rcs, $path);
    }

    #
    # Write YAML to filesystem
    #
    $self->_fsSave();

    #
    # Checkin the new file if using RCS
    #
    if ( $useRcs ) {
      $self->_checkin($rcs, $path, $comment)
    }
  }

  return $self->{$idKey};
}


=pod

=item * $self->_saveToMemcached

Saves a copy of self to the memcached cluster

=cut

sub _saveToMemcached {
  my $self = shift;

  my $class = $self->class;

  my $cacheTTL = $class->__useMemcached();

  if ( $memd && $cacheTTL ) {
    return $memd->set(
      $class->__cacheKey($self->id), $self, $cacheTTL
    );
  }

  return;
}


=pod

=back

=head2 Database I/O

=over 4

=item * $self->_updateRowStatement()

Returns the SQL used to run an "UPDATE" statement for the
receiving object.

=cut

# method _updateRowStatement() {
sub _updateRowStatement {
  my $self = shift;

  return $self->__dispatch("_updateRowStatement");
}


=pod

=item * $self->_insertRowStatement()

Returns the SQL used to run an "INSERT" statement for the
receiving object.

=cut

# method _insertRowStatement() {
sub _insertRowStatement {
  my $self = shift;

  return $self->__dispatch("_insertRowStatement");
}


=pod

=item * $self->_deleteRowStatement()

Returns the SQL used to run a "DELETE" statement for the
receiving object.

=cut

# method _deleteRowStatement() {
sub _deleteRowStatement {
  my $self = shift;

  return $self->__dispatch("_deleteRowStatement");
}


=pod

=item * $self->_updateRecord()

Executes an INSERT or UPDATE for this object's record. Callback method
invoked from _localSave().

Returns number of rows on UPDATE, or ID of object created on INSERT.

=cut

# method _updateRecord() {
sub _updateRecord {
  my $self = shift;

  my $class = $self->class();

  #
  # Try to run an 'update' on an existing row
  #
  my $return = $class->write(
    $self->_updateRowStatement()
  );

  #
  # Row does not exist, must populate it
  #
  if ( $return == 0 ) {
    $return = $class->write(
      $self->_insertRowStatement()
    );

    my $priKey = $class->__primaryKey;

    #
    # If the ID was database-assigned (auto-increment), update self:
    #
    if ( $class->asserts->{$priKey}->isa("OP::Type::Serial") ) {
      my $lastId = $class->__dbh->last_insert_id(
        undef, undef, $class->tableName, $priKey
      );

      $self->set($priKey, $lastId);
    }
  }

  return $return;
}


=pod

=item * $self->_quotedValues()

Callback method used to construct the values portion of an
UPDATE or INSERT query.

=cut

#
#
#
our $ForceInsertSQL;
our $ForceUpdateSQL;

# method _quotedValues(Bool ?$isUpdate ) {
sub _quotedValues {
  my $self = shift;

  return $self->__dispatch('_quotedValues', @_);
}


=pod

=back

=head2 Flatfile I/O

=over 4

=item * $self->_fsDelete()

Unlink self's YAML datafile from the filesystem. Does not dereference self
from memory.

=cut

# method _fsDelete() {
sub _fsDelete {
  my $self = shift;

  unlink $self->_path();

  return true;
}


=pod

=item * $self->_fsSave()

Save $self as YAML to a local filesystem. Path is
$class->__basePath + $self->id();

=cut

# method _fsSave() {
sub _fsSave {
  my $self = shift;

  $self->{ $self->class()->__primaryKey() } ||= $self->_newId();

  return $self->_saveToPath( $self->_path() );
}


=pod

=item * $self->_path()

Return the filesystem path to self's YAML data store.

=cut

# method _path() {
sub _path {
  my $self = shift;

  my $key = $self->key();

  return false if !$key;

  if ( UNIVERSAL::isa($key, "Data::GUID") ) {
    $key = $key->as_string();
  }

  return join('/', $self->class()->__basePath(), $key);
}


=pod

=item * $self->_saveToPath($path)

Save $self as YAML to a the received filesystem path

=cut

# method _saveToPath(Str $path) {
sub _saveToPath {
  my $self = shift;
  my $path = shift;

  my $class = $self->class();

  my $base = $path;
  $base =~ s/[^\/]+$//;

  if ( !-d $base ) {
    eval { mkpath($base) };
    if ($@) {
      throw OP::FileAccessError($@);
    }
  }

  my $id = $self->key();
  if ( UNIVERSAL::isa($id, "Data::GUID") ) {
    $id = $id->as_string();
  }

  my $tempPath = sprintf '%s/%s-%s',
    scratchRoot, $id, OP::Utility::randstr();

  my $tempBase = $tempPath;
  $tempBase =~ s/[^\/]+$//;

  if ( !-d $tempBase ) {
    eval { mkpath($tempBase) };
    if ($@) {
      throw OP::FileAccessError($@);
    }
  }

  my $yaml = $self->toYaml();

  open(TEMP, "> $tempPath");
  print TEMP $yaml;
  close(TEMP);

  chmod '0644', $path;

  move( $tempPath, $path );

  return true;
}


=pod

=back

=head2 RCS I/O

=over 4

=item * $self->_rcsPath()

Return the filesystem path to self's RCS history file.

=cut

# method _rcsPath() {
sub _rcsPath {
  my $self = shift;

  my $key = $self->key();

  return false unless ( $key );

  my $class = ref($self);

  my $joinStr = ( $class->__baseRcsPath() =~ /\/$/ ) ? '' : '/';

  return sprintf('%s%s',
    join($joinStr, $class->__baseRcsPath(), $key), ',v'
  );
}


=pod

=item * $self->_checkout($rcs, $path)

Performs the RCS C<co> command on the received path, using the received
L<Rcs> object.

=cut

# method _checkout(Rcs $rcs, Str $path) {
sub _checkout {
  my $self = shift;
  my $rcs = shift;
  my $path = shift;

  return $rcs->co('-l') if -e $path;
}


=pod

=item * $self->_checkin($rcs, $path, [$comment])

Performs the RCS C<ci> command on the received path, using the received
L<Rcs> object.

=cut

# method _checkin(Rcs $rcs, Str $path, Str $comment) {
sub _checkin {
  my $self = shift;
  my $rcs = shift;
  my $path = shift;
  my $comment = shift;

  my $user = $ENV{REMOTE_USER} || $ENV{USER} || 'nobody';

  $comment ||= "No checkin comment provided by $user";

  return $rcs->ci(
    '-t-Programmatic checkin from '. $self->class(),
    '-u',
    "-mEdited by user $user with comment: $comment"
  );
}


=pod

=item * $self->_rcs()

Return an instance of the Rcs class corresponding to self's backing store.

=cut

# method _rcs() {
sub _rcs {
  my $self = shift;

  my $rcs = Rcs->new();

  $self->_path() =~ /(.*)\/(.*)/;

  my $directory = $1;
  my $filename = $2;

  $rcs->file($filename);
  $rcs->rcsdir(join("/", $directory, rcsDir));
  $rcs->workdir($directory);

  return $rcs;
}


=pod

=back

=head1 SEE ALSO

L<Cache::Memcached::Fast>, L<Rcs>, L<YAML::Syck>, L<GlobalDBI>, L<DBI>

This file is part of L<OP>.

=cut

true;
