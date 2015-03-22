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
use JSON::XS;
use warnings;
use Shrub;
use ScriptUtils;
use Projection;
use Data::Dumper;

=head1 evaluate solid projections against subsystem "truth"

    eval [ options ] < projections

evaluate the output generated by the solid_projection_pipeline

=head2 Parameters

The command-line options are those found in L<Shrub/script_options> and
L<ScriptUtils/ih_options> plus the following.

=cut

# Get the command-line parameters.
my $opt =
  ScriptUtils::Opts( '', Shrub::script_options(), ScriptUtils::ih_options(),
    [] );
my $ih = ScriptUtils::IH( $opt->input );

# Connect to the database.
my $shrub = Shrub->new_for_script($opt);

# Read the projections.

$/ = "\n//\n";
my @calls = <$ih>;
$/ = "\n";

my @tuples = $shrub->GetAll( "Genome", "", [], "id" );
my @genomes = map { $_->[0] } @tuples;
( $calls[0] =~ /^(\S+)/ ) || die "Bad Input";
my $subsys = $1;
my $state = &Projection::relevant_projection_data( $subsys, \@genomes, $shrub );

my $by_vc = $state->{by_vc};
my %g_to_vc_real;
foreach my $vc ( keys(%$by_vc) )
{
    my $gH = $by_vc->{$vc};
    foreach my $genome ( keys(%$gH) )
    {
        $g_to_vc_real{$genome} = $vc;
    }
}
my $success = 0;
my $failed = 0;

foreach my $calls_for_genome (@calls)
{
    if ( $calls_for_genome =~ /^\S+\t(\S+)\t(\S+)(\t\S+)?\n(.*)---\n(.*)\/\/\n/s )
    {
        my ( $g, $vc, $pegs, $probs ) = ( $1, $2, $4, $5 );
        my $real_vc = $g_to_vc_real{$g} || 'no-real-vc';
        if (($real_vc ne $vc) && (($real_vc ne 'no-real-vc')  || ($vc ne 'not-active')))
	{
	    print "real_vc\t$real_vc\n", $calls_for_genome;
	    $failed++;
        }
	else
	{ 
	    $success++;
	}
    }
}
print "success = $success\n";
print "failed = $failed\n";