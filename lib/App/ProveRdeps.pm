package App::ProveRdeps;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use App::ProveDists ();
use Hash::Subset qw(hash_subset);

our %SPEC;

$SPEC{prove_rdeps} = {
    v => 1.1,
    summary => 'Prove all distributions depending on specified module(s)',
    description => <<'_',

To use this utility, first create `~/.config/prove-rdeps.conf`:

    dists_dirs = ~/repos
    dists_dirs = ~/repos-other

The above tells *prove-rdeps* where to look for Perl distributions. Then:

    % prove-rdeps Regexp::Pattern

This will search local CPAN mirror for all distributions that depend on
<pm:Log::ger> (by default for phase=runtime and rel=requires), then search the
distributions in the distribution directories (or download them from local CPAN
mirror), `cd` to each and run `prove` in it.

You can run with `--dry-run` (`-n`) option first to not actually run `prove` but
just see what distributions will get tested. An example output:

    % prove-rdeps Regexp::Pattern -n
    prove-rdeps: Found dep: Acme-DependOnEverything (runtime requires)
    prove-rdeps: Found dep: App-BlockWebFlooders (runtime requires)
    prove-rdeps: Found dep: App-Licensecheck (runtime requires)
    prove-rdeps: Found dep: Pod-Weaver-Plugin-Regexp-Pattern (develop x_spec)
    prove-rdeps: Dep Pod-Weaver-Plugin-Regexp-Pattern skipped (phase not included)
    ...
    prove-rdeps: [DRY] [1/8] Running prove for dist 'Acme-DependOnEverything' in '/tmp/BP3l0kiuZH/Acme-DependOnEverything-0.06' ...
    prove-rdeps: [DRY] [2/8] Running prove for dist 'App-BlockWebFlooders' in '/home/u1/repos/perl-App-BlockWebFlooders' ...
    prove-rdeps: [DRY] [3/8] Running prove for dist 'App-Licensecheck' in '/tmp/pw1hBzUIaZ/App-Licensecheck-v3.0.40' ...
    prove-rdeps: [DRY] [4/8] Running prove for dist 'App-RegexpPatternUtils' in '/home/u1/repos/perl-App-RegexpPatternUtils' ...
    prove-rdeps: [DRY] [5/8] Running prove for dist 'Bencher-Scenarios-RegexpPattern' in '/home/u1/repos/perl-Bencher-Scenarios-RegexpPattern' ...
    prove-rdeps: [DRY] [6/8] Running prove for dist 'Regexp-Common-RegexpPattern' in '/home/u1/repos/perl-Regexp-Common-RegexpPattern' ...
    prove-rdeps: [DRY] [7/8] Running prove for dist 'Release-Util-Git' in '/home/u1/repos/perl-Release-Util-Git' ...
    prove-rdeps: [DRY] [8/8] Running prove for dist 'Test-Regexp-Pattern' in '/home/u1/repos/perl-Test-Regexp-Pattern' ...

The above example shows that I have the distribution directories locally on my
`~/repos`, except for `Acme-DependOnEverything` and `App-Licensecheck`, which
*prove-rdeps* downloads and extracts from local CPAN mirror and puts into
temporary directories.

If we reinvoke the above command without the `-n`, *prove-rdeps* will actually
run `prove` on each directory and provide a summary at the end. Example output:

    % prove-rdeps Regexp::Pattern
    ...
    +-----------------------------+-----------------------------------+--------+
    | dist                        | reason                            | status |
    +-----------------------------+-----------------------------------+--------+
    | Acme-DependOnEverything     | Test failed (Failed 1/1 subtests) | 500    |
    | App-Licensecheck            | Test failed (No subtests run)     | 500    |
    | Regexp-Common-RegexpPattern | Non-zero exit code (2)            | 500    |
    +-----------------------------+-----------------------------------+--------+

The above example shows that three distributions failed testing. You can scroll
up for the detailed `prove` output to see why they failed, fix things, and
re-run. To skip some dists from being tested, use `--exclude-dist`:

    % prove-rdeps Regexp::Pattern --exclude-dist Acme-DependOnEverything

Or you can also put these lines in the configuration file:

    exclude_dists = Acme-DependOnEverything
    exclude_dists = Regexp-Common-RegexpPattern

How distribution directory is searched: see <pm:App::ProveDists> documentation.

When a dependent distribution cannot be found or downloaded/extracted, this
counts as a 412 error (Precondition Failed).

When a distribution's test fails, this counts as a 500 error (Error). Otherwise,
the status is 200 (OK).

*prove-rdeps* will return status 200 (OK) with the status of each dist. It will
exit 0 if all distros are successful, otherwise it will exit 1.

_
    args => {
        %App::ProveDists::args_common,
        modules => {
            summary => 'Module names to find dependents of',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'module',
            schema => ['array*', of=>'perl::modname*'],
            req => 1,
            pos => 0,
            greedy => 1,
        },

        phases => {
            summary => 'Only select dists that depend in these phases',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'phase',
            schema => ['array*', of=>'str*'],
            default => ['runtime'],
            tags => ['category:filtering'],
        },
        rels => {
            summary => 'Only select dists that depend using these relationships',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'rel',
            schema => ['array*', of=>'str*'],
            default => ['requires'],
            tags => ['category:filtering'],
        },

        exclude_dists => {
            summary => 'Distributions to skip',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'exclude_dist',
            schema => ['array*', of=>'perl::distname*', 'x.perl.coerce_rules'=>["From_str::comma_sep"]],
            tags => ['category:filtering'],
        },
        include_dists => {
            summary => 'If specified, only include these distributions',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'include_dist',
            schema => ['array*', of=>'perl::distname*', 'x.perl.coerce_rules'=>["From_str::comma_sep"]],
            tags => ['category:filtering'],
        },
        exclude_dist_pattern => {
            summary => 'Distribution name pattern to skip',
            schema => 're*',
            tags => ['category:filtering'],
        },
        include_dist_pattern => {
            summary => 'If specified, only include distributions with this pattern',
            schema => 're*',
            tags => ['category:filtering'],
        },

        # XXX add arg: level, currently direct dependents only
        # XXX add arg: dzil test instead of prove
    },
    features => {
        dry_run => 1,
    },
};
sub prove_rdeps {
    require App::lcpan::Call;

    my %args = @_;

    my $res = App::lcpan::Call::call_lcpan_script(
        argv => ['rdeps', @{ $args{modules} }],
    );

    return [412, "Can't lcpan rdeps: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;

    my @included_recs;
  REC:
    for my $rec (@{ $res->[2] }) {
        log_info "Found dep: %s (%s %s)", $rec->{dist}, $rec->{phase}, $rec->{rel};
        if (defined $args{phases} && @{ $args{phases} }) {
            do { log_info "Dep %s skipped (phase not included)", $rec->{dist}; next REC } unless grep {$rec->{phase} eq $_} @{ $args{phases} };
        }
        if (defined $args{rel} && @{ $args{rel} }) {
            do { log_info "Dep %s skipped (rel not included)", $rec->{dist}; next REC } unless grep {$rec->{rel} eq $_} @{ $args{rel} };
        }
        if (defined $args{include_dists} && @{ $args{include_dists} }) {
            do { log_info "Dep %s skipped (not in include_dists)", $rec->{dist}; next REC } unless grep {$rec->{dist} eq $_} @{ $args{include_dists} };
        }
        if (defined $args{include_dist_pattern}) {
            do { log_info "Dep %s skipped (does not match include_dist_pattern)", $rec->{dist}; next REC } unless $rec->{dist} =~ /$args{include_dist_pattern}/;
        }
        if (defined $args{exclude_dists} && @{ $args{exclude_dists} }) {
            do { log_info "Dep %s skipped (in exclude_dists)", $rec->{dist}; next REC } if grep {$rec->{dist} eq $_} @{ $args{exclude_dists} };
        }
        if (defined $args{exclude_dist_pattern}) {
            do { log_info "Dep %s skipped (matches exclude_dist_pattern)", $rec->{dist}; next REC } if $rec->{dist} =~ /$args{exclude_dist_pattern}/;
        }

        push @included_recs, $rec;
    }

    App::ProveDists::prove_dists(
        hash_subset(\%args, \%App::ProveDists::args_common),
        _res => [200, "OK", \@included_recs],
    );
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<prove-rdeps>.


=head1 SEE ALSO

L<prove>

L<App::lcpan>
