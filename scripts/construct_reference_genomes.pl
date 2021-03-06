use strict;
use Data::Dumper;
use gjoseqlib;
use SeedUtils;
use ScriptUtils;
use BlastInterface;

use Shrub;
use Shrub::GTO;

my $opt = ScriptUtils::Opts(
    '',
    Shrub::script_options(),
    ScriptUtils::ih_options(),
    [ 'contigs|c=s', 'file of sample contigs',         { required => 1 } ],
    [ 'minhits|m=i', 'minimum number of hits per ref', { default  => 400 } ],
    [
        'refD|r=s',
        'Constructed Directory Reflecting Refernce Genomes',
        { required => 1 }
    ],
    [ 'maxExpect|e=f', 'maximum expectation value for BLASTing', { default => 1e-50 } ]
);
my $ih = ScriptUtils::IH( $opt->input );

my $contigF  = $opt->contigs;
my $refD     = $opt->refd;
my $min_hits = $opt->minhits;
my $shrub    = Shrub->new_for_script($opt);
my $maxE     = $opt->maxexpect;

# usage: construct_reference_genomes -c ContigF -r ReferenceDir < close.ref.report

my @potential_orgs =
  grep { substr( $_->[0], 0, 2 ) ne '//' && $_->[0] >= $min_hits }
  map { chop; [ split( /\t/, $_ ) ] } <$ih>;
BlastInterface::verify_db( $contigF, 'n' );
&pull_ref_contigs( \@potential_orgs, $contigF, $refD );

sub pull_ref_contigs
{
    my ( $potential_orgs, $contigF, $refD ) = @_;

    mkdir( $refD, 0777 );
    foreach my $tuple (@$potential_orgs)
    {
        my ( $count, $g, $gs ) = @$tuple;
        print STDERR "Analyzing $g - $gs\n";
        my $giD = "$refD/$g";
        if (! -d $giD)
        {
            mkdir($giD, 0777);
        }
        my $obj;
        if (! -s "$giD/blast.out.dna")
        {
            $obj //= Shrub::GTO->new($shrub, $g);
            $obj->write_contigs_to_file("$giD/reference.contigs");
            my @matches = BlastInterface::blastn("$giD/reference.contigs", $contigF, { dust => 'no', maxE => $maxE });
            open(SIMS, ">$giD/blast.out.dna") || die "Could not open $giD/blast.out.dna: $!";
            foreach my $m (@matches) {
                print SIMS $m->as_line;
            }
            close(SIMS);
        }
        if (! -s "$giD/blast.out.protein")
        {
            $obj //= Shrub::GTO->new($shrub, $g);
            # Get protein translation FASTA.
            $obj->write_protein_translations_to_file("$giD/reference.translations");
            my @matches = BlastInterface::tblastn("$giD/reference.translations", $contigF, { maxE => $maxE });
            open(SIMS, ">$giD/blast.out.protein") || die "Could not open $giD/blast.out.protein: $!";
            foreach my $m (@matches) {
                print SIMS $m->as_line;
            }
            close(SIMS);
        }
        if (! -s "$giD/genome.gto")
        {
            $obj //= Shrub::GTO->new($shrub, $g);
            $obj->destroy_to_file("$giD/genome.gto");
        }
    }
}

#sub get_contigs_for_this_ref {
#    my($g,$giD,$pseedO,$tmp_contigs) = @_;
#
#    &SeedUtils::run("formatdb -i $tmp_contigs -p F");
#    open(BLAST,"<$giD/blast.out") || die "could not open $giD/blast.out";
#    my %keep;
#    while (defined($_ = <BLAST>))
#    {
#        chomp;
#        my @flds = split(/\s+/,$_);
#        if (($flds[2] >= 70) && (abs($flds[7] - $flds[6]) > 400))
#        {
#            $keep{$flds[1]} = 1;
#        }
#    }
#    close(BLAST);
#
#    return \%keep;
#}

