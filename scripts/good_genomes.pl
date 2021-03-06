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
use Shrub;
use ScriptUtils;

=head1 Output a List of Well-Behaved Genomes

    good_genomes.pl [ options ]

This is a simple script that writes a file of well-behaved genome IDs and names to the standard output.

=head2 Parameters

The command-line options are those found in L<Shrub/script_options>.

=cut

# Get the command-line parameters.
my $opt = ScriptUtils::Opts('',
        Shrub::script_options(),
        );
# Connect to the database.
my $shrub = Shrub->new_for_script($opt);
my @data = $shrub->GetAll('Genome', 'Genome(well-behaved) = ?', [1], 'id name');
for my $datum (@data) {
    print join("\t", @$datum) . "\n";
}
