use strict;
use warnings;

# extract SV information from collated, name-sorted long-read alignments

# initialize reporting
our $script = "extract_nodes";
our $error  = "$script error";
my ($nInputAlns, $nInputMols) = (0) x 20;

# load dependencies
my $perlUtilDir = "$ENV{GENOMEX_MODULES_DIR}/utilities/perl";
map { require "$perlUtilDir/$_.pl" } qw(workflow numeric);
map { require "$perlUtilDir/genome/$_.pl" } qw(chroms);
our ($matchScore, $mismatchPenalty, $gapOpenPenalty, $gapExtensionPenalty) = 
    (1,           -1.5,             -1.5,            -2);
map { require "$perlUtilDir/sequence/$_.pl" } qw(general smith_waterman); # faidx 
resetCountFile();

# environment variables
fillEnvVar(\our $EXTRACT_PREFIX,   'EXTRACT_PREFIX');
fillEnvVar(\our $ACTION_DIR,       'ACTION_DIR');
fillEnvVar(\our $INPUT_DIR,        'INPUT_DIR');
fillEnvVar(\our $GENOMEX_MODULES_DIR, 'GENOMEX_MODULES_DIR');
fillEnvVar(\our $N_CPU,            'N_CPU'); # user options, or derived from them
fillEnvVar(\our $WINDOW_POWER,     'WINDOW_POWER');
fillEnvVar(\our $WINDOW_SIZE,      'WINDOW_SIZE');
fillEnvVar(\our $MIN_SV_SIZE,      'MIN_SV_SIZE');
fillEnvVar(\our $GENOME_FASTA,     'GENOME_FASTA');
fillEnvVar(\our $USE_CHR_M,        'USE_CHR_M');

# initialize the genome
use vars qw(%chromIndex);
setCanonicalChroms();

# load additional dependencies
require "$GENOMEX_MODULES_DIR/align/dna-long-read/get_indexed_reads.pl";
$perlUtilDir = "$ENV{MODULES_DIR}/utilities/perl/svPore";
map { require "$ACTION_DIR/extract/$_.pl" } qw(initialize_windows parse_nodes); # check_junctions
$perlUtilDir = "$ENV{MODULES_DIR}/parse_nodes";
map { require "$perlUtilDir/$_.pl" } qw(parse_nodes_support);
initializeWindowCoverage();

# constants
use constant {
    END_MOLECULE => '_ERM_',
    #-------------
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
    RNAME_INDEX => 13  # added by us 
};

# process data by molecule over multiple parallel threads
launchChildThreads(\&parseMolecule);
use vars qw(@readH @writeH);
my $writeH = $writeH[1];
my ($threadName);
while(my $line = <STDIN>){
    $nInputAlns++;
    my ($qName) = split("\t", $line, 2);  
    if($threadName and $qName ne $threadName){
        $nInputMols++;        
        print $writeH END_MOLECULE, "\t$threadName\n";        
        $writeH = $writeH[$nInputMols % $N_CPU + 1];
    }    
    print $writeH $line; # commit to worker thread
    $threadName = $qName;
}
$nInputMols++;
print $writeH END_MOLECULE, "\t$nInputMols\n";      
finishChildThreads();

# print summary information
printCount($nInputMols, 'nInputMols', 'input molecules');
printCount($nInputAlns, 'nInputAlns', 'input aligned segments over all molecules');

# child process to parse PAF molecules
sub parseMolecule {
    my ($childN) = @_;
    
    # auto-flush output to prevent buffering and ensure proper feed to sort
    $| = 1;

    # working variables
    our (@alns, $molId,
         @nodes,    @types,    @mapQs,    @sizes,    @insSizes,    @outAlns,
         @alnNodes, @alnTypes, @alnMapQs, @alnSizes, @alnInsSizes, @alnAlns) = ();
  
    # run aligner output one alignment at a time
    my $readH = $readH[$childN];
    while(my $line = <$readH>){
        chomp $line;
        my @aln = split("\t", $line, 13); 

        # process all alignments from one source molecule    
        if($aln[0] eq END_MOLECULE){
            $molId = $aln[1]; # ($aln[1] * 100) + $childN;   

            # characterize the path of a single molecule
            @alns = sort { $$a[QSTART] <=> $$b[QSTART] } @alns; # sort alignments in query order (could be right to left on bottom strand)
            foreach my $i(0..$#alns){

                # add information on the junction between two alignments
                if($i > 0){
                    my $jxn = processSplitJunction($alns[$i-1], $alns[$i]);
                    push @types,    $$jxn{jxnType};
                    push @mapQs,    0;
                    push @sizes,    $$jxn{svSize};
                    push @insSizes, $$jxn{insSize};
                    push @outAlns,  [];
                }         

                # add each alignment    
                (@alnNodes, @alnTypes, @alnMapQs, @alnSizes, @alnInsSizes, @alnAlns) = ();
                processAlignedSegment($alns[$i]);
                push @nodes,    @alnNodes;
                push @types,    @alnTypes;
                push @mapQs,    @alnMapQs;
                push @sizes,    @alnSizes;
                push @insSizes, @alnInsSizes;
                push @outAlns,  @alnAlns;
            }

            # examine SV junctions for evidence of duplex reads
            # adjusts the output arrays as needed
            my $nStrands = checkForDuplex(scalar(@types));

            # set junction MAPQ as minimum MAPQ of the two flanking alignments
            fillJxnMapQs();

            # print one line per node pair in the collapsed molecule sequence
            printMolecule($molId, $nStrands);

            # reset for next molecule
            (@alns, @nodes, @types, @mapQs, @sizes, @insSizes, @outAlns) = ();

        # add new alignment to growing source molecule    
        } else{
            $aln[RNAME_INDEX] = $chromIndex{$aln[RNAME]} || 0; # unknown sequences places into chrom/window zero 
            push @alns, \@aln;
        }
    }
}