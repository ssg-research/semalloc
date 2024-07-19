#
#  setup_common.pl - early-access routines for runcpu/rawformat startup
#  Copyright 2006-2020 Standard Performance Evaluation Corporation
#
#  Authors:  Christopher Chan-Nui
#            Cloyce D. Spradling
#
# $Id: setup_common.pl 6544 2020-10-13 22:18:49Z CloyceS $

my $tmpversion = '$LastChangedRevision: 6544 $ '; # Make emacs happier
$tmpversion =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'setup_common.pl'} = $tmpversion;
$::suite_version = 0 unless defined($::suite_version);

use strict;
use IO::File;                   # Because we want to read a file early
use File::Basename;             # Ditto
use File::Spec::Functions qw(rel2abs);
use Time::HiRes;                # For early internal timings
use Carp;
use Scalar::Util qw(reftype);
use POSIX ();
require 'util_common.pl';

$Carp::MaxArgLen = 0;   # Make Carp::longmess show all of an argument
$Carp::MaxArgNums = 0;  # Make Carp::longmess show all arguments

# Set up Data::Dumper a little bit
$Data::Dumper::Indent = 1;      # Potentially readable; maybe not too wide
$Data::Dumper::Sortkeys = 1;    # Consistent order for hashes, please
$Data::Dumper::Purity = 0;      # It's just for show

sub get_suite_version {
    my $fh = new IO::File "<$ENV{'SPEC'}/version.txt";  # DOS is still dumb
    if (defined($fh)) {
        my $suite_ver = <$fh>;
        $suite_ver =~ tr/\015\012//d;
        # CVT2DEV: $suite_ver .= 'dev';
        return $suite_ver;
    } else {
        if (!exists ($ENV{'SPEC'}) || !defined($ENV{'SPEC'}) ||
            $ENV{'SPEC'} eq '') {
            # One of those impossible things
            print STDERR "\nThe SPEC environment variable is not set; please source the shrc before\n  invoking runcpu.\n\n";
            exit 1;
        }
        print STDERR "\nThe ${main::suite} suite version could not be read.  Your distribution is corrupt\n  or incomplete.\n\n";
        exit 1;
    }
}

sub read_toolset_name {
    my $fh = new IO::File "<$ENV{'SPEC'}/bin/packagename";
    my $packagename = defined($fh) ? <$fh> : 'unknown';
    $packagename =~ tr/\015\012//d;
    return $packagename;
}

sub joinpaths {
    my @dirs;
    for my $tmp (@_) {
        next unless defined($tmp) and $tmp ne '';
        # Replace all backslashes with forward slashes (for NT)
        my $a = $tmp;
        $a =~ s|\\|/|go;
        next if $a eq '';
        # If this is the start of an absolute path, remove what's already there
        @dirs = () if ($a=~m/^([^:\[]*):?\[(\S*)\]/o || $a =~ m|^/|o || $a =~ m|^[a-zA-Z]:|o);

        $a =~ s#/+$##;      # Strip trailing /
        push (@dirs, $a);
    }
    my $result = join('/',@dirs);
    return $result;
}
sub jp { joinpaths(@_); }

sub read_manifest {
    my ($path, $manifest, $re, $sumhash, $sizehash) = @_;
    $sumhash  = {} unless reftype($sumhash)  eq 'HASH';
    $sizehash = {} unless reftype($sizehash) eq 'HASH';

    if (!-e $manifest) {
        # This should never happen.  But just in case...
        print STDERR "\nThe manifest file ($manifest) is missing or unreadable;\n  the benchmark suite is incomplete or corrupted!\n\n";
        exit 1;
    } elsif (!-r $manifest) {
        print STDERR "\nThe manifest file ($manifest) is present but cannot be read; please check the permissions!\n\n";
        exit 1;
    }

    my $manifestreadstart = Time::HiRes::time;

    # Read in the manifest and store it in a hash
    my @lines = ();
    my $fh = new IO::File '<'.$manifest;
    if (!defined($fh)) {
        print STDERR "There was a problem opening $manifest: $!\n";
        exit 1;
    }

    # Normalize the path separators and strip the trailing /
    $path =~ tr|\\|/|;
    $path =~ s#/$##;
    my $fullpath;
    my $files = 0;

    while(defined(my $line = <$fh>)) {
        next unless !defined($re) or $line =~ /$re/;
        my ($sum, $size, $fn) = $line =~ m/^([[:xdigit:]]{32,128}) (?:\*| ) ([[:xdigit:]]{8,16}) (.*)/o;
        next if ($fn eq ''
                 or (length($sum) != 32 and length($sum) != 64 and length($sum) != 128)
                 or (length($size) != 8 and length($size) != 16));
        $fullpath = $path.'/'.$fn; # jp() not used because we always want /
        $sumhash->{$fullpath}  = $sum;
        $sizehash->{$fullpath} = hex($size);
        $files++;
    }
    $fh->close();

    # Get the hash of the manifest we just read
    my $hashbits = ($fullpath ne '') ? length($sumhash->{$fullpath}) * 4 : 512;
    $fullpath = 'manifest|'.basename($manifest);
    $sumhash->{$fullpath} = filedigest($manifest, $hashbits);
    $sizehash->{$fullpath} = -s $manifest;

    printf("read_manifest completed in %8.7fs\n", Time::HiRes::time - $manifestreadstart) if ($::debug >= 99);

    return ($files, $sizehash, $sumhash);
}

sub check_files {
    my ($sums, @files) = @_;
    my $top = $ENV{'SPEC'};

    # Check a list of files against the hashes in %file_sums
    foreach my $file (@files) {
        # Add the path to the top level directory, if it's not already there:
        $file = jp($top, $file) unless $file =~ /^\Q$top\E/oi;
        if (!exists($sums->{$file})) {
#           print "No checksum for $file!\n";
           return wantarray ? (0, $file) : 0;
        } else {
            my $genhash = filedigest($file, length($sums->{$file}) * 4);
            if ($sums->{$file} ne $genhash) {
#               print "Checksum mismatch for $file!\n\tstored:    $sums->{$file}\n\tgenerated: $genhash\n";
               return wantarray ? (0, $file) : 0;
            }
        }
    }

    return wantarray ? (1, undef) : 1;
}

sub load_module {
    my ($module, $quiet, $pre) = @_;
    $pre = '' unless defined($pre);

    # Look through @INC to find the location of the module that will actually
    # be loaded, and check its signature in MANIFEST.  This allows programs to
    # say "load_module('foo')" and have correct "foo"'s signature checked.
    foreach my $location (@INC) {
        my $path = jp($location, $module);
        if (-f $path) {
            # Make it relative to $SPEC for looking up in MANIFEST
            $path =~ s#^\Q${ENV{'SPEC'}}\E[/\\]*##;
            if ($::check_integrity && !check_files(\%::file_sums, $path)) {
                print "\n\nPart of the tools ($module in $path) is corrupt!  Aborting...\n\n";
            }
            eval "$pre require \"$module\";";
            print '.' unless ($quiet);
            if ($@) {
                print "\nError loading $module!  Your tools are incomplete or corrupted.\n";
                die "eval said '$@'\nStopped";
            }
            return;
        }
    }
}

sub read_manifests {
    my (@files) = @_;

    # CVT2DEV: return ({}, {});
    return ({}, {}) if ($::tools_versions{'formatter_vars.pl'} &&
        defined($::website_formatter) && $::website_formatter);

    $::check_integrity = 0;
    $::suite_version = get_suite_version();
    my $start = Time::HiRes::time();
    print "Reading file manifests... " unless $::from_runcpu;
    my ($files, $file_size, $file_sum) = (0, {}, {});
    foreach my $file (@files) {
        my ($re, $fn) = ((::ref_type($file) eq 'ARRAY') ? @{$file} : (undef, $file));
        my $path = jp($ENV{'SPEC'}, $fn);
        if (!-e $path) {
            if ($fn eq 'TOOLS.sha512') {
                print "\n\nThe checksums for the binary tools could not be found.  If you have just\n";
                print "built a new set of tools, please run packagetools to create the checksums.\n";
                print "Additionally, packagetools will create a tar file of the newly built tools\n";
                print "which you can use for other installations on the same architecture/OS.\n";
                print "\n";
                exit 1;
            }
        }
        my ($tmpcnt) = read_manifest($ENV{'SPEC'}, $path, $re, $file_sum, $file_size);
        $files += $tmpcnt;
    }
    my $elapsed = Time::HiRes::time() - $start;
    printf "read $files entries from %d files in %0.2fs (%d files/s)\n", @files+0, $elapsed, $files / $elapsed unless $::from_runcpu;

    return ($file_size, $file_sum);
}

sub check_important_files {
    my ($re) = @_;

    # CVT2DEV: $::check_integrity = 0; return;
    return if (::is_devel($::suite_version) and !$ENV{'SPEC_CHECK'})
        or (::is_release($::suite_version) and $ENV{'SPEC_NOCHECK'});
    $::check_integrity = 1;
    # Who I Am is actually the last three components of the path, which should be
    # 'bin' / (harness|formatter) / <me>
    my $whoami;
    my $tmp = rel2abs($0);
    for(my $i = 0; $i < 3; $i++) {
        $whoami = defined($whoami) ? jp(basename($tmp), $whoami) : basename($tmp);
        $tmp = dirname($tmp);
    }
    foreach my $important_file ($whoami, grep { m/$re/ } keys %::file_sums) {
        if (!check_files(\%::file_sums, $important_file)) {
            print STDERR "\n\nPart of the tools ($important_file) is corrupt!\nAborting...\n\n";
            exit 1;
        }
    }
}

sub timeformat {
    my ($format, @timelist) = @_;

    @timelist = CORE::localtime($timelist[0]) if (@timelist == 1);
    my $mon = (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$timelist[4]];

    # Convert the RFC3339 productions that $format might contain into the
    # escapes that strftime expects.
    $format =~ s/full-date/%Y-%m-%d/g;
    $format =~ s/partial-time/%H:%M:%S/g;
    $format =~ s/UGLY-date-time/%Y-%m-%dT%H:%M:%S/g;
    $format =~ s/ugly-date-time/%Y-%m-%dt%H:%M:%S/g;
    $format =~ s/date-time/%Y-%m-%d %H:%M:%S/g;
    # And the non-3339 production to match our ancient ways (for now)
    $format =~ s/avail-date/${mon}-%Y/g;

    return POSIX::strftime($format, @timelist);
}

1;

# Editor settings: (please leave this at the end of the file)
# vim: set filetype=perl syntax=perl shiftwidth=4 tabstop=8 expandtab nosmarttab colorcolumn=120:
