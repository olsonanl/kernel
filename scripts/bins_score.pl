#!/usr/bin/env perl
#
# Copyright (c) 2003-2015 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#


use strict;
use warnings;
use FIG_Config;
use ScriptUtils;
use Shrub;
use Bin::Compute;
use Bin::Score;
use Bin::Analyze;
use Stats;
use Time::HiRes qw(time);
use IO::File;

=head1 Score Bins Built From Community Contigs

    bins_score [ options ] workDirectory covgWeight tetraWeight refWeight uniPenalty uniWeight minScore logFile >scoreFile

This is a special version of L<bins_compute.pl> designed for use by scripts that test different parameter
values. It computes the bins, but rather than writing out the bins themselves, it writes out a number indicating
the bin quality. The incoming parameters are used to determine the comparison score between two bins. Bins with
a comparison score greater than zero can be combined. Bins with a zero comparison score cannot. One of the
input files contains a vector of values produced from the comparison between two incoming contigs. The
weights are applied to this vector and the resulting sum is the comparison score.

=head2 Parameters

The eight positional parameters are as follows.

=over 4

=item workDirectory

The input directory. It should contain the following files:

=over 8

=item contigs.bin

The input file containing the contigs, in L<bin exchange format|Bin/Bin Exchange Format>.

=back

=item logFile

The name of a file to contain status and analysis information about this computation.

=item covgWeight

The weight to assign to the coverage score. The coverage score is the fraction of the coverage values that are within
20% of each other. (So, the coverage vectors are compared, and the number of coordinates in the first bin that are within
20% of the corresponding value for the second bin is computed and divided by the vector length.)

=item tetraWeight

The weight to assign to the tetranucleotide score. The tetranucleotide score is the dot product of the two tetranucleotide
vectors.

=item refWeight

The weight to assign to the reference genome score. The reference genome score is 1.0 if the two reference genome sets are
identical and nonempty, 0.6 if the two sets are empty, 0.5 if one set is empty and the other is not, and 0 if both sets
are nonempty but different.

=item uniPenalty

The penalty for universal roles in common.

=item uniWeight

The weight to assign to the universal role score. This is equal to the number of universal roles in exactly one of the two
bins less the C<uniPenalty> times the number of universal roles in both bins, all scaled by the total number of universal
roles. A negative values is changed to zero.

=item minScore

The minimum acceptable score. Lower scores are set to 0. This value comes in between 0 and 1. We scale it to between
the 40% and 80% of the total of the four main weights.

=back

The command-line options are those in L<Shrub/script_options> plus the following.

=over 4

=item unifile

Name of a tab-delimited file containing the universal roles.

=back

=cut

my $start = time();
# Get the command-line options.
my $opt = ScriptUtils::Opts('workDirectory logFile covgWeight tetraWeight refWeight uniPenalty uniWeight minScore',
        Shrub::script_options(),
        ['unifile=s', 'universal role file', { default => "$FIG_Config::global/uni_roles.tbl" }],
        );
# Connect to the database.
my $shrub = Shrub->new_for_script($opt);
# Get the command-line parameters.
my ($workDir, $logFile, @scores) = @ARGV;
my ($covgWeight, $tetraWeight, $refWeight, $uniPenalty, $uniWeight, $inMinScore) = @scores;
# Scale the minimum score.
my $minScore = Bin::Score::scale_min($covgWeight, $tetraWeight, $refWeight, $uniWeight, $inMinScore);
# Check the working directory.
if (! $workDir) {
    die "No working directory specified.";
} elsif (! -d $workDir) {
    die "Invalid working directory $workDir.\n";
}
# Create the scoring object.
my $score = Bin::Score->new($covgWeight, $tetraWeight, $refWeight, $uniPenalty, $uniWeight, $minScore, $opt->unifile);
# Create the analysis object.
my $totUnis = $score->uni_total;
my $analyzer = Bin::Analyze->new(totUnis => $totUnis, minUnis => (0.8 * $totUnis));
# Open the log file.
my $oh = IO::File->new(">$logFile");
$oh->autoflush(1);
# Get the list of contigs. These are read in as bins.
print $oh "Reading contigs from input.\n";
open(my $ih, "<", "$workDir/contigs.bin") || die "Could not open contigs.bin file: $!";
my $binList = Bin::ReadContigs($ih);
$score->Filter($binList);
close $ih;
# Create the score computation object.
my $computer = Bin::Compute->new($score, logFile => $oh);
my $bins = $computer->ProcessScores($binList);
my $duration = time() - $start;
print $oh "Computation took $duration seconds.\n";
# Analyze the bins and output the score.
my $quality = $analyzer->Analyze($bins);
print "$quality\n";
# Create a report on what we've found.
my $report = $analyzer->Stats($bins);
$report->Accumulate($computer->stats);
print $oh "Run Report\n" . $report->Show() . "\n";
print $oh "SCORE RESULT = $quality from (" . join(", ", @scores) . ")\n";
close $oh;
exit($quality);