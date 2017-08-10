package App::ProveDeps;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

our %SPEC;

$SPEC{prove_deps} = {
    v => 1.1,
    summary => 'Prove all distributions depending on specified module(s)',
    description => <<'_',

To use this utility, first create `~/.config/prove-deps.conf`:

    dist_dirs = ~/repos
    dist_dirs = ~/repos-other

The above tells *prove-deps* where to find for Perl distributions. Then:

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
            'x.name.singular' => 'dir',
            schema => ['array*', of=>'dirname*'],
            req => 1,
        },
        # XXX level, currently direct dependents only
        phases => {
            summary => 'Only select dists that depend in these phases',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'phase',
            schema => ['array*', of=>'str*'],
        },
        rels => {
            summary => 'Only select dists that depend using these relationships',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'rel',
            schema => ['array*', of=>'str*'],
        },
        # XXX dzil test instead of prove
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

  REC:
    for my $rec (@{ $res->[2] }) {
        if (defined $args{phases} && @{ $args{phases} }) {
            next REC unless grep $rec->{phase} eq $_, @{ $args{phases} };
        }
        if (defined $args{rel} && @{ $args{rel} }) {
            next REC unless grep $rec->{rel} eq $_, @{ $args{rel} };
        }
        log_info "Found dep: %s", $rec->{dist};
    }
    [200];
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
