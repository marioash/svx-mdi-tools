use strict;
use warnings;

# initialize a numeric indexing scheme for genome positions and fixed-width bins/windows
# encoded in a signed integer where chromosome positions/windows are numbered sequentially across
# all chromosomes, in fai order, from 1 to genome size, + = top strand, - = bottom strand

# working variables
use vars qw($error $GENOME_FASTA $EXTRACT_PREFIX $WINDOW_SIZE 
            %chromIndex %revChromIndex);
my (%chromSizes, @chromSizes, @windowCoverage);

# constants
use constant {
    QNAME => 0, # PAF fields
    QLEN => 1,
    QSTART => 2,
    QEND => 3,
    STRAND => 4,
    RNAME => 5,
    RLEN => 6,
    RSTART => 7,
    REND => 8,
    N_MATCHES => 9,
    N_BASES => 10,
    MAPQ => 11,
    PAF_TAGS => 12,
    RNAME_INDEX => 13,  # added by us  
    #---------------- 
    N_CHROM_BASES => 0, 
    N_BASES_BEFORE => 1, 
    N_BASES_THROUGH => 2, 
    N_CHROM_WINDOWS => 3, 
    N_WINDOWS_BEFORE => 4,
    N_WINDOWS_THROUGH => 5
};

# functions for converting between 1-based chromosome-level coordinates and 0-based chromosome-level window array indexes
sub coordinateToWindowIndex {
    int(($_[0] - 1) / $WINDOW_SIZE); # bases 1-100 => windowIndex 0 for windowSize==100
}
sub windowIndexToCoordinate {
    $_[0] * $WINDOW_SIZE + 1; # windowIndex 0 => base 1 (first base in window)
}

# functions for converting chromosome[+strand]-level base positions into genome-level base and window positions
sub getUnsignedWindow {
    my ($chromIndex, $coordinate, $add) = @_;
    $chromSizes[$chromIndex][N_WINDOWS_BEFORE] + coordinateToWindowIndex($coordinate + $add);
}
sub getSignedWindow { # called by parse_nodes.pl
    my ($chromIndex, $coordinate, $strand, $add) = @_;
    getUnsignedWindow($chromIndex, $coordinate, $add) * ($strand eq "+" ? 1 : -1);
}
sub parseSignedWindow {
    my ($window) = @_;
    my $strand = $window > 0 ? "+" : "-";
    my $genomeIndex = abs($window);
    my $chromIndex = 1;
    $chromIndex += 1 while($genomeIndex >= $chromSizes[$chromIndex][N_WINDOWS_THROUGH]);
    {
        genomeIndex => $genomeIndex,        
        chromIndex  => $chromIndex,
        chrom       => $chromIndex ? $revChromIndex{$chromIndex} : "?",
        windowIndex => $genomeIndex - $chromSizes[$chromIndex][N_WINDOWS_BEFORE],
        strand      => $strand
    }
}

# construct a map of all concatenated chromosomes from a genome fai file
# called by extract_nodes.pl and window_coverage.pl
sub initializeWindowCoverage {
    open my $inH, "<", "$GENOME_FASTA.fai" or die "$error: file not found: $GENOME_FASTA.fai\n";
    my $nBasesBefore = 0;
    my $nWindowsBefore = 0;
    while(my $line = <$inH>){
        chomp $line;
        my ($chrom, $nChromBases) = split("\t", $line);
        my $chromIndex = $chromIndex{$chrom};
        my $nChromWindows = coordinateToWindowIndex($nChromBases) + 1;     
        $chromSizes{$chrom} = $chromSizes[$chromIndex] = [
            $nChromBases,   $nBasesBefore,   $nChromBases   + $nBasesBefore,
            $nChromWindows, $nWindowsBefore, $nChromWindows + $nWindowsBefore];
        $nBasesBefore += $nChromBases;
        $nWindowsBefore += $nChromWindows;
    }
    @windowCoverage = (0) x ($nWindowsBefore + 1);
    close $inH; 
}

# functions for creating a window coverage map 
# it's possible for short segments to disappear in the map if fully contained in a single window
# these functions are called by window_coverage.pl to parse alignment edges
sub incrementWindowCoverage { # place up/down marks in windows
    my ($window1, $window2) = @_;
    my $genomeIndex1 = abs($window1);
    my $genomeIndex2 = abs($window2);
    $genomeIndex1 > $genomeIndex2 and ($genomeIndex1, $genomeIndex2) = ($genomeIndex2, $genomeIndex1);
    $windowCoverage[$genomeIndex1]     += 1; # up in the aln's first window
    $windowCoverage[$genomeIndex2 + 1] -= 1; # down in the window AFTER this aln
}
sub printWindowCoverage {
    open my $outH, "|-", "bgzip -c | slurp -s 10M -o $ENV{COVERAGE_FILE}" or die "could not open: $ENV{COVERAGE_FILE}\n";
    my $coverage = 0;
    foreach my $genomeIndex(0..($#windowCoverage - 1)){
        $coverage += $windowCoverage[$genomeIndex];
        my $window = parseSignedWindow($genomeIndex);
        print $outH join("\t", $$window{chrom}, windowIndexToCoordinate($$window{windowIndex}), $genomeIndex, $coverage), "\n";
    }
    close $outH;
}

1;
