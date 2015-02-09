#!/usr/bin/perl 
#  
# NAME 
#       mwrap - key event wrapper with mplayer
# 
# SYNOPSIS
#       mwrap.pl video_file [keys file]
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
#       You can use all the mplayer control keys in the mplayer window.
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
# 
# AUTHOR
#       Written by Bán Miklós (banm@vocs.unideb.hu) at 2011.04.25.
# 
# COPYRIGHT
#       I don't know yet. Write an email if you have any question.
# 
# 
# VERSION INFO
#       last modification: Mon Feb  9 14:41:26 CET 2015
# 
# 

use strict;
use warnings;
use Term::ReadKey;
use File::Basename;
use IO::Handle;
use POSIX qw{strftime};
use Getopt::Long;
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

# 
# Set these variables as you need
# ---------------------------------------------------------------------------------------
# default parameters; Define it in user level in the ~/.mwrap.conf file
my $mplayer_params = '-vf scale=960:540 -ao null';
my $fs = ';';   # csv field separator
my $mplayer_path = 'mplayer';
my $bin_path = '/usr/local/bin/';
my $conf = '';
my $ctr_enabled = 1; # pause control by space key enabled
my $short_seek = 10;
my $long_seek = 120;
# ---------------------------------------------------------------------------------------
# Do not change these variables
my $mplayer = $mplayer_path.' '.$mplayer_params;
my $args = ''; # mplayer args like -vo x11
my $FIFO = 'fifo';
my $name = $0;
my ($char, $key, $value, @ll, $ll, @bl, $seek, $answer, $pos, $c, %hash, $project_dir, $pid, $time, $ftime, $duration,@f,$hexchar,$rehexchar,$rehexcharT,$utf8,$switch);
my $player = '';
my $filename = '';
my $keydef = 'keys.txt';
my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
my $rand_name = join("", @chars[ map { rand @chars } ( 1 .. 8 ) ]);
my $events_csv = "$rand_name.csv";
my $mcode_pl = $bin_path.'mcode.pl';
my $version='';
my $seek_to_object = 0;
my $mark_at = '';
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
    open(FILE, $name) or die("Unable to open myself:$name");
    my $text = '';
    while (<FILE>) {
        if ($_ =~ /^#\s+last modification:/) {
            $text .= "Last modification: ".$';
            last;
        } 
    }
    close(FILE);
    print $text;
    exit 1;
}
# ---------------------------------------------------------------------------------------
# Help text
if ($filename eq '') {
    print "A video file name nedeed!\n";

    open(FILE, $name) or die("Unable to open myself:$name");
    my $pager = $ENV{PAGER} || 'less';
    open(my $less, '|-', $pager, '-e') || die "Cannot pipe to $pager: $!";
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

    print $less $text;
    close($less);
    exit 1;
} 
# ---------------------------------------------------------------------------------------
# Set mwrap parameters
if (-e "./mwrap.conf") {
    $conf = "./mwrap.conf";
    printf "Local parameter settings read:\n";
} else {
    if (-e $ENV{'HOME'} . '/.mwrap.conf') {
        $conf = sprintf $ENV{'HOME'} . '/.mwrap.conf';
        printf "Parameter settings read from home directory:\n";
    } else {
        `echo "mplayer_params = $mplayer_params\nfs = ;\n" > mwrap.conf`;
        printf "There was no mwrap.conf defined. It has been created here with default values. You can edit it as you need.\n";
    }
}
my %User_Preferences = ();
if (-e $conf) {
    open(CONFIG, $conf) or warn("Unable to open: $conf");
    while (<CONFIG>) {
        chomp;                  # no newline
        s/#.*//;                # no comments
        s/^\s+//;               # no leading white
        s/\s+$//;               # no trailing white
        next unless length;     # anything left?
        my ($var, $value) = split(/\s*=\s*/, $_, 2);
        printf "\t$var $value\n";
        $User_Preferences{$var} = $value;
    }
}
if (exists $User_Preferences{'fs'}) {
    $fs = $User_Preferences{'fs'};
}
if(exists $User_Preferences{'mplayer_params'}) {
    $mplayer_params = $User_Preferences{'mplayer_params'};
}
if(exists $User_Preferences{'bin_path'}) {
    $bin_path =  $User_Preferences{'bin_path'};
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
if(exists $User_Preferences{'space_pause'}) {
    $ctr_enabled =  $User_Preferences{'space_pause'};
}
# ---------------------------------------------------------------------------------------
# keys
if (-e $keydef) {
    open(KEYF, '<', $keydef);
    print "Currently defined keys:\n";
    while(<KEYF>) {
        printf "\t";
        printf;
        ($key,$value) = split / /;
        chop $value;
        $hash{ $key } = $value;
    }
    print "\n";
    close (KEYF);
} else {
    print "No keys defined!\nYou can specify key events in the 'keys.txt', like in the following example:\nj jumping\ns sleeping\nf fighting\n\n";
    # röptében kulcs definiálás!!!
}
# ---------------------------------------------------------------------------------------
# mwrap starting
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
                printf "\t$i $_\n";
            }
            $answer = <STDIN>;
            chop $answer;
            if ($answer>@f) {
                exit 1;
            }
            $answer = $f[$answer-1];
            $answer =~ s/\.csv$//; 
            $events_csv = "$project_dir/$answer.csv";
            open(CSV, '<', "$events_csv") or die $!;
            @ll = <CSV>;
            close(CSV);
            while(@ll) {
                $ll = pop @ll;
                if ($ll =~ /^#/) { next; }
                else { 
                    print $ll;
                    last;
                }
            }
            open(CSV, '>>', "$events_csv") or die $!;
            CSV->autoflush(1);
            @bl = split /$fs/,$ll;
            $seek = $bl[3];
            $pos = $bl[0];
            $player = $bl[5];
            chomp $player;
            if ($pos =~ /^\d+$/) {
                print "Seeking to $seek\" position\n";
            } else {
                $seek = 0;
                $ll = '';
                $pos = '';
            }
        }
    }
} else {
    print "Videofile: '$filename' does not exists.\n";
    exit 1;
}

print "\nYou can control mplayer with the usual control keys (in the mplayer window!).\nSome useful mplayer key codes:\nq Quit\n{ and } Halve/double current playback speed\n<- and ->  Seek backward/forward 10 seconds\nup and down Seek forward/backward 1 minute\n\n";

# last line from the csv;
if ($ll =~ /\d+.+/) {
    printf "%4.d %-15s%s %.2f\n",split /$fs/,$ll;
}

# create fifo
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
    print "Press 'end' to finish!\n";

    if ($pos =~ /\d+/) {
        $c = $pos+1;
    } else {
        $c = 1;
    }
    open(FIFO,"> $FIFO") || die "Cannot open $! \n";
    print FIFO "key_down_event 111\n";
    print FIFO "osd_show_text '$answer'\n";
    print FIFO "pause\n";
    close FIFO;

    my $interval = 0; 
    my $controlkey=0;
    ReadMode 3;
    while (defined($char = ReadKey(0))) {
        $hexchar = unpack "H*",$char;
        
        #printf("Decimal: %d\tHex: %x\n", ord($char), ord($char));
        if ($hexchar eq '7e') {
            # long control keys END
            $controlkey=0;
            next;
        } elsif ($hexchar eq '1b') {
            # long control keys 2. character
            $controlkey=1;
            next;
        } elsif ($hexchar eq '5b' or $hexchar eq '4f') {
            # long control keys 2. character
            $controlkey=2;
            next;
        } elsif ($hexchar eq 'c3' or $hexchar eq 'c5') {
            #utf8 characters: öüóőúéáűí...
            if ($hexchar eq 'c3') { $utf8 = 'c3' }
            elsif ($hexchar eq 'c5') { $utf8 = 'c5' }
            $controlkey=4;
            next;
        }

        if ($controlkey == 2 and ($hexchar eq '31' or $hexchar eq '32')) {
            # FN keys 5-12
            $controlkey = 3;
            next;
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
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "seek $long_seek\n";
                close FIFO;
                $controlkey=0;
                next;
            }
            elsif ($hexchar eq '42') {
                printf "Seek backward $long_seek sec.\n";
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "seek -$long_seek\n";
                close FIFO;
                $controlkey=0;
                next;
            }
            elsif ($hexchar eq '43') {
                printf "Seek forward $short_seek sec.\n";
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "seek $short_seek\n";
                close FIFO;
                $controlkey=0;
                next;
            }
            elsif ($hexchar eq '44') {
                printf "Seek backward $short_seek sec.\n";
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "seek -$short_seek\n";
                close FIFO;
                $controlkey=0;
                next;
            }
            elsif ($hexchar eq '35') {
                # PageUp - Seek to given Object Id start
                if ($player ne '') { $seek_to_object = "#$player"; }
                else { $seek_to_object = '#'; }
                $controlkey=0;
                next;
            }
            elsif ($hexchar eq '36') {
                # PageDown - Seek the last Object Id start
                open(CSVa, '<', $events_csv) or die $!;
                @ll = <CSVa>;
                close CSVa;
                $pos = "";
                $seek= "";
                CSV->autoflush;

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
                    printf "Last object [%d] start found after position %d. at %s\n",$bl[5],$pos,$seek;
                    open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                    print FIFO "osd_show_text 'Seek to time position: $seek'\n";
                    print FIFO "seek $seek 2\n";
                    close FIFO;
                } else {
                    printf "No object mark found.\n";
                }
                $controlkey=0;
                next;
            }
            elsif (hex($hexchar)>=80 and hex($hexchar)<=83) {
                #FN 1-4 
                $player = hex($hexchar)-79;
                $mark_at = $player;
                $controlkey=0;
            } elsif ($hexchar eq '46') {
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "stop\n";
                close FIFO;
                printf "\"end\" Event recording stopped.\n";
                last;
            } else {
                #unhandled control key
                printf "Unhandled control key:\n";
                printf("Decimal: %d\tHex: %x\n", ord($char), ord($char));
                $controlkey=0;
                next;
            }
            #end control key 2
        } elsif ($controlkey==4) {
            $char=pack "H*",$utf8.$hexchar;
            $controlkey=0;
            $utf8='';
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
            @ll = <CSVa>;
            close CSVa;
            $pos = "";
            $seek= "";
            CSV->autoflush;

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
                printf "Found object [%d] start at: %s\n",$bl[5],$seek;
                open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
                print FIFO "osd_show_text 'Seek to time position: $seek'\n";
                print FIFO "seek $seek 2\n";
                close FIFO;
            } else {
                printf "No marked object found with reference id: $mark_at\n";
            }
            $mark_at = ''; 
            next;
        }
        
        if ($hexchar eq '7f') {
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
        } elsif ($hexchar eq '20' and $ctr_enabled==1) {
            # space to pause if control enabled
            open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
            print FIFO "pause\n";
            printf "pause\n";
            close FIFO;
            next;
        } 
        else {
            # ANY else character 
            open(FIFO,"> $FIFO") || warn "Cannot open fifo $! \n";
            print FIFO "get_time_pos\n";
            close FIFO;
        }
        $rehexchar = chr(hex($hexchar)+hex(20));
        $rehexcharT = chr(hex($hexchar));
        while (<KID_TO_READ>) {
            if (/^ANS_TIME_POSITION=(.+)/) {
                if ($hexchar eq '7f') {
                    last;
                }
                $time = $1;
                $ftime = strftime("\%H:\%M:\%S", gmtime($time));
                if ($mark_at ne '') {
                    printf CSV '#Mark: %d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c-1,'-','-',$time,0,$fs,"\n",$mark_at;
                    printf "object id: $mark_at\n";
                    $mark_at = "";
                    last;
                }
                if (exists  $hash{ $char }) {
                    #kis betűs leütés aminek van cimkéje
                    printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$hash{$char},$char,$time,0,$fs,"\n",$player;
                    printf '%4.d [%6$s] %-15s%s %s%s0%7$s',$c,$hash{$char},$char,$ftime,$fs,$player,"\n";
                    #} elsif (exists $hash{ $rehexchar }) {
                } elsif ((hex($hexchar)>64 and hex($hexchar)<91) or length($hexchar)==4) {
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
                        #nagy betűs leütés aminek van cimkéje
                        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$hash{$rehexchar}."-end",$rehexcharT,$time,$duration,$fs,"\n",$player;
                        printf '%4.d [%6$s] %-15s%s %s %.2f%7$s',$c,$hash{$rehexchar}."-end",$rehexcharT,$ftime,$duration,$player,"\n";
                    } else {
                        #nagy betűs leütés aminek nincs cimkéje
                        printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,$rehexchar."-end",$rehexcharT,$time,$duration,$fs,"\n",$player;
                        printf '%4.d [%6$s] %-15s%s %s %.2f%7$s',$c,$rehexchar."-end",$rehexcharT,$ftime,$duration,$player,"\n";
                    }
                #} elsif (hex($hexchar)>48 and hex($hexchar)<58) {
                #  $player = $char;
                #    $c = $c-1;
                #    # numbers 1-9
                #    printf "object id: $player\n";
                } else {
                    #kis betűs leütés aminek nincs cimkéje
                    printf CSV '%d%6$s%s%6$s%s%6$s%.2f%6$s%.2f%6$s%8$s%7$s',$c,'undefined',$char,$time,0,$fs,"\n",$player;
                    printf '%4.d [%6$s] %-15s%s %s%s0%7$s',$c,'undefined',$char,$ftime,$fs,$player,"\n";
                }
                $c = $c+1;
                last;
            }
            elsif (/^\*(.+)/) {
                #mplayer error messages
                #print $_;
                print $1;
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

    if ($seek ne '0') {
        $seek = "-ss $seek";
    } else {
        $seek = "";
    }
    exec("$mplayer $args $seek -quiet -slave -idle -input file=$FIFO -key-fifo-size 2 '$filename' -geometry 0%:0%;sleep 1") || print "*can't exec mplayer: $!";;
    print $seek;
    exit(0);
}
#waitpid($pid, 0);

ReadMode 0;
print "\nEND\n";
close(CSV) || warn "csv write error: $?";

#exit 0;
# csv processing
print "calling mcode.pl:\n";
`$mcode_pl '$filename' '$events_csv' 1>&2`;

#`mplayer $ARGV[0] -ss $time -frames 1 -vo jpeg -ao null 2>/dev/null;mv 00000001.jpg $time.jpg`;
#cat P1070099.MOV.events.csv | awk -F \; 'function round(A){return int(A+0.5)}{printf "%.2d:%.2d:%2.2f",round($4/3600),round($4/60),$4%60}{printf ",%.2d:%.2d:%2.2f\n",round($4/3600),round($4/60),$4%60+1}{print $2}'>subt.su

exit 0;
