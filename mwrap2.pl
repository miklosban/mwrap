#!/usr/bin/perl 
#  
# NAME 
#       mwrap2 - key event wrapper with mplayer or vlc
# 
# SYNOPSIS
#       mwrap2.pl video_file [keys file,parameters]
# 
# DESCRIPTION
#       each ascii key-press event will logged with their time position into
#       the video_file.events.csv
# 
#       You can interrupt the recording with the 'end' key, so do not use it for any events.
#       If the video_file.events.csv already exists, you can continue the event recording 
#       from the last recorded time position.
#       You can specify the key events like in this example:
#       
#       j jumping
#       s sleeping
#       f fighting
# 
#       The default place of the predefined keys is in the keys.txt, but you can specify any 
#       file name in the second argument.
# 
#       If you append press SHIFT+key character you can measure duration from 
#       last key event, e.g:
#       s sleeping
#       S sleeping-end
# 
#       You can use all the mplayer/vlc control keys in the video player window.
#       You can record the key press events in the parent window.
# 
#       Fn1-12 set the observed object id with number 1-12.
#       this ids will append to next event row.
#
#       PageDown seek back to start point of the current object;
#       PageUp and FN1-12 seek back to the start point of the LAST given object id;
#  
# DEVELOPMENT
#       Join to development on GitHub.
#       
# 
# KNOWN BUGS
#       The mplayer pauses sometimes after a key press. Its happening before 
#       the KID_TO_READ cicle
#       The mplayer seems to have problem playing video if the fps lass then 10. It can play
#       however the interface behave as a heavy load system.
#       VLC not tested yet
# 
# AUTHOR
#       Written by Bán Miklós (banm@vocs.unideb.hu) at 2011.04.25.
# 
# COPYRIGHT
#       I don't know yet. Write an email if you have any question.
# 
my $mwrap_version = 'Thu May  8 15:37:39 CEST 2015';

use strict;
use warnings;
use Term::ReadKey;
use File::Basename;
use File::Copy;
use IO::Handle;
use POSIX qw{strftime};
use Getopt::Long;
use Config;
use File::Temp qw(tempdir);
use File::Spec::Functions qw(catfile);
use Cwd();

# ---------------------------------------------------------------------------------------
# Default main variables
# Set some of these variables as you need in
# ~/.mwrap.conf or project_dir/mwrap.conf
our $short_seek = 10;                                           # left, right arrow seek
our $long_seek = 120;                                           # up, down arrow seek
our $vpa = "VLC"; # default video player application
our $FIFO = 'fifo';
our ($c,$video_player,$socket);
our $controlkey=0;
our $tempdir = tempdir( CLEANUP => 1 );
our $mwrap_log = catfile($tempdir, 'mwrap.log');
my $mplayer_params = '-vf scale=960:540 -ao null';
my $mplayer_path = 'mplayer';
my $vlc_params = '';
my $vlc_host_port = '127.0.0.1:1234';
my $vlc_path = 'vlc';
my $bin_path = '/usr/local/bin/' if $Config{osname} eq 'linux';    # default video player for Linux
$vpa = 'MPLAYER' if $Config{osname} eq 'linux'; # default video player for Linux
my $fs = ';';                                                   # csv field separator
my $conf = '';  # config file path
my $args = '';              # video player args like (mplayer -vo x11) - overwrite with command line argument 
my $keydef = 'keys.txt';    # overwrite with command line argument
my $version='';             # overwrite with command line argument
my $name = $0;  #
my ($char, $key,$value,$answer,%hash,$project_dir,$pid,$time,$ftime,$duration, @f,$hexchar,$rehexchar,$rehexcharT,$utf8,$switch,$get_time);
my $player = 0;
my $filename = '';
my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
my $rand_name = join("", @chars[ map { rand @chars } ( 1 .. 8 ) ]);
my $events_csv = "$rand_name.csv";
my $mcode_pl = $bin_path.'mcode.pl';
my $seek_to_object = 0;
my $seek_to_pos = 0;
my $mark_at = '';
my $ll = '';
my $pos = '';
my $seek = '';
my $pwd = getcwd();
my $red = ''; 
my $green = '';
my $yellow = '';
my $blue = '';
my $lblue = '';
my $gray = '';
my $NC = '';
my $bold = '';
my $console = '';
$console = 'color' if $Config{osname} eq 'linux';
if ($console eq 'color') {
    $red = "\033[0;31m";
    $green = "\033[0;32m";
    $yellow = "\033[1;33m";
    $blue = "\033[0;34m";
    $lblue = "\033[1;34m";
    $gray = "\033[1;30m";
    $NC = "\033[0m";
    $bold = "\e[1m";
}
# ---------------------------------------------------------------------------------------
# Command line options
GetOptions ('k:s' => \$keydef, 'v' => \$version,'<>' => \&args);
sub args {
    my ($p1) = @_;
    if ($filename eq '') {
        $filename = $p1;
        $project_dir = "$filename.dir";
    } else { $keydef = $p1; }
}
# ---------------------------------------------------------------------------------------
# Version information
if ($version) {
    print "$mwrap_version\n";
    exit 1;
}
# ---------------------------------------------------------------------------------------
# Help text
if ($filename eq '') {
    print "A video file name nedeed!\n";
    # read help text
    open(FILE, $name) or die("Unable to open myself:$name");
    my $text = '';
    while (<FILE>) {
        if ($_ =~ /^#!/) {
            next;
        }
        elsif ($_ =~ /^#/) {
            $text .= $';
        } else {
            last;
        }
    }
    close(FILE);
    $text.=" VERSION INFO\n       last modification: $mwrap_version\n\n";
    my $pager = $ENV{PAGER} || 'less';
    open(my $less, '|-', $pager, '-e') || die "Cannot pipe to $pager: $!";
    print $less $text;
    close($less);
    exit 1;
} 
# ---------------------------------------------------------------------------------------
# Set mwrap parameters
if (-e catfile($pwd,'mwrap.conf')) {
    $conf = catfile($pwd, 'mwrap.conf');
} else {
    my $hconf = catfile($ENV{'HOME'}, '.mwrap.conf');
    if (-e $hconf) {
        $conf = $hconf;
    } else {
        `echo "mplayer_params = $mplayer_params\nfs = ;\n" > mwrap.conf`;
        printf "There was no mwrap.conf defined. It has been created here with default values. You can edit it as you need.\n";
    }
}
my %User_Preferences = ();
if (-e $conf) {
    open(CONFIG, $conf) or warn("Unable to open: $conf");
    printf "Parameter settings read from $conf:\n";
    while (<CONFIG>) {
        chomp;                  # no newline
        s/#.*//;                # no comments
        s/^\s+//;               # no leading white
        s/\s+$//;               # no trailing white
        next unless length;     # anything left?
        my ($var, $value) = split(/\s*=\s*/, $_, 2);
        next unless $value ne '';
        print $lblue;
        printf "$var: $value\n";
        print $NC;
        $User_Preferences{$var} = $value;
    }
}
if(exists $User_Preferences{'bin_path'}) {
    $bin_path =  $User_Preferences{'bin_path'};
}
if (exists $User_Preferences{'fs'}) {
    $fs = $User_Preferences{'fs'};
}
if(exists $User_Preferences{'mplayer_params'}) {
    $mplayer_params = $User_Preferences{'mplayer_params'};
}
if(exists $User_Preferences{'mplayer_path'}) {
    $mplayer_path =  $User_Preferences{'mplayer_path'};
}
if(exists $User_Preferences{'short_seek'}) {
    $short_seek =  $User_Preferences{'short_seek'};
}
if(exists $User_Preferences{'long_seek'}) {
    $long_seek =  $User_Preferences{'long_seek'};
}
if(exists $User_Preferences{'mwrap_log'}) {
    $mwrap_log =  $User_Preferences{'mwrap_log'};
}
if(exists $User_Preferences{'vlc_params'}) {
    $vlc_params =  $User_Preferences{'vlc_params'};
}
if(exists $User_Preferences{'vlc_host_port'}) {
    $vlc_host_port =  $User_Preferences{'vlc_host_port'};
}
if(exists $User_Preferences{'vlc_path'}) {
    $vlc_path =  $User_Preferences{'vlc_path'};
}
if(exists $User_Preferences{'vpa'}) {
    $vpa =  uc($User_Preferences{'vpa'}));
}
# Control commands
if ($vpa eq "MPLAYER") {
    $get_time = "get_time";
    $video_player = $mplayer_path.' '.$mplayer_params;
} else {
    $get_time = "get_time_pos";
    $video_player = $vlc_path.' '.$vlc_params;
}

# ---------------------------------------------------------------------------------------
# keys
if (-e $keydef) {
    open(KEYF, '<', $keydef);
    print "-------------------------------------\n";
    print "Currently defined keys:\n$lblue";
    while(<KEYF>) {
        printf "\t";
        printf;
        ($key,$value) = split / /;
        chop $value;
        $hash{ $key } = $value;
    }
    print "$NC-------------------------------------\n";
    close (KEYF);
} else {
    print $red,"No keys defined!$NC\nYou can specify key events in the 'keys.txt', like in the following example:\nj jumping\ns sleeping\nf fighting\n\n";
    # röptében kulcs definiálás!!!
}
# ---------------------------------------------------------------------------------------
# mwrap starting
# Check the video file exists
if (-e $filename) {
    # Check the project directory exists (the video had prcessed)
    # If not ...
    if ( ! -d $project_dir ) {
        mkdir "$project_dir" or die $!;
        
        print $yellow,'You need a unique id for this project',$NC,"\n";
        $answer = <STDIN>;
        chop $answer;
        $events_csv = "$project_dir/$answer.csv";
        open(CSV, '>>', "$events_csv") or die $!;
        CSV->autoflush(1);
        print CSV "#Video File Name: $filename\n";
        print CSV "#Project ID: $answer\n";
        print CSV "#Event codes:\n";
        if (-e $keydef) {
            open(KEYF, '<', $keydef);
            while (<KEYF>) {
                print CSV "#$_";
            }
            close (KEYF);
        }
        print CSV "#Field separator: $fs\n";
        print CSV "#MWrap version: $mwrap_version\n";
        printf CSV '#id%1$sdescription%1$skey%1$stime%1$sduration%1$sobject id%2$s',"$fs","\n";
    } else {
        # if yes
        print "$red$project_dir$bold exists!\n",$NC,$yellow,"Do you want to continue of an existing project? (y,n)\n$gray";
        $answer = <STDIN>;
        print $NC;
        chop $answer;
        # start a new session of the project
        if ($answer ne 'y') {
            do  {
                print $yellow,"You need a unique id for this project$NC\n";
                $answer = <STDIN>;
                chop $answer;
                $events_csv = "$project_dir/$answer.csv";
            } while (-e $events_csv);
            
            open(CSV, '>>', "$events_csv") or die $!;
            CSV->autoflush(1);

            print CSV "#Video File Name: $filename\n";
            print CSV "#Project ID: $answer\n";
            print CSV "#Event codes:\n";
            if (-e $keydef) {
                open(KEYF, '<', $keydef);
                while (<KEYF>) {
                    print CSV "#$_";
                }
                close (KEYF);
            }
            print CSV "#Field separator: $fs\n";
            print CSV "#MWrap version: $mwrap_version\n";
            printf CSV '#id%1$sdescription%1$skey%1$stime%1$sduration%1$sobject id%2$s',"$fs","\n";
        } else {
            # continue a previously interrupted session
            use File::Find;
            my $dir = "$project_dir";
            find( sub {push @f,basename("$File::Find::name$/") if (/\.csv$/)},$dir); 
            print $yellow,"Type the number of your choice.$NC\n";
            my $i = 0;
            chop(@f);
            foreach (@f){
                $i++;
                printf "[$green$i$NC]\t$_\n";
            }
            use Term::ReadKey;
            ReadMode 3;
            if (defined($answer = ReadKey(0))) {
                $hexchar = unpack "H*",$answer;
                #print $hexchar;
                if ($answer !~ /^\d+$/) {
                    exit 1;
                } elsif ($answer>@f) {
                    exit 1;
                }
            }
            ReadMode 0;

            $answer = $f[$answer-1];
            $answer =~ s/\.csv$//; 
            print $gray,$answer.".csv",$NC,"\n";
            $events_csv = "$project_dir/$answer.csv";
            
            print $yellow,"Do you want to start from the last event? (y,n)\n$gray";
            $answer = <STDIN>;
            print $NC;
            chop $answer;
            if ($answer eq 'y') {
                # seek to last event's position
                open(CSV, '<', "$events_csv") or die $!;
                my @ll = <CSV>;
                close(CSV);
                while(@ll) {
                    $ll = pop @ll;
                    if ($ll =~ /^#/) { next; }
                    else { 
                        #print "\nLast line of `$answer.csv`:\n".$ll;
                        last;
                    }
                }
                # create backup file?
                copy("$events_csv", "$project_dir/.".basename($events_csv).".csv~1") or die "csv cannot be backuped.";
                open(CSV, '>>', "$events_csv") or die $!;
                CSV->autoflush(1);
                print CSV "#Restarted recording from the last position\n";
                my @bl = split /$fs/,$ll;
                $seek = $bl[3];
                $pos = $bl[0];
                if(defined $bl[5]) {
                    $player = $bl[5];
                } else {
                    $player = ''; #0
                }
                chomp $player;
                #if ( $player eq '') { $player =}
                if ($pos =~ /^\d+$/) {
                    my $ftime = strftime("\%H:\%M:\%S", gmtime($seek));
                    print "\nSeeking to $ftime position.";
                } else {
                    print "\nStart from 00:00:00 position.";
                    $seek = 0;
                    $ll = '';
                    $pos = '';
                    $player = '';
                }
            } else {
                open(CSV, '<', "$events_csv") or die $!;
                my @ll = <CSV>;
                close(CSV);
                while(@ll) {
                    $ll = pop @ll;
                    if ($ll =~ /^#/) { next; }
                    else { 
                        #print "\nLast line of `$answer.csv`:\n".$ll;
                        last;
                    }
                }
                my @bl = split /$fs/,$ll;
                $pos = $bl[0];

                copy("$events_csv", "$project_dir/.".basename($events_csv).".csv~1") or die "csv cannot be backuped.";
                open(CSV, '>>', "$events_csv") or die $!;
                CSV->autoflush(1);
                print CSV "#Restarted recording from the first position\n";
            }
        }
    }
} else {
    print $red,"Videofile: '$filename' does not exists.\n$NC";
    exit 1;
}

print "\n-------------------------------------\nYou can control the video player with the usual control keys (in the video player window!).\n-------------------------------------\n";

# last line from the csv;
if ($ll =~ /\d+.+/) {
    #printf "%4.d %-15s%s %.2f\n",split /$fs/,$ll;
    my @v = split /$fs/,$ll;
    printf "%4.d %-15s%s %s\n",$v[0],$v[1],$v[2],strftime("\%H:\%M:\%S", gmtime($v[3]));
}

if ($vpa eq 'MPLAYER') {
    # create fifo
    unless (-p $FIFO) {
        unlink $FIFO;
        require POSIX;
        POSIX::mkfifo($FIFO, 0700) or die "Can't make fifo: $FIFO - $!";
    }
    # pipe
    $pid = open(KID_TO_READ, "-|");
    if ($pid) {
        # parent process
        # reading messages from the child process
        #chomp(my $line = <PARENT>);
        #if ($line ne '') {
        #    print "$line\n";
        #}
        print "-------------------------------------$green\nEvent recording started. Press 'end' to finish!\n$NC";

        if ($pos =~ /\d+/) {
            $c = $pos+1;
        } else {
            $c = 1;
        }
        #mplayer specific start commands
        open(FIFO,"> $FIFO") || die "Cannot open $! \n";
        print FIFO "key_down_event 111\n";
        print FIFO "osd_show_text '$answer'\n";
        print FIFO "pause\n";
        close FIFO;

        my $interval = 0; 
        ReadMode 3;
        my $ret;
        while (defined($char = ReadKey(0))) {
            $ret = process($char);
            if ($ret ne '') {
                next if $ret eq 'next';
                last if $ret eq 'last';
            }
            # ha már nem él a pid kilépünk a leütés olvasásból (nem tudom lehet-e ilyen eset valaha)
            shift->(@_), last unless $pid;
        }
        # Ha vége a leütés olvasásnak
        ReadMode 0;
        if (<KID_TO_READ>) {
            kill 'TERM',$pid;
            #`kill -9 $pid&`;
            #close(KID_TO_READ) || print "mplayer exited $?";
        }
        unlink $FIFO;
    } elsif ($pid == 0) {
        # child process
        close STDERR;
        close STDIN;
        if ($seek ne '0' and $seek ne '') {
            $seek = "-ss $seek";
        } else {
            $seek = "";
        }
        my $exec = ''.$video_player.' '.$args.' '.$seek.' -quiet -slave -idle -input file='.$FIFO.' -key-fifo-size 2 \''.$filename.'\' -geometry 0%:0% '."2>$mwrap_log";
        my $wl = ";echo '$exec' >> $mwrap_log";
        exec($exec."$wl;while true; do cat fifo;echo '*$red Mplayer has stopped unexpectedly.$NC Press END or ^C to quit and see mwrap.log for information!';sleep 1;done");
        exit(0);
    }
} else {
    #start vlc remote control mode 
    if ($seek ne '0' and $seek ne '') {
        $seek = "--start-time=$seek";
    } else {
        $seek = "";
    }
    if ($pos =~ /\d+/) {
        $c = $pos+1;
    } else {
        $c = 1;
    }

    if ( $Config{osname} eq 'linux' ) {
        system ("$video_player '$filename' $seek --intf rc --rc-host $vlc_host_port 2>$mwrap_log &");
    } else {
        system ("$video_player '$filename' $seek --intf rc --rc-host $vlc_host_port 2>$mwrap_log");
    }
    sleep 2;
    use IO::Socket;
    my $host='127.0.0.1';
    my $port='1234';
    #connect to vlc
    $socket = new IO::Socket::INET (
                                  PeerAddr  => $host ,
                                  PeerPort  => $port ,
                                  Proto => 'tcp', 
                                  Reuse => 1 )
    or die "Couldn't connect to VLC player\n";

    my $line;
    get_time();
    $line = <$socket>; # header line
    $line = <$socket>; # header line
    $line = <$socket>; # first answer: 0
    ReadMode 3;
    my $ret;
    while (1)
    {  
        if (defined($char = ReadKey(0))) {
            $ret = process($char);
            if ($ret) {
                next if $ret eq 'next';
                last if $ret eq 'last';
            }
        }
    }
    ReadMode 0;
    $socket->close();
} 


#
#
#
#
#

#waitpid($pid, 0);
ReadMode 0;
close(CSV) || warn "csv write error: $?";

#print "\nmwrap event recording done.\n";

# csv processing
print "Press Enter to Skip CSV processing (You can do it later)\n\n";
use Term::ReadKey;
ReadMode 3;
if (defined($char = ReadKey(0))) {
    ReadMode 0;
    $hexchar = unpack "H*",$char;
    if ($hexchar eq '0a') {
        exit 0;
    }
}
ReadMode 0;

print "performing: $mcode_pl -f '$filename' -c '$events_csv'\n";
`$mcode_pl -f '$filename' -c '$events_csv' 1>&2`;

#`mplayer $ARGV[0] -ss $time -frames 1 -vo jpeg -ao null 2>/dev/null;mv 00000001.jpg $time.jpg`;
#cat P1070099.MOV.events.csv | awk -F \; 'function round(A){return int(A+0.5)}{printf "%.2d:%.2d:%2.2f",round($4/3600),round($4/60),$4%60}{printf ",%.2d:%.2d:%2.2f\n",round($4/3600),round($4/60),$4%60+1}{print $2}'>subt.su
#

## SUBRUTINES ************************************************************

sub ctr_seek {
    my $pos = shift;
    my $rel = shift;
    my $osd = shift;
    #my($inVal, $inValTwo, $inArray, $inArrayTwo) = @_;
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        if ($osd) {
            print FIFO "osd_show_text 'Seek to time position: $pos'\n";
        }
        if ($rel eq '') {
            # seek to absolute pos
            print FIFO "seek $pos 2\n";
        } else {
            # seek to relative pos
            print FIFO "seek $rel$pos\n";
        }
        close FIFO;
    } else {
        if ($rel eq '') {
            print $socket "seek $pos\n";
        } else {
            print $socket "seek $rel$pos\n";
        }
    }
}
sub ctr_pause {
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        print FIFO "pause\n";
        close FIFO;
    } else {
        print $socket "pause\n";
    }
}
sub ctr_play {
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        print FIFO "play\n";
        close FIFO;
    } else {
        print $socket "play\n";
    }
}
sub get_time {
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        print FIFO "get_time_pos\n";
        close FIFO;
    } else {
        print $socket "get_time\n";
    }
}
sub ctr_stop {
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        print FIFO "stop\n";
        close FIFO;
    } else {
        print $socket "stop\n";
        print $socket "shutdown\n";
    }
}
sub ctr_osd {
    my $txt = shift;
    if ($vpa eq 'MPLAYER') {
        open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        print FIFO "osd_show_text '$txt'\n";
        close FIFO;
    }
}
sub process {
    $char = shift;
    $hexchar = unpack "H*",$char;
    #printf("Decimal: %d\tHex: %x\n", ord($char), ord($char));
    if ($hexchar eq '7e') {
        # long control keys END
        $controlkey=0;
        return "next";
    } elsif ($hexchar eq '1b') {
        # long control keys 2. character
        $controlkey=1;
        return "next";
    } elsif ($hexchar eq '5b' or $hexchar eq '4f') {
        # long control keys 2. character
        $controlkey=2;
        return "next";
    } elsif ($hexchar eq 'c3' or $hexchar eq 'c5') {
        #utf8 characters: öüóőúéáűí...
        if ($hexchar eq 'c3') { $utf8 = 'c3' }
        elsif ($hexchar eq 'c5') { $utf8 = 'c5' }
        $controlkey=4;
        return "next";
    } elsif ($hexchar eq '2f') {
        # /
        $seek_to_pos = '#';
        print $green,"Search for time position.$NC Type time like this:$green $bold 0:20:10:$NC\n";
        ctr_pause();
        return "next";
    }
    # FN keys 5-12
    if ($controlkey == 2 and ($hexchar eq '31' or $hexchar eq '32')) {
        $controlkey = 3;
        return "next";
    }
    #control key 3. code
    if ($controlkey==3) {
        if (hex($hexchar)==48 or hex($hexchar)==49 or hex($hexchar)==51 or hex($hexchar)==52 or hex($hexchar)==53 or hex($hexchar)==55 or hex($hexchar)==56 or hex($hexchar)==57) {
            #FN 5-8, 9-12 
            if (hex($hexchar) == 53) { $player = 5 }
            elsif (hex($hexchar) == 55)	{ $player = 6 }
            elsif (hex($hexchar) == 56)	{ $player = 7 }
            elsif (hex($hexchar) == 57)	{ $player = 8 }
            elsif (hex($hexchar) == 48)	{ $player = 9 }
            elsif (hex($hexchar) == 49)	{ $player = 10 }
            elsif (hex($hexchar) == 51)	{ $player = 11 }
            elsif (hex($hexchar) == 52)	{ $player = 12 }
            else { $player = '' }
            $mark_at = $player;
            $controlkey=0;
        } 
    }
    #control key 2. code
    if ($controlkey==2) {
        if ($hexchar eq '41') {
            printf "Seek forward $long_seek.\n";
            ctr_seek($long_seek,'+');
            $controlkey=0;
            return "next";
        }
        elsif ($hexchar eq '42') {
            printf "Seek backward $long_seek sec.\n";
            ctr_seek("$long_seek","-");
            $controlkey=0;
            return "next";
        }
        elsif ($hexchar eq '43') {
            printf "Seek forward $short_seek sec.\n";
            ctr_seek($short_seek,"+");
            $controlkey=0;
            return "next";
        }
        elsif ($hexchar eq '44') {
            printf "Seek backward $short_seek sec.\n";
            ctr_seek("$short_seek","-");
            $controlkey=0;
            return "next";
        }
        elsif ($hexchar eq '35') {
            # PageUp - Seek to given Object Id start
            if ($player ne '') { $seek_to_object = "#$player"; }
            else { $seek_to_object = '#'; }
            $controlkey=0;
            return "next";
        }
        elsif ($hexchar eq '36') {
            # PageDown - Seek the last Object Id start
            open(CSVa, '<', $events_csv) or die $!;
            my @ll = <CSVa>;
            close CSVa;
            $pos = "";
            $seek= "";
            my @bl;
            while (@ll) {
                my $e = pop @ll;
                if ($e =~ /^#Mark: (.+)/) {
                    @bl =  split /;/,$1;
                    chomp $bl[5];
                    $seek = $bl[3];
                    $pos = $bl[0];
                    last;
                }
            }
            if ($pos =~ /^\d+?$/) {
                printf "%sLast object [%d] start found after position %d. at %s%s\n",$green,$bl[5],$pos,$seek,$NC;
                ctr_seek($seek,"");
                ctr_osd("Seek to time position: $seek");
            } else {
                print $red,"No object mark found.$NC\n";
            }
            $controlkey=0;
            return "next";
        } elsif (hex($hexchar)>=80 and hex($hexchar)<=83) {
            #FN 1-4 
            $player = hex($hexchar)-79;
            $mark_at = $player;
            $controlkey=0;
        } elsif ($hexchar eq '46') {
            ctr_stop();
            printf "-------------------------------------\nEvent recording terminated.\n";
            return "last";
        } else {
            #unhandled control key
            printf "Unhandled control key:\n";
            printf("Decimal: %d\tHex: %x\n", ord($char), ord($char));
            $controlkey=0;
            return "next";
        }
        #end control key 2
    } elsif ($controlkey==4) {
        $char=pack "H*",$utf8.$hexchar;
        $controlkey=0;
        $utf8='';
    } # END controlkey check
    if ($seek_to_pos ne '0') {
        $seek_to_pos .= $char;
        if ($seek_to_pos =~ /#(\d+):(\d+):(\d+):/) {
            #printf "%sFound object [%d] start at: %s%s\n",$green,$bl[5],$seek,$NC;
            #$ftime = ($+{'min'} * 60) + $+{'sec'} + ($+{'frac'}/(10**length(+$+{'frac'}))); 
            my $seconds=eval($1*60*60+$2*60+$3);
            ctr_seek($seconds,"");
            ctr_osd("Seek to time position: $seconds");
            $controlkey=0;
            $seek_to_pos = 0;
            return "next";
        } else {
            ctr_osd("Position: $seek_to_pos");
            return "next";
        }
    }
    # Seek to given object
    if ($seek_to_object ne '0') {
        if ($seek_to_object =~ /#(\d+)/) {
            $player = $1; # visszaállítjuk a playert
        } else {
            $player = '';
        }
        $seek_to_object = 0;
        open(CSVa, '<', $events_csv) or die $!;
        my @ll = <CSVa>;
        close CSVa;
        $pos = "";
        $seek= "";
        my @bl;
        while (@ll) {
            my $e = pop @ll;
            if ($e =~ /^#Mark: (.+)/) {
                @bl =  split /;/,$1;
                chomp $bl[5];
                if ($bl[5] eq $mark_at) {
                    $seek = $bl[3];
                    $pos = $bl[0];
                    last;
                }
            }
        }
        if ($pos =~ /^\d+?$/) {
            printf "%sFound object [%d] start at: %s%s\n",$green,$bl[5],$seek,$NC;
            ctr_seek($seek,"");
            ctr_osd("Seek to time position: $seek");
        } else {
            print $red,"No marked object found with reference id: $mark_at$NC\n";
        }
        $mark_at = ''; 
        return "next";
    }
    #printf(" Decimal: %d\tHex: %x\n", ord($char), ord($char));
    if ($hexchar eq '7f') {
        # backspace - delete the last event
        open(CSVa, '<', "$events_csv") or die $!;
        my @ll = <CSVa>;
        close CSVa;
        my $l = '';
        $l = pop(@ll);
        if ($l =~ /^#/) {
            print "The last event already deleted!\n"; # or this is the first
            return "next";
        } else {
            open (CSVa, "+<", $events_csv) or die "can't update $events_csv: $!";
            my $addr;
            while (<CSVa>) {
                $addr = tell(CSVa) unless eof(CSVa);
            }
            #truncate the last line 
            truncate(CSVa, $addr) or die "can't truncate $events_csv: $!";
            close CSVa;
            #write back the list line
            open(CSVa, '>>', "$events_csv") or die $!;
            chomp $l;
            print CSVa "#$l\n";
            close CSVa;
            # message
            ctr_osd("Last event deleted");
            print "Last event deleted!\n";
            get_time();
        }
    } elsif ($hexchar eq '0a') {
        #enter
        get_time();
        $hexchar='20';
        $char = ' ';
    } elsif ($hexchar eq '20') {
        # space to pause if control enabled
        ctr_pause();
        printf "pause\n";
        return "next";
    } else {
        # ANY else character 
        get_time();
    }
    $rehexchar = chr(hex($hexchar)+hex(20));
    $rehexcharT = chr(hex($hexchar));

    my $ret;
    # answer processing
    if($vpa eq 'MPLAYER') {
        while (<KID_TO_READ>) {
            if (/^ANS_TIME_POSITION=(.+)/) {
                $ret = writeout($1);
                next if $ret eq "next";
                last if $ret eq "last";
            }
            elsif (/^\*(.+)/) {
                #mplayer error messages
                #print $_;
                print $1."\n";
                last;
            } #else {
            #  print $_."\n";
            #    last;
            #}
        }
        return;
    } else {
        my $line;
        if (defined($line = <$socket>)) {
            if($line =~ /> (\d+)/) {
                writeout($1);
            } else {
                print "Something is wrong: $line.\n";
            }
        } else {
            print "Socket closed?\n";
        }
        return;
    }
    return 1;
}
sub writeout {
    $time = shift;
    if ($hexchar eq '7f') {
        return "last";
    }
    $ftime = strftime("\%H:\%M:\%S", gmtime($time));
    if ($mark_at ne '') {
        printf CSV '#Mark: %d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c-1,'-','-',$time,0,$fs,"\n",$mark_at;
        printf "object id: $mark_at\n";
        $mark_at = "";
        return "last";
    }
    if (exists  $hash{ $char }) {
        #kis betűs leütés aminek van cimkéje
        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$hash{$char},$char,$time,0,$fs,"\n",$player;
        printf '%4.d [%8$s%6$s%9$s] %-15s%8$s%s%9$s %s%s0%7$s',$c,$hash{$char},$char,$ftime,$fs,$player,"\n",$bold,$NC;
        #} elsif (exists $hash{ $rehexchar }) {
    } elsif ((hex($hexchar)>64 and hex($hexchar)<91) or length($hexchar)==4) {
        # letters A-Z
        # UPPERCASE LETTERS
        # DURATION mesuring
        # read the csv file for searching the lowercase letter pair last position
        open(CSVa, '<', "$events_csv") or die "$events_csv: $!\nEXIT\n";
        my @ll = <CSVa>;
        close CSVa;
        $duration = 0;
        my @bl;
        while(@ll) {
            @bl = split /$fs/,pop(@ll);
            #skip the comments
            next if $bl[0] =~ /^#/;
   
            # skip lines if we moved back
            my $pl = $bl[5];
            chop $pl;
            if ($pl eq '') {$pl = '';}

            if ($bl[3]>$time) { next; }
            $value = $bl[2];
            if ($value && $value =~ /^$rehexchar$/ && $player eq $pl) {
                 $duration = $time-$bl[3];
                 last;
            }
        }
        if (exists $hash{ $rehexchar }) {
            #nagy betűs leütés aminek van cimkéje
            printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$hash{$rehexchar}."-end",$rehexcharT,$time,$duration,$fs,"\n",$player;
            printf '%4.d [%8$s%6$s%9$s] %-15s%8$s%s%9$s %s %.2f%7$s',$c,$hash{$rehexchar}."-end",$rehexcharT,$ftime,$duration,$player,"\n",$bold,$NC;
        } else {
            #nagy betűs leütés aminek nincs cimkéje
            printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$rehexchar."-end",$rehexcharT,$time,$duration,$fs,"\n",$player;
            printf '%4.d [%8$s%6$s%9$s] %-15s%8$s%s%9$s %s %.2f%7$s',$c,$rehexchar."-end",$rehexcharT,$ftime,$duration,$player,"\n",$bold,$NC;
        }
        #} elsif (hex($hexchar)>48 and hex($hexchar)<58) {
                #  $player = $char;
                #    $c = $c-1;
                #    # numbers 1-9
                #    printf "object id: $player\n";
    } else {
        #kis betűs leütés aminek nincs cimkéje
        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,'undefined',$char,$time,0,$fs,"\n",$player;
        printf '%4.d [%8$s%6$s%9$s] %-15s%8$s%s%9$s %s%s0%7$s',$c,'undefined',$char,$ftime,$fs,$player,"\n",$bold,$NC;
    }
    $c = $c+1;
    return "last";
}
exit 0;
