#!/usr/bin/perl
use strict; use warnings;
use Getopt::Long qw(GetOptions);
use XML::Parser;
Getopt::Long::Configure qw(gnu_getopt);

my $runners = 1;
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
my $parser = XML::Parser->new(Style => 'Tree');
my $redump = $parser->parsefile('Sony - PlayStation - Datfile (10701) (2023-03-22 01-15-22).dat');
use Data::Dumper qw(Dumper);

sub GetElement {
    my ($values) = @_;
    scalar(@{$values}) or return undef;
    my @newvalues = @$values;
    my $tag = $newvalues[0];
    if($tag =~ /^0$/) {
        my $value = $newvalues[1];
        splice(@newvalues, 0, 2);
        @{$values} = @newvalues;
        return {
            tag => 0,
            value => $value
        };
    }
    my @nextvalues = @{$newvalues[1]};
    my $attr = $newvalues[1][0];
    splice(@nextvalues, 0, 1);
    splice(@newvalues, 0, 2);
    @{$values} = @newvalues;
    return {
        tag => $tag,
        attr => $attr,
        values => \@nextvalues
    };
};

my %redumpgames;
my @rcopy = @{$redump};
my $df = GetElement(\@rcopy);
$df->{tag} eq 'datafile' or die "should be a datafile";
while(my $elm = GetElement($df->{values})) {
    if($elm->{tag} eq 'game') {
        die if (exists $redumpgames{$elm->{attr}{name}});
        my %game;
        while(my $gelm = GetElement($elm->{values})) {
            if($gelm->{tag} eq 'rom') {
                $game{$gelm->{attr}{name}} = $gelm->{attr};
            }
        }
        $redumpgames{$elm->{attr}{name}} = \%game;
    }
}
print Dumper(\%redumpgames);
die;


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
    my @current_games = splice(@games, -1, $num_games);
    my $forkres = fork() // die "failed to fork";
    if($forkres != 0) {
        $numchildren++;
        next;
    }
    my $rc = 0;
    foreach my $game (@current_games) {
        # sanity check, verify against redump before unpacking and repacking

        # unpack and repack

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
