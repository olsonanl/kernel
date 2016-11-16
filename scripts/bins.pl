use strict;
use Data::Dumper;
use Carp;
use File::Copy::Recursive;

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

## CURRENTLY ONLY WORKS ON MAPLE
$| = 1;

my $echo       = 0;
my $time_cmds  = 0;

use Time::HiRes qw(gettimeofday);
use Time::Local;

use SeedUtils;
use File::Path qw(make_path rmtree);

# usage: bins [-echo] [-time] [command]
my $packageDir = "$FIG_Config::data/GenomePackages";
my $updatedDir = "$FIG_Config::data/GenomePackagesUpdated";
my $roles_index = "$FIG_Config::global/roles.in.subsystems";
my $roles_for_class_use = "$FIG_Config::global/roles.to.use";
my $trained_classifiers   = "$FIG_Config::global/FunctionPredictors";
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
    elsif ($req =~ /^\s*checkM(\s+(\S+))?/)
    {
        my $package;
        if ((! $2) && (! $current_package))
        {
            print "You need to specify a package\n";
        }
        else
        {
            my (@packages, $force);
            $package = $2 || $current_package;
            if ($package eq 'all') {
                my $all = AllPackages($packageDir);
                push @packages, @$all;
            } else {
                push @packages, $package;
                $force = 1;
            }
            for $package (@packages) {
                my $ok = 1;
                my $contigs = "$packageDir/$package";
                my $outDir = "$contigs/EvalByCheckm";
                my $cmd = "checkm lineage_wf --tmpdir $FIG_Config::temp -x fa --file $contigs/evaluate.log $contigs $outDir";
                if (-d $outDir) {
                    if ($force) {
                        print "Erasing old $outDir.\n";
                        File::Copy::Recursive::pathempty($outDir);
                    } else {
                        print "CheckM already run for $package-- skipping.\n";
                        $ok = 0;
                    }
                }
                if ($ok) {
                    print "Running checkM for $package.\n";
                    &SeedUtils::run ($cmd);
                    File::Copy::Recursive::fmove("$contigs/evaluate.log", "$contigs/EvalByCheckm/evaluate.log");
                }
            }
        }
    }
    elsif ($req =~ /^\s*eval_tensor_flow(\s+(\S+))?/)
    {
        my $package;
        if ((! $2) && (! $current_package))
        {
            print "You need to specify a package\n";
        }
        else
        {
            my (@packages, $force);
            $package = $2 || $current_package;
            if ($package eq 'all') {
                my $all = AllPackages($packageDir);
                push @packages, @$all;
            } else {
                push @packages, $package;
                $force = 1;
            }
            for $package (@packages) {
                my $ok = 1;
                my $contigs = "$packageDir/$package";
                my $outDir = "$contigs/EvalByTF";
                my $cmd = "eval_tensor_flow $contigs/bin.gto $outDir";
                if (-d $outDir) {
                    if ($force) {
                        print "Erasing old $outDir.\n";
                        File::Copy::Recursive::pathempty($outDir);
                    } else {
                        print "Tensor Flow already run for $package-- skipping.\n";
                        $ok = 0;
                    }
                }
                if ($ok) {
                    print "Running Tensor Flow for $package.\n";
                    &SeedUtils::run ($cmd);
                }
            }
        }
    }
    elsif ($req =~ /^\s*eval_scikit(\s+(\S+))?/)
    {
        my $package;
        if ((! $2) && (! $current_package))
        {
            print "You need to specify a package\n";
        }
        else
        {
            my (@packages, $force);
            $package = $2 || $current_package;
            if ($package eq 'all') {
                my $all = AllPackages($packageDir);
                push @packages, @$all;
            } else {
                push @packages, $package;
                $force = 1;
            }
            for $package (@packages) {
                my $ok = 1;
                my $contigs = "$packageDir/$package";
                my $outDir = "$contigs/EvalBySciKit";
                my $cmd = "gto_consistency $contigs/bin.gto $outDir $FIG_Config::global/FunctionPredictors $FIG_Config::global/roles.in.subsystems $FIG_Config::global/roles.to.use";
                if (-d $outDir) {
                    if ($force) {
                        print "Erasing old $outDir.\n";
                        File::Copy::Recursive::pathempty($outDir);
                    } else {
                        print "SciKit already run for $package-- skipping.\n";
                        $ok = 0;
                    }
                }
                if ($ok) {
                    print "Running SciKit for $package.\n";
                    &SeedUtils::run ($cmd);
                }
            }
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
    elsif ($req =~ /\s*quality_summary(\s+(\S+))?\s*$/)
    {
        my $package = $2 ? $2 : '';
        &quality_report($packageDir,$package);
    }
    elsif ($req =~ /\s*set package\s+(\S+)\s*$/)
    {
        $current_package = $1;
    }
    elsif ($req =~ /\s*good_packages(\s+(force))?\s*$/) {
        good_packages($2);
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

sub quality_report {
    my($packageDir,$package) = @_;
    my $cmd = "package_report $packageDir $package";
    system($cmd);
}

sub good_packages {
    my ($forceFlag) = @_;
    # Insure we have a full set of quality reports.
    print "Verifying quality reports.\n";
    my $cmd = "package_report " . ($forceFlag ? '--force ' : '') . " --quiet $packageDir";
    system($cmd);
    # Our output will go in here.
    my @report;
    # Loop through the packages. For each one, we extract the quality report and reformat it.
    print "Reading quality reports.\n";
    my $packages = AllPackages($packageDir);
    for my $package (@$packages) {
        if (open(my $ih, "$packageDir/$package/quality.tbl")) {
            my $line = <$ih>;
            chomp $line;
            my ($id, $name, $contigs, $bases, $refGenome, $refName, $skScore, $tfScore, $cmScore, $cmContam, $cmTaxon) = split /\t/, $line;
            my $outLine = [$skScore, $id, $name, $refGenome, $tfScore, $cmScore, $cmContam, $refName];
            if ($skScore && $cmScore && $tfScore && $skScore >= 80 && $cmScore >= 80 && $bases >= 500000) {
                push @report, $outLine;
            }
        }
    }
    my $header = ['SK', 'ID', 'Name', 'RefID', 'TF', 'CheckM', 'Contam', 'RefName'];
    my @sorted = ($header, sort { $b->[0] <=> $a->[0] } @report);
    open(my $oh, '>', "$packageDir/good.packages.tbl") || die "Could not open output file: $!";
    for my $row (@sorted) {
        my $line = join("\t", @$row) . "\n";
        print $oh $line;
        print $line;
    }
    close $oh;
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

sub AllPackages {
    my ($packageDir) = @_;
    opendir(my $dh, $packageDir) || die "Could not open package directory: $!";
    my @retVal = sort grep { $_ =~ /^\d+\.\d+$/ && -d "$packageDir/$_" } readdir $dh;
    return \@retVal;
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
    eval_scikit [package]            Eval package using SciKit classifiers
    eval_PATRIC_scikit GenomeId     Evaluate a PATRIC genome using SciKit
    eval_tensor_flow [package]      Eval package using tensor flow predictors
    find_bad_contigs [package]      Check for Bad Contigs
    num_packages                    Number of current packages
    packages                        List current packages
    good_packages                   List good packages
    pegs_on_contig Contig [package] Display PEGs on contig
    quality_summary [package]       Produce a quality report
    scores Package                  Show scores for Package
    set package                     Set default package
    set roles RolesFile             Set default roles from [RoleId,Role] file
END
}
