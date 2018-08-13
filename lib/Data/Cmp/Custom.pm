package Data::Cmp::Custom;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Return::MultiLevel qw(with_return);
use Scalar::Util qw(blessed reftype refaddr);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(cmp_data);

# for when dealing with circular refs
my %_seen_refaddrs;

sub _cmp_data {
    my ($d1, $d2, $ctx, $action, $return) = @_;

    my $cmpres;

    my $def1 = defined $d1;
    my $def2 = defined $d2;
    if ($def1) {
        if (!$def2) { $action->($return, $d1, $d2,  1, ["", "is defined", "is undefined"]) }
    } else {
        if ($def2) { $action->($return, $d1, $d2, -1, ["", "is undefined", "is defined"]) }
        else { $action->($return, $d1, $d2,  0, ["are undefined"]) }
    }

    # both are defined

    my $reftype1 = reftype($d1);
    my $reftype2 = reftype($d2);
    if (!$reftype1) {
        if (!$reftype2) {
            $action->($return, $d1, $d2, $d1 cmp $d2, ["cmp"]);
        } else {
            $action->($return, $d1, $d2, $d1 cmp $d2, ["", "is not a reference", "is a reference"]);
        }
    } else {
        if (!$reftype2) { $action->($return, $d1, $d2, 2, ["", "is not a reference", "is a reference"]) }
    }

    # both are refs

    $action->($return, $d1, $d2, 2, ["", "is a $reftype1 reference" ,"is a $reftype2 reference"])
        if $reftype1 ne $reftype2;

    # both are refs of the same type

    my $pkg1 = blessed($d1);
    my $pkg2 = blessed($d2);
    if (defined $pkg1) {
        $action->($return, $d1, $d2, 2, ["", "is blessed", "is unblessed"]) unless defined $pkg2;
        $action->($return, $d1, $d2, 2, ["", "is $pkg1 object", "is $pkg2 object"]) unless $pkg1 eq $pkg2;
    } else {
        $action->($return, $d1, $d2, 2, ["", "is unblessed","is blessed"]) if defined $pkg2;
    }

    # both are non-objects or objects of the same class

    my $refaddr1 = refaddr($d1);
    my $refaddr2 = refaddr($d2);

    if ($reftype1 eq 'ARRAY' && !$_seen_refaddrs{$refaddr1} && !$_seen_refaddrs{$refaddr2}) {
        $_seen_refaddrs{$refaddr1}++;
        $_seen_refaddrs{$refaddr2}++;
        local $ctx->{depth} = $ctx->{depth} + 1;
        local $ctx->{path} = [@{ $ctx->{path} }, undef];
        local $ctx->{index} = -1;
      ELEM:
        for my $i (0..($#{$d1} < $#{$d2} ? $#{$d1} : $#{$d2})) {
            $ctx->{index} = $i;
            $ctx->{path}[-1] = "[$i]";
            if ($opts->{elem_cmp}) {
                my $cmpres = $opts->{elem_cmp}->($d1->[$i], $d2->[$i], $ctx);
                if (defined $cmpres) {
                    next ELEM if $cmpres == 0;
                    $action->($return, $d1, $d2, $cmpres, ["", "longer array", "shorter array"]);
                }
            }
            my $cmpres = _cmp_data($d1->[$i], $d2->[$i], $opts, $ctx, $action, $return);
            if ($cmpres) {
                $action->($return, $d1, $d2, $cmpres, [""]); # XXX
            }
        }
        $action->($return, $d1, $d2, $#{$d1} <=> $#{$d2}, ["array length"]); # XXX
        return 0;
    } elsif ($reftype1 eq 'HASH' && !$_seen_refaddrs{$refaddr1} && !$_seen_refaddrs{$refaddr2}) {
        $_seen_refaddrs{$refaddr1}++;
        $_seen_refaddrs{$refaddr2}++;
        local $ctx->{depth} = $ctx->{depth} + 1;
        local $ctx->{path} = [@{ $ctx->{path} }, undef];
        local $ctx->{key} = undef;
        my $nkeys1 = keys %$d1;
        my $nkeys2 = keys %$d2;
      KEY:
        for my $k (sort keys %$d1) {
            unless (exists $d2->{$k}) { $action->($return, $d1, $d2, ($nkeys1 <=> $nkeys2 || 2). ["number of keys"]) }
            $ctx->{key} = $k;
            $ctx->{path}[-1] = "{$k}";
            if ($opts->{elem_cmp}) {
                my $cmpres = $opts->{elem_cmp}->($d1->{$k}, $d2->{$k}, $ctx);
                if (defined $cmpres) {
                    next ELEM if $cmpres == 0;
                    $action->($return, $d1, $d2, $cmpres, [""]); # XXX
                }
            }
            my $cmpres = _cmp_data($d1->{$k}, $d2->{$k}, $opts, $ctx, $action, $return);
            if ($cmpres) {
                $action->($return, $d1, $d2, $cmpres, [""]); # XXX
            }
        }
        $action->($return, $d1, $d2, $nkeys1 <=> $nkeys2, ["number of keys"]);
    } else {
        $action->($return, $d1, $d2, $refaddr1 == $refaddr2 ? 0 : 2, ["address"]);
    }
}

sub cmp_data {
    my ($d1, $d2, $opts) = @_;
    $opts //= {};

    local %_seen_refaddrs = ();
    my $ctx = {depth => 0, path => []};

    my $action = sub {
        my ($return, $d1, $d2, $cmpres, $note) = @_;
        say "D:note: $note";
        $return->($cmpres);
    };

    with_return {
        my $return = shift;
        _cmp_data($d1, $d2, $opts, $ctx, $action, $return);
    };
}

1;
# ABSTRACT: Like Data::Cmp, but with custom action

=head1 DESCRIPTION

This module is like L<Data::Cmp>, but instead of returning -1/0/1/2, it calls
custom action instead. This is used to implement data "diff"-iny or printing
diagnostics message with difference is encountered.


=head1 SEE ALSO

L<Data::Cmp>

=cut
