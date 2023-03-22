#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper qw(Dumper);
use Digest::SHA qw(sha1_hex);
use Getopt::Long qw(GetOptions);
use XML::Parser;

use constant {
    IT_ARRAY => 0,
    IT_INDEX => 1,
    IT_INDEX_NEXT => 2,
    ELM_TAG => 0,
    ELM_VALUE => 1,
    ELM_VALUE_ATTR => 0,
    ELM_VALUE_FIRST => 1
};

sub XMLIterator {
    my ($arr) = @_;
    return [$arr, ELM_VALUE_FIRST];
}

sub XMLIteratorGetElement {
    my ($it) = @_;
    my $arr = $it->[IT_ARRAY];
    my $ind = \$it->[IT_INDEX];
    scalar(@{$arr}) - $$ind or return undef;
    my $tag = $arr->[$$ind + ELM_TAG];
    my $value = $arr->[$$ind + ELM_VALUE];
    $$ind += IT_INDEX_NEXT;
    return [$tag, $value];
};

Getopt::Long::Configure qw(gnu_getopt);
my $runners = 1;
my $algo = 'sha1';
my $usage = <<"END_USAGE";
$0 [-h|--help] [-j|--jobs <num_jobs>] <psx_game_dir>
  -h|--help        Print this message
  -j|--jobs        Number of workers (defaults to 1)
END_USAGE
my $help;
GetOptions("jobs|j=i" => \$runners,
           "help|h" => \$help,
) or die($usage);
if($help) {
    print $usage;
    exit 0;
}
my $gamedir = shift @ARGV or die "No psx_game_dir provided";
-d $gamedir or die "psx_game_dir: $gamedir does not exist";

# download psx database from redump, extract, and load.
print "parsing db into hash of games and files ...\n";
my $parser = XML::Parser->new(Style => 'Tree');
my $redump = $parser->parsefile('Sony - PlayStation - Datfile (10701) (2023-03-22 01-15-22).dat');
my %redumpgames;
$redump->[ELM_TAG] eq 'datafile' or die "should be a datafile";
my $dfit = XMLIterator($redump->[ELM_VALUE]);
while(my $elm = XMLIteratorGetElement($dfit)) {
    next if($elm->[ELM_TAG] ne 'game');
    my %game;
    my $gameit = XMLIterator($elm->[ELM_VALUE]);
    while(my $gelm = XMLIteratorGetElement($gameit)) {
        next if($gelm->[ELM_TAG] ne 'rom');
        $game{$gelm->[ELM_VALUE][ELM_VALUE_ATTR]{name}} = $gelm->[ELM_VALUE][ELM_VALUE_ATTR];
    }
    $redumpgames{$elm->[ELM_VALUE][ELM_VALUE_ATTR]{name}} = \%game;
}
print "parsing db into hash of games and files ... done\n";
#print Dumper(\%redumpgames);
#die;


# divide up the games and launch the workers
opendir(my $dh, $gamedir) or die "failed to open psx_game_dir: $gamedir";
my @games = readdir($dh);
@games = grep { ($_ ne '.') && ($_ ne '..')} @games;
my $numchildren = 0;
for(my $i = 0; $i < $runners; $i++) {
    my $num_games = int(scalar(@games) / ($runners-$i));
    if($num_games == 0) {
        print "runner $i: nothing to process\n";
        next;
    }
    my @current_games = splice(@games, -1 * $num_games);
    my $forkres = fork() // die "failed to fork";
    if($forkres != 0) {
        $numchildren++;
        next;
    }
    my $rc = 0;
    GAME:
    foreach my $game (@current_games) {
        # sanity check, verify against redump before unpacking and repacking
        if(! exists $redumpgames{$game}) {
            print "runner $i: game: $game not found in redump database\n";
            $rc = 1;
            next;
        }
        my $gamebad;
        my $binfile;
        foreach my $file (keys %{$redumpgames{$game}}) {
            my $localfile = "$gamedir/$game/$file";
            if($localfile =~ /\.bin/) {
                if($binfile) {
                    print "runner $i: $game failed, multi-bin is not supported yet\n";
                    $gamebad = 1;
                    next;
                }
                $binfile = $localfile;
            }
            if(! -f $localfile) {
                print "runner $i: $localfile was not found\n";
                $gamebad = 1;
                next;
            }
            open(my $fh, '<', $localfile) or die "failed to open file";
            my $file_content = do { local $/; <$fh>};
            close($fh);
            my $calculated = sha1_hex($file_content);
            my $expected = $redumpgames{$game}{$file}{sha1};
            if($expected ne $calculated) {
                print "runner $i: $localfile does not match redump\n";
                print "runner $i: expected ". $expected . " got $calculated\n";
                $gamebad = 1;
            }
        }
        if($gamebad) {
            $rc = 1;
            next;
        }

        # unpack and repack
        my @dumpsxiso = ('dumpsxiso', '-x', 'dump/'.$game, '-s', "dump/$game.xml", $binfile);

        # verify repack against redump
    }
    print "runner $i: " . (($rc == 0) ? "success\n" : "failure\n");
    exit $rc;
}
!scalar(@games) or die "did not pass out all games, did you pass a bad value for --jobs?";
for(my $i = 0; $i < $numchildren; $i++) {
    waitpid(-1, 0) > 0 or die "waitpid failed";
    $? == 0 or die "a runner failed!";
}
print "success for everyone\n";
