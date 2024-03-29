use ExtUtils::MakeMaker;

my $prereqs = {
   Cache::Memcached::Fast => 0.13,
                    Clone => 0.29,
               Data::GUID => 0.043,
             Digest::SHA1 => 2.11,
                    Error => 0.17015,
               File::Copy => 2,
               File::Path => 2.04,
      File::HomeDir::Unix => 0.86,
            File::Tempdir => 0.02,
                GlobalDBI => 0.21,
               IO::Handle => 1.14,
            Math::VecStat => 0.08,
              Net::Syslog => 0.03,
                      Rcs => 1.05,
             Scalar::Util => 1.19,
            Sys::Hostname => 1.11,
               Test::More => 0.86,
              Time::HiRes => 1.9711,
              Time::Piece => 1.12,
          Unicode::String => 2.09,
              URI::Escape => 3.29,
               YAML::Syck => 1.05,
};

WriteMakefile(
  ABSTRACT_FROM => 'lib/OP.pm',
  VERSION_FROM  => 'lib/OP.pm',
  NAME          => 'OP',
  PREREQ_PM     => $prereqs,
  LICENSE       => 'open_source',
  AUTHOR        => 'Alex Ayars <pause@nodekit.org>',
  EXE_FILES     => ['bin/opconf', 'bin/oped', 'bin/opid'],
);
