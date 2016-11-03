use strict;
use Data::Dumper;
use Carp;

# bins: a Simple tool to Support Analysis of bins/GenomePackages
# 
# We have built a set of tools that we are using to mine close-to-complete
# genomes from metagenomic samples.  The first stage of this effort to
# extract genomes without culturing organisms involves creation of
# bins that contain what looks like a single, complete genome.
# 
# For these relatively high-quality bins, we construct "GenomePackages"
# which include a GTO, evaluations by a number of tools (checkM,
# classifier-based, and tensor-flow-based tools), estimates of
# phylogentic position, and so forth).
# 
# Each GenomePackage has an ID, which is the genome ID assigned
# by RAST.
# 
# 	The GenomePackages directory packages up this data
# 
# 	Each subdirectdory includes all of the information we tie to
# 	the original bin.
# 
# 	If the contigs of a GenomePackage are updated, the existing
# 	GenomePackage is archived, and a new GenomePage is constructed
# 	
########################################################################
# Copyright (c) 2003-2008 University of Chicago and Fellowship
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
########################################################################

my $echo       = 0;
my $time_cmds  = 0;

use Time::HiRes qw(gettimeofday);
use Time::Local;

use SeedUtils;
use File::Path qw(make_path rmtree);

# usage: bins [-echo] [-time] [command]
my $packageDir = "/homes/parrello/SEEDtk/Data/GenomePackages";
my $updatedDir = "/homes/parrello/SEEDtk/Data/GenomePackagesUpdated";
my $roles_index = "/homes/overbeek/Ross/BinningProjectNov1/roles.in.subsystems";
my $roles_for_class_use = "/homes/overbeek/Ross/BinningProjectNov1/roles.to.use";
my $trained_classifiers   = "/homes/gdpusch/Projects/Machine_Learning/Function_Validation/Accurate_Classifiers.final";
my $tmpD = "/homes/overbeek/Ross/BinningProjectNov1/Tmp.$$";
my $class_probs_bin = "/homes/overbeek/Ross/ClassProbs/bin";
my $current_package;

$echo       = 0;
$time_cmds  = 0;

while ((@ARGV > 0) && ($ARGV[0] =~ /^-/))
{
    my $arg = shift @ARGV;
    if ($arg =~ /^-time/i) { $time_cmds = 1 }
    if ($arg =~ /^-echo/i) { $echo      = 1 }
}


my($t1,$t2);
my $req = '';

if (@ARGV > 0)  { $req = join( " ", @ARGV ); }
while ( (defined($req) && $req) || ((@ARGV == 0) && ($req = &get_req)) )
{
    if ($time_cmds)
    {
	$t1 = gettimeofday;
    }
    if ($req =~ /^\s*h\s*$/ || $req =~ /^\s*help\s*$/)
    {
	&help;
    }
    elsif ($req =~ /^\s*eval_class(\s+(\S+))?/)
    {
	my $package;
	if ((! $2) && (! $current_package))
	{
	    print "You need to specify a package\n";
	}
	else
	{
	    $package = $2 ? $2 : "$packageDir/$current_package";
	    my $gto = "$package/bin.gto";
	    my $cmd = "perl $class_probs_bin/genome_consistency.pl $gto $tmpD $trained_classifiers $roles_index $roles_for_class_use > $packageDir/classifier.evaluated.roles";
	    &SeedUtils::run ($cmd);
	    die $tmpD;
	}
    }
    elsif ($req =~ /^\s*find_bad_contigs(\s+(\S+))\s*$/)
    {
	my $package;
	if ((! $2) && (! $current_package))
	{
	    print "You need to specify a package\n";
	}
	else
	{
	    $package = $2 ? $2 : "$packageDir/$current_package";
            &find_bad_contigs($package);
	}
    }
    elsif ($req =~ /^\s*num_packages\s*$/)
    {
	&number_packages($packageDir);
    }
    elsif ($req =~ /^\s*packages\s*$/)
    {
	&display_packages($packageDir);
    }
    elsif ($req =~ /^\s*pegs_on_contig\s+(\S+)(\s+(\S+))\s*$/)
    {
	my $contig = $1;
	my $package;
	if ((! $3) && (! $current_package))
	{
	    print "You need to specify a package\n";
	}
	else
	{
	    $package = $3 ? $3 : "$packageDir/$current_package";
            &pegs_on_contig($package,$contig);
	}
    }
    elsif ($req =~ /\s*set package\s+(\S+)\s*$/)
    {
	$current_package = $1;
    }
    else
    {
	print "invalid command\n";
    }
    print "\n";
    $req = "";
    if ($time_cmds)
    {
	$t2 = gettimeofday;
	print $t2-$t1," seconds to execute command\n\n";
    }
}
sub padded {
    my($x,$n) = @_;

    if (length($x) < $n)
    {
	return $x . (" " x ($n - length($x)));
    }
    return $x;
}

sub get_req {
    my($x);

    print "?? ";
    $x = <STDIN>;
    while (defined($x) && ($x =~ /^h$/i) )
    { 
	&help;
	print "?? ";
	$x = <STDIN>;
    }
    
    if ((! defined($x)) || ($x =~ /^\s*[qQxX]/))
    {
	return "";
    }
    else
    {
        if ($echo)
	{
	    print ">> $x\n";
	}
	return $x;
    }
}

sub find_bad_contigs {
    my($package) = @_;

    if (! -s "$package/classifier.evaluated.roles")
    {
	print "You need to run \"eval_class $package\" first\n";
	return;
    }
    my $gto = "$package/bin.gto";    
    my $role_pred_actual = '';
    &SeedUtils::run("find_bad_contigs --gto $gto -r $packageDir/classifier.evaluated.roles > $package/bad.contigs");
    open(BAD,"<$package/bad.contigs") || die "Where is $package/bad.contigs";
    my @contigs = <BAD>;
    close(BAD);
    my $n = @contigs;
    print "$n bad contigs\n";
}

sub display_packages {
    my($packageDir) = @_;

    opendir(P,$packageDir) || die "$packageDir seems to be missing";
    my @packages = sort grep { $_ !~ /^\./ } readdir(P);
    closedir(P);
    foreach $_ (@packages)
    {
	print $_,"\n";
    }
}

sub number_packages {
    my($packageDir) = @_;

    opendir(P,$packageDir) || die "$packageDir seems to be missing";
    my @packages = sort grep { $_ !~ /^\./ } readdir(P);
    my $n = @packages;
    closedir(P);
    print "$n current packages\n";
}

sub pegs_on_contig {
    my($package,$contig) = @_;

    my $gto = "$package/bin.gto";    
    open(REP,"echo $contig | pegs_on_contigs --gto $gto |") || die "echo pegs on contigs failed";
    while (defined($_ = <REP>))
    {
	print $_;
    }
    close(REP);
}

sub help {
    print <<END;
    checkM [package]                Update checkM evaluation for package
    checkM_PATRIC GenomeId          Evaluate a PATRIC genome
    closest_PATRIC_genomes [package] Estimate closest PATRIC genomes
    delete_bad_contigs [package]    Update Package (generate new package, 
						    archiving old); resets
						    current package
    estimate_taxonomy [package]     Estimates taxonomy of the organism
    eval_class [package]            Eval package using classifiers
    eval_PATRIC_genome GenomeId     Evaluate a PATRIC genome
    eval_tensor_flow [package]      Eval package using tensor flow predictors
    find_bad_contigs [package]      Check for Bad Contigs
    num_packages                    Number of current packages
    packages                        List current packages
    pegs_on_contig Contig [package] Display PEGs on contig
    scores Package                  Show scores for Package
    set package                     Set default package
    set roles RolesFile             Set default roles from [RoleId,Role] file
END
}
