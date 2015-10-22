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


package Bin::Analyze;

    use strict;
    use warnings;
    use Stats;

=head1 Community Bin Analysis Object.

This object computes a quality score for a set of bins computed by the L<Bin::Compute> algorithm. A bin will be considered
of good quality if it has a specified minimum number of the universal roles and a specified maximum number of duplicate roles.
The quality score for a bin is 1 if it is a good bin and zero if it is not, plus the number of non-duplicate universal roles
divided by the total number of universal roles plus 0.5 if it is a big bin..

This object has the following fields.

=over 4

=item minUnis

The minimum number of universal roles necessary to be considered a good bin.

=item maxDups

The maximum number of duplicate universal roles allowed in a good bin.

=item minLen

The minimum number of base pairs required for a bin to be considered big.

=item totUnis

The total number of universal roles. The default is C<101>.

=back

=head2 Special Methods

=head3 new

    my $analyzer = Bin::Analyze->new(%options);

Construct a new analysis object.

=over 4

=item options

Hash of tuning options.

=over 8

=item minUnis

Minimum number of universal roles necessary to be considered a good bin. The default is C<80>.

=item maxDups

Maximum number of duplicate universal roles allowed in a good bin. The default is C<4>.

=item totUnis

The total number of universal roles.

=item minLen

The minimum number of base pairs required for a bin to be considered big.

=back

=back

=cut

sub new {
    my ($class, %options) = @_;
    # Get the options.
    my $minUnis = $options{minUnis} // 80;
    my $maxDups = $options{maxDups} // 4;
    my $totUnis = $options{totUnis} // 101;
    my $minLen = $options{minLen} // 500000;
    # Create the analysis object.
    my $retVal = {
        minUnis => $minUnis,
        maxDups => $maxDups,
        totUnis => $totUnis,
        minLen => $minLen
    };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}


=head3 Quality

    my $score = Bin::Analyze::Quality(\@bins, %options);

Analyze a list of bins to determine a quality score. This is a non-object-oriented version that can be used for cases
where only one list of bins is being analyzed.

=over 4

=item bins

Reference to a list of L<Bin> objects.

=item options

Hash of tuning options.

=over 8

=item minUnis

Minimum number of universal roles necessary to be considered a good bin. The default is C<51>.

=item maxDups

Maximum number of duplicate universal roles allowed in a good bin. The default is C<4>.

=back

=item RETURN

Returns a value from indicating the number of quality bins.

=back

=cut

sub Quality {
    my ($bins, %options) = @_;
    my $analyze = Bin::Analyze->new(%options);
    my $retVal = $analyze->Analyze($bins);
    return $retVal;
}


=head3 Report

    my $stats = Bin::Analyze::Report(\@bins);

Produce a statistical report about a list of bins. This will show the number of contigs without any BLAST hits,
the number without universal roles, and the distribution of contig lengths, among other things.

=over 4

=item bins

Reference to a list of L<Bin> objects.

=item RETURN

Returns a L<Stats> object containing useful information about the bins.

=back

=cut

sub Report {
    my ($bins) = @_;
    # Get an analysis object.
    my $analyze = Bin::Analyze->new();
    # Create the return object.
    my $stats =$analyze->Stats($bins);
    # Return the statistics.
    return $stats;
}


=head2 Public Methods

=head3 Stats

    my $stats = $analyzer->Stats(\@bins);

Produce a statistical report about a list of bins. This will show the number of contigs without any BLAST hits,
the number without universal roles, and the distribution of contig lengths, among other things.

=over 4

=item bins

Reference to a list of L<Bin> objects.

=item RETURN

Returns a L<Stats> object containing useful information about the bins.

=back

=cut

sub Stats {
    my ($self, $bins) = @_;
    # Create the return object.
    my $stats = Stats->new('goodBin');
    # Loop through the bins.
    for my $bin (@$bins) {
        # Categorize the size, more or less logarithmically. So, we have a category for each
        # multiple of a million for the megabase-order bins, then one for each multiple of 100K,
        # and so forth.
        my $len = $bin->len;
        my $lenCat;
        if ($len < 1000) {
            $lenCat = '0000K';
        } else {
            my $lenThing = 1000000;
            my $zeroes = "";
            my $xes = "XXXK";
            while ($len < $lenThing) {
                $lenThing /= 10;
                $zeroes .= "0";
                $xes = substr($xes, 1);
            }
            my $cat = int($len / $lenThing);
            $lenCat = "$zeroes$cat$xes";
        }
        $stats->Add("binSize-$lenCat" => 1);
        $stats->Add(letters => $len);
        $stats->Add(bins => 1);
        # Check for no proteins and no blast hits.
        my $genomeCount = scalar $bin->refGenomes;
        if (! $genomeCount) {
            $stats->Add(noBlastHits => 1);
            $stats->Add(noUniProts => 1);
        } else {
            $stats->Add(someBlastHits => 1);
            $stats->Add("blastHits-$lenCat" => 1);
            $stats->Add(refHits => $genomeCount);
            my $uniH = $bin->uniProts;
            my $uniCount = scalar keys %$uniH;
            if (! $uniCount) {
                $stats->Add(noUniProts => 1);
            } else {
                $stats->Add(someUniProts => 1);
                my $uniCat = int($uniCount / 10) . "X";
                $stats->Add("uniProtsFound$uniCat" => 1);
                $stats->Add("uniProts-$lenCat" => 1);
                $stats->Add(uniHits => $uniCount);
                for my $uni (keys %$uniH) {
                    $stats->Add("uni-$uni" => $uniH->{$uni});
                }
            }
        }
        # Check for a good bin.
        my $quality = $self->AnalyzeBin($bin);
        if ($quality >= 1) {
            $stats->Add(greatBin => 1);
        }
        if ($quality > 0.5) {
            $stats->Add(goodBin => 1)
        } else {
            $stats->Add(notGoodBin => 1);
        }
    }
    # Return the statistics.
    return $stats;
}


=head3 Analyze

    my $score = $analyzer->Analyze(\@bins);

Analyze a list of bins to determine a quality score.

=over 4

=item bins

Reference to a list of L<Bin> objects.

=item RETURN

Returns a value from indicating the quality of the bins.

=back

=cut

sub Analyze {
    my ($self, $bins) = @_;
    # Analyze the individual bins.
    my $retVal = 0;
    for my $bin (@$bins) {
        $retVal += $self->AnalyzeBin($bin);
    }
    # Return the score.
    return $retVal;
}


=head3 AnalyzeBin

    my $flag = $analyze->AnalyzeBin($bin);

Return the quality score for the bin.

=over 4

=item bin

L<Bin> object to check for sufficient universal roles.

=item RETURN

Returns the number of non-duplicate universal roles divided by the total number of universal roles, plus 1 if the bin is good,
plus 0.5 if the bin is big.

=back

=cut

sub AnalyzeBin {
    my ($self, $bin) = @_;
    # This will be the return value.
    my $retVal = 0;
    # Get this bin's universal role hash.
    my $uniRoles = $bin->uniProts;
    my $uniCount = scalar(keys %$uniRoles);
    # Count the number of duplicates.
    my $dups = 0;
    for my $uniRole (keys %$uniRoles) {
        if ($uniRoles->{$uniRole} > 1) {
            $dups++;
        }
    }
    # Check the universal role count.
    if ($uniCount >= $self->{minUnis} && $dups <= $self->{maxDups}) {
        $retVal = 1;
    }
    # Check the length.
    if ($bin->len >= $self->{minLen}) {
        $retVal += 0.5;
    }
    # Add the full score.
    $retVal += ($uniCount - $dups) / $self->{totUnis};
    # Return the determination indicator.
    return $retVal;
}

=head3 BinReport

    $analyzer->BinReport($oh, $shrub, $uniRoles, $binList);

Write a detailed report about the bins. Information about the content of the larger bins will be presented, along
with the standard statistical report from L</Report>.

=over 4

=item oh

Open handle for the output file.

=item shrub

L<Shrub> object for accessing the database.

=item uniRoles

Reference to a hash mapping each universal role ID to its description.

=item binList

Reference to a list of L<Bin> objects for which a report is desired.

=back

=cut

sub BinReport {
    my ($self, $oh, $shrub, $uniRoles, $binList) = @_;
    # This will be a hash mapping each universal role to a hash of the bins it appears in. The bins will be
    # identified by an ID number we assign.
    my %uniBins;
    my $binID = 0;
    # Loop through the bins.
    for my $bin (@$binList) {
        # Compute the bin ID.
        $binID++;
        my $quality = $self->AnalyzeBin($bin);
        print $oh "\nBIN $binID (from " . $bin->contig1 . ", " . $bin->contigCount . " contigs, " . $bin->len . " base pairs, quality $quality)\n";
        # Only do a detail report if the bin is big.
        if ($bin->len >= $self->{minLen}) {
            # List the close reference genomes.
            my @genomes = $bin->refGenomes;
            if (@genomes) {
                my $filter = 'Genome(id) IN (' . join(', ', map { '?' } @genomes) . ')';
                my %gNames =  map { $_->[0] => $_->[1] } $shrub->GetAll('Genome', $filter, \@genomes, 'id name');
                for my $genome (@genomes) {
                    print $oh "    $genome: $gNames{$genome}\n";
                }
            }
            # Compute the average coverage.
            my $coverageV = $bin->coverage;
            my $avg = 0;
            for my $covg (@$coverageV) {
                $avg += $covg;
            }
            $avg /= scalar @$coverageV;
            print $oh "*** Mean coverage is $avg.\n";
            # Finally, the universal role list. This hash helps us find the missing ones.
            print $oh "    Universal Roles\n";
            print $oh "    ---------------\n";
            my %unisFound = map { $_ => 0 } keys %$uniRoles;
            my $uniFoundCount = 0;
            my $uniMissingCount = 0;
            my $uniDuplCount = 0;
            # Get the universal role hash for the bin.
            my $binUnis = $bin->uniProts;
            for my $uni (sort keys %$binUnis) {
                my $count = $binUnis->{$uni};
                if ($count) {
                    print $oh "    $uni\t$uniRoles->{$uni}\t$count\n";
                    $unisFound{$uni} = 1;
                    $uniBins{$uni}{$binID} = $count;
                    $uniFoundCount++;
                    if ($count > 1) {
                        $uniDuplCount++;
                    }
                }
            }
            # Now the roles not found.
            if (! $uniFoundCount) {
                print $oh "    NONE FOUND\n";
            } else {
                print $oh "    ---------------\n";
                for my $uni (sort keys %unisFound) {
                    if (! $unisFound{$uni}) {
                        print $oh "    $uni\t$uniRoles->{$uni}\tmissing\n";
                        $uniMissingCount++;
                    }
                }
                print $oh "    ---------------\n";
                print $oh "    $uniFoundCount present, $uniMissingCount missing, $uniDuplCount duplicated.\n";
            }
        }
    }
    # Now output the universal role matrix.
    print $oh "\nUNIVERSAL ROLE MATRIX\n";
    print $oh join("\t", 'Role', map { "bin$_" } (1 .. $binID)) . "\n";
    for my $uni (sort keys %uniBins) {
        print $oh join("\t", $uni, map { $uniBins{$uni}{$_} // ' ' } (1 .. $binID)) . "\n";
    }
    print $oh "\n\n";
    # Finally, the bin statistics.
    my $stats = $self->Stats($binList);
    print $oh "FINAL REPORT\n\n" . $stats->Show();
}

1;