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
use GPUtils;
use File::Copy::Recursive;
use Stats;

=head1 Produce Report on Seed Protein in Good Genomes

    good_proteins.pl [ options ] packageDir outDir

This script produces two files-- an amino-acid FASTA file of all occurrences of a selected protein in the specified
genome packages, and a tab-delimited file listing each genome ID and its name.

=head2 Output Files

Two output files will be put in the designated output directory.

=over 4

=item genomes.tbl

A tab-delimited file of genomes, each record consisting of (0) a genome ID and (1) a genome name.

=item proteins.fa

A FASTA file containing the amino acid sequences of the features containing the desired protein role. The
sequence ID will be the feature ID. The comment will be the genome ID.

=head2 Parameters

The positional parameters are the name of the package directory from which the genomes should be taken and the
name of a directory to contain the output files.

The command-line options are the following.

=over 4

=item protein

The description string of the desired protein role. The default is C<Phenylalanyl-tRNA synthetase alpha chain>.

=item minlen

The minimum acceptable length for the protein. The default is 209.

=item maxlen

The maximum acceptable length for the protein. The default is 485.

=back

=cut

$| = 1;
# Get the command-line parameters.
my $opt = ScriptUtils::Opts('packageDir outDir',
        ['protein=s', 'protein role description', { default => 'Phenylalanyl-tRNA synthetase alpha chain'}],
        ['minlen=i', 'minimum protein length', { default => 209 }],
        ['maxlen=i', 'maximum protein length', { default => 485 }],
        ['eraseBad', 'erase the bad genomes']
        );
# Get the positional parameters.
my ($packageDir, $outDir) = @ARGV;
if (! $packageDir) {
    die "No package input directory specified.";
} elsif (! -d $packageDir) {
    die "Invalid or missing package directory $packageDir.";
} elsif (! $outDir) {
    die "No output directory specified.";
} elsif (! -d $outDir) {
    File::Copy::Recursive::pathmk($outDir) ||
        die "Could not created $outDir: $!";
}
# Get the options.
my $role = $opt->protein;
my $min = $opt->minlen;
my $max = $opt->maxlen;
my $stats = Stats->new();
# Save the bad genome IDs in here.
my @bad;
# Open the output files.
open(my $fh, '>', "$outDir/proteins.fa") || die "Could not open FASTA output file: $!";
open(my $oh, '>', "$outDir/genomes.tbl") || die "Could not open genome output file: $!";
# Get all of the incoming genomes.
print "Parsing $packageDir.\n";
my $ghash = GPUtils::get_all($packageDir);
# Loop through the genomes.
for my $genome (sort keys %$ghash) {
    print "Searching $genome for seed proteins:  ";
    my $gto = GPUtils::gto_of($ghash, $genome);
    $stats->Add(genomesIn => 1);
    my $flist = GPUtils::role_to_features($gto, $role);
    # Did we find any proteins?
    my $found = scalar @$flist;
    if (! $found) {
        print "none found.\n";
        $stats->Add(genomesNoSeed => 1);
    } elsif ($found > 1) {
        print "$found found. GENOME SKIPPED.\n";
        $stats->Add(("genomes$found" . "Seed") => 1);
        push @bad, $genome;
    } else {
        print "$found found.";
        $stats->Add(genomes1Seed => 1);
        my $feature = $flist->[0];
        # Check the protein length.
        my $aa = $feature->{protein_translation};
        my $aaLen = length $aa;
        if ($aaLen < $min) {
            print " Length $aaLen < $min. GENOME SKIPPED.\n";
            $stats->Add(protTooShort => 1);
            push @bad, $genome;
        } elsif ($aaLen > $max) {
            print " Length $aaLen > $max. GENOME SKIPPED.\n";
            $stats->Add(protTooLong => 1);
            push @bad, $genome;
        } else {
            print "\n";
            # We found the protein. Output the genome.
            print $oh "$genome\t$gto->{scientific_name}\n";
            $stats->Add(genomesOut => 1);
            # Output the proteins.
            for my $feature (@$flist) {
                print $fh ">$feature->{id} $genome\n$aa\n";
                $stats->Add(proteinsOut => 1);
            }
        }
    }
}
if ($opt->erasebad) {
    for my $genome (@bad) {
        my $dir = $ghash->{$genome};
        print "Erasing $dir.\n";
        File::Copy::Recursive::pathrmdir($dir);
    }
}
print "All done.\n" . $stats->Show();