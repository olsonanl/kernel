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

package MapToRef;

use strict;
use warnings;
use FIG_Config;
use Data::Dumper;
use SeedUtils;
use ScriptUtils;
use gjoseqlib;

=head1 project reference genome to a close strain

    fast_project -r RererenceGenomeDir -g SkeletalGenomeDir [ options ]

project a reference genome to call features


=head2 Parameters

## describe positional parameters

The command-line options are those found in L<Shrub/script_options> and
L<ScriptUtils/ih_options> plus the following.

=over 4

=item -r ReferenceGenomeDir

a path to a SEED genome directory for the reference genome

=item -g SkeletalGenomeDir

a path to a skeletal SEED genome directory that must include

    contigs
    GENETIC_CODE (if not 11)

=back

=cut

## method documentation and code

sub build_mapping {
    my ( $k, $r_tuples, $g_tuples ) = @_;

    #print STDERR "Calling build_hash for reference\n";
    my $r_hash = &build_hash( $r_tuples, $k );

    #print STDERR "Calling build_hash for new\n";
    my $g_hash = &build_hash( $g_tuples, $k );

    my $pins = &build_pins( $r_tuples, $k, $g_hash, $r_hash );
    my @map = &fill_pins( $pins, $r_tuples, $g_tuples );

    return \@map;
}

# a hash has a 0-base for each kmer (kmer is a key to a 0-based location)
sub build_hash {
    my ( $contigs, $k ) = @_;

    my $hash = {};
    my %seen;
    foreach my $tuple (@$contigs) {
        my ( $contig_id, $comment, $seq ) = @$tuple;
        my $last = length($seq) - $k;
        for ( my $i = 0 ; ( $i <= $last ) ; $i++ ) {
            my $kmer = uc substr( $seq, $i, $k );
            if ( $kmer !~ /[^ACGT]/ ) {
                my $comp = &rev_comp($kmer);
                if ( $hash->{$kmer} ) {
                    $seen{$kmer} = 1;
                    $seen{$comp} = 1;
                }
                $hash->{$kmer} = [ $contig_id, "+", $i ];
                $hash->{$comp} = [ $contig_id, "-", $i + $k - 1 ];
            }
        }
    }

    foreach my $kmer ( keys(%seen) ) {
        delete $hash->{$kmer};
    }

    #print STDERR &Dumper( 'hash', $hash );
    return $hash;
}

# pins are 0-based 2-tuples.  It is an ugly fact that the simple pairing of unique
# kmers can lead to a situation in which 1 character in the reference genome is paired
# with more than one character in the new genome (and vice, versa).  We sort of handle that.
sub build_pins {
    my ( $r_contigs, $k, $g_hash, $r_hash ) = @_;

    my @pins;
    foreach my $tuple (@$r_contigs) {
        my ( $contig_id, $comment, $seq ) = @$tuple;
        my $last = length($seq) - $k + 1;
        my $found = 0;
        my $i = 0;
        while ( $i <= $last ) {
            my $kmer = uc substr( $seq, $i, $k );
            if ( ( $kmer !~ /[^ACGT]/ ) && $r_hash->{$kmer} ) {
                my $g_pos = $g_hash->{$kmer};
                if ($g_pos) {
                    my ( $g_contig, $g_strand, $g_off ) = @$g_pos;
                    for ( my $j = 0 ; $j < $k ; $j++ ) {
                        if ( $g_strand eq '+' ) {
                            push(
                                @pins,
                                [
                                    [ $contig_id, '+', $i + $j ],
                                    [ $g_contig,  '+', $g_off + $j ]
                                ]
                            );
                        } else {
                            push(
                                @pins,
                                [
                                    [ $contig_id, '+', $i + $j ],
                                    [ $g_contig,  '-', $g_off - $j ]
                                ]
                            );
                        }
                    }
                    $i = $i + $k;
                } else {
                    $i++;
                }
            } else {
                $i++;
            }
        }
    }
    @pins = &remove_dups( 0, \@pins );
    @pins = &remove_dups( 1, \@pins );
    @pins = sort {
             ( $a->[0]->[0] cmp $b->[0]->[0] )
          or ( $a->[0]->[2] <=> $b->[0]->[2] )
    } @pins;

    #print STDERR &Dumper( [ '0-based pins', \@pins ] );
    return \@pins;
}

sub remove_dups {
    my ( $which, $pins ) = @_;

    my %bad;
    my %seen;
    for ( my $i = 0 ; ( $i < @$pins ) ; $i++ ) {
        my $keyL = $pins->[$i]->[$which];
        my $key = join( ",", @$keyL );
        if ( $seen{$key} ) {
            $bad{$i} = 1;
        }
        $seen{$key} = 1;
    }
    my @new_pins;
    for ( my $i = 0 ; ( $i < @$pins ) ; $i++ ) {
        if ( !$bad{$i} ) {
            push( @new_pins, $pins->[$i] );
        }
    }
    return @new_pins;
}

sub fill_pins {
    my ( $pins, $ref_tuples, $g_tuples ) = @_;

    my %ref_seqs = map { ( $_->[0] => $_->[2] ) } @$ref_tuples;
    my %g_seqs   = map { ( $_->[0] => $_->[2] ) } @$g_tuples;

    my @filled;
    for ( my $i = 0 ; ( $i < @$pins ) ; $i++ ) {
        if ( $i == ( @$pins - 1 ) ) {
            push( @filled, $pins->[$i] );
        } else {
            my @expanded = &fill_between( $pins->[$i], $pins->[ $i + 1 ],
                \%ref_seqs, \%g_seqs );
            push( @filled, @expanded );
        }
    }
    return @filled;
}

sub fill_between {
    my ( $pin1, $pin2, $ref_seqs, $g_seqs ) = @_;
    my ( $rp1, $gp1 ) = @$pin1;
    my ( $rp2, $gp2 ) = @$pin2;
    my ( $contig_r_1, $strand_r_1, $pos_r_1 ) = @$rp1;
    my ( $contig_r_2, $strand_r_2, $pos_r_2 ) = @$rp2;
    my ( $contig_g_1, $strand_g_1, $pos_g_1 ) = @$gp1;
    my ( $contig_g_2, $strand_g_2, $pos_g_2 ) = @$gp2;

    my @expanded;
    if (
           ( $contig_r_1 eq $contig_r_2 )
        && ( $contig_g_1 eq $contig_g_2 )
        && ( $strand_g_1 eq $strand_g_2 )
        && ( ( $pos_r_2 - $pos_r_1 ) == abs( $pos_g_2 - $pos_g_1 ) )
        && ( ( $pos_r_2 - $pos_r_1 ) > 1 )
        && &same(
            [ $contig_r_1,, $pos_r_1, $pos_r_2 - 1, $ref_seqs ],

            #[ $contig_r_1, '+', $pos_r_1, $pos_r_2 - 1, $ref_seqs ],
            [
                $contig_g_1,

                #$strand_g_1,
                ( $strand_g_1 eq '+' )
                ? ( $pos_g_1, $pos_g_2 - 1 )
                : ( $pos_g_1, $pos_g_2 + 1 ),
                $g_seqs
            ]
        )
      )
    {
        my $p_r = $pos_r_1;
        my $p_g = $pos_g_1;
        while ( $p_r < $pos_r_2 ) {
            push(
                @expanded,
                [
                    [ $contig_r_1, '+',         $p_r ],
                    [ $contig_g_1, $strand_g_1, $p_g ]
                ]
            );
            $p_r++;
            $p_g = ( $strand_g_1 eq "+" ) ? $p_g + 1 : $p_g - 1;
        }
    } else {
        push @expanded, $pin1;
    }
    return @expanded;
}

sub same {
    my ( $gap1, $gap2 ) = @_;
    my ( $c1, $b1, $e1, $seqs1 ) = @$gap1;
    my ( $c2, $b2, $e2, $seqs2 ) = @$gap2;

    my $seq1 = &seq_of( $c1, $b1, $e1, $seqs1 );
    my $seq2 = &seq_of( $c2, $b2, $e2, $seqs2 );
    if ( length($seq1) < 20 ) {
        return 1;
    } else {
        my $iden = 0;
        my $len  = length($seq1);
        for ( my $i = 0 ; ( $i < $len ) ; $i++ ) {
            if ( substr( $seq1, $i, 1 ) eq substr( $seq2, $i, 1 ) ) {
                $iden++;
            }
        }
        return ( ( $iden / $len ) >= 0.8 );
    }
}

sub seq_of {
    my ( $c, $b, $e, $seqs ) = @_;

    my $seq = $seqs->{$c};
    if ( $b <= $e ) {
        return uc substr( $seq, $b - 1, ( $e - $b ) + 1 );
    } else {
        return uc &rev_comp( substr( $seq, $e - 1, ( $b - $e ) + 1 ) );
    }
}

sub build_features {
    my ( $map, $g_tuples, $features, $genetic_code ) = @_;
    #my ( $map, $refD, $genomeD, $g_tuples, $genetic_code ) = @_;

    my %g_seqs = map { ( $_->[0] => $_->[2] ) } @$g_tuples;

    my %refH;
    foreach my $pin (@$map) {
        my ( $ref_loc, $g_loc ) = @$pin;
        my ( $r_contig, $r_strand, $r_pos ) = @$ref_loc;
        $refH{ $r_contig . ",$r_pos" } = $g_loc;
    }

    my @new_features;

    foreach my $tuple (@$features) {
        my ($fid, $type, $loc, $assign) = @$tuple;
        print "Feature = $fid of $type at " . join(",",@$loc) . "\n"; ## TODO trace
        my ($r_contig, $r_beg, $r_strand, $r_len) = @$loc;
        my $r_end = ($r_strand eq '+') ? $r_beg+($r_len-1) : $r_beg-($r_len-1);
        print "Loc ends at $r_end\n"; ## TODO trace
        if (   ( my $g_locB = $refH{ $r_contig . ",$r_beg" } )
            && ( my $g_locE = $refH{ $r_contig . ",$r_end" } ) ) {

            my ( $g_contig1, $g_strand1, $g_pos1 ) = @$g_locB;
            my ( $g_contig2, $g_strand2, $g_pos2 ) = @$g_locE;
            print "gpos1 = $g_pos1, gpos2 = $g_pos2, rbeg = $r_beg, rend = $r_end\n"; ##TODO trace
            if ( ( $g_contig1 eq $g_contig2 ) && ( $g_strand1 eq $g_strand2 )
                    && ( abs( $g_pos1 - $g_pos2 ) == abs( $r_beg - $r_end ) )) {

                my $g_len = abs( $r_end - $r_beg) + 1;
                my $g_strand = ($r_end > $r_beg) ? '+' : '-';
                my $g_location = "$g_contig1:" . ($g_pos1+1) . $g_strand . $g_len;
                print "Checking sequence.\n"; ## TODO trace
                my $seq = &seq_of_feature( $type, $genetic_code, $g_contig1, $g_pos1, $g_pos2, \%g_seqs );

                if ($seq) {
                    push @new_features, [$type, $g_location, $assign, $fid, $seq];
                    print "New feature $type at $g_location from $fid.\n"; ## TODO trace
                }
            }
        }
    }
    return \@new_features;
}

sub get_genetic_code {
    my ($dir) = @_;

    if ( !-s "$dir/GENETIC_CODE" ) { return 11 }
    open(my $ih, "<$dir/GENETIC_CODE") || die "Could not open genetic code file in $dir: $!";
    my $tmp = <$ih>;
    chomp $tmp;
    return $tmp;
}

sub seq_of_feature {
    my ( $type, $genetic_code, $g_contig, $g_beg, $g_end, $g_seqs ) = @_;
    my $dna = &seq_of( $g_contig, $g_beg, $g_end, $g_seqs );
    if ( ( $type ne "peg" ) && ( $type ne "CDS" ) ) {
        return $dna;
    } else {
        my $code = &SeedUtils::standard_genetic_code;
        if ( $genetic_code == 4 ) {
            $code->{"TGA"} = "W";    # code 4 has TGA encoding tryptophan
        }
        my $tran = &SeedUtils::translate( $dna, $code, 1 );
        print "$tran\n"; ## TODO trace
        die "die on purpose"; ## TODO trace
        if ($tran =~ s/\*$// && $tran =~ /^M/) {
         	return ( $tran =~ /\*/ ) ? undef : $tran;
        } else {
        	return undef;
        }
    }
}

1;
