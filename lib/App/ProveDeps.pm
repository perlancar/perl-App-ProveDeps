package App::ProveDeps;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use File::chdir;

our %SPEC;

sub _find_dist_dir {
    my ($dist, $dirs) = @_;

  DIR:
    for my $dir (@$dirs) {
        my @entries = do {
            opendir my $dh, $dir or do {
                warn "prove-deps: Can't opendir '$dir': $!\n";
                next DIR;
            };
            my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
            closedir $dh;
            @entries;
        };
        #log_trace("entries: %s", \@entries);
      FIND:
        {
            my @res;

            # exact match
            @res = grep { $_ eq $dist } @entries;
            #log_trace("exact matches: %s", \@res);
            return "$dir/$res[0]" if @res == 1;

            # case-insensitive match
            my $dist_lc = lc $dist;
            @res = grep { lc($_) eq $dist_lc } @entries;
            return "$dir/$res[0]" if @res == 1;

            # suffix match, e.g. perl-DIST or cpan_DIST
            @res = grep { /\A\w+[_-]\Q$dist\E\z/ } @entries;
            #log_trace("suffix matches: %s", \@res);
            return "$dir/$res[0]" if @res == 1;

            # prefix match, e.g. DIST-perl
            @res = grep { /\A\Q$dist\E[_-]\w+\z/ } @entries;
            return "$dir/$res[0]" if @res == 1;
        }
    }
    undef;
}

sub _prove {
    require IPC::System::Options;

    my $opts = shift;

    my $stdout = "";
    my $stderr = "";

    my $act_stdout;
    my $act_stderr;
    if (log_is_warn()) {
        $act_stdout = "tee_stdout";
        $act_stderr = "tee_stderr";
    } else {
        $act_stdout = "capture_stdout";
        $act_stderr = "capture_stderr";
    }
    IPC::System::Options::system(
        {
            log=>1,
            ($act_stdout => \$stdout) x !!$act_stdout,
            ($act_stderr => \$stderr) x !!$act_stderr,
        },
        "prove", @{ $opts || [] },
        log_is_debug() ? ("-v") : (),
    );
    if ($?) {
        if ($stdout =~ /^Result: FAIL/m) {
            my $detail = "";
            if ($stdout =~ m!^(Failed \d+/\d+ subtests|No subtests run)!m) {
                $detail = " ($1)";
            }
            [500, "Test failed". $detail];
        } else {
            [500, "Non-zero exit code (".($? >> 8).")"];
        }
    } else {
        if ($stdout =~ /^Result: PASS/m) {
            [200, "PASS"];
        } elsif ($stdout =~ /^Result: NOTESTS/m) {
            [200, "NOTESTS"];
        } else {
            [500, "No PASS marker"];
        }
    }
}

$SPEC{prove_deps} = {
    v => 1.1,
    summary => 'Prove all distributions depending on specified module(s)',
    description => <<'_',

To use this utility, first create `~/.config/prove-deps.conf`:

    dist_dirs = ~/repos
    dist_dirs = ~/repos-other

The above tells *prove-deps* where to look for Perl distributions. Then:

    % prove-deps Log::ger

This will search local CPAN mirror for all distributions that depend on
<pm:Log::ger> then search the distributions in the distribution directories,
`cd` to each and run `prove` in it.

_
    args => {
        modules => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module',
            schema => ['array*', of=>'perl::modname*'],
            req => 1,
            pos => 0,
            greedy => 1,
        },
        prove_opts => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'prove_opt',
            schema => ['array*', of=>'str*'],
            default => ['-l'],
        },
        dist_dirs => {
            summary => 'Where to find the distributions',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'dist_dir',
            schema => ['array*', of=>'dirname*'],
            req => 1,
        },

        phases => {
            summary => 'Only select dists that depend in these phases',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'phase',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
        },
        rels => {
            summary => 'Only select dists that depend using these relationships',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'rel',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
        },

        exclude_dists => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'rel',
            schema => ['array*', of=>'perl::distname*'],
            tags => ['category:filtering'],
        },
        include_dists => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'rel',
            schema => ['array*', of=>'perl::distname*'],
            tags => ['category:filtering'],
        },
        exclude_dist_pattern => {
            schema => 're*',
            tags => ['category:filtering'],
        },
        include_dist_pattern => {
            schema => 're*',
            tags => ['category:filtering'],
        },

        # XXX add arg: level, currently direct dependents only
        # XXX add arg: dzil test instead of prove
    },
    deps => {
        prog => 'prove',
    },
    features => {
        dry_run => 1,
    },
};
sub prove_deps {
    require App::lcpan::Call;

    my %args = @_;

    my $res = App::lcpan::Call::call_lcpan_script(
        argv => ['rdeps', @{ $args{modules} }],
    );

    return [500, "Can't lcpan rdeps: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;

    my @fails;
    my $i = 0;
  REC:
    for my $rec (@{ $res->[2] }) {
        $i++;
        if (defined $args{phases} && @{ $args{phases} }) {
            next REC unless grep $rec->{phase} eq $_, @{ $args{phases} };
        }
        if (defined $args{rel} && @{ $args{rel} }) {
            next REC unless grep $rec->{rel} eq $_, @{ $args{rel} };
        }
        log_info "Found dep: %s (%s %s)", $rec->{dist}, $rec->{phase}, $rec->{rel};

        my $dir = _find_dist_dir($rec->{dist}, $args{dist_dirs});
        unless (defined $dir) {
            log_error "Can't find dir for dist '%s', skipped", $rec->{dist};
            push @fails, {dist=>$rec->{dist}, reason=>"Can't find dist dir"};
            next REC;
        }

        if ($args{-dry_run}) {
            log_info("[DRY] [%d/%d] Running prove for dist '%s' in '%s' ...",
                     $i, scalar(@{ $res->[2] }),
                     $rec->{dist}, $dir);
            next REC;
        }

        {
            local $CWD = $dir;
            log_warn("[%d/%d] Running prove for dist '%s' in '%s' ...",
                     $i, scalar(@{ $res->[2] }),
                     $rec->{dist}, $dir);
            my $pres = _prove($args{prove_opts});
            log_debug("Prove result: %s", $pres);
            if ($pres->[0] == 200) {
                # success
            } else {
                log_error "Test for dist '%s' failed: %s",
                    $rec->{dist}, $pres->[1];
                push @fails, {dist=>$rec->{dist}, reason=>$pres->[1]};
            }
        }
    }

    [
        @{@fails == 0 ? [200, "All succeeded"] : @fails == @{$res} ? [500, "All failed"] : [200, "Some failed"]},
        \@fails
    ];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<prove-deps>.


=head1 TODO

Download distributions.


=head1 SEE ALSO

L<prove>

L<App::lcpan>
