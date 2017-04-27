use strict;
use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use Time::Local;
use gjoseqlib;
use RepKmers;
use SeedUtils;
use P3DataAPI;
use Shrub;
use Shrub::Contigs;

# CachedDir ($dir) must contain the following files
#    complete.genomes
#    genome.index
#    similarities
#
my $dir;
my $usage = "usage: rep_server CachedDir [ inputFile ]\n";
(
 ($dir = shift @ARGV) &&
 (-s "$dir/complete.genomes") &&
 (-s "$dir/genome.index") &&
 (-s "$dir/similarities")
)
    || die $usage;
my $IH;
my $infile = shift @ARGV;
if ($infile) {
    open($IH, "<$infile") || die "Could not open $infile: $!";
} else {
    $IH = \*STDIN;
}
my $cached = &load_data($dir);
my $shrub = Shrub->new();
my $p3 = P3DataAPI->new();

my $request;
$| = 1;
while ($request = &next_request())
{
    &process_request($cached,$request);
}

sub load_data {
    my($dir) = @_;

    open(K,"<$dir/K") || die "could not open $dir/K";
    $_ = <K>; chomp;
    my $cached->{K} = $_;
    close(K);

    my $tails = {};
    open(TAILS,"<$dir/tail.16mers") || die "could not open $dir/tail.16mers";
    while (defined($_ = <TAILS>) && ($_ =~ /^(\S+)\t(\S+)$/))
    {
        $tails->{$2} = $1;
    }
    close(TAILS);
    $cached->{tails} = $tails;
    open(COMPLETE,"<$dir/complete.genomes") || die "could not open $dir/complete_genomes";
    my %complete = map { ($_ =~ /^(\d+\.\d+)\s+(\S.*\S)/) ? ($1 => $2) : () } <COMPLETE>;
    close(COMPLETE);
    $cached->{complete} = \%complete;

    my %g_to_index;
    my %index_to_g;
    open(INDEX,"<$dir/genome.index") || die "could not open $dir/genome.index";
    while (defined($_ = <INDEX>))
    {
        if ($_ =~ /(\d+)\t(\d+\.\d+)/)
        {
            $g_to_index{$2} = $1;
            $index_to_g{$1} = $2;
        }
    }
    close(INDEX);
    $cached->{g_to_index} = \%g_to_index;
    $cached->{index_to_g} = \%index_to_g;

    open(SIMS,"<$dir/similarities") || die "could not open $dir/similarities";
    my $sims = [];;
    $/ = "\n//\n";
    while (defined($_ = <SIMS>))
    {
        chomp;
        my @lines = split(/\n/,$_);
        my $hdr = shift @lines;
        if ($hdr =~ /^(\d+)/)
        {
            my $i1 = $1;
            while (defined($_ = shift @lines) && ($_ =~ /^(\d+)\t(\d+)/))
            {
                push(@{$sims->[$i1]},[$1,$2]);   # [count,i2]
            }
        }
    }
    $/ = "\n";
    close(SIMS);
    $cached->{sims} = $sims;

    my %seqs = map { ($_->[0] =~ /^fig\|(\d+\.\d+)/) ? ($1 => $_->[2]) : () }
               &gjoseqlib::read_fasta("$dir/6.1.1.20.fasta");
    $cached->{seqs} = \%seqs;

    return $cached;
}

sub next_request {

    print "?? ";
    my $req;
    if (defined($_ = <$IH>))
    {
        if ($_ =~ /^[xX]$/) { return undef }
        chomp;
        $req = [split(/\s+/,$_)];
#	print "request: ",join("\t",@$req),"\n";
    }
    return $req;
}

sub process_request {
    my($cached,$req) = @_;
    my $index_to_g = $cached->{index_to_g};
    my $g_to_index = $cached->{g_to_index};
    my $complete   = $cached->{complete};
    my $t1 = gettimeofday;

    if ($req->[0] =~ /^\s*h\s*$/ || $req->[0] =~ /^\s*help\s*$/)
    {
     &help;
    }
    elsif ($req->[0] eq 'index_to_id')    # index to id
    {
        my $index = $req->[1];
        my $id = $cached->{index_to_g}->{$index};
        my $g  = $complete->{$id};
        print join("\t",($index,$id,$g)),"\n";
    }
    elsif ($req->[0] eq 'id_to_index')    # id to index
    {
        my $id = $req->[1];
        my $index = $cached->{g_to_index}->{$id};
        my $g  = $complete->{$id};
        print join("\t",($index,$id,$g)),"\n";
    }
    elsif ($req->[0] eq 'closest_N_genomes')    # closest N genomes
    {
        my $index = $req->[1];
        my $n = $req->[2];
        my @closest_genomes = &RepKmers::closest_N_genomes($cached,$index,$n);
        print $index,"\t",$index_to_g->{$index},
                     "\t",$complete->{$index_to_g->{$index}},"\n";
        foreach my $tuple (@closest_genomes)
        {
            my($count,$i2) = @$tuple;
            print "\t", join("\t",($count,
                                   $i2,
                                   $index_to_g->{$i2},
                                   $complete->{$index_to_g->{$i2}})),"\n";
        }
        print "\n";
    }
    elsif ($req->[0] eq 'closest_by_sc')    # closest by threshold
    {
        my $index = $req->[1];
        my $n = $req->[2];
        my @closest_genomes = &RepKmers::closest_by_sc($cached,$index,$n);
        print $index,"\t",$index_to_g->{$index},
                     "\t",$complete->{$index_to_g->{$index}},"\n";
        foreach my $tuple (@closest_genomes)
        {
            my($count,$i2) = @$tuple;
            print "\t", join("\t",($count,
                                   $i2,
                                   $index_to_g->{$i2},
                                   $complete->{$index_to_g->{$i2}})),"\n";
        }
        print "\n";
    }
    elsif ($req->[0] eq 'rep_by')   # who represents this guy?
    {
        my(undef,$who,$file) = @$req;
        my($i) = &ids_to_indexes([$who],$g_to_index);
        &who_represents($i,$file,$cached->{sims});
    }
    elsif ($req->[0] eq 'rep_set')   # represetative set
    {
        my $save = ($req->[-1] =~ /^save=(\S+)/) ? $1 : undef;
        if ($save) {
            pop @$req;
        }
        my(undef,$max_sim,@keep_ids_or_indexes) = @$req;
        if ((@keep_ids_or_indexes == 1) &&
            (-s $keep_ids_or_indexes[0]))
        {
            @keep_ids_or_indexes = SeedUtils::read_ids($keep_ids_or_indexes[0]);
        }
        my ($keep, $keepMap) = &compute_keep_data(\@keep_ids_or_indexes,$g_to_index,$index_to_g);
        &rep($cached,$max_sim,$keep, $save, $keepMap);
    }
    elsif ($req->[0] eq "close_rep_seq")  # closest rep [N,Seq]
    {
        my(undef,$N,$seq) = @$req;
        my @reps = &rep1($cached,$N,[]);
        my ($best_id,$count) = &best_id($cached,\@reps,$N,$seq,undef,undef);
        if (defined($best_id))
        {

            print join("\t",($count,
                             $best_id,
                             $index_to_g->{$best_id},
                             $complete->{$index_to_g->{$best_id}})),"\n";
        }
        else
        {
            print "failed to get closest\n";
        }
    }
    elsif ($req->[0] eq "match_tails")  # tail match [seq] returns ID of match
    {
        my $seq = $req->[1];
        my $tail = lc substr($seq,-16);
        my $tails = $cached->{tails};
        my $close_g = $tails->{$tail};
        if (defined($close_g))
        {
            my $close_id = $cached->{g_to_index}->{$close_g};
            print join("\t",($close_id,
                             $close_g,
                             $complete->{$close_g})),"\n";
        }
        else
        {
            print "failed for tail $tail\n";
        }
    }
    elsif ($req->[0] eq 'n_reps')   # N represetative sequences, keeping
    {
        my(undef,$N,@keep) = @$req;
        if (! defined($keep[0])) { @keep = () }
        &repN($cached,$N,\@keep);
    }
    elsif ($req->[0] eq 'thin_set')   # thin set
    {
        my(undef,$max_sim,$to_thin) = @$req;
        my @thinned = &thin($cached,$max_sim,$to_thin);
        if (@thinned == 0)
        {
            print STDERR "failed to thin\n";
        }
        else
        {
            my $n = @thinned;
            print "$n\t",join(",",@thinned),"\n\n";
        }
    }
    elsif ($req->[0] eq 'load_sigs') {
        # Signature hash.
        my %sigs;
        my $sigK = $req->[1];
        if (! open(my $ih, "<$req->[2]")) {
            print "Could not open signature file: $!\n";
        } else {
            while (! eof $ih) {
                if (<$ih> =~ /^(\S+)\t(\d+\.\d+)/) {
                    $sigs{$1} = $2;
                }
            }
        }
        $cached->{signatures} = \%sigs;
        $cached->{signatureK} = $sigK;
    }
    elsif ($req->[0] eq 'find_sigs') {
        # Find signatures in genome.
        my $genome = $req->[1];
        my $contigs = get_contigs($genome);
        if (! $contigs) {
            print "$genome not found in Shrub or PATRIC.\n";
        } else {
            my $sigsH = $cached->{signatures};
            my $K = $cached->{signatureK};
            my %results;
            for my $contig (@$contigs) {
                my %hits;
                my ($id, undef, $seq) = @$contig;
                my $len = length($seq);
                my $n = $len - $K;
                for (my $i = 0; $i <= $n; $i++) {
                    my $kmer = substr($seq, $i, $K);
                    my $rev = SeedUtils::rev_comp($kmer);
                    if ($rev lt $kmer) {
                        $kmer = $rev;
                    }
                    my $hitGenome = $sigsH->{$kmer};
                    if ($hitGenome) {
                        $hits{$hitGenome}++;
                    }
                }
                my ($best, $second) = sort { $hits{$b} <=> $hits{$a} } keys %hits;
                if (! $best) {
                    print "$id ($len) had no hits.\n";
                } else {
                    print "$id ($len) hit $best [$hits{$best}]";
                    if ($second) {
                        print " and $second [$hits{$second}]";
                    }
                    print ".\n";
                }
            }
        }
    }
    else
    {
        print &Dumper(["failed request",$req]);
    }
    my $t2 = gettimeofday;
    print $t2-$t1," seconds to execute command\n\n";
}


#
sub best_id {
    my($cached,$reps,$max_sim,$seq,$best_id,$best_so_far) = @_;

    my $index_to_g = $cached->{index_to_g};
    my $kmersQ     = &RepKmers::kmers_of_seq($cached->{K},$seq);
    foreach my $rep (@$reps)
    {
        my $gid     = $index_to_g->{$rep};
        my $seqR    = $cached->{seqs}->{$gid};
        my $K = $cached->{K};
        my $common  = &RepKmers::in_common($K,$kmersQ,$seqR);
        if ((! defined($best_id)) || ($common > $best_so_far))
        {
            $best_so_far = $common;
            $best_id     = $rep;
        }
    }
    if (! defined($best_id)) { return (undef,undef) }
    ($best_id,$best_so_far) = &RepKmers::find_closest($cached,$best_id,$best_so_far,$max_sim,$kmersQ);
    return ($best_id,$best_so_far);
}

sub rep1 {
    my($cached,$max_sim,$keep) = @_;
#   print STDERR &Dumper(['keep',$keep,'max_sim',$max_sim]);
    my $sims = $cached->{sims};
    my $n = @$sims - 1;
    my @todo = (@$keep,0..$n);
    return &RepKmers::rep_guts($cached,$max_sim,\@todo);
}

sub rep {
    my($cached,$max_sim,$keep,$save,$keepMap) = @_;

    if ($save) { open(SAVE,">$save") }
    my $fh = $save ? \*SAVE : \*STDOUT;
    my @reps = &rep1($cached,$max_sim,$keep);
    my $n = @reps;
    print "$max_sim\t$n\n\n";
    my $complete = $cached->{complete};
    my $index_to_g = $cached->{index_to_g};
    foreach my $r (@reps)
    {
        my $genome;
        if ($keepMap->{$r}) {
            $genome = $keepMap->{$r};
        } else {
            $genome = $index_to_g->{$r};
        }
        print $fh join("\t",($r,$genome,$complete->{$genome})),"\n";
    }
    if ($save) { close(SAVE) }
}

sub repN {
    my($cached,$N,$keep) = @_;

    my $lo = 5;
    my $hi = 200;
    my $mid = int(($lo+$hi)/2);
    my @reps = &rep1($cached,$mid,$keep);
#   $_ = @reps; print STDERR "$_ $N mid=$mid lo=$lo hi=$hi\n";
    while ($hi > ($lo+4))
    {
        if (@reps > $N)
        {
            $hi = $mid
        }
        else
        {
            $lo = $mid;
        }
        $mid = int(($lo+$hi)/2);
        @reps = &rep1($cached,$mid,$keep);
#       $_ = @reps; print STDERR "$_ $N mid=$mid lo=$lo hi=$hi\n";
    }
    my $n = @reps;
    print "$n\t",join(",",@reps),"\n\n";
}

sub ids_to_indexes {
    my($ids_or_indexes,$g_to_index) = @_;

    my @indexes = ();
    foreach $_ (@$ids_or_indexes)
    {
        if ($_ =~ /^(\d+)$/)
        {
            push(@indexes,$1);
        }
        elsif ($_ =~ /^(\d+\.\d+)$/)
        {
            if (my $i = $g_to_index->{$1})
            {
                push(@indexes,$i);
            }
            else
            {
                print STDERR "BAD GENOME ID OR INDEX\n";
            }
        }
    }
    return @indexes;
}

sub who_represents {
    my($i,$file,$sims) = @_;

    open(SAV,"<$file") || die "could not open $file";
    $_ = <SAV>;
    ($_ =~/^(\d+)/) || die "$file is malformed";
    my $min = $1;
    $_ = <SAV>;

    my %set = map { ($_ =~ /^(\d+)\t(\d+\.\d+)\t(\S.*\S)$/) ? ($1 => [$2,$3]) : () } <SAV>;
    close(SAV);

    if ($set{$i})
    {
        print "$i is a representative\n";
    }
    else
    {
        my $closest = $sims->[$i];
        my $j;
        for ($j=0; ($j < @$closest); $j++)
        {
            if ($closest->[$j]->[0] >= $min)
            {
                print join("\t",($i,@{$closest->[$j]})),"\n";
            }
        }
    }
}

sub thin {
    my($cached,$max_sim,$to_thin) = @_;
    my $sims = $cached->{sims};
    my $n = @$sims - 1;
    my @to_thin = split(/,/,$to_thin);
    my @thinned = ();

    my %seen;
    while (defined(my $i = shift @to_thin))
    {
        if (! $seen{$i})
        {
            push(@thinned,$i);
            $seen{$i} = 1;
#           print STDERR "added $i to reps\n";
            if (my $close = $sims->[$i])
            {
                if (defined($close))
                {
                    my $i2 = 0;
                    while (($i2 < @$close) && ($close->[$i2]->[0] >= $max_sim))
                    {
                        $seen{$close->[$i2]->[1]} = 1;
#			print STDERR "marked $close->[$i2]->[1]\n";
                        $i2++;
                    }
                }
            }
        }
    }
    return @thinned;
}

#   my ($keep, $keepMap) = &compute_keep_data(\@keep_ids_or_indexes,$g_to_index);
#
# We must convert genome IDs to VSS indexes. First, we map each genome ID to its VSS representative.
# Then the index is $g_to_index->{$vssMap{$genome}}. If the genome ID is not found we emit a warning.
# The keep map converts each index to its original genome ID. We use this for output.
#
sub compute_keep_data {
    my ($keep_ids_or_indexes, $g_to_index, $index_to_g) = @_;
    # First we create the VSS map.
    open(my $ih, "<$dir/vss") || die "Could not open VSS file: $!";
    my (%vssMap, $current);
    while (! eof $ih) {
        my $line = <$ih>; chomp $line;
        if ($line eq '//') {
            # Here we are starting a new group.
            undef $current;
        } else {
            # The first ID in the group becomes its representative.
            if (! $current) {
                $current = $line;
            }
            # Map this genome to the current rep.
            $vssMap{$line} = $current;
        }
    }
    # Loop through the IDs now.
    my (@keep, %keepMap);
    for my $id_or_index (@$keep_ids_or_indexes) {
        my $id;
        if ($id_or_index =~ /^\d+\.\d+/) {
            # Here we have a genome ID.
            if ($vssMap{$id_or_index}) {
                $id = $g_to_index->{$vssMap{$id_or_index}};
                $keepMap{$id} = $id_or_index;
                #print "Genome $id_or_index mapped to group $id.\n";
            } elsif ($g_to_index->{$id_or_index}) {
                $id = $g_to_index->{$id_or_index};
                $keepMap{$id} = $id_or_index;
                #print "Genome $id_or_index mapped to singleton $id.\n";
            } else {
                #print "Genome $id_or_index not found.\n";
            }
        } else {
            # Here we have a raw index. The output will be a genome ID.
            $id = $id_or_index;
            $keepMap{$id} = $index_to_g->{$id};
        }
        if (defined $id) {
            push @keep, $id;
        }
    }
    return (\@keep, \%keepMap);
}

sub get_contigs {
    my ($genome) = @_;
    my $retVal;
    my $contigs = Shrub::Contigs->new($shrub, $genome);
    if ($contigs) {
        $retVal = [ $contigs->tuples ];
    } else {
        $contigs = $p3->fasta_of($genome);
        if (@$contigs) {
            $retVal = $contigs;
        }
    }
    return $retVal;
}

sub help {
    print <<END;
    closest_by_sc Index N      [returns closest N genomes by sc]
    closest_N_genomes Index N  [returns closest N genomes]
    close_rep_seq N Sequence   [returns close representative]
    id_to_index  Id            [returns genome index]
    index_to_id  Index         [returns genome id]
    match_tails 16-mer         [returns genomes with matching PheS tail]
    n_reps N [keep1, keep2, ...keepn]
                               [returns rep set of about N seqs]
    rep_by IndexOrId File      [returns representative]
    represents IndexOrId File  [returns genomes represented by a given one]
    rep_set N [[keep1, keep2, ...keepN] or FileIn] [save=FileO]
                               [returns rep set ]
    thin_set N Index1 Index2 ... IndexN  [ make thinned set ]
    load_sigs K sigFile        [load signature kmers of size K from the file]
    find_sigs genome           [analyzes each contig in patric genome using signatures]
END
}

