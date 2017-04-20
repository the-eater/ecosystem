use v6;
use LWP::Simple;
use JSON::Fast;
use Test;
use Test::META;

my $diffproc = run 'git', 'diff', '--no-color', '-p', '-U0', %*ENV<TRAVIS_COMMIT>, %*ENV<TRAVIS_PULL_REQUEST_SHA>, '--', 'META.list', :out;
my $metadiff = $diffproc.out.slurp-rest;

if $metadiff ~~ /^\s*$/ {
  say "Nothing changed all fine.";
  ok 1, "all fine";
  exit 0;
}

my @urls = ();
my $lines = 0;

for split("\n", $metadiff.trim).map({ .trim; }) -> $line {
  $lines++;
  if $lines < 6 or $line !~~ /^\+/ {
    next;
  }

  my $metaurl = substr $line, 1;
  @urls.push: $metaurl;
}

if (@urls.end lt 0) {
  say "No packages have been added.";
  exit 0;
}

my $amountUrls = @urls.end + 1;
say "$amountUrls packages were added";

  plan $amountUrls;

  my $lwp = LWP::Simple.new();

  my $oldpwd = $*CWD;

  for @urls -> $url {
    subtest {
      my $sourcedir;
      lives-ok {
        my $meta = from-json($lwp.get($url));

        if ! $meta<source-url> {
          bail-out "no source-url defined in META file";
        }

        $_ = $meta<name>;
        s:g/\:\:/__/;
        $sourcedir = $*TMPDIR ~ "/" ~ $_;
        my $sourceurl = $meta<source-url>;
        my $git = run "git", "clone", $sourceurl, $sourcedir;
        if $git.exitcode ne 0 {
          bail-out "Couldn't clone repo " ~ $sourceurl;
        }
      }, "Downloading $url";

      chdir($sourcedir);

      my $*DIST-DIR = $sourcedir.IO;
      my $*TEST-DIR //= Any;
      my $*META-FILE //= Any;
      meta-ok();

      my $zef = run "zef", "install", "--depsonly", "--/build", ".";
      ok $zef.exitcode eq 0, "Able to install deps";
      $zef = run "zef", "test", ".";
      ok $zef.exitcode eq 0, "Package tests pass";

      rm-all($sourcedir.IO);
      chdir($oldpwd);
    }, "Checking correctness of $url";
  }
# When we have a directory first recurse, then remove it
multi sub rm-all(IO::Path $path where :d) {
    .&rm-all for $path.dir;
    rmdir($path)
}

# Otherwise just remove the thing directly
multi sub rm-all(IO::Path $path) { $path.unlink }
