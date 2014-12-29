#!/usr/bin/perl 
#  
# NAME 
#       mwrap - key event wrapper for mplayer
# 
# SYNOPSIS
#       mwrap.pl video_file [keys file]
# 
# DESCRIPTION
# 
#       each ascii key-press event will logged with their time position into
#       the video_file.events.csv
# 
#       You can interrupt the recording with the 'esc' key, so do not use it for any events.
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
#       You can use all the mplayer control keys in the mplayer window and record the key 
#       press events in the parent window.
#  
# DEVELOPMENT
# 
#       
# 
# KNOWN BUGS
# 
#       The mplayer pauses sometimes after a key press. Its happening before 
#       the KID_TO_READ cicle
# 
# AUTHOR
#  
#       Written by Bán Miklós (banm@vocs.unideb.hu) at 2011.04.25.
# 
# COPYRIGHT
# 
#       I don't know yet. Write an email if you have any question.
#
#
# DEVELOPMENT INFO
#       last modication: Mon Dec 29 16:17:30 CET 2014
#
#

use strict;
use warnings;
use Term::ReadKey;
use File::Basename;
use IO::Handle;


# 
# Set these variables as you need
# ---------------------------------------------------------------------------------------
# default parameters; Define it in user level in the ~/.mwrap.conf file
my $mplayer_params = '-vf scale=960:540 -cache 8192 -forceidx -mc 0 -nobps -ni -ao null';
my $fs = ';';   # csv field separator
my $mplayer_path = 'mplayer';
my $bin_path = '/usr/local/bin/';
# ---------------------------------------------------------------------------------------
my $conf = $ENV{"HOME"} . '/.mwrap.conf';
my %User_Preferences = ();
# ---------------------------------------------------------------------------------------

if (-e $conf) {
    open(CONFIG, $conf) or warn("Unable to open: $conf");
    while (<CONFIG>) {
        chomp;                  # no newline
        s/#.*//;                # no comments
        s/^\s+//;               # no leading white
        s/\s+$//;               # no trailing white
        next unless length;     # anything left?
        my ($var, $value) = split(/\s*=\s*/, $_, 2);
        $User_Preferences{$var} = $value;
    }
}
if (exists $User_Preferences{'fs'}) {
    $fs = $User_Preferences{'fs'};
} elsif(exists $User_Preferences{'mplayer_params'}) {
    $mplayer_params = $User_Preferences{'mplayer_params'};
} elsif(exists $User_Preferences{'bin_path'}) {
    $bin_path =  $User_Preferences{'bin_path'};
} elsif(exists $User_Preferences{'mplayer_path'}) {
    $mplayer_path =  $User_Preferences{'mplayer_path'};
}

# Do not change these variables
my $mplayer = $mplayer_path.' '.$mplayer_params;
my $args = ''; # mplayer args like -vo x11
my $FIFO = 'fifo';
my $name = $0;
my ($char, $key, $value, @ll, $ll, @bl, $seek, $answer, $pos, $c, %hash, $keydef, $project_dir ,$filename, $pid, $time, $duration,@f,$hexchar,$rehexchar,$pause,$player);
my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
my $rand_name = join("", @chars[ map { rand @chars } ( 1 .. 8 ) ]);
my $events_csv = "$rand_name.csv";
my $mcode_pl = $bin_path.'mcode.pl';

#for bidirectional communication; we don't need it actually
#use Socket;
#use IO::Socket;
#use IO::Select;
#socketpair(CHILD, PARENT, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
#    or die "socketpair: $!";
#CHILD->autoflush(1);
#PARENT->autoflush(1);
#my $s = IO::Select->new();
#$s->add(\*CHILD);
#

if (@ARGV == 0) {
    print "A video file name nedeed!\n";

    open(FILE, $name) or die("Unable to open myself:$name");
    my $pager = $ENV{PAGER} || 'less';
    open(my $less, '|-', $pager, '-e') || die "Cannot pipe to $pager: $!";
    my $text = '';
    while (<FILE>) {
        if ($_ =~ /^#!/) {
            next;
        }
        elsif ($_ =~ /^# /) {
            $text .= $';
        } else {
            last;
        }
    }
    close(FILE);

    print $less $text;
    close($less);
    exit 1;
} else {
    $filename = shift(@ARGV);
    $project_dir = "$filename.dir";
} 
if (@ARGV == 1) {
    $keydef = shift(@ARGV);
    if (! -e $keydef) { print "$keydef file does not exists!\n"; }
} else {
    $keydef = 'keys.txt';
}
if (-e $keydef) {
    open(KEYF, '<', $keydef);
    print "Currently defined keys:\n";
    while(<KEYF>) {
        print;
        ($key,$value) = split / /;
        chop $value;
        $hash{ $key } = $value;
    }
    print "\n";
    close (KEYF);
} else {
    print "You can specify the key events in the 'keys.txt' like in the following example:\nj jumping\ns sleeping\nf fighting\n\n";
    # röptében kulcs definiálás!!!
}
if (-e $filename) {
    if ( ! -d $project_dir ) {
        mkdir "$project_dir" or die $!;

        print "You need a unique id for this project\n";
        $answer = <STDIN>;
        chop $answer;
        $events_csv = "$project_dir/$answer.csv";
        open(CSV, '>', "$events_csv") or die $!;
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
        printf CSV '#id%1$sdescription%1$skey%1$stime%1$sduration%1$sobject id%2$s',"$fs","\n";
    } else {
        print "$project_dir exists.\nDo you want to continue from the last event? (y,n)\n";
        $answer = <STDIN>;
        chop $answer;
        if ($answer ne 'y') {
            do  {
                print "You need a unique id for this project\n";
                $answer = <STDIN>;
                chop $answer;
                $events_csv = "$project_dir/$answer.csv";
            } while (-e $events_csv);
            
            open(CSV, '>', "$events_csv") or die $!;
            CSV->autoflush(1);

            print CSV "#Project ID: $answer\n";
            print CSV "#Event codes:\n";
            if (-e $keydef) {
                open(KEYF, '<', $keydef);
                while (<KEYF>) {
                    print CSV "#$_";
                }
                close (KEYF);
            }
            printf CSV '#id%1$sdescription%1$skey%1$stime%1$sduration%1$sobject id%2$s',"$fs","\n";
        } else {
            use File::Find;
            my $dir = "$project_dir";
            find( sub {push @f,basename("$File::Find::name$/") if (/\.csv$/)},$dir); 
            print "Which project?\n";
            my $i = 0;
            chop(@f);
            foreach (@f){
                $i++;
                print "$i $_\n";
            }
            $answer = <STDIN>;
            chop $answer;
            if ($answer>@f) {
                exit 1;
            }
            $answer = $f[$answer-1];
            $answer =~ s/\.csv$//; 
            $events_csv = "$project_dir/$answer.csv";
            #$ll = `tail -n 1 $events_csv`;
            open(CSV, '<', "$events_csv") or die $!;
            @ll = <CSV>;
            $ll = pop @ll;
            print $ll;
            close(CSV);
            open(CSV, '>>', "$events_csv") or die $!;
            CSV->autoflush(1);
            @bl = split /;/,$ll;
            $seek = $bl[3];
            $pos = $bl[0];
            if ($pos =~ /^\d+?$/) {
                chop $seek;
                print "Seeking to $seek\" position\n";
            } else {
                undef $seek;
                undef $ll;
                undef $pos;
            }
        }
    }
} else {
    print "$filename does not exists.\n";
    exit 1;
}

print "\nYou can control the mplayer with the usual keys.\nSome useful mplayer key codes:\nq Quit\n{ and } Halve/double current playback speed\n<- and ->  Seek backward/forward 10 seconds\nup and down Seek forward/backward 1 minute\n\n";

# last line from the csv;
if (defined $ll) {
    printf "%4.d %-15s%s %.2f\n",split /$fs/,$ll;
}

unless (-p $FIFO) {
    unlink $FIFO;
    require POSIX;
    POSIX::mkfifo($FIFO, 0700) or die "can't mkfifo $FIFO: $!";
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
    print "Press 'esc' to escape\n";


    if (defined($pos)) {
        $c = $pos+1;
    } else {
        $c = 1;
    }
    open(FIFO,"> $FIFO") || die "Cannot open $! \n";
    #print FIFO "key_down_event 111\n";
    print FIFO "osd_show_text '$answer'\n";
    print FIFO "pause\n";
    close FIFO;

    my $interval = 0; 
    my $pause = 0;
    ReadMode 3;
    while (defined($char = ReadKey(0))) {
        $hexchar = unpack "H*",$char;
        if ($hexchar eq '1b') {
            # ESC signal
            open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
            print FIFO "stop\n";
            close FIFO;
            printf "[escape], event recording stopped.\n";
            last;
        } elsif ($hexchar eq '7f') {
            # backspace
            open(CSVa, '<', "$events_csv") or die $!;
            @ll = <CSVa>;
            close CSVa;

            $ll = pop(@ll);
            if ($ll =~ /^\d+$fs/) {
                open(CSVa, '>', "$events_csv") or die $!;
                foreach (@ll) 
                { 
                    print CSVa $_; 
                }
                print CSVa "#$ll";
                close CSVa;
            }
            open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
            print FIFO "osd_show_text 'Last event deleted'\n";
            print FIFO "get_time_pos\n";
            close FIFO;
        #} elsif ($hexchar eq '20') {
        #  open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
        #    print FIFO "pause\n";
        #    #print FIFO "key_down_event\n";
        #    close FIFO;
        #    if ($pause) { $pause = 0; }
        #    else { $pause = 1; }
        } else {
            open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
            print FIFO "get_time_pos\n";
            print FIFO "key_down_event\n";
            if ($pause) {
                print FIFO "pause\n";
                print FIFO "key_down_event\n";
                $pause = 0;
            } 
            close FIFO;
        }
        $rehexchar = chr(hex($hexchar)+hex(20));
        while (<KID_TO_READ>) {
            if (/^ANS_TIME_POSITION=(.+)/) {
                if ($hexchar eq '7f') {
                    last;
                }
                $time = $1;
                if (exists  $hash{ $char }) {
                    printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$hash{$char},$char,$time,0,$fs,"\n",$player;
                    printf '%4.d [%6$s] %-15s%s %.2f%s0%7$s',$c,$hash{$char},$char,$time,$fs,$player,"\n";
                    #} elsif (exists $hash{ $rehexchar }) {
                } elsif (hex($hexchar)>64 and hex($hexchar)<91) {
                    # letters A-Z
                    # flush csv here
                    CSV->autoflush;
                    # UPPERCASE LETTERS
                    # DURATION mesuring
                    # read the csv file for searching the lowercase letter pair last position
                    open(CSVa, '<', "$events_csv") or die $!;
                    @ll = <CSVa>;
                    close CSVa;
                    $duration = 0;
                    while(@ll) {
                        @bl = split /$fs/,pop(@ll);
                        $value = $bl[2];
                        if ($value && $value =~ /^$rehexchar$/) {
                            $duration = $time-$bl[3];
                            last;
                        }
                    }
                    if (exists $hash{ $rehexchar }) {
                        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,"$hash{$rehexchar}-end",$rehexchar,$time,$duration,$fs,"\n",$player;
                        printf '%4.d [%6$s] %-15s%s %.2f %.2f%7$s",$c,"$hash{$rehexchar}-end',$rehexchar,$time,$duration,$player,"\n";
                    } else {
                        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,"$rehexchar-end",$rehexchar,$time,$duration,$fs,"\n",$player;
                        printf '%4.d [%6$s] %-15s%s %.2f %.2f%7$s',$c,"$rehexchar-end",$rehexchar,$time,$duration,$player,"\n";
                    }
                } elsif (hex($hexchar)>48 and hex($hexchar)<58) {
                    $player = $char;
                    $c = $c-1;
                    # numbers 1-9
                    printf "object id: $player\n";
                } else {
                    printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,'undefined',$char,$time,0,$fs,"\n",$player;
                    printf '%4.d [%6$s] %-15s%s %.2f%s0%7$s',$c,'undefined',$char,$time,$fs,$player,"\n";
                }
                $c = $c+1;
                last;
            }
            elsif (/^\*(.+)/) {
                #mplayer error messages
                print $_;
            }
        # KID_TO_READ WHILE
        }
        # ha már nem él a pid kilépünk a leütés olvasásból (nem tudom lehet-e ilyen eset valaha)
        shift->(@_), last unless $pid;
    # ReadKey WHILE
    }
    # Ha vége a leütés olvasásnak
    ReadMode 0;
    if (<KID_TO_READ>) {
        kill 'TERM',$pid;
        #`kill -9 $pid&`;
        #close(KID_TO_READ) || print "mplayer exited $?";
    }
    unlink $FIFO;
# if pid
} elsif ($pid == 0) {
    close STDERR;
    close STDIN;
    # child process

    if ((defined $seek) && $seek ne '') {
        $seek = "-ss $seek";
    } else {
        $seek = "";
    }
    exec("$mplayer $args $seek -quiet -slave -idle -input file=$FIFO -key-fifo-size 2 '$filename' -geometry 0%:0%;sleep 1") || print "*can't exec mplayer: $!";;
    exit(0);
}
#waitpid($pid, 0);

ReadMode 0;
print "\nEND\n";
close(CSV) || warn "csv write error: $?";

#exit 0;
# csv processing
print "csv processing";
`$mcode_pl '$filename' '$events_csv' 1>&2`;

#`mplayer $ARGV[0] -ss $time -frames 1 -vo jpeg -ao null 2>/dev/null;mv 00000001.jpg $time.jpg`;
#cat P1070099.MOV.events.csv | awk -F \; 'function round(A){return int(A+0.5)}{printf "%.2d:%.2d:%2.2f",round($4/3600),round($4/60),$4%60}{printf ",%.2d:%.2d:%2.2f\n",round($4/3600),round($4/60),$4%60+1}{print $2}'>subt.su

exit 0;
