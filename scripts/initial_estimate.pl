use strict;
use Data::Dumper;
use SeedUtils;
use ScriptUtils;
use Shrub;
use File::Slurp;
use BasicLocation;

# usage: initial_estimate -r reference.counts -d ReferenceDir > initial.estimate
my $opt = ScriptUtils::Opts(
    '',
    Shrub::script_options(),
    [ 'unicontigs|u=s','write contig to universal into this file',{}],
    [ 'refcounts|c=s', 'kmer reference counts', { required => 1 } ],
    [
        'minlen|l=i',
        'minimum length for blast match to count',
        { default => 500 }
    ],
    [
        'maxpsc|p=f',
        'maximum pscore for blast match to count',
        { default => 1.0e-100 }
    ],
    [ 'blast|b=s',  'blast type (p or n)',               { default => 'p' } ],
    [ 'minsim|s=f', 'minimum % identity for condensing', { default => 0.8 } ],
    [ 'savevecs|v=s', 'File used to save sim vecs (dot products)',  {} ],
    [ 'normalize|n',  'normalize position vectors as unit vectors', {} ],
    [
        'refD|r=s',
        'Constructed Directory Reflecting Reference Genomes',
        { required => 1 }
    ],
    [
        'covgRatio|cr=s',
        'maximum acceptable coverage ratio for condensing',
        { default => 1.2 }
    ],
    [
        'univLimit|ul=n',
        'maximum number of duplicate universal proteins in a set', { default => 2 }
    ],
    [
        'minCovg|C=f',
        'minimum coverage amount for a community sample contig', { default => 0 }
    ],
);

my $blast_type = $opt->blast;
$blast_type = ( $blast_type =~ /^[pP]/ ) ? 'p' : 'n';

my $uni_contigsF = $opt->unicontigs;
my $ref_counts      = $opt->refcounts;
my $refD            = $opt->refd;
my $save_vecsF      = $opt->savevecs;
my $max_psc         = $opt->maxpsc;
my $min_len         = $opt->minlen;
my $min_sim         = $opt->minsim;
my $normalize       = $opt->normalize;
my $covg_constraint = $opt->covgratio;
my $univ_limit      = $opt->univlimit;
my $min_covg        = $opt->mincovg;

my %univ_roles = map { $_ => 1 } File::Slurp::read_file("$FIG_Config::global/uni.roles", { chomp => 1 });
opendir( REFD, $refD ) || die "Could not access $refD";
my @refs = sort { $a <=> $b } grep { $_ !~ /^\./ } readdir(REFD);
my %refs = map { ( $_ => 1 ) } @refs;
closedir(REFD);

open(LOG, ">$FIG_Config::data/sets.log") || die "Could not open log file: $!"; ## TODO logging
my %setNames; ## TODO logging

my @lines = File::Slurp::read_file($ref_counts);
my %ref_counts =
  map { ( ( $_ =~ /^(\d+)\t(\S+)/ ) && $refs{$1} ) ? ( $2 => $1 ) : () } @lines;
my %ref_names =
  map { ( ( $_ =~ /^\d+\t(\S+)\t(\S.*\S)/ ) && $refs{$1} ) ? ( $1 => $2 ) : () }
  @lines;
@lines = ();    # Free up memory.

my $univ_in_ref =
  &univ_roles_in_ref_pegs( $refD, \%univ_roles, \@refs, $blast_type );

my ( $contig_similarities_to_ref, $univ_in_contigs ) =
  &process_blast_against_refs( \@refs, $refD, $univ_in_ref, $min_len, $max_psc,
    $blast_type, $min_covg );

if ($uni_contigsF)
{
    &write_unis_in_contigs($uni_contigsF,$univ_in_contigs);
}

my $normalized_contig_vecs =
  &compute_ref_vecs( \@refs, $contig_similarities_to_ref, $normalize );
my @similarities =
  &similarities_between_contig_vecs( $normalized_contig_vecs, $save_vecsF );

my @contigs = sort keys(%$normalized_contig_vecs);
my $final_sets =
  &cluster_contigs( \@contigs, \@similarities, $univ_in_contigs, $min_sim,
    $covg_constraint );
&output_final_sets( $final_sets, \%ref_names, \@refs, $normalized_contig_vecs );

sub output_final_sets
{
    my ( $final_sets, $ref_names, $refs, $normalized_contig_vecs ) = @_;

    my @sets = map { $final_sets->{$_} } keys(%$final_sets);

    #   an ugly Schwarzian transform
    my @s1 =
      map { my ( $contigs, $univ ) = @$_; [ scalar keys(%$univ), $_ ] } @sets;
    my @s2 = sort { $b->[0] <=> $a->[0] } @s1;
    @sets = map { $_->[1] } @s2;

    foreach my $set (@sets)
    {
        my ( $contigs, $univ ) = @$set;
        foreach my $contig (@$contigs)
        {
            &display_contig( $contig, $ref_names, $refs,
                $normalized_contig_vecs->{$contig} );
        }
        &display_univ($univ);
        print "//\n";
    }
}

sub write_unis_in_contigs {
    my($uni_contigsF,$univ_in_contigs) = @_;

    open(UNI,">$uni_contigsF") || die "could not open $uni_contigsF";
    foreach my $contig (sort keys(%$univ_in_contigs))
    {
        my $x = $univ_in_contigs->{$contig};
        foreach my $univ (sort keys(%$x))
        {
            print UNI join("\t",($contig,$univ)),"\n";
        }
    }
    close(UNI);
}

sub display_univ
{
    my ($univ) = @_;

    foreach my $role ( sort keys(%$univ) )
    {
        print join( "\t", ( $univ->{$role}, $role ) ), "\n";
    }
}

sub display_contig
{
    my ( $contig, $ref_names, $refs, $ref_vec ) = @_;

    print "$contig\n";
    my @hits;
    for ( my $i = 0 ; ( $i < @$ref_vec ) ; $i++ )
    {
        if ( $ref_vec->[$i] > 0 )
        {
            push( @hits,
                [ $ref_vec->[$i], $refs->[$i], $ref_names->{ $refs->[$i] } ] );
        }
    }
    @hits = sort { ( $b->[0] <=> $a->[0] ) } @hits;
    foreach my $hit (@hits)
    {
        print join( "\t", @$hit ), "\n";
    }
    print "\n";
}

sub cluster_contigs
{
    my ( $contigs, $similarities, $univ_in_contigs, $min_sim, $covg_constraint )
      = @_;

    my ( $sets, $contig_to_set ) = &initial_sets( $contigs, $univ_in_contigs );
    my $final_sets =
      &condense_sets( $sets, $contig_to_set, $similarities, $min_sim,
        $covg_constraint );
    return $final_sets;
}

sub condense_sets
{
    my ( $sets, $contig_to_set, $similarities, $min_sim, $covg_constraint ) =
      @_;

    foreach my $sim (@$similarities)
    {
        my ( $sc, $contig1, $contig2 ) = @$sim;
        my $set1 = $contig_to_set->{$contig1};
        my $set2 = $contig_to_set->{$contig2};
        if (   $set1
            && $set2
            && ( $set1 != $set2 )
            && ( $sc >= $min_sim )
            && &univ_ok( $sets->{$set1}->[1], $sets->{$set2}->[1] )
            && &covg_ok( $sets->{$set1}[2], $sets->{$set2}[2],
                $covg_constraint ) )
        {
            print LOG "Combining $set1 ($contig1) and $set2 ($contig2) with score $sc.\n";  ##TODO logging
            my $contigs_to_move = $sets->{$set2}->[0];
            foreach my $contig_in_set2 (@$contigs_to_move)
            {
                $contig_to_set->{$contig_in_set2} = $set1;
            }
            my $contigs1 = $sets->{$set1}->[0];
            my $contigs2 = $sets->{$set2}->[0];
            push( @$contigs1, @$contigs2 );
            my $u = $sets->{$set2}->[1];
            foreach my $role ( keys(%$u) )
            {
                my $v = $sets->{$set2}->[1]->{$role};
                $sets->{$set1}->[1]->{$role} += $v;
            }

        # Compute the new coverage (covg1 * len1 + covg2 * len2) / (len1 + len2)
            $sets->{$set1}[2] =
              ( $sets->{$set1}[2] * $sets->{$set1}[3] +
                  $sets->{$set2}[2] * $sets->{$set2}[3] ) /
              ( $sets->{$set1}[3] + $sets->{$set2}[3] );
            $sets->{$set1}[3] += $sets->{$set2}[3];

            delete $sets->{$set2};
        }
    }
    return $sets;
}

sub covg_ok
{
    my ( $covg1, $covg2, $covg_constraint ) = @_;
    my $retVal;
    if ( $covg1 > $covg2 )
    {
        $retVal = ( $covg1 <= $covg_constraint * $covg2 );
    }
    elsif ( $covg1 < $covg2 )
    {
        $retVal = ( $covg2 <= $covg_constraint * $covg1 );
    }
    else
    {
        $retVal = 1;
    }
    return $retVal;
}

sub univ_ok
{
    my ( $univ1, $univ2 ) = @_;
    return ( &in_common( $univ1, $univ2 ) <= $univ_limit );
}

sub in_common
{
    my ( $s1, $s2 ) = @_;

    my $in_common = 0;
    foreach $_ ( keys(%$s1) )
    {
        if ( $s2->{$_} )
        {
            $in_common++;
        }
    }
    return $in_common;
}

sub initial_sets
{
    my ( $contigs, $univ_in_contigs ) = @_;

    my $sets          = {};
    my $contig_to_set = {};
    my $nxt_set       = 1;
    foreach my $contig (@$contigs)
    {
        my $univ = $univ_in_contigs->{$contig};
        if ( !$univ )
        {
            $univ = {};
        }
        my ( $covg, $length );
        if ( $contig =~ /length_(\d+)_cov_([\d\.]+)_/ )
        {
            ( $length, $covg ) = ( $1, $2 );
        }
        else
        {
            die "Invalid contig ID $contig.";
        }
        $sets->{$nxt_set} = [ [$contig], $univ, $covg, $length ];
        $setNames{$nxt_set} = $contig; ## TODO logging
        $contig_to_set->{$contig} = $nxt_set;
        $nxt_set++;
    }
    return ( $sets, $contig_to_set );
}

sub similarities_between_contig_vecs
{
    my ( $contig_vecs, $save_vecsF ) = @_;

    if ( $save_vecsF && ( -s $save_vecsF ) )
    {
        open(my $ih, "<", $save_vecsF) || die "Cannot open saved vectors: $!";
        return sort { $b->[0] <=> $a->[0] }
          map { chomp; [ split( /\t/, $_ ) ] }
          <$ih>;
    }
    else
    {
        my @sims = &similarities_between_contig_vecs_1($contig_vecs);
        if ( $save_vecsF && open( SAVE, ">$save_vecsF" ) )
        {
            foreach my $tuple (@sims)
            {
                print SAVE join( "\t", @$tuple ), "\n";
            }
            close(SAVE);
        }
        return @sims;
    }
}

sub similarities_between_contig_vecs_1
{
    my ($contig_vecs) = @_;

    my @sims;
    my @contigs = sort keys(%$contig_vecs);
    my $n       = @contigs;
    my ( $i, $j );
    for ( $i = 0 ; ( $i < @contigs ) ; $i++ )
    {
        my $cv1 = $contig_vecs->{ $contigs[$i] };
        for ( $j = $i + 1 ; ( $j < @contigs ) ; $j++ )
        {
            my $cv2 = $contig_vecs->{ $contigs[$j] };
            my $sim = &dot_product( $cv1, $cv2 );
            if ( $sim > 0 )
            {
                push( @sims, [ $sim, $contigs[$i], $contigs[$j] ] );
            }
        }
        if ( ( $i % 100 ) == 0 ) { print STDERR "$i of $n\n" }
    }
    return sort { $b->[0] <=> $a->[0] } @sims;
}

sub compute_ref_vecs
{
    my ( $refs, $contig_similarities_to_ref, $normalize ) = @_;

    my $contig_vecs = {};
    foreach my $contig ( sort keys(%$contig_similarities_to_ref) )
    {
        my $v    = [];
        my $keep = 0;    # we keep only contigs that hit at least one ref
        for ( my $i = 0 ; ( $i < @$refs ) ; $i++ )
        {
            my $r = $refs->[$i];
            my $x = $contig_similarities_to_ref->{$contig}->{$r};
            if ( !$x )
            {
                $x = 0;
            }
            else
            {
                $keep = 1;
            }
            push( @$v, $x );
        }
        if ( $keep && &sims_ok($v) )
        {
            $contig_vecs->{$contig} = $normalize ? &unit_vector($v) : $v;
        }
    }
    return $contig_vecs;
}

sub sims_ok
{
    my ($v) = @_;

    my $tot = 0;
    foreach $_ (@$v) { $tot += $_ }
    return (( $tot > 30) && ($tot < 10000))
}

sub dot_product
{
    my ( $v1, $v2 ) = @_;

    my $tot = 0;
    my $i;
    for ( $i = 0 ; ( $i < @$v1 ) ; $i++ )
    {
        if ( $v1->[$i] && $v2->[$i] )
        {
            $tot += $v1->[$i] * $v2->[$i];
        }
    }
    return $tot;
}

sub unit_vector
{
    my ($v) = @_;

    my $tot = 0;
    my $uv  = [];
    my $i;
    for ( $i = 0 ; ( $i < @$v ) ; $i++ )
    {
        my $x = $v->[$i];
        if ( defined($x) )
        {
            $tot += $x * $x;
        }
    }

    my $nf = sqrt($tot);
    for ( $i = 0 ; ( $i < @$v ) ; $i++ )
    {
        my $x = $v->[$i];
        $x = $x ? $x : 0;
        if ($nf)
        {
            my $y = $x / $nf;
            if ( $y > 1 ) { $y = 1 }
            push( @$uv, sprintf( "%0.2f", $y ) );
        }
        else
        {
            push( @$uv, 0 );
        }
    }
    return $uv;
}

sub process_blast_against_refs
{
    my ( $refs, $refD, $univ_in_ref, $min_len, $max_psc, $blast_type, $min_covg ) = @_;

    my $contig_similarities_to_ref = {};
    my $univ_in_contigs            = {};

    my $blast_out =
      ( $blast_type =~ /^[pP]/ ) ? 'blast.out.protein' : 'blast.out.dna';
    foreach my $r (sort @$refs)
    {
        my $dir = "$refD/$r";
        open( BLAST, "<$dir/$blast_out" ) || die "$dir/$blast_out is missing";
        while ( defined( $_ = <BLAST> ) )
        {
            chomp;
            my (
                $ref_id, $contig_id, $iden, undef, undef, undef,
                $rbeg,   $rend,      $beg,  $end,  $psc,  $bsc
               ) = split( /\s+/, $_ );
            $contig_id =~ /cov_([\d\.]+)/;

            my $covg = $1 // 0;
            if ( ($covg >= $min_covg) && ( $psc <= $max_psc ) && ( abs( $end - $beg ) >= $min_len ) )
            {
                if ( ( ! defined($contig_similarities_to_ref->{$contig_id}->{$r})) ||
                     ( $contig_similarities_to_ref->{$contig_id}->{$r} <  $iden))
                {
                    $contig_similarities_to_ref->{$contig_id}->{$r} = $iden;
                }

                if ( $blast_type eq 'n' )
                {
                    if ( $_ =
                        &in_univ( $univ_in_ref, $r, $ref_id, $rbeg, $rend ) )
                    {
                        $univ_in_contigs->{$contig_id}->{$_} = 1;
                    }
                }
                else
                {
                    if ( $_ = &univ_prot( $univ_in_ref, $r, $ref_id ) )
                    {
                        $univ_in_contigs->{$contig_id}->{$_} = 1;
                    }
                }
            }
        }
        close(BLAST);
    }
    return ( $contig_similarities_to_ref, $univ_in_contigs );
}

sub univ_prot
{
    my ( $univ_in_ref, $ref, $ref_id ) = @_;

    if ( my $x = $univ_in_ref->{$ref}->{$ref_id} )
    {
        return $x->[0]->[1];
    }
    return undef;
}

sub in_univ
{
    my ( $univ_in_ref, $ref, $ref_contig, $beg, $end ) = @_;

    if ( my $x = $univ_in_ref->{$ref}->{$ref_contig} )
    {
        my $i;
        for (
            $i = 0 ;
            ( $i < @$x ) && ( !&between( $beg, $x->[$i]->[0], $end ) ) ;
            $i++
          )
        {
        }
        if ( $i < @$x )
        {
            return $x->[$i]->[1];
        }
    }
    return undef;
}

sub univ_roles_in_ref_pegs
{
    my ( $refD, $univ_roles, $refs, $blast_type ) = @_;

    my $univ_in_ref = {};
    foreach my $r (@$refs)
    {
        my $dir      = "$refD/$r";
        my $gto      = &SeedUtils::read_encoded_object("$dir/genome.gto");
        my $features = $gto->{features};
        foreach my $f (@$features)
        {
            if ( $univ_roles->{ $f->{function} } )
            {
                if ( $blast_type eq 'n' )
                {
                    my @locs =
                      map { BasicLocation->new($_) } @{ $f->{location} };
                    my $contig = $locs[0]->Contig;
                    my $midpt =
                      int( ( $locs[0]->Left + $locs[-1]->Right ) / 2 );
                    push(
                        @{ $univ_in_ref->{$r}->{$contig} },
                        [ $midpt, $f->{function} ]
                    );
                }
                else
                {
                    push( @{ $univ_in_ref->{$r}->{ $f->{id} } },
                        [ undef, $f->{function} ] );
                }
            }
        }
    }
    return $univ_in_ref;
}

# $univ_in_ref = &fids_of_univ_roles_in_refs( $refD, \%univ_roles, \@refs );
sub fids_of_univ_roles_in_refs {
    my ($refD, $univ_roles, $refs) = @_;

    my $univ_in_ref = {};
    foreach my $r (@$refs) {
        my $dir      = "$refD/$r";
        my $gto      = &SeedUtils::read_encoded_object("$dir/genome.gto");
        my $features = $gto->{features};
        foreach my $f (@$features)
        {
            if ( $univ_roles->{ $f->{function} } ) {
                $univ_in_ref->{$f->{id}} = $f->{function};
            }
        }
    }
    return $univ_in_ref;
}
