#
# benchmark.pm
# Copyright 1999-2019 Standard Performance Evaluation Corporation
#
# $Id: benchmark.pm 6381 2019-09-10 19:48:45Z CloyceS $
#

package Spec::Benchmark;
use strict;
use Archive::Tar;
use File::Path qw(remove_tree);
use File::Basename;
use File::stat;
use File::Temp qw(tempfile);
use IO::File;
use IO::Dir;
use Cwd;
use IO::Scalar;
use Digest::SHA;
use Carp qw(cluck);
use MIME::Base64;
use Math::BigFloat;
use Time::HiRes;
use List::Util qw(max);
use POSIX qw(:sys_wait_h);
use vars '@ISA';
eval 'use String::ShellQuote';
my $shellquote = $@ eq '';

@ISA = (qw(Spec::Config));

my $version = '$LastChangedRevision: 6381 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'benchmark.pm'} = $version;

# List of things that MUST be included in the checksum of options.
# This list does not include things which will appear on the compile/link
# command line:
my %option_cksum_include = (
    'srcalt' => '',
    'RM_SOURCES' => '',
    'explicit_dimensions' => 0,
    'strict_rundir_verify' => 0,
    'version' => 0,
);

sub new {
    no strict 'refs';
    my ($class, $topdir, $config, $num, $name) = @_;
    my $me       = bless {}, $class;

    $me->{'name'}        = ${"${class}::benchname"};
    $me->{'num'}         = ${"${class}::benchnum"};
    if ($me->{'name'} eq '' || $me->{'num'} eq '') {
        Log(0, "Either \$benchname or \$benchnum are empty for $name.$num; Ignoring.\n");
        return undef;
    }
    if (!defined(${"${class}::need_math"}) ||
        (${"${class}::need_math"} eq '0') ||
        (lc(${"${class}::need_math"}) eq 'no')) {
        $me->{'need_math'} = '';
    } else {
        $me->{'need_math'} = ${"${class}::need_math"};
    }
    if (${"${class}::sources"} ne '') {
        $me->{'sources'} = ${"${class}::sources"};
    } elsif (@{"${class}::sources"} > 0) {
        $me->{'sources'} = [ @{"${class}::sources"} ];
    } else {
        $me->{'sources'} = { %{"${class}::sources"} };
    }

    $me->{'deps'}        = { %{"${class}::deps"} };
    $me->{'srcdeps'}     = { %{"${class}::srcdeps"} };
    $me->{'workload_dirs'} = { %{"${class}::workloads"} };

    if ($me->{'name'} ne  $name || $me->{'num'} != $num) {
        Log(0, "Benchmark name (".$me->{'num'}.".".$me->{'name'}.") does not match directory name '$topdir'.  Ignoring benchmark\n");
        return undef;
    }

    # Allow a benchmark to opt out of power measurement
    $me->{'power'}       = ${"${class}::power"};
    if (defined($me->{'power'}) && $me->{'power'} ne '' && !istrue($me->{'power'})) {
        $config->{'cl_opt_override'}->{'power'}->{$me}++;
    } else {
        delete $me->{'power'};
    }

    # Here are the settings that get passed to specdiff.  If these are changed,
    # don't forget to add a new sub for each new item below.
    foreach my $toltype (qw(abstol reltol calctol)) {
        $me->{$toltype}      = ${"${class}::${toltype}"};
        delete $me->{$toltype} unless defined($me->{$toltype});
    }
    # Check the tolerances
    if (! ::istrue(${"${class}::these_tolerances_are_as_intended"})) {
        my $out = ::check_tolerances($me->{'abstol'},
            $me->{'reltol'},
            $me->{'num'}.".".$me->{'name'});
        if (defined($out) && $out ne '') {
            Log(0, $out);
            return undef;
        }
    }
    $me->{'compwhite'}   = ${"${class}::compwhite"};
    $me->{'floatcompare'}= ${"${class}::floatcompare"};
    $me->{'obiwan'}      = ${"${class}::obiwan"};
    $me->{'skiptol'}     = ${"${class}::skiptol"};
    $me->{'skipabstol'}  = ${"${class}::skipabstol"};
    $me->{'skipreltol'}  = ${"${class}::skipreltol"};
    $me->{'skipobiwan'}  = ${"${class}::skipobiwan"};
    $me->{'binary'}      = ${"${class}::binary"};
    $me->{'ignorecase'}  = ${"${class}::ignorecase"};
    $me->{'nansupport'}  = ${"${class}::nansupport"};
    $me->{'dependent_workloads'}  = ${"${class}::dependent_workloads"} || 0;

    if (!defined(${"${class}::benchlang"}) || ${"${class}::benchlang"} eq '') {
        %{$me->{'BENCHLANG'}} = %{"${class}::benchlang"};
        @{$me->{'allBENCHLANG'}}= ();
        # Fix up the benchlang lists (so that they're lists), and make the
        # full list of all benchlangs
        foreach my $exe (keys %{$me->{'BENCHLANG'}}) {
            if (ref($me->{'BENCHLANG'}->{$exe}) eq 'ARRAY') {
                push @{$me->{'allBENCHLANG'}}, @{$me->{'BENCHLANG'}->{$exe}};
            } else {
                my @langs = split(/[\s,]+/, $me->{'BENCHLANG'}->{$exe});
                $me->{'BENCHLANG'}->{$exe} = [ @langs ];
                push @{$me->{'allBENCHLANG'}}, @langs;
            }
        }
    } else {
        @{$me->{'BENCHLANG'}}= split(/[\s,]+/, ${"${class}::benchlang"});
        @{$me->{'allBENCHLANG'}}= @{$me->{'BENCHLANG'}};
    }
    if ($::lcsuite eq 'cpu2017'
            and grep { $_ eq 'F77' } @{$me->{'allBENCHLANG'}}) {
        # SPEC CPU uses F variables for F77 codes
        push @{$me->{'allBENCHLANG'}}, 'F';
    }

    # Set up the language-specific benchmark flags
    foreach my $blang ('', 'c', 'f', 'cxx', 'f77', 'fpp') {
        if (defined ${"${class}::bench_${blang}flags"}) {
            $me->{'BENCH_'.uc($blang).'FLAGS'} = ${"${class}::bench_${blang}flags"};
        }
    }
    $me->{'benchmark'}   = $me->{'num'}.'.'.$me->{'name'};
    $me->{'path'}        = $topdir;
    $me->{'base_exe'}    = [@{"${class}::base_exe"}];
    $me->{'EXEBASE'}     = [@{"${class}::base_exe"}];
    $me->{'config'}      = $config;
    $me->{'refs'}        = [ $me, $config ];
    $me->{'result_list'} = [ ];
    $me->{'added_files'} = { };
    $me->{'generated_files'} = { };
    $me->{'version'}     = ${"${class}::version"};
    $me->{'clean_between_builds'} = ${"${class}::clean_between_builds"} || 'no';
    for my $specdiffopt (qw( abstol reltol compwhite obiwan skiptol binary
                             skipabstol skipreltol skipobiwan floatcompare
                             ignorecase nansupport )) {
        $me->{$specdiffopt} = '' if !defined $me->{$specdiffopt};
    }
    if (!@{$me->{'base_exe'}}) {
        Log(0, "There are no executables listed in \@base_exe for ".$me->{'num'}.".".$me->{'name'}.".  Ignoring benchmark\n");
        return undef;
    }
    $me->{'srcalts'} = { };
    $me->{'srcsource'} = jp($me->path, $me->srcdir);

    return $me;
}

sub per_file_param_val {
    my ($me, $param, $size, $size_class, $tune, $file) = @_;
    my $val = $me->{$param} ne '' ? $me->{$param} : undef;
    my $result;
    if (ref($val) eq 'HASH') {
        if (exists($val->{$size}) && ref($val->{$size}) eq 'HASH') {
            $val = $val->{$size};
        } elsif (exists($val->{$size_class}) && ref($val->{$size_class}) eq 'HASH') {
            $val = $val->{$size_class};
        }
        if (exists($val->{$tune}) && ref($val->{$tune}) eq 'HASH') {
            $val = $val->{$tune};
        }
        if (exists $val->{$file}) {
            $result = $val->{$file};
        } elsif (ref ($val->{'default'}) eq 'HASH' &&
            exists $val->{'default'}{$file}) {
            $result = $val->{'default'}{$file};
        }
        if (!defined $result) {
            if (exists $val->{$tune} && ref($val->{$tune}) eq '') {
                $result = $val->{$tune};
            } elsif (exists $val->{$size} && ref($val->{$size}) eq '') {
                $result = $val->{$size};
            } elsif (exists $val->{$size_class} && ref($val->{$size_class}) eq '') {
                $result = $val->{$size_class};
            } elsif (exists $val->{$file} && ref($val->{$file}) eq '') {
                $result = $val->{$file};
            } else {
                $result = $val->{'default'};
            }
        }
    } else {
        $result = $val;
    }
    return $result;
}
sub per_file_param {
    my $val = per_file_param_val(@_);
    return istrue($val)?1:undef;
}

sub compwhite    { shift->per_file_param    ('compwhite'   , @_) }
sub floatcompare { shift->per_file_param    ('floatcompare', @_) }
sub calctol      { shift->per_file_param    ('calctol'     , @_) }
sub abstol       { shift->per_file_param_val('abstol'      , @_) }
sub reltol       { shift->per_file_param_val('reltol'      , @_) }
sub obiwan       { shift->per_file_param    ('obiwan'      , @_) }
sub skiptol      { shift->per_file_param_val('skiptol'     , @_) }
sub skipreltol   { shift->per_file_param_val('skipreltol'  , @_) }
sub skipabstol   { shift->per_file_param_val('skipabstol'  , @_) }
sub skipobiwan   { shift->per_file_param_val('skipobiwan'  , @_) }
sub binary       { shift->per_file_param    ('binary'      , @_) }
sub ignorecase   { shift->per_file_param_val('ignorecase'  , @_) }
sub nansupport   { shift->per_file_param_val('nansupport'  , @_) }

sub instance {
    my ($me, $config, $tune, $size, $label) = @_;

    my $child = bless { %$me }, ref($me);
    $child->{'config'}      = $config;
    $child->{'tune'}        = $tune;
    $child->{'label'}       = $label;
    $child->{'size'}        = $size;
    $child->{'size_class'}  = $me->get_size_class($size);
    $child->{'result_list'} = [];
    $child->{'iteration'}   = -1;
    my $bench = $child->benchmark;
    # Arrange the list of benchsets so that benchsets that generate output
    # will be searched first by accessor().
    my @sets = (
        reverse(sort $config->benchmark_in_sets(0, $bench)),
        reverse(sort $config->benchmark_in_sets(1, $bench)),
    );

    # All of these adjustments (except for label) should always happen
    unshift @sets, 'default' unless grep { $_ eq 'default' } @sets;
    my @tunes = ($tune);
    unshift @tunes, 'default' if $tune ne 'default';
    my @labels = ($label);
    unshift @labels, 'default' if $label ne 'default';

    $child->{'refs'} = [ $child,
        reverse ($config,
                 $config->ref_tree(basename(__FILE__).':'.__LINE__,
                                   [ @sets, $bench ],
                                   [ @tunes        ],
                                   [ @labels       ])
                )
        ];

    if ($child->basepeak == 2 &&
        !exists($child->{'basepeak'})) {
        # We've inherited this weird setting from the top level, so ignore
        # it.
        $child->{'basepeak'} = 0;
    } else {
        $child->{'basepeak'} = istrue($child->basepeak);
    }
    if (istrue($child->{'basepeak'})) {
        $child->{'smarttune'} = 'base';
        $child->{'refs'} = [ $child,
            reverse ($config,
                     $config->ref_tree(basename(__FILE__).':'.__LINE__,
                                       [ @sets, $bench     ],
                                       [ 'default', 'base' ],
                                       [ @labels           ])
                    )
            ];
    } else {
        $child->{'smarttune'} = $tune;
    }

    $child->{'srcalts'} = $me->srcalts;

    my $copies = $child->accessor_nowarn('copies');
    $child->{'copies'} = $copies;

    $child->{'threads'} = $child->threads;
    $child->{'ranks'} = $child->ranks;

    # Fix up the sources list, if necessary.  This isn't done in new() because
    # the benchmark may get its sources from another benchmark which hasn't
    # yet been instantiated at new() time.
    if ((::ref_type($child->sources) ne 'ARRAY') && (::ref_type($child->sources) ne 'HASH')) {
        # $child->sources contains the name of the benchmark whose sources
        # it will inherit.
        # Find out where the benchmark lives
        if (!exists ($child->benchmarks->{$child->sources})) {
            ::Log(0, "ERROR: Benchmark ".$child->sources." specified as source code source for ".$child->benchmark."\ncan not be found!\n");
            main::do_exit(1);
        }
        my $donor = $child->benchmarks->{$child->sources};
        my $tmptop = $donor->{'path'};
        $child->{'srcsource'} = jp($tmptop, $donor->srcdir);
        $child->{'sources'} = $donor->{'sources'};
        $child->{'srcalts'} = $donor->{'srcalts'};
        $child->{'deps'} = $donor->{'deps'};
        $child->{'srcdeps'} = $donor->{'srcdeps'};
    }

    if ($child->build_check(1, 0) || !$config->accessor_nowarn('nobuild')) {
        # Check the number of threads.  Maybe the benchmark can warn ahead of time
        # if the setting is bad.  Benchmark is responsible for logging any non-generic
        # error messages.
        if ($child->check_threads()) {
            ::Log(0, "ERROR: ".$me->name." (".$me->tune.") failed thread check with ".$child->{'threads'}." threads.\n");
            return undef;
        }
    }

    return $child;
}

sub descmode {
    my ($me, %opts) = @_;
    my @stuff = ();
    push @stuff, $me->benchmark unless $opts{'no_benchmark'};
    if (!$opts{'no_size'}) {
        my $size = $me->size;
        $size .= ' ('.$me->size_class.')' if ($me->size_class ne $size);
        push @stuff, $size;
    }
    push @stuff, $me->tune unless $opts{'no_tune'};
    push @stuff, $me->label unless $opts{'no_label'};
    push @stuff, 'threads:'.$me->{'threads'} unless ($opts{'no_threads'} or $me->{'threads'} <= 1 or ($::lcsuite eq 'cpu2017' and $me->runmode =~ /rate$/));
    return join(' ', @stuff);
}

sub workload_dirs {
    my ($me, $head, $size, $direction) = @_;

    $direction = '' if $direction eq 'base';

    # The "all" directory is always involved
    my @dirs = ( jp($head, 'all', $direction) );

    return @dirs unless $size ne '';

    # The default also includes the size-specific workload data directory
    unshift @dirs, jp($head, $size, $direction);

    return @dirs unless exists($me->{'workload_dirs'}->{$size});

    # If there are directories from which this workload size should inherit
    # files, add them here.
    if ((::ref_type($me->{'workload_dirs'}->{$size}) eq 'ARRAY')) {
        push @dirs, $me->handle_workload_dir_addition($head, $direction, $size, @{$me->{'workload_dirs'}->{$size}});
    } elsif ($me->{'workload_dirs'}->{$size} ne '') {
        push @dirs, $me->handle_workload_dir_addition($head, $direction, $size, $me->{'workload_dirs'}->{$size});
    }

    return @dirs;
}

sub handle_workload_dir_addition {
    my ($me, $head, $direction, $origsize, @dirs) = @_;
    my @rc = ();
    my %seen = ();

    foreach my $dir (@dirs) {
        if ((::ref_type($dir) eq 'ARRAY')) {
            # Remote benchmark, with benchmark name and workload size
            my ($bmark, @sizes) = @{$dir};
            if (@sizes > 0) {
                push @sizes, 'all';
            } else {
                @sizes = ('', 'all');
            }
            if (!exists ($me->benchmarks->{$bmark})) {
                ::Log(0, "Benchmark $bmark specified as $origsize workload source for $me->benchmark\ncan not be found!  Ignoring...\n");
                next;
            }
            my $donor = $me->benchmarks->{$bmark};
            foreach my $size (@sizes) {
                next if exists($seen{$size.$bmark});
                $seen{$size.$bmark}++;
                $size = $origsize unless defined($size) && $size ne '';
                my $donorpath = jp($donor->{'path'}, $donor->datadir, $size, $direction);
                if (-d $donorpath) {
                    push @rc, $donorpath;
                } elsif (exists($donor->{'workload_dirs'}->{$size})) {
                    push @rc, $donor->handle_workload_dir_addition(jp($donor->{'path'}, $donor->datadir), $direction, $size, @{$donor->{'workload_dirs'}->{$size}});
                }
            }
        } else {
            # Just a different size from the same benchmark
            push @rc, jp($head, $dir, $direction);
        }
    }

    return @rc;
}

sub copy_input_files_to {
    my ($me, $fast, $size, $srcdir, @paths) = @_;
    my $try_link = istrue($me->reportable) || istrue($me->link_input_files);

    # Make sure there's something to do
    return 0 unless (grep { defined } @paths);

    my ($files, $dirs) = $me->input_files_hash($size);
    if (!defined($files) || !defined($dirs)) {
        Log(0, "ERROR: couldn't get file list for $size input set\n");
        return 1;
    }
    my $genfile_hash = $me->generated_files_hash;

    # If we're linking/copying from a particular directory, add in the list
    # of generated files to the ones that are being copied/linked around
    if (defined($srcdir) and -d $srcdir) {
        foreach my $genfile (sort keys %$genfile_hash) {
            $files->{$genfile} = jp($srcdir, $genfile);
        }
    }

    for my $dir (@paths) {
        next unless defined($dir);
        # Create directories
        eval {
            main::mkpath($dir, 0, 0755);
            for my $reldir (sort keys %$dirs) {
                main::mkpath(jp($dir, $reldir), 0, 0755);
            }
        };
        if ($@) {
            Log(0, "ERROR: couldn't create destination directories: $@\n");
            return 1;
        }
    }

    # Copy files
    for my $file (sort keys %$files) {
        next if istrue($me->fake) and exists($genfile_hash->{$file});
        my $rc = copy_or_link($file, $srcdir, $files, $fast, $try_link, exists($genfile_hash->{$file}), \@paths);
        if ($rc == 2) {
            # hard link failed; try again without linking
            Log(10, "\nNOTICE: Linking $file from $srcdir failed: $!\n".
                "            ".Carp::longmess()."\n".
                "            Switching to copy mode.\n");
            $try_link = 0;
            redo;
        } elsif ($rc) {
            # copy failed; just bail
            Log(0, "ERROR: couldn't copy file '$file' for $size input set\n");
            return 1;
        }
    }

    # Generate inputs (if any), but only if linking isn't being done.  If it
    # is, assume that this has been run already for $srcdir
    unless ($try_link and defined($srcdir) and -d $srcdir) {
        my ($genpath) = (grep { defined } @paths);
        chdir($genpath);
        my $origwd = main::cwd();
        my @generation_commands;
        eval { @generation_commands = $me->generate_inputs() };
        if ($@) {
            Log(0, "ERROR: generate_inputs() failed for ".$me->benchmark."\n");
            Log(190, $@);
            chdir($origwd); # Back from whence we came
            return 1;
        }
        my @do_gen = ();
        @paths = grep { defined && $_ ne $genpath } @paths;


        # Go through the input generation commands and build a list of the
        # ones that generate files not already in $genpath.
        # If a file exists but there's no hash in the input set or the
        # generation object, then that counts as needing regeneration.
        GENERATION_OBJECT: foreach my $obj (@generation_commands) {
            if (!exists($obj->{'generates'})) {
                # Running a command to modify existing files isn't okay.
                Log(0, "ERROR: Input generation command $obj->{'command'} does not list files it generates.\n");
                chdir($origwd); # Back from whence we came
                return 1;
            }
            my ($genfile, $genhash);
            foreach my $fileref (@{$obj->{'generates'}}) {
                ($genfile, $genhash) = @{$fileref};
                # Since different workloads can have files with the same name
                # and different contents, it's necessary to disambiguate them.
                my $genfile_sumpath = jp($me->benchmark, $me->size, $genfile);
                if (! -f jp($genpath, $genfile)) {
                    # Doesn't exist; generate it
                    Log(81, "Missing '$genfile' in $genpath; going to run '$obj->{'command'}' to generate\n");
                    push @do_gen, $obj;
                    next GENERATION_OBJECT;
                } else {
                    # Does exist; check the hash
                    if (!defined($genhash)) {
                        # See if there's a stored checksum for this file; this
                        # can happen if this file has been generated before.
                        $genhash = (exists($me->{'generated_files'}->{$genfile}) && exists($::file_sums{$genfile_sumpath})) ? $::file_sums{$genfile_sumpath} : undef;

                    }
                    if (!defined($genhash)) {
                        # No checksum available to check the file; regenerate
                        # the file AND the checksum
                        Log(81, "Missing checksum for generated input file '$genfile' in $genpath; going to run '$obj->{'command'}' to regenerate\n");
                        push @do_gen, $obj;
                        next GENERATION_OBJECT;
                    }
                    my ($check_hash) = ::filedigest(jp($genpath, $genfile), length($genhash) * 4);
                    if (lc($check_hash) ne lc($genhash)) {
                        Log(81, "Checksum mismatch for generated input file '$genfile' in $genpath; going to run '$obj->{'command'}' to regenerate\n");
                        push @do_gen, $obj;
                        next GENERATION_OBJECT;
                    }
                    Log(81, "Checksum match for generated input file '$genfile' in $genpath\n");
                }
            }
            Log(81, "Skipping run of $obj->{'command'}; all generated files present and verified\n");
        }

        if (@do_gen) {
            my $tmpres = $me->make_empty_result(0, undef, 0);
            my ($threads, $user_set_env, %oldENV) = $me->setup_run_environment(0, 0);
            my $dirs = [ bless { 'dir' => $genpath }, 'Spec::Listfile::entry' ]; # This is Bad, if Spec::Listfile::entry ever changes
            # Input generation requires a pretty clean slate
            $me->unshift_ref({
                    'iter'                    => 0,
                    'command'                 => '',
                    'commandexe'              => '',
                    'copynum'                 => 0,
                    'fdocommand'              => '',
                    'phase'                   => 'input_generation',
                    'enable_monitor'          => 0,
                });
            my ($runfile, $cmdoutputs, undef, $specrun, $outfiles) = $me->prep_specrun($tmpres, $dirs,
                        $me->inputgenfile,
                        $me->inputgenoutfile,
                        \%oldENV, 1, 0, 0,
                        [
                            [ '-e', $me->inputgenerrfile    ],
                            [ '-o', $me->inputgenstdoutfile ],
                        ],
                        'generate_inputs', @do_gen);
            if ($tmpres->{'valid'} ne 'S' || !defined($runfile)) {
                $me->shift_ref();
                chdir($origwd); # Back from whence we came
                %ENV = %oldENV;
                return 1;
            }

            # This is the part where we actually do the input generation
            my $command = join (' ', @{$specrun});
            $me->command($command);
            my $specrun_wrapper;
            if ($me->do_monitor(0)) {
                $specrun_wrapper = $me->assemble_monitor_specrun_wrapper;
                $command = ::command_expand($specrun_wrapper, [ $me ]);
                $command = "echo \"$command\"" if istrue($me->fake);
            }
            my $outname = istrue($me->fake) ? 'input_generation' : undef;
            $me->shift_ref();
            my $start = time;
            my $rc = ::log_system($command, { 'basename' => $outname, 'env_vars' => istrue($me->env_vars) });
            my $stop = time;
            %ENV = %oldENV;
            my $elapsed = $stop-$start;
            Log(110, "Input generation total elapsed time = $elapsed seconds\n");
            if (defined($rc) && $rc) {
                Log(0, "\n".$me->benchmark.' input generation: '.$me->specrun.' non-zero return code (exit code='.WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n\n");
                $me->log_err_files($genpath, 1, undef);
                chdir($origwd); # Back from whence we came
                return 1;
            }

            my $fh = new IO::File "<$cmdoutputs";
            if (defined $fh) {
                my $error = 0;
                my @counts = ();
                while (defined(my $line = <$fh>)) {
                    # Make sure the environment gets into the debug log
                    Log(99, $line);
                    if ($line =~ m/child finished:\s*(\d+),\s*(\d+),\s*(\d+),\s*(?:sec=)?(\d+),\s*(?:nsec=)?(\d+),\s*(?:pid=)?\d+,\s*(?:rc=)?(\d+)/) {
                        my ($num, $ssec, $snsec, $esec, $ensec, $rc) =
                        ($1, $2, $3, $4, $5, $6);
                        $counts[$num] = 0 unless defined($counts[$num]);
                        $counts[$num]++;
                        if ($rc != 0) {
                            Log(0, "\n".$me->benchmark." input generation: non-zero return code (exit code=".WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n\n");
                            $me->log_err_files($genpath, 0, undef);
                            $error++;
                        }
                        Log(110, "Input generation elapsed time ($num:$counts[$num]) = ".($esec + ($ensec/1000000000))." seconds\n");
                    }
                }
                $fh->close;
                if ($error) {
                    chdir($origwd); # Back from whence we came
                    return 1;
                }
            } elsif (!istrue($me->fake)) {
                Log(0, "couldn't open input generation result file '$cmdoutputs'\n");
                chdir($origwd); # Back from whence we came
                return 1;
            }

            # Mark input generation artifacts for preservation
            foreach my $file (@$outfiles) {
                $me->{'preserve_files'}->{$file}++;
            }

            if (!istrue($me->fake)) {
                # Now generate (or verify) hashes for generated files
                foreach my $obj (@do_gen) {
                    my ($genfile, $genhash);
                    foreach my $fileref (@{$obj->{'generates'}}) {
                        ($genfile, $genhash) = @{$fileref};
                        # Since different workloads can have files with the same name
                        # and different contents, it's necessary to disambiguate them.
                        my $genfile_sumpath = jp($me->benchmark, $me->size, $genfile);
                        if (! -f jp($genpath, $genfile)) {
                            # Doesn't exist; this is a problem, as we just ran the program to generate it
                            Log(0, "ERROR: Generated file '$genfile' was not found in $genpath\n");
                            chdir($origwd); # Back from whence we came
                            return 1;
                        } else {
                            # Does exist; fix the permissions and check the hash
                            ::copy_perms(jp($genpath, $genfile), jp($genpath, $genfile), 0644);
                            if (!defined($genhash)) {
                                # See if there's a stored checksum for this
                                # file; this can happen if this file has been
                                # generated before.
                                $genhash = (exists($me->{'generated_files'}->{$genfile}) && exists($::file_sums{$genfile_sumpath})) ? $::file_sums{$genfile_sumpath} : undef;
                            }
                            my ($check_hash) = ::filedigest(jp($genpath, $genfile), defined($genhash) ? length($genhash) * 4 : 512);
                            if (defined($genhash)) {
                                # Checksum available; check it
                                if (lc($check_hash) ne lc($genhash)) {
                                    Log(0, "ERROR: Checksum of generated file '$genfile' in $genpath did not match expected\n");
                                    chdir($origwd); # Back from whence we came
                                    return 1;
                                }
                                Log(81, "Checksum match for generated input file '$genfile' in $genpath\n");
                            } else {
                                # No pre-made checksum; use the one that was just
                                # generated and store it for future reference
                                Log(81, "Checksum generated for generated input file '$genfile' in $genpath\n");
                                $me->{'generated_files'}->{$genfile} = $check_hash;
                                $files->{$genfile} = $genfile;
                                $::file_sums{$genfile_sumpath} = $check_hash;
                                my $refsize = stat($genfile);
                                $::file_size{$genfile_sumpath} = $refsize->size if (defined($refsize));
                            }

                            # Now arrange for the file to be copied to all the
                            # other directories (if any)
                            if (@paths) {
                                my $rc = copy_or_link($genfile, $genpath, $files, $fast, $try_link, 0, \@paths);
                                if ($rc == 2) {
                                    $try_link = 0;      # Probably already 0
                                } elsif ($rc) {
                                    chdir($origwd); # Back from whence we came
                                    return 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        chdir($origwd); # Back from whence we came
    }

    return 0;
}

sub copy_or_link {
    my ($file, $srcdir, $files, $fast, $try_link, $genhash_ok, $paths) = @_;

    if ($try_link and defined($srcdir) and -d $srcdir) {
        # Attempt to link the file first.  This assumes that the files
        # in $srcdir have already undergone whatever verification is
        # necessary.
        if (!main::link_file($srcdir, $file, $paths)) {
            return 2;
        }
    } else {
        if (!main::copy_file($files->{$file}, $file, $paths, !$fast, undef, $genhash_ok)) {
            return 1;
        }
    }
}

sub input_files_hash {
    my ($me, $size) = @_;
    my $head = jp($me->path, $me->datadir);

    $size = $me->size if ($size eq '');

    my @candidate_dirs = $me->workload_dirs($head, $size, $me->inputdir);

    my @dirs = ();
    for my $dir (@candidate_dirs) {
        unshift (@dirs, $dir) if -d $dir;
    }
    my ($files, $dirs) = main::build_tree_hash($me, \%::file_sums, @dirs);

    return ($files, $dirs);
}

sub input_files_base {
    my $me = shift;
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub input_files {
    my $me = shift;
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub input_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub compare_files_hash {
    my ($me, $size) = @_;
    my $head = jp($me->path, $me->datadir);

    $size = $me->size if ($size eq '');

    my @candidate_dirs = $me->workload_dirs($head, $size, $me->comparedir);

    my @dirs = ();
    for my $dir (@candidate_dirs) {
        unshift (@dirs, $dir) if -d $dir;
    }
    my ($files, $dirs) = main::build_tree_hash($me, \%::file_sums, @dirs);

    return ($files, $dirs);
}

sub compare_files_base {
    my $me = shift;
    my ($hash) = $me->compare_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub compare_files {
    my $me = shift;
    my ($hash) = $me->compare_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub compare_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->compare_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub output_files_hash {
    my ($me, $size) = @_;
    my $head = jp($me->path, $me->datadir);

    $size = $me->size if ($size eq '');

    my @candidate_dirs = $me->workload_dirs($head, $size, $me->outputdir);

    my @dirs = ();
    foreach my $dir (@candidate_dirs) {
        unshift (@dirs, $dir) if -d $dir;
    }

    return main::build_tree_hash($me, \%::file_sums, @dirs);
}

sub output_files_base {
    my $me = shift;
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub output_files {
    my $me = shift;
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub output_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub added_files_hash {
    my ($me) = @_;
    if (defined($me->{'added_files'}) && ref($me->{'added_files'}) eq 'HASH') {
        return $me->{'added_files'};
    } else {
        return {};
    }
}

sub added_files_base {
    my $me = shift;
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub added_files {
    my $me = shift;
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub added_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub generated_files_hash {
    my ($me) = @_;
    if (defined($me->{'generated_files'}) && ref($me->{'generated_files'}) eq 'HASH') {
        return $me->{'generated_files'};
    } else {
        return {};
    }
}

sub generated_files_base {
    my $me = shift;
    my ($hash) = $me->generated_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub generated_files {
    my $me = shift;
    my ($hash) = $me->generated_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub generated_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->generated_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub preserve_files_hash {
    my ($me) = @_;
    if (defined($me->{'preserve_files'}) && ref($me->{'preserve_files'}) eq 'HASH') {
        return $me->{'preserve_files'};
    } else {
        return {};
    }
}

sub preserve_files_base {
    my $me = shift;
    my ($hash) = $me->preserve_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub exe_files {
    my $me    = shift;
    my $tune  = $me->smarttune;
    my $label = $me->label;
    my $fdocommand = $me->accessor_nowarn('fdocommand');
    if (defined($fdocommand) && ($fdocommand ne '')) {
        return @{$me->base_exe};
    } else {
        return map { "${_}_$tune.$label" } @{$me->base_exe};
    }
}

sub exe_file {
    my $me = shift;
    return ($me->exe_files)[0];
}

sub exe_files_abs {
    my $me = shift;
    my $path = $me->path;
    if (::check_output_root($me->config, $me->output_root, 1)) {
        my $oldtop = ::make_path_re($me->top);
        my $newtop = $me->output_root;
        $path =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';
    my $head   = jp($path, $me->bindir, $subdir);
    return sort map { jp($head, $_) } $me->exe_files;
}

sub get_size_class {
    my ($me, $size) = @_;

    my @stuff = read_reftime('time', $size, $me->workload_dirs(jp($me->path, $me->datadir), $size, 'base'));
    return $stuff[2];
}

sub reference {
    my $me = shift;
    my ($ref, $size, $size_class) = read_reftime('time', $me->size, $me->workload_dirs(jp($me->path, $me->datadir), $me->size, 'base'));
    return 1 unless defined($ref);
    if ($size_class eq 'ref' && ($ref == 0)) {
        Log(0, "$size (ref) reference time for ".$me->descmode('no_size' => 1, 'no_threads' => 1)." == 0\n");
        return 1;
    };
    return $ref;
}

sub reference_power {
    my $me = shift;
    my ($ref, $junk) = read_reftime('power', $me->size, $me->workload_dirs(jp($me->path, $me->datadir), $me->size, 'base'));
    return 1 unless defined($ref);
    return $ref;
}

sub supports_workload {
    my ($me, $size) = @_;
    my @rc = read_reftime_silent('time', $size, $me->workload_dirs(jp($me->path, $me->datadir), $size, 'base'));
    return 1 if @rc > 1;
    return 0;
}

sub read_reftime {
    my ($name, $size, @dirs) = @_;
    my @rc = read_reftime_silent($name, $size, @dirs);
    if (@rc == 0) {
        # If we get here, no reftime files were found, so log the list
        Log(0, "read_reftime: 'ref$name' could not be found in any of the following directories:\n   ".join("\n   ", grep { !m#[\\/]all[\\/]?$# } @dirs)."\n");
        return undef;
    }
    return @rc;
}

sub read_reftime_silent {
    my ($name, $size, @dirs) = @_;
    my @missing = ();

    foreach my $dir (@dirs) {
        next if ($dir =~ m#[\\/]all[\\/]?$#); # 'all' never has a reftime file
        my $file = jp($dir, 'ref'.$name);

        if (!-f $file) {
            push @missing, $dir;
            next;
        };
        my ($line) = grep { /^$size\s/ } main::read_file($file);
        chomp($line);
        my ($size, $size_class, $ref) = split(/\s+/, $line);

        return ($ref, $size, $size_class);
    }

    return undef;
}

sub Log     { main::Log(@_); }
sub jp      { main::joinpaths(@_); }
sub istrue  { main::istrue(@_); }
sub src     { my $me = shift; return $me->{'srcsource'} };
sub apply_diff { main::apply_diff(@_); }

sub verify_binaries {
    my $me = shift;
    return 1 if istrue($me->reportable);
    return $me->accessor_nowarn('verify_binaries');
}

sub make {
    my $me = shift;
    return 'specmake' if istrue($me->reportable);
    return $me->accessor_nowarn('make');
}

sub make_no_clobber {
    my $me = shift;
    return 0 if istrue($me->reportable);
    return $me->accessor_nowarn('make_no_clobber');
}

# Check to make sure that the input set exists.
sub check_size {
    my ($me, $size) = @_;
    $size = $me->size unless defined($size) && $size ne '';
    my $datadir = jp($me->path, $me->datadir);

    my @dirs = $me->workload_dirs($datadir, $size, 'base');
    my $found = 0;
    for my $dir (grep { !m#[\\/]all[\\/]?$# } @dirs) {
        if (-f jp($dir, 'reftime')) {
            $found++;
            Log(99, "Found reftime file in $dir\n");
            last;
        }
    }
    if ($found == 0) {
        Log(130, "ERROR: No reftime files found in any of ".join(', ', grep { !m#[\\/]all[\\/]?$# } @dirs)."\n");
        return 0;
    }

    for my $direction ($me->inputdir, $me->outputdir) {
        DIRS:   for my $dir (@dirs) {
            if (-d jp($dir, $direction)) {
                $found++;
                Log(99, "Found $direction directory under $dir\n");
                last DIRS;
            }
        }
    }
    if ($found < 3) {   # Need inputs AND outputs
        Log(130, "ERROR: Missing some ".$me->inputdir." or ".$me->outputdir." directories\n");
        return 0;
    }

    return 1;
}

sub build_check {
    my ($me, $check_exe, $check_options) = @_;
    $check_exe = 1 unless defined($check_exe);
    $check_options = 1 unless defined($check_options);
    my $verify_binaries = istrue($me->verify_binaries) || istrue($me->reportable);
    my $ok = 1;

    if (!$check_exe and !$check_options) {
        # This should really never happen
        confess("build_check called without options to check anything");
    }

    # If there are no hashes then we will definitely fail the compare
    if ($check_options and $verify_binaries and ($me->accessor_nowarn('opthash') eq '')) {
        Log(130, "When checking options for ".join(',', $me->exe_files_abs).", no checksums were\n  found in the config file.  They will be installed after build.\n");
        $ok = 0;
    }
    if ($check_exe and $verify_binaries and ($me->accessor_nowarn('exehash') eq '')) {
        Log(130, "When checking executables (".join(',', $me->exe_files_abs)."), no checksums were\n  found in the config file.  They will be installed after build.\n");
        $ok = 0;
    }

    # Build a hash of the executable files
    my $bits = $me->accessor_nowarn('exehash_bits') || 512256;
    my $ctx = ::get_hash_context($bits);

    if ($ok and $check_exe) {
        for my $name (sort $me->exe_files_abs) {
            if ((! -e $name) || ($^O !~ /MSWin/i && ! -x $name)) {
                if (!-e $name) {
                    Log(190, "$name does not exist\n");
                } elsif (!-x $name) {
                    Log(190, "$name exists, but is not executable\n");
                    Log(190, "stat for $name returns: ".join(', ', @{stat($name)})."\n") if (-e $name);
                }
                $ok = 0;
            }
            if (-f $name) {
                eval { $ctx->addfile($name, 'b') };
                if ($@) {
                    Log (0, "Can't open file '$name' for reading:\n\t$@\n");
                }
            }
        }
    }
    if ($ok and $verify_binaries) {
        if ($check_exe) {
            my $genexehash = $ctx->hexdigest;
            if ($genexehash ne $me->accessor_nowarn('exehash')) {
                Log(130, "Checksum mismatch for executables (stored: ".$me->accessor_nowarn('exehash').")\n");
                $ok = 1;
            }
        }
        if ($check_options) {
            # When generating options to for binary check, log of the options is suppressed unless the log level is
            # 90 or higher, since this is voluminous and generally uninteresting in most cases.
            my $genopthash = $me->option_cksum(Log(90));
            if ($genopthash ne $me->accessor_nowarn('opthash')) {
                Log(130, "Checksum mismatch for options (stored: ".$me->accessor_nowarn('opthash').")\n");
                $ok = 0;
            }
        }
    }
    Log(87, "build_check('".$me->descmode('no_size' => 1, 'no_threads' => 1)."' ($me), check_exe=$check_exe, check_options=$check_options) called".Carp::longmess()."\n") unless $ok;

    return $ok;
}

sub form_makefiles {
    my $me = shift;
    my %vars;
    my %deps;

    my $tune  = $me->smarttune;
    my $label = $me->label;
    my $bench = $me->benchmark;

    my $srcref = $me->sources;
    my %sources;
    my @targets;

    if (ref($srcref) eq 'ARRAY') {
        $sources{$me->base_exe->[0]} = [ @{$srcref} ];
        @targets = ($me->base_exe->[0]);
    } else {
        %sources = %{$srcref};
        @targets = @{$me->base_exe};
    }

    my @output_files = ();
    if (istrue($me->feedback)) {
        # Assume that it's okay.  If it's not, the run will be stopped after
        # the makefiles are formed.  In any case, the list of output files
        # we're adding here is just for the benefit of fdoclean, which won't
        # happen unless FDO is happening.
        my ($filehash) = $me->output_files_hash($me->train_with);
        @output_files = sort keys %{$filehash} if (::ref_type($filehash) eq 'HASH');
    }

    foreach my $exe (@targets) {
        $vars{$exe} = [];
        push @{$vars{$exe}}, "TUNE="     .$tune;
        push @{$vars{$exe}}, "LABEL="    .$label;
        # Do the stuff that used to be in src/Makefile
        push @{$vars{$exe}}, "NUMBER="   .$me->num;
        push @{$vars{$exe}}, "NAME="     .$me->name;
        push @{$vars{$exe}}, ::wrap_join(75, ' ', "\t ", " \\",
            ('SOURCES=', @{$sources{$exe}}));
        push @{$vars{$exe}}, 'EXEBASE='  .$exe;
        push @{$vars{$exe}}, 'NEED_MATH='.$me->need_math;
        my @benchlang;
        if (ref($me->BENCHLANG) eq 'HASH') {
            if (!exists($me->BENCHLANG->{$exe})) {
                Log(0, "ERROR: No benchlang is defined for target $exe\n");
                main::do_exit(1);
            }
            if (ref($me->BENCHLANG->{$exe}) eq 'ARRAY') {
                @benchlang = @{$me->BENCHLANG->{$exe}};
            } else {
                @benchlang = split(/[\s,]+/, $me->BENCHLANG->{$exe});
            }
            push @{$vars{$exe}}, 'BENCHLANG='.join(' ', @benchlang);
        } else {
            @benchlang = @{$me->BENCHLANG};
            push @{$vars{$exe}}, 'BENCHLANG='.join(' ', @benchlang);
        }
        push @{$vars{$exe}}, '';

        foreach my $var (sort $me->list_keys) {
            # Exclude some variables that we don't want in the makefile
            next if $var =~ /^(?:(?:pp|raw)txtconfig|oldhashes|cfidx_|toolsver|baggage|compile_options|rawcompile_options|compiler_version|rawcompiler_version|exehash|opthash|flags(?:url)?|ref_added|nc\d*$|nc_is_(?:cd|na)|BENCHLANG|sources)/;
            my $val = $me->accessor($var);

            # Don't want references in makefile either
            if (ref ($val) eq '') {
                # Escape the escapes
                $val =~ s/\\/\\\\/go;
                $val =~ s/(\r\n|\n)/\\$1/go;
                $val =~ s/\#/\\\#/go;
                push (@{$vars{$exe}}, sprintf ('%-16s = %s', $var, $val));
            } elsif ((::ref_type($val) eq 'HASH')) {
                if (exists($val->{$exe})) {
                    push (@{$vars{$exe}}, sprintf ('%-16s = %s', $var, $val->{$exe}));
                } # else ignore it
            }
        }
        push @{$vars{$exe}}, sprintf ('%-16s = %s', 'OUTPUT_RMFILES', join(' ', @output_files));

        $vars{$exe} = join ("\n", @{$vars{$exe}}) . "\n";

        # Add in dependencies, if any
        push @{$deps{$exe}}, '','# These are the build dependencies', '';
        my (%objdeps, %srcdeps);
        if (exists($me->deps->{$exe}) &&
            (::ref_type($me->deps->{$exe}) eq 'HASH')) {
            %objdeps = %{$me->deps->{$exe}};
        } else {
            %objdeps = %{$me->deps};
        }
        if (exists($me->srcdeps->{$exe}) &&
            (::ref_type($me->srcdeps->{$exe}) eq 'HASH')) {
            %srcdeps = %{$me->srcdeps->{$exe}};
        } else {
            %srcdeps = %{$me->srcdeps};
        }

        # Object dependencies are for things like F9x modules which must
        # actually be built before the object in question.
        foreach my $deptarget (sort keys %objdeps) {
            my $deps = $objdeps{$deptarget};
            my (@normaldeps, @ppdeps);

            # Coerce the dependencies into a form that we like
            if (ref($deps) eq '') {
                # Not an array, just a single entry
                $deps = [ $deps ];
            } elsif (ref($deps) ne 'ARRAY') {
                Log(0, "WARNING: Dependency value for $deptarget is not a scalar or array; ignoring.\n");
                next;
            }

            # Figure out which will need to be preprocessed and which won't
            foreach my $dep (@{$deps}) {
                if ($dep =~ /(\S+)\.F(90|95|)$/o) {
                    push @ppdeps, "$1.fppized";
                } else {
                    push @normaldeps, $dep;
                }
            }

            # Change the name of the target, if necessary
            my ($ppname, $fulltarget) = ($deptarget, '');
            if ($deptarget =~ /(\S+)\.F(90|95|)$/o) {
                $fulltarget = "$1.fppized";
                $ppname = "$fulltarget.f$2";
            } else {
                $fulltarget = "\$(basename $deptarget)";
            }

            # The end result
            push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), $fulltarget): $ppname \$(addsuffix \$(OBJ),\$(basename ".join(' ', sort @normaldeps).") ".join(' ', sort @ppdeps).")";
        }

        # Source dependencies are for things like #include files for C
        foreach my $deptarget (sort keys %srcdeps) {
            my $deps = $srcdeps{$deptarget};
            if (ref($deps) eq '') {
                push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), \$(basename $deptarget)): $deptarget $deps";
            } elsif (ref($deps) eq 'ARRAY') {
                push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), \$(basename $deptarget)): $deptarget ".join(' ', sort @{$deps});
            } else {
                Log(0, "WARNING: Dependency value for $deptarget is not a scalar or array; ignoring.\n");
            }
        }
        push @{$deps{$exe}}, '# End dependencies';
    }

    foreach my $exe (keys %deps) {
        $deps{$exe} = join ("\n", sort @{$deps{$exe}}) . "\n";
    }
    if (@targets == 1) {
        # No per-executable deps
        $deps{''} = $deps{$targets[0]};
        delete $deps{$targets[0]};
    }
    return (\%deps, %vars);
}

sub write_makefiles {
    my ($me, $path, $varname, $depname, $no_write, $log) = @_;
    my @files = ();
    my ($deps, %vars) = $me->form_makefiles;
    my ($filename, $fh);

    if (!$no_write) {
        # Dump the dependencies
        foreach my $exe (sort keys %{$deps}) {
            my $tmpname = $depname;
            my $tmpexe = $exe;
            $tmpexe .= '.' unless ($exe eq ''); # Add the trailing .
            $tmpname =~ s/%T/$tmpexe/;
            $filename = jp($path, $tmpname);
            Log (150, "Wrote to makefile '$filename':\n", \$deps->{$exe}) if $log;
            $fh = new IO::File;
            if (!$fh->open(">$filename")) {
                Log(0, "Can't write makefile '$filename': $!\n");
                main::do_exit(1);
            }
            $fh->print($deps->{$exe});
            $fh->close();
            if (-s $filename < length($deps->{$exe})) {
                Log(0, "\nERROR: $filename is short!\n       Please check for sufficient disk space.\n");
                main::do_exit(1);
            }
        }
    }

    my @targets = sort keys %vars;
    foreach my $target (sort keys %vars) {
        # Dump the variables
        $filename = jp($path, $varname);
        # Benchmarks with a single executable get 'Makefile.spec'; all
        # others get multiple makefiles with the name of the target
        # in the filename.
        if ($target eq $me->baseexe && (@targets+0) == 1) {
            $filename =~ s/YYYtArGeTYYYspec/spec/;
        } else {
            $filename =~ s/YYYtArGeTYYYspec/${target}.spec/;
        }
        if (!$no_write) {
            $fh = new IO::File;
            if (!$fh->open(">$filename")) {
                Log(0, "Can't write makefile '$filename': $!\n");
                main::do_exit(1);
            }
            Log (150, "Wrote to makefile '$filename':\n", \$vars{$target}) if $log;
            $fh->print($vars{$target});
            $fh->close();
            if (-s $filename < length($vars{$target})) {
                Log(0, "\nERROR: $filename is short!\n       Please check for sufficient disk space.\n");
                main::do_exit(1);
            }
        }
        push @files, $filename;
    }
    return @files;
}

sub option_cksum {
    my ($me, $log, $opts) = @_;
    my $bits = $me->accessor_nowarn('exehash_bits') || 512256;
    $log = 1 unless defined($log);
    $opts = $me->get_options($log) unless $opts ne '';

    my $ctx = ::get_hash_context($bits);
    # WHY can I get away with splitting on just '\n'?  read_compile_options
    # normalizes all line endings to \n!
    foreach my $line (split(/\n/, $opts)) {
        # Normalize whitespace
        $line =~ tr/ \012\015\011/ /s;
        $ctx->add($line);
    }
    my $rc = $ctx->hexdigest;

    return $rc;
}

# Generate a list of build options that would actually be used for a benchmark.
# Lots of this code is similar to what's in build(), so changes there _may_
# need to be reflected here.
sub get_options {
    my ($me, $log) = @_;
    my $origwd = main::cwd();
    $origwd = $me->top unless -d $origwd;
    my $top = $me->top;

    # Binaries built using make_no_clobber aren't usable for reportable
    # runs, so make sure that we get a value of '0' for make_no_clobber
    # if reportable is set.
    # This is only effective if the user hasn't specified --make_no_clobber
    # on the command line.  The check for that is in runcpu.
    if (istrue($me->reportable)) {
        $me->{'make_no_clobber'} = 0;
    }

    # Now generate options from specmake
    my $tmpdir = ::get_tmp_directory($me, 1, 'options.'.$me->num.'.'.$me->name.'.'.$me->tune);
    if ( ! -d $tmpdir ) {
        # Something went wrong!
        Log(0, "ERROR: Temporary directory \"$tmpdir\" couldn't be created\n");
        return undef;
    }
    chdir($tmpdir);

    my $langref = {};
    $langref->{'commandexe'} = ($me->exe_files)[0];
    $langref->{'baseexe'} = ($me->base_exe)[0]->[0];
    $me->unshift_ref($langref);

    # Do pre-build stuff (but not for real)
    if ($me->pre_build($tmpdir, 0, undef, undef)) {
        Log(0, "\n\nERROR: benchmark pre-build function failed\n\n");
        $me->shift_ref;
        return undef;
    }

    # Actually write out the makefiles and get a list of targets
    my @makefiles = $me->write_makefiles($tmpdir, $me->makefile_template,
        'Makefile.%Tdeps', 0, $log);
    my @targets = map { basename($_) =~ m/Makefile\.(.*)\.spec/o; $1 } @makefiles;

    # What's make?
    my $make = $me->make;
    my $makeflags = '';
    $makeflags .= ' --output-sync' if ::specmake_can($make, '--output-sync');
    $makeflags .= ' '.$me->makeflags if ($me->makeflags ne '');

    # Check to see if feedback is being used.
    my ($fdo, @pass) = $me->feedback_passes();
    if ($fdo) {
        $fdo = 0 if ($::lcsuite eq 'mpi2007');
        $fdo = 0 if ($me->smarttune eq 'base');
    }

    my ($fdo_defaults, @commands);
    if ($fdo) {
        ($fdo_defaults, @commands) = $me->fdo_command_setup(\@targets, $make.$makeflags, @pass);
        $me->push_ref($fdo_defaults);
    } else {
        @pass = ( 0 );
        # Somewhat magical value(s) for non-FDO builds
        @commands = map { 'fdo_make_pass_'.$_ } @targets;
    }

    # Add in mandatory options
    my $options = $me->get_mandatory_option_cksum_items(($fdo) ? 'train_with' : '');

    my %compiler_version = ();

    my $rc = 0;
    foreach my $cmd (@commands) {
        my $val = $me->accessor_nowarn($cmd);
        my $pass = '';
        my $target = '';
        if ($cmd =~ m/^fdo_make_pass(\d*)_(.*)$/) {
            $pass = $1;
            $target = $2;
        } elsif ($cmd =~ m/(\d+)$/) {
            $pass = $1;
        }
        next if $fdo && $val =~ m/^\s*$/;
        if ($cmd =~ /^fdo_run/) {
            $options .= "RUN$pass: $val\n" if $fdo;
        } else {
            if ($fdo) {
                # Don't record options whose default values have not been
                # overridden by the user.  This will keep changes in
                # makeflags (for example) from causing rebuilds.  This mimics
                # the v1.0 behavior.
                $options .= "$cmd: $val\n" if ($val ne $fdo_defaults->{$cmd});
            } elsif ($target ne '') {
                $options .= "Options for ${target}:\n";
            }
            if ($cmd =~ m/^fdo_make_pass/) {
                my $exe = ($target ne '') ? ".$target" : '';
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                my $passflag = ($pass ne '') ? " FDO=PASS$pass" : '';
                my $file = "options$pass$exe";
                $rc = ::log_system("$make -f $top/benchspec/Makefile.defaults options$targetflag$passflag",
                            {
                                'basename' => $file,
                                'repl'     => [ { 'teeout' => 0 }, $me ],
                                'nooutput' => 1,
                                'env_vars' => istrue($me->env_vars),
                            });
                if ($rc) {
                    Log(0, "\n\nERROR running '$make options$targetflag$passflag'\n\n");
                    $me->shift_ref;
                    return undef;
                }
                $options .= read_compile_options("${file}.out", $pass, 0);
                unlink "${file}.out" unless istrue($me->accessor_nowarn('keeptmp'));
                $file =~ s/options/compiler-version/;
                $rc = ::log_system("$make -f $top/benchspec/Makefile.defaults compiler-version$targetflag$passflag",
                                    {
                                        'basename' => $file,
                                        'repl'     => [ { 'teeout' => 0 }, $me ],
                                        'nooutput' => 1,
                                        'env_vars' => istrue($me->env_vars),
                                    });
                if ($rc) {
                    Log(0, "\n\nERROR running '$make compiler-version$targetflag$passflag'\n\n");
                    $me->shift_ref;
                    return undef;
                }
                ($rc, my $verinfo) = read_compiler_version("${file}.out", $pass);
                if ($rc) {
                    Log(0, whine_compiler_version());
                    $me->shift_ref;
                    return undef;
                }
                $compiler_version{$verinfo}++;
            }
        }
    }
    unlink @makefiles unless istrue($me->accessor_nowarn('keeptmp'));

    chdir($origwd); # Back from whence we came
    remove_tree($tmpdir, { 'verbose' => 0, 'safe' => 1 }) unless istrue($me->accessor_nowarn('keeptmp'));

    my $compiler_version = join("\n", sort keys %compiler_version);
    if ($log) {
        Log(30, "option_cksum list contains ------------------------------------\n");
        Log(30, "$options");
        Log(30, "------------------------------------ end option_cksum list\n");
        Log(30, "compiler_version list contains ------------------------------------\n");
        Log(30, "$compiler_version");
        Log(30, "----------------------------------------- end compiler_version list\n");
    }
    return wantarray ? ($options, $compiler_version) : $options;
}

sub build {
    my ($me, $directory, $setup) = @_;
    my $rc;
    my $bench = $me->benchmark;
    my ($fdo, @pass);
    my $valid_build = 1;
    my $compile_options = '';
    my $path = $directory->path;
    my $ownpath = $me->path;
    if (::check_output_root($me->config, $me->output_root, 0)) {
        my $oldtop = ::make_path_re($me->top);
        my $newtop = $me->output_root;
        $ownpath =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';
    my $no_clobber = istrue($me->make_no_clobber);
    my $os_ext = $me->os_exe_ext;

    $valid_build = 0 if istrue($me->fake);

    # Get a pointer to where we update our build status info
    my $opthashref    = $me->config;
    for my $key ($me->benchmark, $me->smarttune, $me->label) {
        if (!exists $opthashref->{$key} || ref($opthashref->{$key} ne 'HASH')) {
            $opthashref->{$key} = {};
        }
        $opthashref = $opthashref->{$key};
    }
    $opthashref->{'changedhash'} = 0;
    my $baggage;
    if (defined($opthashref->{'baggage'})) {
        # Keep only baggage not related to src.alts, as those will be rewritten as necessary.
        $baggage = join("\n", grep { !/^note:.*src.alt/i } split(/\n/, $opthashref->{'baggage'}));
    } else {
        $baggage = '';
    }
    $opthashref->{'baggage'} = '';
    my %compiler_version = ();

    if (!istrue($me->fake) && !istrue($me->make_no_clobber)) {
        # First things first, remove any existing binaries with these names,
        # this makes sure that if the build fails any pre-existing binaries are
        # erased
        for my $file ($me->exe_files_abs) {
            if (-f $file && !unlink $file) {
                Log(0, "Can't remove file '$file': $!\n");
                main::do_exit(1);
            }
            # Take care of the auxiliary bundle
            $file =~ s/\Q$os_ext\E// if $os_ext ne '';
            $file .= '.aux.tar';
            if (-f $file && !unlink $file) {
                Log(0, "Can't remove file '$file': $!\n");
                main::do_exit(1);
            }
        }
    }

    if (istrue($me->accessor_nowarn('fail')) ||
        istrue($me->accessor_nowarn('fail_build'))) {
        Log(0, "ERROR: fail or fail_build set for this benchmark\n");
        $me->release($directory);
        $me->compile_error_result('CE', 'failed by request');
        return 1;
    }

    my $langref = {};
    $langref->{'commandexe'} = ($me->exe_files)[0];
    $langref->{'baseexe'} = ($me->base_exe)[0]->[0];
    $me->unshift_ref($langref);

    if ( $setup ||
        ! istrue($me->make_no_clobber) ||
        ! -f jp ( $path, 'Makefile' )) {
        $no_clobber = 0;        # Must turn this off for makefiles to be made

        if (! -d $me->src()) {
            Log(0, "ERROR: src subdirectory (".$me->src().") for ".$me->benchmark." is missing!\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'MISSING src DIRECTORY');
            return 1;
        }

        if (!::rmpath($path)) { # It's probably not there
            eval { main::mkpath($path) };
            if ($@) {
                Log(0, "ERROR: Cannot create build directory for ".$me->benchmark.": $@\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', 'COULD NOT CREATE BUILD DIRECTORY');
                return 1;
            }
            Log(9, "   Creating directory at '$path' for ".$me->descmode('no_size' => 1, 'no_threads' => 1)." build\n");
        } else {
            Log(9, "   Using existing directory at '$path' for ".$me->descmode('no_size' => 1, 'no_threads' => 1)." build\n");
        }

        # Copy the src directory, but leave out the src.alts
        if (!main::copy_tree($me->src(), $directory->path(), undef, [qw(src.alt .svn .git .gitignore)], !istrue($me->strict_rundir_verify))) {
            Log(0, "ERROR: src directory for ".$me->benchmark." contains corrupt files.\n");
            Log(0, "       Is your SPEC $::suite distribution corrupt, or have you changed any\n");
            Log(0, "       of the files listed above?\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'CORRUPT src DIRECTORY');
            return 1;
        }
        if ($me->pre_build($directory->path(), 1, undef, undef)) {
            Log(0, "ERROR: pre-build setup failed for ".$me->benchmark."\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'pre-build FAILED');
            return 1;
        }

##################################
# This is where we apply src.alts!
##################################
        my @srcalts = $me->get_srcalt_list();

        # This happens in several stages.  First, make sure that all the
        # src.alts that have been asked for are available.
        my $srcalt_applied = 0;
        foreach my $srcalt (@srcalts) {
            if (!exists($me->srcalts->{$srcalt})) {
                Log(103, "ERROR: Requested src.alt \"$srcalt\" does not exist!  Build failed.\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', "src.alt \"$srcalt\" not found");
                return 1;
            }
        }
        my %touched = ();
        # Next, copy all of the _new_ files from all of the src.alts into
        # the source directory.  Don't just copy blindly; do only the ones
        # listed as new in the src.alt.  (This is to not cause errors
        # when testing against the original src.alt directory.)
        # Though it should NOT be possible for a src.alt to modify a file
        # introduced by another (since the file won't have been in the
        # original src directory when the src.alt was made), let's be sort
        # of safe and mark all of the new ones as touched.
        my $top = $me->top;
        foreach my $srcalt (@srcalts) {
            my $saref = $me->srcalts->{$srcalt};
            my $srcaltpath = ::make_path_re(jp($me->src(), 'src.alt', $saref->{'name'}));
            my $dest = $directory->path();
            foreach my $newfile (grep { m{^(?:$top[/\\]?)?benchspec[/\\]}o } sort keys %{$saref->{'filehashes'}}) {
                # Skip README files; if there are multiple src.alts, one will
                # stomp the other, and chaos will ensue.
                next if $newfile =~ m{/README$};
                my $shortpath = $newfile;
                $shortpath =~ s{$srcaltpath[/\\]?}{};
                # Each "new" file's path will start will benchspec/
                if (!main::copy_file($newfile, $shortpath, [ $dest ],
                        $::check_integrity && istrue($me->strict_rundir_verify), $saref->{'filehashes'}, 0)) {
                    Log(0, "ERROR: src.alt \'$saref->{'name'}\' contains corrupt files.\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'CORRUPT src.alt DIRECTORY');
                    return 1;
                } else {
                    $touched{jp($dest, $shortpath)}++;
                }
            }
        }

        # Now that all the files have been copied in, apply the diffs to
        # the existing files.
        foreach my $srcalt (@srcalts) {
            my $saref = $me->srcalts->{$srcalt};
            my $dest = $directory->path();
            foreach my $difffile (sort keys %{$saref->{'diffs'}}) {
                my $difftext = decode_base64($saref->{'diffs'}->{$difffile});
                if ($::check_integrity) {
                    my $diffhash = ::scalardigest($difftext, length($saref->{'diffhashes'}->{$difffile}) * 4);
                    if ($diffhash ne $saref->{'diffhashes'}->{$difffile}) {
                        Log(0, "ERROR: src.alt \'$saref->{'name'}\' contains corrupt difference information.\n");
                        $me->shift_ref;
                        $me->release($directory);
                        $me->compile_error_result('CE', 'CORRUPT src.alt CONTROL FILE DIFFS (HASHES)');
                        return 1;
                    }
                }
                my $s = ::new_safe_compartment(undef, 1);
                my $hunks = $s->reval($difftext);
                if ($@ or !defined($hunks)) {
                    Log(0, "ERROR: src.alt \'$saref->{'name'}\' has corrupted control file: $@\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'CORRUPT src.alt CONTROL FILE DIFFS (SYNTAX)');
                    return 1;
                }

                my ($newsum, $offset, $ok) = apply_diff(jp($dest, $difffile), $hunks);
                # Application failed if application of diff
                # 1. failed (duh)
                # 2. succeeded with offset and file not previously touched
                # 3. succeeded with no offset and checksum mismatch
                if (!$ok ||
                    (!$touched{$difffile} && ($offset ||
                            ($newsum ne $saref->{'filehashes'}->{$difffile})))) {
                    if (!$ok) {
                        Log(0, "ERROR: application of diff failed\n");
                    } elsif (!$touched{$difffile} && $offset) {
                        Log(0, "ERROR: diff application offsets needed for previously untouched file\n");
                    } elsif (!$touched{$difffile} && ($newsum ne $saref->{'filehashes'}->{$difffile})) {
                        Log(0, "ERROR: checksum mismatch for previously untouched file\n");
                    }
                    Log(0, "ERROR: application of src.alt \'$saref->{'name'}\' failed!\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'src.alt APPLICATION FAILED');
                    return 1;
                }
                $touched{$difffile}++;
            }
            # If we get to here, the src.alt was applied successfully
            my $tmpstr = $me->note_srcalts($opthashref, 0, $srcalt);
            Log(0, "$tmpstr\n") if $tmpstr ne '';
        }
        my $origmakefile = jp($me->src,"Makefile.${main::lcsuite}");
        $origmakefile = jp($me->src,'Makefile') if (!-f $origmakefile);
        if (!main::copy_file($origmakefile, 'Makefile', [$path], istrue($me->strict_rundir_verify), undef, 0)) {
            Log(0, "ERROR: Failed copying makefile into build directory!\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'Build directory setup FAILED');
            return 1;
        }
    } else {
        $valid_build = 0;
    }

    if (!chdir($path)) {
        Log(0, "Couldn't chdir to $path: $!\n");
    }

    main::monitor_shell('build_pre_bench', $me);

    my @makefiles = $me->write_makefiles($path, $me->makefile_template,
        'Makefile.%Tdeps', $no_clobber, 0);
    my @targets = map { basename($_) =~ m/Makefile\.(.*)\.spec/o; $1 } @makefiles;

    if ($setup) {
        $me->release($directory);
        return 0;
    }

    my $compile_start = time;  ## used by the following log statement
    Log(160, "  Compile for '$bench' started at: ".::timeformat('date-time', $compile_start)." ($compile_start)\n");

    my $make = $me->make;
    $make .= ' -n' if istrue($me->fake);
    $make .= ' --output-sync' if ::specmake_can($make, '--output-sync');
    $make .= ' '.$me->makeflags if ($me->makeflags ne '');

    # Check to see if feedback is being used.
    ($fdo, @pass) = $me->feedback_passes();

    # Disable feedback where it's not allowed
    if ($fdo) {
        # Feedback is not allowed at all in MPI2007
        if (# CVT2DEV: 0 and
            $::lcsuite eq 'mpi2007')
        {
            Log(0, "WARNING: Feedback-directed optimization is not allowed. FDO directives\n");
            Log(0, "         will be ignored.\n");
            undef @pass;
            $fdo = 0;
        }

        # Feedback is only allowed in peak for CPU
        if (# CVT2DEV: 0 and
            $::lcsuite =~ /^cpu/ and $me->smarttune eq 'base')
        {
            Log(0, "WARNING: Feedback-directed optimization is not allowed for base tuning;\n");
            Log(0, "         Ignoring FDO directives for this build.\n");
            undef @pass;
            $fdo = 0;
        }

        # Feedback builds must use a training workload that exists
        if (!$me->check_size($me->train_with)) {
            Log(0, "ERROR: $me->{'name'} does not support training workload ". $me->train_with. " (specified by train_with)\n");
            $me->release($directory);
            $me->compile_error_result('CE', 'train_with specifies non-existent workload');
            return 1;
        }

        # Feedback builds must use a training workload that's classified as one
        if (# CVT2DEV: 0 and
            $me->get_size_class($me->train_with) ne 'train')
        {
            Log(0, "ERROR: The workload specified by train_with MUST be a training workload!\n");
            $me->release($directory);
            $me->compile_error_result('CE', 'train_with specifies non-training workload '. $me->train_with);
            return 1;
        }
    }

    # Add in mandatory stuff to compile options
    $compile_options = $me->get_mandatory_option_cksum_items(($fdo) ? 'train_with' : '');

    # Set up some default values for FDO, don't set these if the user has
    # overridden them
    my ($fdo_defaults, @commands) = $me->fdo_command_setup(\@targets, $make, @pass);
    $me->push_ref($fdo_defaults);
    my %replacements = (
        'benchmark' => $me->benchmark,
        'benchtop'  => $me->path,
        'benchnum'  => $me->num,
        'benchname' => $me->name,
        'spectop'   => $me->top,
    );

    my $tmp;
    foreach my $target (@targets) {
        next if istrue($no_clobber);
        my $targetflag = ($target ne '') ? " TARGET=$target" : '';
        my $file = ($target ne '') ? "make.clean.$target" : 'make.clean';
        if (::log_system("$make clean$targetflag",
                        {
                            'basename' => $file,
                            'combined' => 1,
                            'repl'     => [ $me, \%replacements ],
                            'env_vars' => istrue($me->env_vars),
                        })) {
            $tmp = "Error with make clean!\n";
            Log(0, "  $tmp") if $rc;
            $me->pop_ref;
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            return 1;
        }
    }

    if ($fdo) {
        my $reason = undef;
        for my $cmd (@commands) {
            my $val = $me->accessor_nowarn($cmd);
            my $pass = '';
            my $target = '';
            if ($cmd =~ m/^fdo_make_pass(\d+)_(.+)$/) {
                $pass = $1;
                $target = $2;
            } elsif ($cmd =~ m/(\d+)$/) {
                $pass = $1;
            }
            next if $val =~ m/^\s*$/;

            # Pre-build cleanup and setup (possibly)
            if ($cmd =~ m/^fdo_make_pass/) {
                # Inter-build clean, if the benchmark calls for it
                if (@targets > 1 && istrue($me->clean_between_builds)) {
                    foreach my $target (@targets) {
                        my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                        my $file = ($target ne '') ? "make.objclean.$target" : 'make.clean';
                        if (::log_system("$make objclean$targetflag",
                                    {
                                        'basename' => $file,
                                        'combined' => 1,
                                        'repl'     => [ $me, \%replacements ],
                                        'env_vars' => istrue($me->env_vars),
                                    })) {
                            $tmp = "Error with make objclean!\n";
                            Log(0, "  $tmp") if $rc;
                            $me->pop_ref;
                            $me->shift_ref;
                            $me->release($directory);
                            $me->compile_error_result('CE', $tmp);
                            return 1;
                        }
                    }
                }

                if ($me->pre_build($directory->path(), 1, $target, $pass)) {
                    # Do pre-build for each target
                    Log(0, "ERROR: pre-build setup failed for $target (pass $pass) in ".$me->benchmark."\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'pre-build FAILED');
                    return 1;
                }
            }

            if ($cmd =~ /^fdo_run/) {
                $me->unshift_ref({
                        'size'          => $me->train_with,
                        'dirlist'       => [ $directory ],
                        'fdocommand'    => $val
                    });

                # Do the setup now; if input is being generated, it will rely
                # on a binary built during the previous make pass.
                $rc = $me->copy_input_files_to(!istrue($me->strict_rundir_verify), $me->train_with, undef, $directory->path);
                if ($rc) {
                    $tmp = "  Error setting up training run!\n";
                    Log(0, $tmp);
                    $reason = 'FE';
                    last;
                }
                if ($me->post_setup($directory->path)) {
                    $tmp = "training post_setup for " . $me->benchmark . " failed!\n";
                    Log(0, $tmp);
                    $reason = 'FE';
                    last;
                }

                Log(3, "Training ", $me->benchmark, ' with the ', $me->train_with. " workload\n");
                $rc = $me->run_benchmark(0, 1, undef, 1);
                $me->shift_ref();
                $compile_options .= "RUN$pass: $val\n";
                if ($rc->{'valid'} ne 'S' && !istrue($me->fake)) {
                    $tmp = "Error ($rc->{'valid'}) with training run!\n";
                    Log(0, "  $tmp");
                    $reason = 'FE';
                    last;
                }
            } else {
                my $really_fake = 0;
                my $fake_cmd = substr($val, 0, 35);
                $fake_cmd .= '...' if length($fake_cmd) >= 35;
                $fake_cmd = "$cmd ($fake_cmd)";
                if (istrue($me->fake) and $val !~ /$make/) {
                    $really_fake = 1;
                    Log(0, "\n%% Fake commands from $fake_cmd:\n");
                }
                $rc = ::log_system($val,
                                    {
                                        'basename' => $cmd,
                                        'combined' => 1,
                                        'fake'     => $really_fake,
                                        'repl'     => [ $me, \%replacements ],
                                        'env_vars' => istrue($me->env_vars),
                                    });
                Log(0, "%% End of fake output from $fake_cmd\n\n") if $really_fake;

                # Don't record options whose default values have not been
                # overridden by the user.  This will keep changes in
                # makeflags (for example) from causing rebuilds.  This
                # mimics the CPU2006 v1.0 behavior.
                $compile_options .= "$cmd: $val\n" if ($val ne $fdo_defaults->{$cmd});
                if ($rc == 0 and $cmd =~ m/^fdo_make_pass/) {
                    # Since only one target was built, it's not necessary
                    # to generate options for all of them.
                    my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                    my $file = "options$pass";
                    $file .= ".$target" if ($target ne '');
                    $rc = ::log_system("$make options$targetflag FDO=PASS$pass",
                                    {
                                        'basename' => $file,
                                        'fake'     => $really_fake,
                                        'repl'     => [ $me, \%replacements ],
                                        'env_vars' => istrue($me->env_vars),
                                    });
                    if ($rc and !istrue($me->fake)) {
                        $tmp = "Error with $cmd!\n";
                        Log(0, "  $tmp");
                        $reason = 'CE';
                        last;
                    }
                    $compile_options .= read_compile_options("${file}.out", $pass, 0);
                    # We don't need the compiler version for every pass, but
                    # it's easier to get it than to not get it.
                    $file =~ s/options/compiler-version/;
                    $rc = ::log_system("$make compiler-version$targetflag FDO=PASS$pass",
                                    {
                                        'basename' => $file,
                                        'fake'     => $really_fake,
                                        'repl'     => [ $me, \%replacements ],
                                        'env_vars' => istrue($me->env_vars),
                                    });
                    if ($rc and !istrue($me->fake)) {
                        $tmp = "Error with $cmd!\n";
                        Log(0, "  $tmp");
                        $reason = 'CE';
                        last;
                    }
                    ($rc, my $verinfo) = read_compiler_version("${file}.out", $pass);
                    if ($rc and !istrue($me->fake)) {
                        Log(0, whine_compiler_version());
                        $reason = 'CE';
                        last;
                    }
                    $compiler_version{$verinfo}++;
                } elsif ($rc and !istrue($me->fake)) {
                    $tmp = "Error with $cmd!\n";
                    Log(0, "  $tmp");
                    $reason = 'CE';
                    last;
                }
            }
        }
        if ($rc && !istrue($me->fake)) {
            $me->pop_ref;
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result($reason, $tmp);
            log_finish($bench, $compile_start);
            return 1;
        }
    } else {
        # Inter-build clean, if the benchmark calls for it
        if (@targets > 1 and istrue($me->clean_between_builds)) {
            foreach my $target (@targets) {
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                my $file = ($target ne '') ? "make.objclean.$target" : 'make.clean';
                if (::log_system("$make objclean$targetflag",
                                {
                                    'basename' => $file,
                                    'combined' => 1,
                                    'repl'     => [ $me, \%replacements ],
                                    'env_vars' => istrue($me->env_vars),
                                })) {
                    $tmp = "Error with make objclean!\n";
                    Log(0, "  $tmp") if $rc;
                    $me->pop_ref;
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', $tmp);
                    return 1;
                }
            }
        }
        foreach my $target (@targets) {
            # Do pre-build for each target
            if ($me->pre_build($directory->path(), 1, $target, undef)) {
                Log(0, "ERROR: pre-build setup failed for $target in ".$me->benchmark."\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', 'pre-build FAILED');
                return 1;
            }

            my $targetflag = ($target ne '') ? " TARGET=$target" : '';
            my $exe = ($target ne '') ? ".$target" : '';
            $rc = ::log_system("$make build$targetflag",
                                {
                                    'basename' => "make$exe",
                                    'combined' => 1,
                                    'repl'     => [ $me, \%replacements],
                                    'env_vars' => istrue($me->env_vars),
                                });
            last if $rc;
            $rc = ::log_system("$make options$targetflag",
                                {
                                    'basename' => "options$exe",
                                    'repl'     => [ $me, \%replacements ],
                                    'env_vars' => istrue($me->env_vars),
                                });
            last if $rc;
            $compile_options .= read_compile_options("options${exe}.out", undef, 0);
            $rc = ::log_system("$make compiler-version$targetflag",
                                {
                                    'basename' => "compiler-version$exe",
                                    'repl'     => [ $me, \%replacements ],
                                    'env_vars' => istrue($me->env_vars),
                                });
            last if $rc;
            ($rc, my $verinfo) = read_compiler_version("compiler-version${exe}.out", undef);
            if ($rc and !istrue($me->fake)) {
                Log(0, whine_compiler_version());
                last;
            }
            $compiler_version{$verinfo}++;
        }

        if ($rc and !istrue($me->fake)) {
            $tmp = "Error with make!\n";
            $me->pop_ref;
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            Log(0, "  $tmp");
            log_finish($bench, $compile_start);
            return 1;
        }
    }

    main::monitor_shell('build_post_bench', $me);

    $me->pop_ref;
    $me->shift_ref;

    log_finish($bench, $compile_start);

    # Check to make sure that all the executables were built AND are
    # executable.  (The HP-UX compiler will sometimes generate an
    # output file but not mark it as executable.)
    my @unmade = ();
    my $tune  = $me->smarttune;
    my $label = $me->label;
    if (!istrue($me->fake)) {
        for my $name (sort { "${a}_$tune" cmp "${b}_$tune" } @{$me->base_exe}) {
            if (! -x $name && ! -x "$name$os_ext") {
                my $tmpfname = ( -e $name ) ? $name : ( -e "$name$os_ext" ) ? "$name$os_ext" : '';
                if ($tmpfname ne '') {
                    my $statinfo = stat($tmpfname) || [];
                    Log(99, "stat for $tmpfname returns: ".join(', ', @{$statinfo})."\n");
                    push @unmade, "$tmpfname (exists; not executable)";
                } else {
                    # $name$os_ext should usually be not too confusing a guess
                    push @unmade, "$name$os_ext (does not exist)";
                }
            }
        }
        if (@unmade) {
            $tmp = "Some files did not appear to be built:\n\t". join("\n\t", @unmade). "\n";
            Log(0, "  $tmp");
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            return 1;
        }
    }


    # Well we made it all the way here, so the executable(s) must be built
    # But are they executable? (Thank you, HP-UX.)
    # Copy them to the exe directory if they are.
    my $bits = $me->accessor_nowarn('exehash_bits') || 512256;
    my $ctx = ::get_hash_context($bits);
    my $head = jp($ownpath, $me->bindir, $subdir);
    if ( ! -d $head ) {
        eval { main::mkpath($head, 0, 0777) };
        if ($@) {
            $tmp .= "ERROR: Cannot create exe directory for ".$me->benchmark."\n";
            Log(0, $tmp);
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            return 1;
        }
    }

    for my $name (sort { "${a}_$tune" cmp "${b}_$tune" } @{$me->base_exe}) {
        my $sname = $name;
        $sname .= $os_ext if ! -f $name && -f "$name$os_ext";
        if (!istrue($me->fake) &&
            !main::copy_file($sname, "${name}_$tune.$label", [$head], istrue($me->strict_rundir_verify), undef, 1)) {
            Log(0, "ERROR: Copying executable from build dir to exe dir FAILED!\n");
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            return 1;
        }
        if (-f $sname) {
            eval { $ctx->addfile($sname, 'b') };
            if ($@ and !istrue($me->fake)) {
                Log(0, "ERROR: While attempting to read '$sname':\n\t$@\n");
            }
        }

        # Make up the auxiliary archive, if requested and possible
        if ($name eq $me->base_exe->[0] and $me->accessor_nowarn('save_build_files') ne '') {
            # Glob 'em up and ship 'em out.  The glob not matching is not
            # an error.
            my @auxfiles = glob($me->save_build_files);
            if (@auxfiles) {
                my $sumbits = $me->exehash_bits || 512256;
                my $tar = new Archive::Tar;
                # Generate checksums for the auxiliary files
                my $sumfile = "${name}.sum";
                my $ofh = new IO::File ">$sumfile";
                if (defined($ofh)) {
                    $ofh->print($sumbits."\n");
                    my $ok = 1;
                    foreach my $auxfile (@auxfiles) {
                        next if grep { /$auxfile/ } @{$me->base_exe};
                        if (-d $auxfile) {
                            push @auxfiles, glob("$auxfile/*");
                        } else {
                            $tar->add_files($auxfile);
                            (my $filehash, undef, my $algo) = ::filedigest($auxfile, $sumbits);
                            if (defined($filehash)) {
                                $ofh->print($filehash.' '.$auxfile."\n");
                            } else {
                                Log(0, "ERROR: Could not generate $algo hash of '$auxfile'\n");
                                $ok = 0;
                            }
                        }
                    }
                    $ofh->close();
                    if ($ok) {
                        $tar->add_files($sumfile);
                        if (!$tar->write(jp($head, "${name}_$tune.$label.aux.tar"))) {
                            Log(0, "\nERROR: Writing archive of auxiliary build files failed:\n      ".$tar->error()."\n");
                        }
                    } else {
                        unlink $sumfile;
                    }
                }
            }
        }
    }
    my $exehash = $ctx->hexdigest;

    $opthashref->{'valid_build'} = $valid_build ? 'yes' : 'no';
    ($opthashref->{'rawcompile_options'}, undef, $opthashref->{'compile_options'}) =
        main::compress_encode($compile_options, []);
    ($opthashref->{'rawcompiler_version'}, undef, $opthashref->{'compiler_version'}) =
        main::compress_encode(join("\n", sort keys %compiler_version), []);
    my $opthash = $me->option_cksum($compile_options);

    if ($opthashref->{'opthash'} ne $opthash) {
        $opthashref->{'opthash'} = $opthash;
        $opthashref->{'changedhash'}++;
    }
    if ($opthashref->{'exehash'} ne $exehash) {
        $opthashref->{'exehash'} = $exehash;
        $opthashref->{'changedhash'}++;
    }
    if ($opthashref->{'baggage'} ne $baggage) {
        if ($baggage !~ /^\s*$/) {
            $opthashref->{'baggage'} .= "\n$baggage";
        }
        $opthashref->{'changedhash'}++;
    }

    $me->{'dirlist'} = [] unless (ref($me->{'dirlist'}) eq 'ARRAY');
    if ((istrue($me->minimize_rundirs) && ($directory->{'type'} eq 'run')) ||
        (istrue($me->minimize_builddirs) && ($directory->{'type'} eq 'build'))) {
        push @{$me->{'dirlist'}}, $directory;
    } else {
        $me->release($directory);
    }

    return 0;
}

sub log_finish {
    my ($bench, $compile_start) = @_;

    my $compile_finish = time;  ## used by the following log statement
    my $elapsed_time = $compile_finish - $compile_start;
    ::Log(160, "  Compile for '$bench' ended at: ".::timeformat('date-time', $compile_finish)." ($compile_finish)\n");
    ::Log(160, "  Elapsed compile for '$bench': ".::to_hms($elapsed_time)." ($elapsed_time)\n");
}

sub compile_error_result {
    my $me = shift @_;
    my $result = Spec::Config->new(undef, undef, undef, undef);

    $result->{'valid'}     = shift(@_);
    $result->{'errors'}    = [ @_ ];
    $result->{'tune'}      = $me->tune;
    $result->{'label'}     = $me->label;
    $result->{'benchmark'} = $me->benchmark;
    if ($me->size_class eq 'ref') {
        $result->{'reference'} = $me->reference;
        $result->{'reference_power'} = $me->reference_power;
    } else {
        $result->{'reference'} = '--';
        $result->{'reference_power'} = '--';
    }

    $result->{'reported_sec'}  = '--';
    $result->{'reported_nsec'} = '--';
    $result->{'reported_time'} = '--';
    $result->{'ratio'}         = '--';
    $result->{'energy'}        = '--';
    $result->{'energy_ratio'}  = '--';
    $result->{'selected'}  = 0;
    $result->{'dp'}        = -1;
    $result->{'iteration'} = -1;
    $result->{'basepeak'}  = 0;
    $result->{'copies'}    = 1 if $::lcsuite eq 'cpu2017';
    $result->{'ranks'}     = 1;
    $result->{'threads'}   = 1;
    $result->{'runmode'}   = $me->runmode;
    $result->{'submit'}    = 0;
    $result->{'env'}       = {};
    if (istrue($me->power)) {
        $result->{'avg_power'} = 0;
        $result->{'min_power'} = 0;
        $result->{'max_power'} = 0;
        $result->{'max_uncertainty'} = -1;
        $result->{'avg_uncertainty'} = -1;
        $result->{'avg_temp'}  = 0;
        $result->{'min_temp'}  = 0;
        $result->{'max_temp'}  = 0;
        $result->{'avg_hum'}   = 0;
        $result->{'min_hum'}   = 0;
        $result->{'max_hum'}   = 0;
    }

    push (@{$me->{'result_list'}}, $result);

    # Remove the options read in from the __HASH__ section in the config file
    # (if any); they're not valid for this failed build.
    my $opthashref    = $me->config;
    for my $key ($me->benchmark, $me->smarttune, $me->label) {
        if (!exists $opthashref->{$key} || ref($opthashref->{$key} ne 'HASH')) {
            $opthashref->{$key} = {};
        }
        $opthashref = $opthashref->{$key};
    }
    delete $opthashref->{'compile_options'};
    delete $opthashref->{'rawcompile_options'};
    delete $opthashref->{'compiler_version'};
    delete $opthashref->{'rawcompiler_version'};

    return $me;
}

sub link_rundirs {
    my ($me, $owner) = @_;
    $me->{'dirlist'} = $owner->{'dirlist'};
    $me->{'dirlist_is_copy'} = 1;
}

sub main::check_setup {
    # Given a list of log file lines, look to see whether a run directory
    # was created or re-used, and what its name was.
    my (@lines) = @_;

    foreach my $line (@lines) {
        if ($line =~ /: (created|existing) \((\S+)\)$/) {
            if ($1 eq 'created') {
                $::dirs_created = 1;
            }
            $::dirs_created{$2}++;
        }
    }
}

sub setup_rundirs {
    my ($me, $numdirs, $path) = @_;
    my $rc;
    my $tune  = $me->smarttune;
    my $label = $me->label;
    my $size   = $me->size;
    my $nodel  = exists($ENV{"SPEC_${main::suite}_NO_RUNDIR_DEL"}) ? 1 : 0;
    my @dirs;
    my ($dest, $src);
    my $origwd = main::cwd();

    # Get some run dirs
    @dirs = $me->reserve($nodel, $numdirs,
        'type'     => 'run',
        'label'    => $label,
        'tune'     => $tune,
        'size'     => $size,
        'username' => $me->username);
    if (!@dirs) {
        Log(0, "\nERROR: Could not reserve run directories!\n");
        return ();
    }

    my $head = jp($me->path, $me->datadir);
    my @work_dirs = $me->workload_dirs($head, $size, $me->inputdir);
    chdir($work_dirs[0]);
    my $try_linking = istrue($me->reportable) || istrue($me->link_input_files);

    for my $dir (@dirs) {
        # CVT2DEV: $dir->{'bad'} = 1;    # No sums, so always re-create
        # They're bad if we say they are
        if (istrue($me->deletework)) {
            $dir->{'bad'} = 1;
        }
        # Any directories that don't exist or aren't directories are bad
        if (!-d $dir->path) {
            # Try to remove, in case $dir->path is a symlink or something.  If
            # it's not anything, remove_tree() won't complain.
            remove_tree($dir->path, { 'verbose' => 0, 'error' => \my $rmtree_errors, 'safe' => 0 });
            if (ref($rmtree_errors) eq 'ARRAY' && @$rmtree_errors) {
                Log(0, "\nERROR: Cannot remove existing run directory for ".$me->benchmark.":\n\t".
                       ::dump_removetree_errors("\n\t", $rmtree_errors)."\n");
                return ();
            }
            eval { main::mkpath($dir->path) };
            if ($@) {
                Log(0, "\nERROR: Cannot create run directory for ".$me->benchmark.": $@\n");
                return ();
            }
            Log(10, "\tRun directory ".$dir->path." will be created\n");
            $dir->{'bad'} = 1;
        }
    }

    # Now all the directories definitely exist.  If we're going to link input
    # files and the first (source) directory needs to be redone, we should
    # re-do ALL of them.  Do a quick test link here to know whether linking
    # is going to work.  If not, then we won't automatically mark all run
    # dirs for rebuilding just because the first needs rebuilding.
    if (@dirs > 1 and $try_linking) {
        my ($tfh, $tfn) = tempfile('linktest.XXXXXXXX', DIR => $dirs[0]->path);
        if (!main::link_file(dirname($tfn), basename($tfn), $dirs[1]->path)) {
            $try_linking = 0;
        } else {
            unlink jp($dirs[1]->path, basename($tfn));
        }
        unlink $tfn;    # Should happen automatically, but this won't hurt

        if ($try_linking) {
            # Since linking a new directory is faster than verifying existing
            # run directory, we don't even try to re-use existing run
            # directories.  This also has the nice side-effect of defeating any
            # attacks that might try to mess with run directory placement using
            # symlinks, etc.
            for(my $i = 1; $i < @dirs; $i++) {
                $dirs[$i]->{'bad'} = 1;
                Log(10, "\tRun directory ".$dirs[$i]->path." will be linked from ".basename($dirs[0]->path)."\n");
            }
        }
    }

    # Get the list of files that will be generated (if any) and add them to
    # the list to be checked.
    my @genfiles;
    eval { @genfiles = $me->generate_inputs() };
    if ($@) {
        Log(0, "ERROR: generate_inputs() for ".$me->benchmark." failed to generate file list\n");
        Log(190, $@);
        chdir($origwd); # Back from whence we came
        return ();
    }
    foreach my $genfiles (map { $_->{'generates'} } @genfiles) {
        next unless defined($genfiles);
        foreach my $fileref (@$genfiles) {
            next unless defined($fileref);
            my ($fname, $fsum) = @{$fileref};
            # Since different workloads can have files with the same name
            # and different contents, it's necessary to disambiguate them.
            my $fname_sumpath = jp($me->benchmark, $me->size, $fname);
            $me->{'generated_files'}->{$fname}++;
            $::file_sums{$fname_sumpath} = $fsum if defined($fsum) and $fsum ne '';
        }
    }
    my $generated_files = $me->generated_files_hash;

    my $fast = !istrue($me->strict_rundir_verify) || istrue($me->fake);
    my $no_rundir_checking = 0;
    # CVT2DEV: $fast = 1; $no_rundir_checking = 1;
    my @input_files = (
        $me->input_files_abs($me->size, 1),
        sort keys %{$generated_files},
    );
    if (@input_files+0 == 0 ||
        !defined($input_files[0])) {
        Log(0, "\tError during setup for ".$me->benchmark.": No input files!?\n");
        return ();
    }

    # This only makes sure that the reference input files have checksums
    # against which to check copied files.
    if (!$no_rundir_checking and !istrue($me->fake)) {
        for my $reffile (@input_files) {
            next if exists($generated_files->{$reffile});
            if ($::file_sums{$reffile} eq '' and -r $reffile) {
                # This really shouldn't ever happen, as all input files should
                # be in MANIFEST.  Generated files should have entries added
                # when they're made.
                $::file_sums{$reffile} = ::filedigest($reffile, 512);
            }
        }
    }

    # Check to see which directories are ok
    for(my $i = 0; $i < @dirs; $i++) {
        my $dir = $dirs[$i];
        next if $dir->{'bad'} || istrue($me->fake);
        $dir->{'bad'} = 0;   # Just so it's defined

        for my $reffile (@input_files) {
            my $refsize;
            my $short    = $reffile;
            my $sumfname = exists($generated_files->{$reffile}) ? jp($me->benchmark, $me->size, $reffile) : $reffile;
            my $refdigest = $::file_sums{$sumfname};
            foreach my $wdir (map { ::make_path_re($_.'/') } @work_dirs) {
                $short       =~ s/^$wdir//i;
            }
            if (exists($::file_size{$sumfname}) && $refdigest ne '') {
                $refsize = $::file_size{$sumfname};
            } else {
                $refsize = stat($reffile);
                $refsize = $refsize->size if (defined($refsize));
            }
            my $target = jp($dir->path, $short);
            if (!-f $target) {
                Log(10, "\t'$short' not found; ".$dir->path." will be rebuilt.\n");
                $dir->{'bad'} = 1;
            } elsif (!$no_rundir_checking) {
                if (defined($refsize) and (-s $target != $refsize)) {
                    Log(10, "\tSize of '$short' does not match reference; ".$dir->path." will be rebuilt.\n");
                    $dir->{'bad'} = 1;
                } else {
                    # Non-generated reference files are guaranteed to have entries
                    # in %::file_sums, thanks to the loop above this one.
                    my $shorthash = (-r $target) ? ::filedigest($target, 512) : 'MISSING_FILE';
                    Log(10, "\tChecking checksum of '$short' in ".$dir->path." against cached source checksums.\n");
                    if ($refdigest ne $shorthash) {
                        Log(10, "\tChecksum of '$short' does not match cached checksum of reference file; ".$dir->path." will be rebuilt.\n");
                        $dir->{'bad'} = 1;
                    }
                }
            }
            last if $dir->{'bad'};
        }
    }

    # Remove output and other files from directories which are ok.
    for my $dir (@dirs) {
        next if $dir->{'bad'};
        my $basepath = $dir->path;
        $dir->{'bad'} = $me->clean_single_rundir($basepath);
        my $dh = new IO::Dir $dir->path;
        if (!defined $dh) {
            $dir->{'bad'} = 1;
            next;
        }
        # This should never have anything to do.
        while (defined(my $file = $dh->read)) {
            next if ($file !~ m/\.(out|err|cmp|mis)$/);
            my $target = jp($dir->path, $file);
            if (!unlink ($target)) {
                $dir->{'bad'} = 1;
                last;
            }
        }
    }

    my @dirnum = ();
    # Now rebuild all directories which are not okay
    my @copy_dirs = ();
    for my $dir (@dirs) {
        my $path = $dir->path();
        push @dirnum, File::Basename::basename($path);

        if ($dir->{'bad'}) {
            delete $dir->{'bad'};
            remove_tree($path, { 'verbose' => 0, 'error' => \my $rmtree_errors, 'safe' => 0 });
            if (ref($rmtree_errors) eq 'ARRAY' && @$rmtree_errors) {
                Log(0, "ERROR: Cannot remove existing run directory $path for ".$me->benchmark.":\n\t".
                       ::dump_removetree_errors("\n\t", $rmtree_errors)."\n");
                return ();
            }
            eval { main::mkpath($path) };
            if ($@) {
                Log(0, "ERROR: Cannot create run directory at $path for ".$me->benchmark.": $@\n");
                return ();
            }
            push @copy_dirs, $path;
        } else {
            push @copy_dirs, undef;
        }
    }

    # Copy executables to first directory
    if (!istrue($me->fake)) {
        my $os_ext = $me->os_exe_ext;
        for my $file ($me->exe_files_abs) {
            if (!main::copy_file($file, undef, [$dirs[0]->path], istrue($me->strict_rundir_verify), undef, 1)) {
                Log(0, "ERROR: Copying executable to run directory at ".$dirs[0]->path." FAILED\n");
                return ();
            }
            if (!istrue($me->reportable)) {
                my $aux_name = $file;
                $file =~ s/\Q${os_ext}\E$// if $os_ext ne '';
                $file .= '.aux.tar';
                my $sumfile = basename($file);
                $sumfile =~ s/_(?:base|peak)\..*//;      # Back to the base name
                $sumfile .= '.sum';
                if (-f $file) {
                    # Unpack the auxiliary files in the tarball
                    chdir($dirs[0]->path);
                    my @aux_files = Archive::Tar->extract_archive($file);
                    if (@aux_files == 0) {
                        Log(0, "\nWARNING: Copying auxiliary files to run directory at ".$dirs[0]->path." FAILED\n");
                    } elsif (!-f $sumfile) {
                        Log(0, "\nERROR: Could not find checksum file '$sumfile' after extraction of auxiliary file archive.\n");
                        chdir($origwd);
                        return ();
                    } else {
                        # Files were extracted and checksums are present; read and verify
                        my @lines = ::read_file($sumfile);
                        my $bits = shift(@lines) + 0;
                        my $sumlen = $bits / 4;
                        if (@lines + 1 != @aux_files) {
                            Log(0, "\nERROR: Incorrect number of files extracted from auxiliary file archive (got ".(@aux_files+0)."; expected ".(@lines+0).").\n");
                            chdir($origwd);
                            return ();
                        }
                        foreach my $sumline (@lines) {
                            next if $sumline =~ m{/$};  # Don't do directories
                            if ($sumline !~ /^([[:xdigit:]]{$sumlen}) (.*)/) {
                                Log(0, "\nERROR: Malformed auxiliary file hash.\n");
                                chdir($origwd);
                                return ();
                            }
                            my ($storedsum, $file) = ($1, $2);
                            next if (-d $file); # Really don't do directories
                            my ($gensum) = ::filedigest($file, $bits);
                            if (!defined($gensum)) {
                                Log(0, "\nERROR: Could not generate checksum for $file\n");
                                chdir($origwd);
                                return ();
                            }
                            if ($gensum ne $storedsum) {
                                Log(0, "\nERROR: Checksum for auxiliary file $file doesn't match\n");
                                chdir($origwd);
                                return ();
                            }
                            $me->{'added_files'}->{$file}++;
                        }
                    }
                }
            }
        }
    }

    # Copy input files to dirs that need them
    if (grep { defined } @copy_dirs) {
        # Populate the first run directory separately, since it will be the link source
        # for all the other directories.
        if (defined($copy_dirs[0])) {
            if ($me->copy_input_files_to($fast, $me->size, undef, $copy_dirs[0])) {
                Log(0, "ERROR: Copying input files to first run directory at $copy_dirs[0] FAILED\n".Carp::longmess());
                chdir($origwd);
                return ();
            }
            $copy_dirs[0] = undef;
        }
        if ($me->copy_input_files_to($fast, $me->size, $dirs[0]->path, @copy_dirs)) {
            Log(0, "ERROR: Copying input files to run directory FAILED\n");
            chdir($origwd);
            return ();
        }
    }

    if ($me->post_setup(map { $_->path } @dirs)) {
        Log(0, "ERROR: post_setup for " . $me->benchmark . " failed!\n");
        chdir($origwd);
        return ();
    }

    $me->{'dirlist'} = [ @dirs ];

    chdir($origwd);
    return @dirnum;
}

# The starting point for all run directory cleanup.
sub cleanup_rundirs {
    my ($me, $numdirs, $path) = (@_);
    my $rc = 0;

    return 0 if istrue($me->fake);

    $numdirs = @{$me->{'dirlist'}}+0 if ($numdirs <= 0);

    for (my $i = 0; $i < $numdirs; $i++) {
        my $dir = $me->{'dirlist'}[$i]->path;
        my $pid = undef;

        my @fh_list = ();
        for my $file ($me->exe_files_abs) {
            my $fullpath = jp($dir, basename($file));
            if (-e $fullpath) {
                # Make an effort to make the executable be less-easily identifiable
                # as the _same_ executable that we used last time.
                rename $fullpath, "${fullpath}.used.$$";
                my $ofh = new IO::File ">${fullpath}.used.$$";
                $ofh->print("#!/bin/sh\necho This is a non-functional placeholder\n");
                # Make sure that we maintain an open filehandle to the placeholder,
                # so that when the file is unlinked its inode doesn't get reallocated.
                push @fh_list, $ofh;
                # clean_single_rundir will take care of the placeholder file for us
                if (!main::copy_file($file, undef, [$dir], 1, undef, 1)) {
                    Log(0, "ERROR: Copying executable to run directory FAILED in cleanup_rundirs\n");
                    return 1;
                }
            }
        }
        # All the files are copied now, so go ahead and kill the temps
        my $fh = shift @fh_list;
        while(defined($fh) && ref($fh) eq 'IO::File') {
            $fh->close();
            $fh = shift @fh_list;
        }
        $rc |= $me->clean_single_rundir($dir);
    }

    return $rc;
}

sub clean_single_rundir {
    my ($me, $basepath) = @_;
    my $head = jp($me->path, $me->datadir);
    my @work_dirs = $me->workload_dirs($head, $me->size, $me->inputdir);
    my @tmpdir = ($basepath);
    my @files = ();

    while (defined(my $curdir = shift(@tmpdir))) {
        my $dh = new IO::Dir $curdir;
        next unless defined $dh;
        foreach my $file ($dh->read) {
            next if ($file eq '.' || $file eq '..');
            $file = jp($curdir, $file);
            if ( -d $file ) {
                push @tmpdir, $file;
            } else {
                push @files, $file;
            }
        }
    }
    # Strip the top path from the list of files we just discovered
    @files = sort map { s%^$basepath/%%i; $_ } @files;

    # Make a list of the files that are allowed to be in a run directory
    # before a run starts.  This could be (and was) done as a much more
    # concise and confusing one-liner using map.  Hey, not everyone has
    # 1337 p3r1 skillz.
    my %okfiles = ();
    foreach my $okfile ($me->exe_files,
                        $me->input_files_base,
                        $me->added_files_base,
                        $me->generated_files_base,
                        $me->preserve_files_base,
                        ) {
        foreach my $wdir (map { ::make_path_re($_.'/') } @work_dirs) {
            $okfile =~ s/^$wdir//i;
        }
        $okfiles{$okfile}++;
    }

    # The "everything not mandatory is forbidden" enforcement section
    for my $reffile (@files) {
        next if exists($okfiles{$reffile});
        my $target = jp($basepath, $reffile);
        next if !-f $target;
        if (!unlink($target)) {
            Log(0, "\nERROR: Failed to unlink $target\n");
            return 1;
        }
    }

    return 0;
}

sub delete_binaries {
    my ($me, $all) = @_;
    my $os_ext = $me->os_exe_ext;
    my $path = $me->path;
    if (::check_output_root($me->config, $me->output_root, 0)) {
        my $oldtop = ::make_path_re($me->top);
        my $newtop = $me->output_root;
        $path =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';

    my $head = jp($path, $me->bindir, $subdir);
    if ($all) {
        ::rmpath($head);
    } else {
        my $tune  = $me->smarttune;
        my $label = $me->label;
        for my $name (@{$me->base_exe}) {
            unlink(jp($head, "${name}_$tune.$label"));
            unlink(jp($head, "${name}_$tune.$label$os_ext"));
            unlink(jp($head, "${name}_$tune.$label.aux.tar"));
        }
    }
}

sub delete_rundirs {
    my ($me, $all) = @_;
    my $path = $me->{'path'};
    my $top = $me->top;
    if (::check_output_root($me->config, $me->output_root, 0)) {
        my $oldtop = ::make_path_re($top);
        $top = $me->output_root;
        $path =~ s/^$oldtop/$top/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';

    my @attributes = ();

    if ($all) {
        my $dir = jp($path, $::global_config->{'rundir'}, $subdir);
        ::rmpath($dir);
        $dir = jp($path, $::global_config->{'builddir'}, $subdir);
        ::rmpath($dir);
    } else {
        @attributes = ([
                'username' => $me->username,
                'label'    => $me->label,
                'size'     => $me->size,
                'tune'     => $me->smarttune,
            ], [
                'username' => $me->username,
                'type'     => 'build',
                'label'    => $me->label,
            ]);

        foreach my $type (qw(build run)) {
            my $file = $me->lock_listfile($type);
            my $entry;
            for my $attr (@attributes) {
                while (1) {
                    $entry = $file->find_entry($top, @$attr);
                    last if !$entry;
                    ::rmpath($entry->path);
                    rmdir($entry->path);
                    $entry->remove();
                }
            }
            $file->update();
            $file->close();
        }
    }
}

sub remove_rundirs {
    my ($me) = @_;

    if ($me->{'dirlist_is_copy'}) {
        delete $me->{'dirlist_is_copy'};
    } else {
        if (ref($me->{'dirlist'}) eq 'ARRAY') {
            my @dirs = @{$me->{'dirlist'}};
            for my $dirobj (@dirs) {
                ::rmpath($dirobj->path);
            }
            $me->release(@dirs);
        } else {
            Log(3, "No list of directories to remove for ".$me->descmode('no_threads' => 1)."\n");
        }
    }
    $me->{'dirlist'} = [];
}

sub release_rundirs {
    my ($me) = @_;

    if ($me->{'dirlist_is_copy'}) {
        delete $me->{'dirlist_is_copy'};
    } elsif (ref($me->{'dirlist'}) eq 'ARRAY') {
        my @dirs = @{$me->{'dirlist'}};
        $me->release(@dirs);
    }
    $me->{'dirlist'} = [] unless (istrue($me->minimize_rundirs));
}

sub reserve {
    my ($me, $nodel, $num, %attributes) = @_;
    my $top = $me->top;
    if (::check_output_root($me->config, $me->output_root, 0)) {
        $top = $me->output_root;
    }

    $num = 1 if ($num eq '');
    if (keys %attributes == 0) {
        %attributes = (
            'username' => $me->username,
            'label'    => $me->label,
            'tune'     => $me->smarttune,
        );
    }
    # If we're looking for a particular PATH, then we want it to be locked.
    # Otherwise, it should be unlocked.
    if (exists($attributes{'dir'}) && $attributes{'dir'} ne '') {
        $attributes{'lock'} = 1;
    } else {
        $attributes{'lock'} = 0;
    }
    my $name;
    my %temp;
    foreach my $thing (qw(type tune size label)) {
        ($temp{$thing} = $attributes{$thing}) =~ tr/-A-Za-z0-9./_/cs;
    }
    if ($attributes{'type'} eq 'run') {
        $name = sprintf("%s_%s_%s_%s", $temp{'type'}, $temp{'tune'},
            $temp{'size'}, $temp{'label'});
    } elsif ($attributes{'type'} eq 'build') {
        $name = sprintf("%s_%s_%s", $temp{'type'}, $temp{'tune'}, $temp{'label'});
    } else {
        if ($attributes{'type'} eq '') {
            $attributes{'type'} = 'unknown';
        }
        $name = sprintf("UNKNOWN_%s_%s_%s", $temp{'tune'}, $temp{'size'},
            $temp{'label'});
    }

    my $file = $me->lock_listfile($attributes{'type'});
    my @entries;

    for (my $i = 0; $i < $num; $i++ ) {
        my $entry = $file->find_entry($top, %attributes);
        if (!$entry || $nodel) {
            $attributes{'lock'} = 0;
            $entry = $file->new_entry($name, 'username' => $me->username, %attributes);
        }
        push @entries, $entry;
        $entry->lock($me->username);
    }
    $file->update();
    $file->close();
    push @{$me->{'entries'}}, @entries;

    return @entries;
}

sub release {
    my ($me, @dirs) = @_;

    my %dirs = (
        'build' => [ grep { $_->{'type'} eq 'build' } @dirs ],
        'run'   => [ grep { $_->{'type'} ne 'build' } @dirs ],
    );

    foreach my $type (qw(build run)) {
        next unless @{$dirs{$type}};
        my $file = $me->lock_listfile($type);
        for my $dir (@{$dirs{$type}}) {
            my $entry = $file->find_entry_name($dir->name);
            if ($entry) {
                $entry->unlock($dir->name);
            } else {
                Log(0, "WARNING: release: Bogus entry in $type entries list\n");
            }
        }
        $file->update();
        $file->close();
    }
}

sub was_submit_used {
    # Determine whether submit was used
    my ($me, $is_training) = @_;

    # For the purposes of this determination, it's sufficient for _any_
    # submit (other than the default) to be set.
    my %submit = $me->assemble_submit();
    delete $submit{'default'} if $submit{'default'} eq $::nonvolatile_config{'default_submit'};
    my $submit = join("\n", map { $submit{$_} } keys %submit);

    if ($me->check_submit($submit, $is_training)) {
        return 1;
    } else {
        return 0;
    }
}

sub make_empty_result {
    my ($me, $iter, $add_to_list, $is_training) = @_;

    my $result = Spec::Config->new();
    $result->{'valid'}         = 'S';
    $result->{'errors'}        = [];
    $result->{'tune'}          = $me->tune;
    $result->{'label'}         = $me->label;
    $result->{'selected'}      = 0;
    $result->{'runmode'}       = $me->runmode;
    $result->{'benchmark'}     = $me->benchmark;
    $result->{'exehash'}       = $me->accessor_nowarn('exehash') || 'MISSING';
    $result->{'basepeak'}      = 0;
    $result->{'iteration'}     = $iter;
    $result->{'copies'}        = $me->copies if $::lcsuite eq 'cpu2017';
    $result->{'threads'}       = $me->threads;
    $result->{'ranks'}         = $me->ranks;
    $result->{'submit'}        = was_submit_used($me, $is_training);
    $result->{'rc'}            = 0;
    $result->{'reported_sec'}  = 0;
    $result->{'reported_nsec'} = 0;
    $result->{'reported_time'} = 0;
    $result->{'selected'}      = 0;
    $result->{'dp'}            = -1;
    $result->{'env'}           = {};
    if ($me->size_class eq 'ref' && !$is_training) {
        $result->{'ratio'}           = 0;
        $result->{'energy_ratio'}    = 0 if istrue($me->power);
        $result->{'reference'}       = $me->reference;
        $result->{'reference_power'} = $me->reference_power;
    } else {
        $result->{'ratio'}           = '--';
        $result->{'energy_ratio'}    = '--' if istrue($me->power);
        $result->{'reference'}       = '--';
        $result->{'reference_power'} = '--';
    }
    if (istrue($me->power)) {
        $result->{'energy'}    = 0;
        $result->{'avg_power'} = 0;
        $result->{'min_power'} = 0;
        $result->{'max_power'} = 0;
        $result->{'max_uncertainty'} = -1;
        $result->{'avg_uncertainty'} = -1;
        $result->{'avg_temp'}  = 0;
        $result->{'min_temp'}  = 0;
        $result->{'max_temp'}  = 0;
        $result->{'avg_hum'}   = 0;
        $result->{'min_hum'}   = 0;
        $result->{'max_hum'}   = 0;
    }
    return undef if $result->{'reference'} == 1;

    if (defined($add_to_list)) {
        push @{$me->{'result_list'}}, $result;
    }

    return $result;
}

sub assemble_submit {
    # Assemble a hash (keyed by executable name) of submit commands.
    # Ones that were multiply-valued will be joined into a single string.
    my ($me) = @_;
    my %submit = ('default' => [ $::nonvolatile_config->{'default_submit'} ]);

    foreach my $line (grep { /^submit_\S+\d*$/ } $me->list_keys) {
        my ($exe, $idx) = $line =~ m/^submit_(\S+)(\d*)$/;
        next if $exe =~ /notes(?:_\d*)?/;
        my $val = $me->accessor($line);
        $submit{$exe}->[$idx] = $val;
    }

    # Now do the "generic" one
    my @generic_submit = grep { /^submit\d*$/ } $me->list_keys;
    if (@generic_submit) {
        # Get rid of the default; otherwise work may be doubled.
        # See CPUv6 Trac #645.
        $submit{'default'} = [];
    }
    foreach my $line (@generic_submit) {
        my ($idx) = $line =~ m/^submit(\d*)$/;
        my $val = $me->accessor($line);
        $submit{'default'}->[$idx] = $val;
    }

    foreach my $exe (sort keys %submit) {
        # The linefeeds will be substituted with the correct command join
        # character ('&&' for Windows cmd, ';' for all others)
        $submit{$exe} = join("\n", grep { defined } @{$submit{$exe}});
        # Arrange for mini-batch files to work.  No worries about the check
        # for default_submit elsewhere; this fixup will not happen for
        # the default command (which does not contain "&&" or "\n").
        if ($^O =~ /MSWin/
                and $submit{$exe} =~ /(?:\&\&|\n)/
                and $submit{$exe} !~ /^cmd /) {
            $submit{$exe} = 'cmd /E:ON /D /C '.$submit{$exe};
        }
    }
    return %submit;
}

sub assemble_monitor_wrapper {
    return _assemble_monitor('monitor_wrapper', @_);
}

sub assemble_monitor_specrun_wrapper {
    return _assemble_monitor('monitor_specrun_wrapper', @_);
}

sub _assemble_monitor {
    # Assemble possibly multi-line monitor command
    my ($thing, $me) = @_;
    my @cmds = ();

    foreach my $line (grep { /^\Q${thing}\E\d*$/ } $me->list_keys) {
        my ($idx) = $line =~ m/^\Q${thing}\E(\d*)$/;
        my $val = $me->accessor($line);
        $cmds[$idx] = $val;
    }

    my $cmd = join("\n", grep { defined and /\S/ } @cmds);
    # Arrange for mini-batch files to work
    if (   $^O =~ /MSWin/
        && $cmd =~ /(?:\&\&|\n)/
        && $cmd !~ /^cmd /) {
        $cmd = 'cmd /E:ON /D /C '.$cmd;
    }
    if ($cmd =~ m#^cmd # && $^O =~ /MSWin/) {
        # Convert line feeds into && for cmd.exe
        $cmd =~ s/[\r\n]+/\&\&/go;
    } else {
        $cmd =~ s/[\r\n]+/;/go;
    }

    return $cmd;
}

sub do_monitor {
    my ($me, $is_training) = @_;
    return (!istrue($me->reportable)
            and (istrue($me->force_monitor)
                or (istrue($me->enable_monitor)
                    and !(istrue($me->plain_train) and $is_training)
                    and !::check_list($me->no_monitor, $me->size))));
}

sub run_benchmark {
    my ($me, $setup, $is_build, $iter, $is_training) = @_;
    my ($start, $stop, $elapsed);
    my @skip_timing = ();
    my %err_seen = ();
    my $specperl = ($^O =~ /MSWin/) ? 'specperl.exe' : 'specperl';
    my $origwd = main::cwd();
    my $num_copies = $is_training ? 1 : $me->copies;
    my $do_monitor = $me->do_monitor($is_training);

    my @dirs = @{$me->dirlist}[0..$num_copies-1];
    my $error = 0;

    my $result = $me->make_empty_result($iter, undef, $is_training);

    if (!defined($result)) {
        Log(0, "ERROR: ".$me->benchmark." does not support workload size ".$me->size."\n");
        return undef;
    }

    if (istrue($me->accessor_nowarn('fail')) ||
        istrue($me->accessor_nowarn('fail_run'))) {
        Log(0, "ERROR: fail or fail_run set for this benchmark\n");
        $result->{'valid'} = 'RE';
        push (@{$result->{'errors'}}, "failed by request\n");
        return $result;
    }

    my $path = $dirs[0]->path;
    chdir($path);

    # Munge the environment now so it can be seen by pre_run() and invoke()
    # and be stored in the command file
    my ($threads, $user_set_env, %oldENV) = $me->setup_run_environment(1, $is_training);

    if ($me->pre_run(map { $_->path } @dirs)) {
        Log(0, "ERROR: pre-run failed for ".$me->benchmark."\n");
        $result->{'valid'} = 'TE';
        push (@{$result->{'errors'}}, "pre_run failed\n");
        %ENV = %oldENV;
        return $result;
    }
    $me->unshift_ref({ 'iter' => 0, 'command' => '', 'commandexe' => '',
            'copynum' => 0, 'phase' => 'run' });
    $me->push_ref   ({ 'fdocommand' => '', });

    if (istrue($me->fake)) {
        Log(0, "\nBenchmark invocation\n");
        Log(0, "--------------------\n");
    }

    my @run_commands;
    eval { @run_commands = $me->invoke };
    if ($@) {
        Log(0, "ERROR: invoke() failed for ".$me->benchmark."\n");
        Log(190, $@);
        $result->{'valid'} = 'TE';
        push (@{$result->{'errors'}}, "invoke() failed\n");
        %ENV = %oldENV;
        $me->shift_ref();
        $me->pop_ref();
        return $result;
    }
    if (@run_commands == 0) {
        Log(0, "ERROR: invoke() returned no commands for ".$me->benchmark."\n");
        $result->{'valid'} = 'TE';
        push (@{$result->{'errors'}}, "invoke() returned no commands\n");
        %ENV = %oldENV;
        $me->shift_ref();
        $me->pop_ref();
        return $result;
    }

    # There's no point in continuing if one part craps out.
    # The -q causes specinvoke to stop to avoid destroying evidence in the
    # run directory.
    my ($absrunfile, $resfile, $skip_timing_list, $specrun, undef) = $me->prep_specrun($result, \@dirs,
                        $me->commandfile, $me->commandoutfile,
                        \%oldENV, $setup, $is_training, $iter,
                        [
                            '-q',
                            [ '-e', $me->commanderrfile    ],
                            [ '-o', $me->commandstdoutfile ],
                        ],
                        'invoke', @run_commands);
    if ($result->{'valid'} ne 'S' || !defined($absrunfile)) {
        $me->pop_ref();
        $me->shift_ref();
        return $result;
    }

    if (!$setup) {
        # This is the part where the benchmark is actually run...

        my $command = join (' ', @{$specrun});
        $me->command($command);
        my $specrun_wrapper = '';
        if ($do_monitor) {
            $specrun_wrapper = $me->assemble_monitor_specrun_wrapper;
            if ($specrun_wrapper ne '') {
                $command = ::command_expand($specrun_wrapper, [ $me, { 'iter', $iter } ]);
                $command = "echo \"$command\"" if istrue($me->fake);
            }
        }
        main::monitor_pre_bench($me, { 'iter' => $iter }) if $do_monitor;
        if ($me->delay > 0 && !istrue($me->reportable)) {
            Log(190, "Entering user-requested pre-invocation sleep for ".$me->delay." seconds.\n");
            sleep $me->delay;
        }

        Log(191, "Specinvoke: $command\n") unless istrue($me->fake);

        # Begin power measurement if requested
        if (($::from_runcpu & 1) == 0
                and istrue($me->power)
                and !$is_training) {
            my $isok = ::meter_start($me->benchmark,
                {
                    'a' => { 'default' => $me->current_range },
                    'v' => { 'default' => $me->voltage_range },
                },
                @{$me->powermeterlist});
            if (!$isok) {
                Log(0, "ERROR: Power analyzers could not be started\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) power analyzers could not be started\n");
            }
            $isok = ::meter_start($me->benchmark, undef, @{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Temperature meters could not be started\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) temperature meters could not be started\n");
            }
        }

        $start = time;
        my $outname = istrue($me->fake) ? 'benchmark_run' : undef;
        my $rc = ::log_system($command, { 'basename' => $outname, 'env_vars' => istrue($me->env_vars) });
        $stop = time;
        $elapsed = $stop-$start;

        $result->{'env'} = { ::get_actual_env_values(%$user_set_env) };

        # Restore pre-run environment
        %ENV = %oldENV;

        # End the power measurement and collect the results
        if (($::from_runcpu & 1) == 0
                and istrue($me->power)
                and !$is_training) {

            # Sleep for the maximum sample time among all power analyzers.
            # This will allow for short-running benchmarks to get a sample
            # that's within the slightly expanded time window (see
            # the ::add_interval() call below).  This will (slightly) increase
            # the time necessary to do a run, but won't change the benchmark
            # score.
            my $max_interval = max(map { abs($_->{'interval'}) } @{$me->powermeterlist}) / 1000;
            $max_interval++ unless $max_interval;
            Log(34, "Sleeping $max_interval seconds to ensure power sample collection.\n");
            sleep $max_interval;

            my $isok = ::meter_stop(@{$me->powermeterlist});
            if (!$isok) {
                Log(0, "ERROR: Power analyzers could not be stopped\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) power analyzers could not be stopped\n");
            }
            $isok = ::meter_stop(@{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Temperature meters could not be stopped\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) temperature meters could not be stopped\n");
            }

            # Give the meters a second to stop
            sleep 1;

            # Read the info and store it in the result object
            my ($total, $avg, $min, $max, $max_uncertainty, $avg_uncertainty, $statsref, @list);

            # First, power:
            ($isok, $total, $avg, $max_uncertainty, $avg_uncertainty, @list) = ::power_analyzer_watts($me->meter_errors_percentage, @{$me->powermeterlist});
            if (!$isok || !defined($avg)) {
                Log(0, "ERROR: Reading power analyzers returned errors\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) reading power analyzers returned errors\n");
            }
            push @{$result->{'powersamples'}}, @list;
            $result->{'avg_power'} = $total;
            $result->{'min_power'} = -1;        # Placeholder until extract_samples
            $result->{'max_power'} = -1;        # Placeholder until extract_samples
            $result->{'max_uncertainty'} = $max_uncertainty;
            $result->{'avg_uncertainty'} = $avg_uncertainty;
            ::extract_ranges($result, $result->{'powersamples'}, '', @{$me->powermeterlist});

            # Now, temperature:
            ($isok, $statsref, @list) = ::temp_meter_temp_and_humidity($me->meter_errors_percentage, @{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Reading temperature meters returned errors\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) reading temperature meters returned errors\n");
            }
            $statsref = {} unless ::ref_type($statsref) eq 'HASH';
            foreach my $thing (qw(temperature humidity)) {
                $statsref->{$thing} = [] unless ::ref_type($statsref->{$thing}) eq 'ARRAY';
            }
            ($avg, $min, $max) = @{$statsref->{'temperature'}};
            push @{$result->{'tempsamples'}}, @list;
            $result->{'avg_temp'} = defined($avg) ? $avg : 'Not Measured';
            $result->{'min_temp'} = defined($min) ? $min : 'Not Measured';
            $result->{'max_temp'} = defined($max) ? $max : 'Not Measured';
            ($avg, $min, $max) = @{$statsref->{'humidity'}};
            $result->{'avg_hum'} = defined($avg) ? $avg : 'Not Measured';
            $result->{'min_hum'} = defined($min) ? $min : 'Not Measured';
            $result->{'max_hum'} = defined($max) ? $max : 'Not Measured';

            # Check the limits
            if (   (istrue($me->reportable) || $result->{'min_temp'} ne 'Not Measured')
                && $::global_config->{'min_temp_limit'}
                && $result->{'min_temp'} < $::global_config->{'min_temp_limit'}) {
                Log(0, "ERROR: Minimum temperature during the run (".$result->{'min_temp'}." degC) is less than the minimum allowed (".$::global_config->{'min_temp_limit'}." degC)\n");
                $result->{'valid'} = 'EE';
                push @{$result->{'errors'}}, "(EE) Minimum allowed temperature exceeded\n";
            }
            if (   (istrue($me->reportable) || $result->{'max_hum'} ne 'Not Measured')
                && $::global_config->{'max_hum_limit'}
                && $result->{'max_hum'} > $::global_config->{'max_hum_limit'}) {
                Log(0, "ERROR: Maximum humidity during the run (".$result->{'max_hum'}."%) is greater than the maximum allowed (".$::global_config->{'max_hum_limit'}."%)\n");
                $result->{'valid'} = 'EE';
                push @{$result->{'errors'}}, "(EE) Maximum allowed humidity exceeded\n";
            }
        }

        if ($me->delay > 0 && !istrue($me->reportable)) {
            Log(190, "Entering user-requested post-invocation sleep for ".$me->delay." seconds.\n");
            sleep $me->delay;
        }

        main::monitor_post_bench($me, { 'iter' => $iter }) if $do_monitor;

        $me->pop_ref();
        $me->shift_ref();
        my $specrun_rc = 0;
        my $specrun_sig = 0;
        if (defined($rc) and $rc != 0) {
            # We'll log this after the loop
            $specrun_rc = WEXITSTATUS($rc);
            $specrun_sig = WTERMSIG($rc);
        }

        # Record the number of threads run
        $result->{'threads'} = $threads;

        my $fh = new IO::File "<$resfile";
        if (defined $fh) {
            $error = 0;
            my @child_times = ( );
            my @counts = ();
            my @power_intervals = ();
            while (defined(my $runline = $fh->getline())) {
                # Make sure the environment gets into the debug log
                Log(99, $runline);
                if ($runline =~ m/child started:\s*(\d+),\s*(\d+),\s*(\d+),\s*pid=/) {
                    my ($num, $starttime) = ($1, $2 + ($3 / 1_000_000_000));
                    $counts[$num] = 0 unless defined($counts[$num]);
                    my $skip_timing = $skip_timing_list->[$counts[$num]] || 0;
                    $child_times[$num] = { 'time' => 0, 'untime' => [0, 0], 'num' => $num } unless defined($child_times[$num]);
                    if (!$skip_timing and
                        (!defined($child_times[$num]->{'start'}) or $child_times[$num]->{'start'} > $starttime)) {
                        $child_times[$num]->{'start'} = $starttime;
                    }

                } elsif ($runline =~ m/child finished:\s*(\d+),\s*(\d+),\s*(\d+),\s*sec=(\d+),\s*nsec=(\d+),\s*pid=\d+,\s*rc=(\d+)/) {
                    my ($num, $endtime, $elapsedtime, $esec, $ensec, $rc) =
                    ($1, $2 + ($3 / 1_000_000_000), $4 + ($5 / 1_000_000_000), $4, $5, $6);
                    $counts[$num] = 0 unless defined($counts[$num]);
                    my $skip_timing = $skip_timing_list->[$counts[$num]] || 0;
                    $counts[$num]++;
                    if ($rc != 0) {
                        $error = 1;
                        $result->{'rc'} = $rc;
                        $result->{'valid'} = 'RE';
                        Log(0, "\n".$me->benchmark.": copy $num non-zero return code (exit code=".WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n\n");
                        push (@{$result->{'errors'}}, "copy $num non-zero return code (exit code=".WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n");
                        $me->log_err_files($path, 0, \%err_seen);
                    }
                    Log(110, "Workload elapsed time (copy $num workload $counts[$num]) = $elapsedtime seconds".($skip_timing ? ' (not counted in total)' : '')."\n");
                    $child_times[$num] = { 'time' => 0, 'untime' => [0, 0], 'num' => $num } unless defined($child_times[$num]);
                    $child_times[$num]->{'lastline'} = "Copy $num of ".$me->benchmark.' ('.$me->tune.' '.$me->size.") run ".($iter+1)." finished at ".::timeformat('date-time', $endtime).".  Total elapsed time: ";
                    if ($skip_timing) {
                        # Remember the elapsed time per child so that it can be
                        # subtracted from the reported time.
                        $child_times[$num]->{'untime'}->[0] += $esec;
                        $child_times[$num]->{'untime'}->[1] += $ensec;
                    } else {
                        if (!defined($child_times[$num]->{'end'}) or $child_times[$num]->{'end'} < $endtime) {
                            $child_times[$num]->{'end'} = $endtime;
                        }
                        $child_times[$num]->{'time'} += $elapsedtime;
                        # When adding power intervals, round end times up,
                        # and start times down, to the nearest second.
                        # This will help catch intervals for very short-
                        # running benchmarks, and won't adversely affect
                        # long-running ones.
                        my $starttime = ::floor($endtime - $elapsedtime);
                        $endtime = int($endtime + 0.5);
                        ::add_interval(\@power_intervals,
                                       $endtime,
                                       $endtime - $starttime);
                    }

                } elsif ($runline =~ m/timer ticks over every (\d+) ns/) {
                    # Figure out the number of significant decimal places
                    # for the reported times.
                    my $tmpdp = new Math::BigFloat $1+0;
                    $tmpdp->bdiv(1_000_000_000);  # Convert to seconds
                    $tmpdp->blog(10);             # Get number of decimal places
                    if ($tmpdp->is_neg()) {
                        $result->{'dp'} = abs(int($tmpdp->bstr() + 0));
                    } else {
                        # This shouldn't happen.  If it does, we're screwed --
                        # it means the timer has granularity of at least 1
                        # second.  So just don't figure the decimal places.
                        Log(0, "WARNING: System timer resolution is less than .1 second\n");
                    }

                } elsif ($runline =~ m/runs elapsed time:\s*(\d+),\s*(\d+)/) {
                    if ($me->runmode =~ /rate$/) {
                        # The length of a rate run is from the start of the
                        # first timed section of any copy to the end of the
                        # last timed section of any copy.
                        # These times may differ quite significantly from what
                        # specinvoke reports on this line.
                        # This could of course include some time taken by
                        # an untimed section, but never in a way that would
                        # change what the overall duration would be.
                        # Best to just not have untimed sections in rate
                        # benchmarks.
                        my ($starttime) = (sort { $a->{'start'} <=> $b->{'start'} } @child_times);
                        $starttime = $starttime->{'start'} if ref($starttime) eq 'HASH';
                        my ($endtime) = (sort { $b->{'end'} <=> $a->{'end'} } @child_times);
                        $endtime = $endtime->{'end'} if ref($endtime) eq 'HASH';
                        if (defined($starttime) and $starttime + 0 > 0 and
                            defined($endtime) and $endtime + 0 > 0) {
                            $result->{'reported_sec'}  = int($endtime - $starttime);
                            $result->{'reported_nsec'} = int(($endtime - $starttime - $result->{'reported_sec'}) * 1_000_000_000);
                            $result->{'rate_start'} = $starttime;
                            $result->{'rate_end'}   = $endtime;
                        } else {
                            $result->{'valid'} = 'TE';
                            my $msg = "could not get rate run times: start=".(defined($starttime) ? $starttime : 'undef')."; end=".(defined($endtime) ? $endtime : 'undef');
                            Log(0, "\nERROR: ".$me->benchmark.": ".$msg."\n\n");
                            push @{$result->{'errors'}}, "$msg\n";
                        }

                    } else {
                        # The speed case is a lot more intuitive.
                        $result->{'reported_sec'}  = $1;
                        $result->{'reported_nsec'} = $2;

                        # Now subtract the "un"time.  There's always just one,
                        # since in speed mode there's only one copy being run.
                        $result->{'reported_sec'} -= $child_times[0]->{'untime'}->[0];
                        $result->{'reported_nsec'} -= $child_times[0]->{'untime'}->[1];
                        if ($result->{'reported_nsec'} < 0) {
                            $result->{'reported_sec'}--;
                            $result->{'reported_nsec'} += 1_000_000_000;
                        }
                    }
                } elsif ($runline =~ m/specinvoke exit: rc=(\d+)/) {
                    if ($1 != $specrun_rc) {
                        # What specinvoke says its exit code was is definitive
                        $specrun_rc = $1;
                    }
                }
            }
            $fh->close;

            if ($specrun_rc != 0 or $specrun_sig != 0) {
                $result->{'valid'} = 'RE';
                Log(0, "\n".$me->benchmark.': '.$me->specrun." non-zero return code (exit code=${specrun_rc}, signal=${specrun_sig})\n\n");
                push (@{$result->{'errors'}}, $me->specrun." non-zero return code (exit code=${specrun_rc}, signal=${specrun_sig})\n");
                $me->log_err_files($path, 1, \%err_seen);
            }

            my $lifetime = Time::HiRes::time() - $main::runcpu_time;
            $lifetime++ unless ($lifetime);
            foreach my $ref (@child_times) {
                next unless defined($ref);
                if (ref($ref) ne 'HASH') {
                    Log(0, "Non-HASH ref found in child stats: $ref\n");
                } else {
                    if ($ref->{'time'} - 1 > $lifetime) {
                        # Something stupid has happened, and an elapsed time
                        # greater than the total amount of time in the run so
                        # far has been claimed.
                        Log(0, "\n".
                               "ERROR: Claimed elapsed time of ".$ref->{'time'}." for copy #".$ref->{'num'}." of ".$me->benchmark." is longer than\n".
                               "       total run time of $lifetime seconds.\n".
                               "       This is extremely bogus and the run will now be stopped.\n");
                        main::do_exit(1);
                    }
                    Log(125, $ref->{'lastline'}.$ref->{'time'}."\n");
                    $result->{'copytime'}->[$ref->{'num'}] = $ref->{'time'};
                }
            }

            if (($::from_runcpu & 1) == 0
                    and istrue($me->power)
                    and !$is_training) {
                # Now trim up the power samples.  This will select based
                # on sample time, discard (if applicable), and recalculate
                # min/avg/max.
                my ($newavg, $junk, $newmin, $newmax, @newsamples) = ::extract_samples($result->{'powersamples'}, \@power_intervals, $me->discard_power_samples);
                if (defined($newavg) && @newsamples) {
                    ($result->{'avg_power'}, $result->{'min_power'}, $result->{'max_power'}, @{$result->{'powersamples'}}) = ($newavg, $newmin, $newmax, @newsamples);
                } else {
                    Log(0, "ERROR: No power samples found during benchmark run\n");
                    $result->{'valid'} = 'PE';
                    push @{$result->{'errors'}}, "(PE) no power samples found during benchmark run\n";
                }
            }

        } elsif (!istrue($me->fake)) {
            $result->{'valid'} = 'RE';
            Log(0, "couldn't open specrun result file '$resfile'\n");
            push (@{$result->{'errors'}}, "couldn't open specrun result file\n");
        }

        # For regular runs, proceed to validation even if there were
        # measurement (PE) or environmental (EE) errors.  This is so
        # that the result can potentially be reformatted with --nopower.
        # Avoid making a no-validation loophole. :)
        if (
            $me->accessor_nowarn('fdocommand') ne ''
            # There was a problem reading the results
                and ($error
                # The result failed for reasons other than power or physical environment
                    or $result->{'valid'} !~ /^(?:S|PE|EE)$/
                # The errors were logged and the result is not marked as having power or physical environment errors
                    or ($result->{'valid'} !~ /^(?:PE|EE)$/ and @{$result->{'errors'}}+0 > 0)
                )
           ) {
           return $result;
       }
    } else {
        # Just in case
        %ENV = %oldENV;
    }

    # Now make sure that the results compared!
    if ($me->action eq 'only_run' && !$is_training) {
        $result->{'valid'} = 'R?' if $result->{'valid'} eq 'S';
    } elsif ($result->{'valid'} =~ /^(?:S|PE|EE)$/) {
        my $size        = $me->size;
        my $size_class  = $me->size_class;
        my $tune        = $me->tune;

        if (istrue($me->fake)) {
            Log(0, "\nBenchmark verification\n");
            Log(0, "----------------------\n");
        }

        if (!$setup) {
            # If we're just setting up, there won't be any output files
            # to fix up in pre_compare().
            if ($me->pre_compare(@dirs)) {
                Log(0, "pre_compare for " . $me->benchmark . " failed!\n");
            }
            # There also won't be any run-time flags info (for ACCEL; not CPU).
            my @run_flags = $me->add_runtime_flags(@dirs);
            if ($run_flags[0] < 0) {
                Log(0, "add_runtime_flags for " . $me->benchmark . " failed!\n");
                $result->{'valid'} = 'RE';
                push (@{$result->{'errors'}}, $run_flags[1] || "Error retrieving run-time flags info");
            } elsif (@run_flags) {
                $me->{'baggage'} .= 'flag: '.join("\nflag: ", @run_flags)."\n";
            }
        }

        # Get benchmark-specific compare commands to run before specdiff
        my @compare_cmds;
        eval { @compare_cmds = $me->compare_commands() };
        if ($@) {
            Log(0, "ERROR: compare_commands() failed for ".$me->benchmark."\n");
            Log(190, $@);
            $result->{'valid'} = 'TE';
            push @{$result->{'errors'}}, "compare_commands() failed\n";
            return $result;
        }
        my ($threads, $user_set_env, %oldENV) = $me->setup_run_environment(0, 0);

        # Setting runmode to 'compare' will enable the use_submit_for_compare
        # setting to come into play.  We only want that to happen when submit
        # would've been used for the run as well.
        my $runmode_override = ($me->runmode =~ /rate$/ or istrue($me->use_submit_for_speed)) ? 'compare' : 'unset';
        my $precomp_ref = {
            'stagger'                 => 0,
            'env_vars'                => 0,
            'device'                  => '',
            'platform'                => '',
            'use_submit_for_speed'    => 0,
            'runmode'                 => $runmode_override,
            'command'                 => '',
            'commandexe'              => '',
            'copynum'                 => 0,
            'fdocommand'              => '',
            'enable_monitor'          => 0,
        };
        if ($runmode_override eq 'unset') {
            # Do not disable $BIND unless submit won't be used
            $precomp_ref->{'bind'} = [ ];
        }
        $me->unshift_ref($precomp_ref);
        # It's also necessary to set cl_opt_override for runmode, in case the
        # user has specified the run mode on the command line.
        $me->set_cl_override('runmode');

        my $num_output_files = 0;
        my $can_commandfile_k = (::specinvoke_cmd_can('-k') == 1) || 0;

        # Figure out the parameters for all of the output files once, and
        # then apply them for each run directory
        my %specdiff_opts = ();
        my @diffcmds = ();
        for my $absname ($me->output_files_abs) {
            next unless defined($absname);
            my $relname = basename($absname);
            my $cur_diff = {
                'command' => jp($me->top, 'bin', $specperl),
                'args'    => [ jp($me->top, 'bin', 'harness', $me->specdiff), '-m', '-l', $me->difflines ],
                'output'  => $relname.'.cmp',
                'opts'    => $can_commandfile_k ? [ '-k' ] : [],
            };

            $specdiff_opts{'cw'}           = $me->compwhite   ($size, $size_class, $tune, $relname);
            $specdiff_opts{'floatcompare'} = $me->floatcompare($size, $size_class, $tune, $relname);
            $specdiff_opts{'calctol'}      = $me->calctol     ($size, $size_class, $tune, $relname);
            $specdiff_opts{'abstol'}       = $me->abstol      ($size, $size_class, $tune, $relname);
            $specdiff_opts{'reltol'}       = $me->reltol      ($size, $size_class, $tune, $relname);
            $specdiff_opts{'obiwan'}       = $me->obiwan      ($size, $size_class, $tune, $relname);
            $specdiff_opts{'skiptol'}      = $me->skiptol     ($size, $size_class, $tune, $relname);
            $specdiff_opts{'skipabstol'}   = $me->skipabstol  ($size, $size_class, $tune, $relname);
            $specdiff_opts{'skipreltol'}   = $me->skipreltol  ($size, $size_class, $tune, $relname);
            $specdiff_opts{'skipobiwan'}   = $me->skipobiwan  ($size, $size_class, $tune, $relname);
            $specdiff_opts{'binary'}       = $me->binary      ($size, $size_class, $tune, $relname);
            $specdiff_opts{'ignorecase'}   = $me->ignorecase  ($size, $size_class, $tune, $relname);
            $specdiff_opts{'nansupport'}   = $me->nansupport  ($size, $size_class, $tune, $relname);

            Log(150, "comparing '$relname' with ".join(', ', map { "$_=$specdiff_opts{$_}" } grep { defined($specdiff_opts{$_}) } sort keys %specdiff_opts)."\n") unless (istrue($me->fake) || $setup);

            # Add options that have skip- variants and take args
            foreach my $cmptype (qw(abstol reltol skiptol)) {
                if (defined($specdiff_opts{$cmptype}) and $specdiff_opts{$cmptype} ne '') {
                    push @{$cur_diff->{'args'}}, "--$cmptype", $specdiff_opts{$cmptype};
                }
                if (defined($specdiff_opts{"skip$cmptype"}) and $specdiff_opts{"skip$cmptype"} ne '') {
                    push @{$cur_diff->{'args'}}, "--skip$cmptype", $specdiff_opts{"skip$cmptype"};
                }
            }
            # skipobiwan is special because obiwan is a switch
            if (defined($specdiff_opts{'skipobiwan'}) and $specdiff_opts{'skipobiwan'} ne '') {
                push @{$cur_diff->{'args'}}, "--skipobiwan", $specdiff_opts{'skipobiwan'};
            }

            # Add options for switches that default to off
            foreach my $cmptype (qw(calctol obiwan binary cw floatcompare
                                    ignorecase)) {
                if (defined($specdiff_opts{$cmptype})
                        and istrue($specdiff_opts{$cmptype})) {
                    push @{$cur_diff->{'args'}}, "--$cmptype";
                }
            }
            # Add options for switches that default to on
            foreach my $cmptype (qw(nansupport)) {
                if (defined($specdiff_opts{$cmptype})
                        and $specdiff_opts{$cmptype} ne ''
                        and !istrue($specdiff_opts{$cmptype})) {
                    push @{$cur_diff->{'args'}}, "--no$cmptype";
                }
            }
            push @{$cur_diff->{'args'}}, $absname, $relname;
            $num_output_files += @dirs;
            push @diffcmds, $cur_diff;
        }

        if ($num_output_files == 0) {
            Log(0,
                "\nNo output files were found to compare!  Evil is afoot, or the benchmark\n",
                "tree is corrupt or incomplete.\n\n");
            main::do_exit(1);
        }

        # The -k tells specinvoke to keep going.  If possible we only apply it
        # to specdiff runs.  If not possible then to any validation commands
        # as well.
        my ($comparename, $compareout, undef, $specrun, undef) = $me->prep_specrun($result, \@dirs,
                    $me->comparefile, $me->compareoutfile,
                    \%oldENV, 1, $is_training, 0,
                    [
                        '-E',
                        [ '-e', $me->compareerrfile    ],
                        [ '-o', $me->comparestdoutfile ],
                        $can_commandfile_k ? () : '-k',
                    ],
                    'compare_commands', (@compare_cmds, @diffcmds));
        $me->unset_cl_override('runmode');
        $me->shift_ref();
        if ($setup or $result->{'valid'} eq 'TE' or !defined($comparename)) {
            %ENV = %oldENV;
            return $result;
        }

        my $specrun_wrapper = '';
        my $command = join (' ', @{$specrun});
        if (istrue($me->force_monitor) and $me->do_monitor($is_training)) {
            $specrun_wrapper = $me->assemble_monitor_specrun_wrapper;
            if ($specrun_wrapper ne '') {
                $command = ::command_expand($specrun_wrapper, [ $me,
                        {
                            'iter'    => $iter,
                            'command' => $command,
                            'phase'   => 'compare'
                        } ]);
                $command = "echo \"$command\"" if istrue($me->fake);
            }
        }
        Log(191, "Specinvoke: $command\n") unless istrue($me->fake);
        my $outname = istrue($me->fake) ? 'compare_run' : undef;
        my $rc = ::log_system($command, { 'basename' => $outname, 'env_vars' => istrue($me->env_vars) });
        if (defined($rc) && $rc) {
            $me->log_err_files($path, 1, \%err_seen);
        }
        %ENV = %oldENV;

        # Scan the specdiff output files for indications of completed
        # runs.
        my @misfiles = ();
        my %specdiff_errors = ();
        my @missing = ();
        my @empty = ();
        for my $obj (@dirs) {
            my $file;
            my $dh = new IO::Dir $obj->path;
            while (defined($file = $dh->read)) {
                next if $file !~ m/\.(mis|cmp)$/i;
                if ($1 eq 'mis') {
                    # Remember it for later
                    push @misfiles, jp($obj->path, $file);
                    next;
                }
                my ($basename) = $file =~ m/(.*)\.cmp$/;
                my $cmpname = jp($obj->path, $file);
                my $orig_file = jp($obj->path, $basename);
                if (!-e $orig_file) {
                    push @missing, $orig_file;    # Shouldn't happen here
                } else {
                    my $diff_ok = 0;
                    my $fh = new IO::File "<$cmpname";
                    if (!defined($fh)) {
                        if (-s $orig_file <= 0) {
                            push @empty, $orig_file;
                            $diff_ok = 1;       # Not really, but only generate one kind of complaint
                        } else {
                            Log(0, "*** specdiff error on $basename; no output was generated\n");
                            $rc = 1 unless $rc;
                        }
                    } else {
                        # Just read it in to make sure specdiff said "all ok"
                        while(<$fh>) {
                            $diff_ok = 1 if /^specdiff run completed$/o;
                            last if $diff_ok;
                        }
                        $fh->close();
                    }
                    if ($diff_ok == 0) {
                        $specdiff_errors{$cmpname}++;
                        $rc = 1 unless $rc;
                    }
                }
            }
        }
        if ($rc) {
            $result->{'valid'} = 'VE' if $result->{'valid'} =~ /^(?:S|PE|EE)$/;
            push (@{$result->{'errors'}}, "Output miscompare");
            my $logged = 0;
            while (defined(my $misname = shift(@misfiles))) {
                my $cmpname = $misname;
                $cmpname =~ s/\.mis$/.cmp/o;
                my $basename = basename($misname, '.mis');
                my $dirname = dirname($misname);
                my $orig_file = ::jp($dirname, $basename);

                if (!-e $orig_file) {
                    push @missing, $orig_file;    # Shouldn't happen here
                } elsif (-s $orig_file <= 0) {
                    push @empty, $orig_file unless grep m/^\Q$orig_file\E/, @empty;
                } else {
                    my $msg = "\n*** Miscompare of $basename";
                    if (-s $misname > 0) {
                        $msg .= "; for details see\n    $misname\n";
                    } else {
                        $msg .= ", but the miscompare file is empty.\n";
                    }
                    Log (0, $msg);
                    $logged = 1;
                    my $fh = new IO::File "<$misname";
                    if (!defined $fh) {
                        if ($specdiff_errors{$cmpname}) {
                            Log(0, "specdiff did not complete successfully!\n");
                        } else {
                            Log (0, "Can't open miscompare file!\n");
                        }
                    } else {
                        while (<$fh>) {
                            Log (120, $_);
                        }
                        $fh->close();
                    }
                    delete $specdiff_errors{$cmpname};
                }
            }
            if (@missing) {
                if (@missing > 1) {
                    Log(0, "\n*** The following output files were expected, but were not found:\n");
                } else {
                    Log(0, "\n*** The following output file was expected, but does not exist:\n");
                }
                Log(0, '      '.join("\n      ", @missing)."\n".
                    "    This often means that the benchmark did not start, or failed so\n".
                    "    quickly that some output files were not even opened.\n".
                    "    Possible causes may include:\n".
                    "      - Did you run out of memory? (Check both your process limits and the system limits.)\n".
                    "      - Did you run out of disk space? (Check both your process quotas and the actual disk.)\n".
                    "    See also any specific messages printed in .err or .mis files in the run directory.\n\n");
                foreach my $missing_file (@missing) {
                    delete $specdiff_errors{$missing_file.'.cmp'};
                }
                $logged = 1;
            }
            if (@empty) {
                if (@empty > 1) {
                    Log(0, "\n*** The following output files had no content:\n");
                } else {
                    Log(0, "\n*** The following output file had no content:\n");
                }
                Log(0, '      '.join("\n      ", @empty)."\n".
                    "    This often means that the benchmark did not start, or failed so\n".
                    "    quickly that some output files were not written.\n".
                    "    Possible causes may include:\n".
                    "      - Did you run out of memory? (Check both your process limits and the system limits.)\n".
                    "      - Did you run out of disk space? (Check both your process quotas and the actual disk.)\n".
                    "    See also any specific messages printed in .err or .mis files in the run directory.\n\n");
                foreach my $empty_file (@empty) {
                    delete $specdiff_errors{$empty_file.'.cmp'};
                }
                $logged = 1;
            }
            foreach my $diff_error (sort keys %specdiff_errors) {
                Log(0, "\n*** Error comparing $diff_error: specdiff did not complete\n");
            }
            Log(0, "\nCompare command returned $rc!\n") unless $logged;
        }
    }

    return $result if ($me->accessor_nowarn('fdocommand') ne '');

    my $reported_sec  = $result->{'reported_sec'};
    my $reported_nsec = $result->{'reported_nsec'};
    my $reported = $reported_sec + ::round($reported_nsec / 1_000_000_000, $result->{'dp'});
    $result->{'reported_time'} = $reported;
    $result->{'energy'}        = (defined($reported) && $reported) ? ::round($result->{'avg_power'} * $reported, $result->{'dp'}) : 0;

    if (defined($reported) and $reported < 0) {
        # Something stupid has happened, and a negative elapsed time has been
        # calculated.
        Log(0, "\n".
            "ERROR: Claimed elapsed time of ${reported}s for ".$me->benchmark." is negative.\n".
            "       This is extremely bogus and the run will now be stopped.\n");
        main::do_exit(1);
    }

    if ($me->size_class eq 'ref') {
        $result->calc_ratio($me->size, $me->size_class, $me->reference, $me->reference_power);
    }

    if (!istrue($me->fake)) {
        Log (155, "Benchmark Times:\n",
            '  Run Start:    ', ::timeformat('date-time', $start), " ($start)\n",
            defined($result->{'rate_start'}) ?
            ('  Rate Start:   ', ::timeformat('date-time', $result->{'rate_start'}), " ($result->{'rate_start'})\n") : '',
            defined($result->{'rate_end'}) ?
            ('  Rate End:     ', ::timeformat('date-time', $result->{'rate_end'}), " ($result->{'rate_end'})\n") : '',
             '  Run Stop:     ', ::timeformat('date-time', $stop),  " ($stop)\n",
             '  Run Elapsed:  ', ::to_hms($elapsed), " ($elapsed)\n",
             '  Run Reported: ', ::to_hms($reported), " ($reported_sec $reported_nsec $reported)\n");
    }

    push (@{$me->{'result_list'}}, $result);
    chdir($origwd);
    return $result;
}

sub check_threads {
    # Placeholder function
    return 0;
}

sub pre_build {
    # Placeholder function
    return 0;
}

sub generate_inputs {
    # Placeholder function
    return ();
}

sub post_setup {
    # Placeholder function
    return 0;
}

sub compare_commands {
    # Placeholder function
    return ();
}

sub pre_compare {
    # Placeholder function
    return 0;
}

sub pre_run {
    # Placeholder function
    return 0;
}

sub add_runtime_flags {
    # Placeholder function
    return ();
}

sub extract_opencl_device_info {
    # Helper function for OpenCL benchmarks
    my ($me, @files) = @_;
    my @rc = ();

    foreach my $file (@files) {
        my %tmp = ('S' => '', 'D' => []);
        my @devinfo = main::read_file($file);
        if (@devinfo == 0) {
            return (-1, "No output in '$file'");
        }
        foreach my $line (@devinfo) {
            next unless ($line =~ s/\s*\(SELECTED\)\s*//);
            if ($line =~ /PLATFORM\s*=\s*(.*)/) {
                if ($tmp{'S'} ne '' && $tmp{'S'} ne $1) {
                    ::Log(0, "ERROR: OpenCL platform found in '$file' ($1) does not match previous ($tmp{'S'})\n");
                    return (-1, "Different OpenCL platform values found in the same iteration");
                } else {
                    $tmp{'S'} = "OpenCL-Platform=\"$1\"";
                }
            } elsif ($line =~ /\s*\+\s*(\d+):\s*(.*)/) {
                if (defined($tmp{'D'}->[$1]) && $tmp{'D'}->[$1] ne $2) {
                    ::Log(0, "ERROR: OpenCL device #$1 found in '$file' ($2) does not match previous ($tmp{'D'}->[$1])\n");
                    return (-1, "Different OpenCL device values found in the same iteration");
                } else {
                    $tmp{'D'}->[$1] = "OpenCL-Device-$1=\"$2\"";
                }
            }
        }
        $tmp{'D'} = join("\nD: ", grep { defined } @{$tmp{'D'}});
        my @tmprc = ('RUN: ', map { "$_: ".$tmp{$_} } reverse sort keys %tmp);
        if (@rc) {
            # Compare them to make sure it's consistent from dir to dir
            if (@rc == @tmprc) {
                # Same number of outputs; a good sign
                for(my $i = 0; $i < @rc; $i++) {
                    if ($rc[$i] ne $tmprc[$i]) {
                        ::Log(0, "ERROR: OpenCL device/platform info inconsistency in the same iteration: '$rc[$i]' vs '$tmprc[$i]'\n");
                        return (-1, "Different OpenCL device or platform values found in the same iteration");
                    }
                }
            } else {
                # Different number of outputs; a bad sign
                ::Log(0, "ERROR: OpenCL device/platform info inconsistency in the same iteration\n");
                return (-1, "Different OpenCL device or platform values found in the same iteration");
            }
        } else {
            @rc = @tmprc;
        }
    }

    return @rc;
}

sub result_list {
    my ($me, $copies) = @_;

    if ($::lcsuite eq 'cpu2017' and defined $copies) {
        return grep ($_->copies == $copies, @{$me->{'result_list'}});
    } else {
        return @{$me->{'result_list'}};
    }
}

sub ratio {
    my ($me, $num_copies) = @_;
    my @res = @{$me->{'result_list'}};
    if (defined $num_copies) {
        @res = grep ($_->copies == $num_copies, @res);
    }
    @res = sort { $a->{'ratio'} <=> $b->{'ratio'} } @{$me->{'result_list'}};
    if (@res % 2) {
        return $res[(@res-1)/2]; # Odd # results, return the median ratio
    } else {
        # For even # of results, return the lower median.
        # See chapter 9 of Cormen, Thomas, et al. _Introduction to Algorithms,
        #   2nd Edtion_. Cambridge: MIT Press, 2001
        return $res[@res/2-1];   # Return the lower median
    }
}

sub lock_listfile {
    my ($me, $type) = @_;

    my $subdir = $me->expid;
    $subdir = undef if ($subdir eq '');
    my $path = $me->{'path'};
    if (::check_output_root($me->config, $me->output_root, 0)) {
        my $oldtop = ::make_path_re($me->top);
        my $newtop = $me->output_root;
        $path =~ s/^$oldtop/$newtop/;
    }

    my $dir;
    if ($type eq 'build') {
        $dir = jp($path, $::global_config->{'builddir'}, $subdir);
    } else {
        $dir = jp($path, $::global_config->{'rundir'}, $subdir);
    }
    my $file      = jp($dir,  $me->worklist);
    my $obj = Spec::Listfile->new($dir, $file);
    $me->{'listfile'} = $obj;
    return $obj;
}

sub log_err_files {
    my ($me, $path, $specinvoke_problem, $already_done) = @_;
    $already_done = {} unless ::reftype($already_done) eq 'HASH';
    my %to_do = ();

    # Read the contents of the error files (other than speccmds.err and
    # compare.cmd) and put them in the log file.
    # Since output (as for specmake) may be combined, also log contents
    # of any .out files that do not have a corresponding .err file.
    tie my %dir, 'IO::Dir', $path;
    if (!%dir) {
        Log(0, "\nCouldn't log contents of error files from $path: $!\n\n");
        return;
    }

    my $specinvoke_errfiles = join('|', $me->commanderrfile, $me->compareerrfile, $me->inputgenerrfile);
    $specinvoke_errfiles = qr/(?:$specinvoke_errfiles)$/;

    # Go through the list of files looking for *.out and *.err.  The sorting
    # allows us to know whether *.err exists by the time we see *.out.
    foreach my $file (sort grep { /\.(?:out|err)$/ and -f $_ } keys %dir) {
        next if exists($already_done->{$file});
        next if (!$specinvoke_problem && $file =~ /$specinvoke_errfiles/);
        if ($file =~ s/\.out$//) {
            $to_do{$file.'.out'}++ if -s "${file}.out" and !exists($already_done->{"${file}.err"}) and !exists($to_do{"${file}.err"});
        } elsif ($file =~ /\.err$/) {
            if (-s $file) {
                $to_do{$file}++;
            } else {
                # Don't log the corresponding .out file if .err is empty
                $already_done->{$file}++;
            }
        }
    }
    foreach my $file (sort keys %to_do) {
        my $fh = new IO::File "<$file";
        next unless defined($fh);
        my $eol = $/;
        $/ = undef;
        Log(100, "\n****************************************\n");
        Log(100, "Contents of $file\n");
        Log(100, "****************************************\n");
        Log(100, <$fh>."\n");
        Log(100, "****************************************\n");
        $/ = $eol;
        $already_done->{$file}++ ;
    }
}

# Read and munge the output of 'specmake options'
sub read_compile_options {
    my ($fname, $pass, $compress_whitespace) = @_;
    my $rc = '';

    my $fh = new IO::File "<$fname";
    if (defined $fh) {
        while (<$fh>) {
            if ($^O =~ /MSWin/) {
                # Strip out extra quotes that Windows echo
                # may have left in
                if (s/^"//) {
                    s/"([\012\015]*)$/$1/;
                    s/\\"/"/;
                    s/\\"(?!.*\\")/"/;
                }
            }
            # Knock out unused variables (shouldn't be any)
            next if (/^[CPO]: _/o);
            # Ignore empty variables
            next if (m/^[CPO]: \S+="\s*"$/o);
            # Ignore lines containing the output filename (as could happen if
            # the command to delete the file prints something as it runs.)
            next if m/options\.tmpout/;
            # Fix up "funny" compiler variables
            s/^C: (CXX|F77)C=/C: $1=/o;
            # Add the current pass number (if applicable)
            s/:/$pass:/ if $pass ne '';
            if ($compress_whitespace) {
                # Normalize whitespace
                tr/ \012\015\011/ /s;
            } else {
                # Just normalize line endings
                tr/\012\015//d;
            }
            $rc .= "$_\n";
        }
        $fh->close();
    }

    return $rc;
}


# Read and munge the output of 'specmake compiler-version'
sub read_compiler_version {
    my ($fname, $pass) = @_;
    my $status = 0;
    my $rc = '';

    my $fh = new IO::File "<$fname";
    if (defined $fh) {
        while (defined(my $line = <$fh>)) {
            # If the compiler wants to crap things up, hide the evidence.
            # This also skips empty lines, because it's convenient.
            # Expand this as necessary.
            next if $line =~ m{
                ^\s*$
                |\Qwarning: argument unused during compilation:\E
            }xo;
            # Note missing options
            $status = 1 if $line =~ /version information option not set/;
            # Normalize line endings
            $line =~ tr/\012\015//d;
            $rc .= "$line\n";
        }
        $fh->close();
    }

    return ($status, $rc);
}

# Construct an action-oriented diagnostic.
sub whine_compiler_version {
    my $whine = <<EOT;
  ERROR: Compiler version missing!  For SPEC $::suite, you must add these
         lines to your config file:
            CC_VERSION_OPTION  = flag to print C compiler version
            CXX_VERSION_OPTION = flag to print C++ compiler version
            FC_VERSION_OPTION  = flag to print Fortran compiler version
         For more information and examples, please see:
            https://www.spec.org/$::lcsuite/Docs/config.html#compilerVersion
EOT
    my $longest = 0;
    for my $line (split "\n", $whine) {
        $longest = length($line) if length($line) > $longest;
    }
    my $bars = "-" x $longest;
    return "\n$bars\n$whine$bars\n\n";
}

# This sets up some default stuff for FDO builds
sub fdo_command_setup {
    my ($me, $targets, $make, @pass) = @_;
    $targets = [] unless (::ref_type($targets) eq 'ARRAY');
    my @targets = @$targets;

    my (@commands) = ('fdo_pre0');
    my $tmp = {
        'fdo_run1'         => '$command',
    };
    for (my $i = 1; $i < @pass; $i++) {
        if ($pass[$i]) {
            if ($i != 1) {
                foreach my $target (@targets) {
                    my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                    $tmp->{"fdo_make_clean_pass$i"} = "$make fdoclean FDO=PASS$i$targetflag";
                }
            }
            if (($i < (@pass-1)) && !exists($tmp->{"fdo_run$i"})) {
                $tmp->{"fdo_run$i"} = '$command';
            }
            push (@commands, "fdo_pre_make$i", "fdo_make_clean_pass$i");
            foreach my $target (sort @targets) {
                my $exe = ($target ne '') ? "_$target" : '';
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                $tmp->{"fdo_make_pass${i}${exe}"} ="$make --always-make build FDO=PASS$i$targetflag";
                push @commands, "fdo_make_pass${i}${exe}";
            }
            foreach my $thing ("fdo_make_pass$i", "fdo_post_make$i",
                "fdo_pre$i", "fdo_run$i", "fdo_post$i") {
                if (!grep { /^$thing/ } @commands) {
                    push @commands, $thing;
                }
            }
        }
    }

    return ($tmp, @commands);
}

sub get_mandatory_option_cksum_items {
    my ($me, @extras) = @_;
    my $rc = '';

    # CVT2DEV: $rc = "DEVELOPMENT TREE BUILD\n";
    foreach my $opt (sort (keys %option_cksum_include, grep { $_ ne '' } @extras)) {
        my $val = $me->accessor_nowarn($opt);
        if ((::ref_type($val) eq 'ARRAY')) {
            $val = join(',', @$val);
        } elsif ((::ref_type($val) eq 'HASH')) {
            $val = join(',', map { "$_=>$val->{$_}" } sort keys %$val);
        }
        if (defined($val) and $val ne '') {
            if ($opt eq 'version') {
                # Only record major.minor
                $val = ::normalize_version($val, 1);
            }
            $rc .= "$opt=\"$val\"\n";
        }
    }
    $rc = "Non-makefile options:\n".$rc if $rc ne '';
    return $rc;
}

sub get_srcalt_list {
    my ($me) = @_;

    if ((::ref_type($me->srcalt) eq 'ARRAY')) {
        return ( grep { defined($_) && $_ ne '' } @{$me->srcalt} );
    } elsif (   ref($me->srcalt) eq ''
        && defined($me->srcalt)
        && $me->srcalt ne '') {
        return ( $me->srcalt );
    }
    return ();
}

sub note_srcalts {
    my ($me, $opthashref, $nocheck, @srcalts) = @_;
    my $rc = '';

    foreach my $srcalt (@srcalts) {
        my $saref = $me->srcalts->{$srcalt};
        if (!defined($saref) || (::ref_type($saref) ne 'HASH')) {
            next unless $nocheck;
            $saref = { 'name' => $srcalt };
        }
        my $tmpstr = 'note: '.$me->benchmark.' ('.$me->tune."): \"$saref->{'name'}\" src.alt was used.";
        if ($opthashref->{'baggage'} !~ /\Q$tmpstr\E/) {
            if ($opthashref->{'baggage'} ne '' && $opthashref->{'baggage'} !~ /\n$/) {
                $opthashref->{'baggage'} .= "\n";
            }
            $opthashref->{'baggage'} .= $tmpstr;

            if ($rc ne '' && $rc !~ /\n$/) {
                $rc .= "\n";
            }
            $rc .= $tmpstr;
        }
    }
    return $rc;
}

sub specinvoke_dump_env {
    my ($me, $fh) = @_;

    return unless defined($fh);

    # Dump the environment into the specinvoke command file opened at $fh
    foreach my $envvar (sort keys %ENV) {
        # Skip read-only variables
        next if ($envvar =~ /^(_|[0-9]|\*|\#|\@|-|!|\?|\$|PWD|SHLVL)$/);
        if ($envvar =~ /\s/) {
            Log(110, "**WARNING: environment variable name '$envvar' contains whitespace and will be skipped in output\n");
            next;
        }
        my $origenvval = $ENV{$envvar};
        my $complaint_key = substr($envvar.$origenvval, 0, 2048); # Let's not hash too much
        if ($origenvval =~ /[\n\r]/) {
            if (!exists($me->config->{'env_hash_complaints'}->{$complaint_key})) {
                Log(110, "**WARNING: environment variable '$envvar' contains embedded CR or LF; they will be converted to spaces\n");
                $me->config->{'env_hash_complaints'}->{$complaint_key} = 1;
            }
            $origenvval =~ s/[\n\r]/ /g;
        }
        my $envval = $shellquote ? shell_quote_best_effort($origenvval) : $origenvval;
        if (length($envvar) + length($envval) + 6 >= 16384) {
            if (!exists($me->config->{'env_hash_complaints'}->{$complaint_key})) {
                Log(110, "**WARNING: Length of environment variable '$envvar' is too long; must be less than ".(16384 - length($envvar) - 6)." bytes; truncating value\n");
                $me->config->{'env_hash_complaints'}->{$complaint_key} = 1;
            }
            # Set the initial limit to (16KB - length of variable name
            # - 8 (space for '#', ' ', '-E ', '=', '\n', and terminating NULL))
            my $limit;
            do {
                $limit = 16384 - length($envvar) - 8;
                $origenvval = substr($ENV{$envvar}, 0, $limit - (length($envval) - length($origenvval)));
                $origenvval =~ s/\n.*//;        # Just in case
                $envval = $shellquote ? shell_quote_best_effort($origenvval) : $origenvval;
            } while (length($envval) > $limit);
        }
        print $fh "-E $envvar $envval\n";
    }
}

sub check_submit {
    my ($me, $submit, $is_training) = @_;

    ::Log(99, "check_submit for $me: called from ".(caller(1))[3]."\n");
    # This is written strangely to faciliate the debug output
    if ($submit ne '') {
        ::Log(99, "check_submit for $me: YES: submit ne '' ($submit)\n");

        if ($submit ne $::nonvolatile_config->{'default_submit'}) {
            ::Log(99, "check_submit for $me: YES: non-default submit\n");

            # Submit should only be used for training runs when plain_train is
            # unset and use_submit_for_speed is set.
            if ($is_training == 0
                    or (!istrue($me->plain_train)
                        and istrue($me->use_submit_for_speed))) {
                ::Log(99, "check_submit for $me: YES: not training ($is_training) or it's okay (!plain_train=".!istrue($me->plain_train).' and use_submit_for_speed='.istrue($me->use_submit_for_speed).")\n");

                if (($::from_runcpu & 1) == 0   # Skip for parallel test/train
                        and ($me->runmode =~ /rate$/
                            or ($me->runmode eq 'speed'
                                and istrue($me->use_submit_for_speed))
                            or ($me->runmode eq 'compare'
                                and istrue($me->use_submit_for_compare)))) {
                    ::Log(99, "check_submit for $me: YES: not in parallel test/train and (run mode (".$me->runmode.") is rate, or (speed and use_submit_for_speed (".istrue($me->use_submit_for_speed).")) or (compare and use_submit_for_compare (".istrue($me->use_submit_for_compare).")))\n");

                    ::Log(99, "check_submit for $me: YES\n");
                    return 1;
                } else {
                    ::Log(99, "check_submit for $me: NO: run mode (".$me->runmode.") is not rate, and !(speed and use_submit_for_speed (".istrue($me->use_submit_for_speed).")) and !(compare and use_submit_for_compare (".istrue($me->use_submit_for_compare)."))\n");
                }

            } else {
                ::Log(99, "check_submit for $me: NO: is training ($is_training) or it's not okay (plain_train=".istrue($me->plain_train).' or !use_submit_for_speed='.!istrue($me->use_submit_for_speed).")\n");
            }

        } else {
            ::Log(99, "check_submit for $me: NO: default submit\n");
        }

    } else {
        ::Log(99, "check_submit for $me: NO: submit eq ''\n");
    }

    ::Log(99, "check_submit for $me: NO\n");
    return 0;
}

sub prep_specrun {
    my ($me, $result, $dirs, $commands, $commands_output, $backup_env, $log_cmds, $is_training, $iter, $opts, $objgen_name, @objs) = @_;

    my $path = $dirs->[0]->path;
    my $tune = $me->tune;
    my $label = $me->label;
    my %submit = $me->assemble_submit();
    my $workload_num = 0;
    my @newcmds = ();
    my @skip_timing = ();
    my $command_add_redirect = istrue($me->command_add_redirect) ? (::specinvoke_cmd_can('-r') ? 2 : 1) : 0;
    my $commandfile_no_input = ::specinvoke_cmd_can('-N');
    my @opts = ();
    my @output_files = ();

    # Figure out how the no input case will be handled
    my $no_input_handler;
    if ($me->no_input_handler =~ /null/io) {
        $no_input_handler = 'N';
    } elsif ($me->no_input_handler =~ /(?:zero|file)/io) {
        $no_input_handler = 'Z';
    } else {
        $no_input_handler = 'C';
    }

    if (::reftype($opts) eq 'ARRAY') {
        foreach my $opt (@$opts) {
            if (::reftype($opt) ne 'ARRAY' and ::specinvoke_can($opt)) {
                push @opts, $opt;
            } else {
                my @args = ();
                if (::reftype($opt) eq 'ARRAY') {
                    ($opt, @args) = @{$opt};
                }
                if (::specinvoke_can($opt)) {
                    push @opts, $opt, @args;
                } else {
                    # This is logged at such a high level because it's
                    # unlikely that this error could ever be caused
                    # by a user.
                    $opt .= ' '.join(' ', @args) if @args;
                    ::Log(98, "WARNING: Requested specinvoke option '$opt' is not usable either in the command file or on the command line; ignoring\n");
                }
            }
        }
    }
    push @newcmds, '-r' if ($command_add_redirect == 2);
    push @newcmds, "-N $no_input_handler" if $commandfile_no_input;
    push @newcmds, '-S '.$me->stagger if ($me->runmode eq 'shrate');
    my $bindval = $me->bind;
    my @bindopts = (::ref_type($bindval) eq 'ARRAY') ? @{$bindval} : ();
    my $do_binding = defined($bindval) && @bindopts;
    for(my $i = 0; $i < @{$dirs}; $i++) {
        my $dir = $dirs->[$i];
        if ($do_binding) {
            $bindval = $bindopts[$i % ($#bindopts + 1)];
            $bindval = '' unless defined($bindval);
            push @newcmds, "-b $bindval";
        }
        push @newcmds, '-C ' . $dir->path;
    }
    for my $obj (@objs) {
        if (!defined($obj) || ::ref_type($obj->{'args'}) ne 'ARRAY') {
            # invoke() or generate_inputs() or whatever is unhappy
            Log(0, "ERROR: $objgen_name() failed for ".$me->benchmark."\n");
            $result->{'valid'} = 'TE';
            push (@{$result->{'errors'}}, "$objgen_name() failed\n");
            %ENV = %{$backup_env} if ::reftype($backup_env) eq 'HASH';
            return undef;
        }

        if ($::lcsuite eq 'accel') {
            # Append the supplied values for platform and device
            unshift @{$obj->{'args'}}, '--device', $me->device if $me->device ne '';
            unshift @{$obj->{'args'}}, '--platform', $me->platform if $me->platform ne '';
        }

        my $command = $obj->{'command'};
        if ($command ne 'specperl') {
            $command = ::path_protect(jp('..', basename($path), $command));
        } else {
            my $specperl = ($^O =~ /MSWin/) ? 'specperl.exe' : 'specperl';
            $command = ::path_protect(jp($me->top, 'bin', $specperl));
        }

        my $shortexe = $obj->{'command'};
        if (basename($shortexe, '.exe') eq 'specperl') {
            $shortexe = basename($obj->{'args'}->[0]);
            $shortexe = $obj->{'command'} if $shortexe eq '';
        }
        $shortexe =~ s/\Q_$tune.$label\E//;
        my $submit = exists($submit{$shortexe}) ? $submit{$shortexe} : $submit{'default'};
        # The path_protect/unprotect dance is to normalize the path separators
        # in the same way as will happen to $command later; the target-specific
        # submit command must be found first, though.
        $shortexe = ::path_unprotect(::path_protect($shortexe));

        # Protect path separators in submit; they'll be put back later
        $submit = ::path_protect($submit);
        $me->accessor_nowarn('commandexe', $command);
        $command .= ' ' . join (' ', @{$obj->{'args'}}) if @{$obj->{'args'}};
        if ($command_add_redirect != 0) {
            $command .= ' < '.$obj->{'input'} if ($obj->{'input'} ne '');
            $command .= ' > '.$obj->{'output'} if ($obj->{'output'} ne '');
            $command .= ' 2>> '.$obj->{'error'} if ($obj->{'error'} ne '');
        }
        push @output_files, $obj->{'input'}  if $obj->{'input'}  ne '';
        push @output_files, $obj->{'output'} if $obj->{'output'} ne '';
        push @output_files, $obj->{'error'}  if $obj->{'error'}  ne '';
        $command = ::path_protect($command);
        $me->command($command);

        ## expand variables and values in the command line
        if ($me->fdocommand ne '') {
            $command = ::command_expand($me->fdocommand,
                [ $me,
                    {
                        'iter' => $iter,
                        'workload' => $workload_num,
                    }
                ]);
            $command = ::path_protect($command);
            $me->command($command);
        } elsif ($me->do_monitor($is_training)) {
            my $wrapper = $me->assemble_monitor_wrapper;
            if ($wrapper ne '') {
                $wrapper = ::path_protect($wrapper);
                $command = ::command_expand($wrapper,
                    [ $me,
                        {
                            'iter' => $iter,
                            'workload' => $workload_num,
                        }
                    ]);
                $command = ::path_protect($command);
                $me->command($command);
            }
        }

        $me->copynum(0);

        if ($me->check_submit($submit, $is_training)) {
            Log(40, "Submit command for ".$me->descmode." (workload $workload_num):\n  ".::path_unprotect($submit)."\n");
            $command = ::command_expand($submit,
                [ $me,
                    {
                        'iter' => $iter,
                        'workload' => $workload_num
                    }
                ]);
            $command = ::path_protect($command);
            $me->command($command);
            $result->{'submit'} = 1;
        }
        my $opts = '';
        $opts .= join(' ', @{$obj->{'opts'}}).' ' if ::reftype($obj->{'opts'}) eq 'ARRAY';
        $opts .= '-i '. $obj->{'input'}  .' ' if (exists $obj->{'input'});
        $opts .= '-o '. $obj->{'output'} .' ' if (exists $obj->{'output'});
        $opts .= '-e '. $obj->{'error'}  .' ' if (exists $obj->{'error'});
        if ($command =~ m#^cmd # && $^O =~ /MSWin/) {
            # Convert line feeds (shouldn't exist anyway) into && for cmd.exe
            $command =~ s/[\r\n]+/\&\&/go;
        } else {
            $command =~ s/[\r\n]+/;/go;
        }
        $command = ::path_unprotect($command);
        $me->command($command);
        if ($command !~ /\Q$shortexe\E/) {  # This indicates a big problem
            Log(0, "ERROR: The $objgen_name command for workload #$workload_num of ".
                   $me->benchmark." would not\n".
                   "       result in any execution.\n");
            Log(120, "       The full command string does not contain the exectuable name ($shortexe):\n       $command\n");
            $result->{'valid'} = 'TE';
        }
        push @newcmds, "$opts$command";
        push @skip_timing, $obj->{'notime'} || 0;
        $workload_num++;
    }

    if (!$log_cmds) {
        Log(150, "Commands to run (specinvoke command file):\n");
        my $i = 0;
        my $show_bind = 0;
        # Scan backwards through commands to see if $BIND appears
        for($i = @newcmds; $i >= 0 && $newcmds[$i] !~ /^-[rNESbCu]/; $i--) {
            if ($newcmds[$i] =~ /\$BIND/) {
                $show_bind = 1;
                last;
            }
        }

        for($i = 0; $i < @newcmds && $newcmds[$i] =~ /^-[rNESbCu]/; $i++) {
            if ($newcmds[$i] =~ /^-[rNSCu]/ or
                ($show_bind and $newcmds[$i] =~ /^-b/)) {
                Log(150, "    $newcmds[$i]\n")
            }
        }
        # The apparent $i/$j confusion stems from the fact that @newcmds and
        # @skip_timing are NOT fully parallel arrays; @skip_timing has
        # entries only for actual commands to be executed; @newcmds has
        # specinvoke setup stuff too.
        for(my $j = 0; $i < @newcmds; $i++, $j++) {
            Log(150, "    $newcmds[$i] (".($skip_timing[$j] ? 'NOT ' : '')."timed)\n");
        }
    }

    # Abort now if there are problems in the run file that can't be fixed with rawformat --nopower
    return undef if $result->{'valid'} !~ /^(?:S|PE|EE)$/;

    my $absrunfile = jp($path, $commands);
    push @output_files, $commands;
    my $resfile    = jp($path, $commands_output);
    push @output_files, $commands_output;
    {
        my $fh = new IO::File ">$absrunfile";
        if (defined($fh)) {
            $me->specinvoke_dump_env($fh);
            print $fh join ("\n", @newcmds), "\n";
            $fh->close;
            my $expected_length = length(join("\n", @newcmds));
            $expected_length++ unless $expected_length;
            if (-s $absrunfile < $expected_length) {
                Log(0, "\n$absrunfile is short; evil is afoot,\n  or the benchmark tree is corrupted or incomplete.\n");
                main::do_exit(1);
            }
        } else {
            Log(0, "Error opening $absrunfile for writing!\n");
            main::do_exit(1);
        }
    }

    my @specrun = (
        jp($me->top, 'bin', $me->specrun),
        '-d', $path,
        '-f', $commands,
    );
    push @specrun, @opts;
    push @specrun, '-r'  if ($command_add_redirect == 1);
    push @specrun, '-nn' if istrue($me->fake);
    push @specrun, "-$no_input_handler" unless $commandfile_no_input;

    return ($absrunfile, $resfile, \@skip_timing, \@specrun, \@output_files);
}

sub feedback_passes {
    my ($me) = @_;

    my $fdo = 0;
    my @pass = ();

    if (istrue($me->feedback)) {
        for my $tmpkey ($me->list_keys) {
            if    ($tmpkey =~ m/^fdo_\S+?(\d+)/p   && $me->accessor_nowarn(${^MATCH}) ne '') {
                $pass[$1] = 1; $fdo = 1;
            }
            elsif ($tmpkey =~ m/^PASS(\d+)_(\S+)/p && $me->accessor_nowarn(${^MATCH}) ne '')    {
                my ($pass, $what) = ($1, $2);
                $what =~ m/^(\S*)(FLAGS|OPTIMIZE)/;
                if ($1 ne '' and $1 ne 'LD' and !grep { $_ eq $1 } @{$me->allBENCHLANG}) {
                    next;
                }
                $pass[$pass] = 1; $fdo = 1;
            }
        }
    }

    return ($fdo, @pass);
}

sub setup_run_environment {
    my ($me, $is_run, $is_training) = @_;
    $is_run = 1 unless defined($is_run);
    my %user_set_env = ();

    my $threads = $me->accessor_nowarn('threads');
    if ($is_training and istrue($me->train_single_thread)) {
        $threads = 1;
    }
    my %oldENV = %ENV;

    # Keep track of environment variables the user has asked to set.  If the tools override or otherwise set a variable
    # in this list, it will be removed to reflect the fact that the user-supplied value was not used.
    %user_set_env = map { $_ => $ENV{$_} } main::munge_environment($me) if istrue($me->env_vars);

    if (istrue($me->reportable) and $::lcsuite ne 'cpu2017') {
        $ENV{'OMP_NESTED'} = 'FALSE';
        delete $user_set_env{'OMP_NESTED'};
    }
    if ($::lcsuite ne 'mpi2007') {
        my @to_remove = ();
        my @openmp_var_list = (
            # From OpenMP API Specification v4.5, ch. 4 (or before)
            qw(
            OMP_THREAD_LIMIT
            OMP_STACKSIZE
            OMP_SCHEDULE
            OMP_DYNAMIC
            OMP_PROC_BIND
            OMP_PLACES
            OMP_NESTED
            OMP_WAIT_POLICY
            OMP_MAX_ACTIVE_LEVELS
            OMP_CANCELLATION
            OMP_DISPLAY_ENV
            OMP_DEFAULT_DEVICE
            OMP_MAX_TASK_PRIORITY),
            # From OpenMP API Specification v5.0, ch. 6
            qw(
            OMP_DISPLAY_AFFINITY
            OMP_AFFINITY_FORMAT
            OMP_TARGET_OFFLOAD
            OMP_TOOL
            OMP_TOOL_LIBRARIES
            OMP_DEBUG
            OMP_ALLOCATOR
            ));
        if ($::lcsuite eq 'cpu2017' and $me->runmode =~ /rate$/) {
            ::Log(0, "In SPECrate mode, threads is always 1 (ignoring setting of $threads)\n") if defined($threads) and $threads > 1 and $is_run;
            $threads = 1;
            # Remove other OpenMP environment variables
            push @to_remove, (grep { exists($ENV{$_}) } @openmp_var_list);
        }

        if (defined($threads) && $threads > 0) {
            $ENV{'OMP_NUM_THREADS'} = $threads;
            delete $user_set_env{'OMP_NUM_THREADS'};
            if ($::lcsuite eq 'cpu2017' and $threads == 1) {
                $ENV{'OMP_THREAD_LIMIT'} = $threads;
                delete $user_set_env{'OMP_THREAD_LIMIT'};
            }
        } else {
            unshift @to_remove, 'OMP_NUM_THREADS' if exists $ENV{'OMP_NUM_THREADS'};
        }

        if (@to_remove) {
            delete @ENV{@to_remove};
            delete @user_set_env{@to_remove};
            ::Log(121, "OpenMP environment variables removed: ".join(', ', @to_remove)."\n");
        } else {
            ::Log(121, "OpenMP environment variables removed: None\n");
        }
        my @openmp_vars = grep { exists($ENV{$_}) } ('OMP_NUM_THREADS', @openmp_var_list);
        if (@openmp_vars) {
            ::Log(121, "OpenMP environment variables in effect:\n\t".join("\n\t", map { "$_\t=> '$ENV{$_}'" } @openmp_vars)."\n");
        } else {
            ::Log(121, "OpenMP environment variables in effect: None\n");
        }
    }

    # The accelerator benchmark needs a couple of environment variables set
    # for OpenACC.  They will also be set for OpenCL and OpenMP, but won't
    # mean anything for the benchmark.  If the user passed in a value, set
    # it to that value; no judgement is made on the quality of what they gave us!
    if ($::lcsuite eq 'accel') {
        my @to_remove = ();
        if ( $me->device ne '' ) {
            $ENV{'ACC_DEVICE_NUM'} = $me->device;
            delete $user_set_env{'ACC_DEVICE_NUM'};
            ::Log(121, "OpenACC device (ACC_DEVICE_NUM) set to '".$me->device."'\n");
        } else {
            push @to_remove, 'ACC_DEVICE_NUM';
        }
        if ( $me->platform ne '' ) {
            $ENV{'ACC_DEVICE_TYPE'} = $me->platform;
            delete $user_set_env{'ACC_DEVICE_TYPE'};
            ::Log(121, "OpenACC platform (ACC_DEVICE_TYPE) set to '".$me->platform."'\n");
        } else {
            push @to_remove, 'ACC_DEVICE_TYPE';
        }
        if (@to_remove) {
            delete @ENV{@to_remove};
            delete @user_set_env{@to_remove};
            ::Log(121, "OpenACC environment variables removed: ".join(', ', @to_remove)."\n");
        } else {
            ::Log(121, "OpenACC environment variables removed: None\n");
        }
    }

    # Log changes made to %ENV
    my @changes = ();
    foreach my $item (sort(::unique_elems(keys %oldENV, keys %ENV))) {
        if (exists($ENV{$item}) and exists($oldENV{$item})) {
            if ($ENV{$item} ne $oldENV{$item}) {
                push @changes, "'$item' changed: (value now '$ENV{$item}')".(exists($user_set_env{$item}) ? ' [user supplied]' : '');
            }
        } elsif (exists($ENV{$item})) {
            push @changes, "'$item' added: (value now '$ENV{$item}')".(exists($user_set_env{$item}) ? ' [user supplied]' : '');
        } elsif (exists($oldENV{$item})) {
            push @changes, "'$item' removed (value was '$oldENV{$item}')";
        }
    }
    if (@changes) {
        Log(110, "Pre-run environment changes:\n\t".join("\n\t", @changes)."\n");
    }

    return ($threads, { %user_set_env }, %oldENV);
}

1;

# Editor settings: (please leave this at the end of the file)
# vim: set filetype=perl syntax=perl shiftwidth=4 tabstop=8 expandtab nosmarttab mouse= colorcolumn=120:
