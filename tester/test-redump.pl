#!/usr/bin/perl
use strict; use warnings;
use Getopt::Long qw(GetOptions);
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
