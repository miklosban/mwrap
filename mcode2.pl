#!/usr/bin/perl
#  
# NAME 
#       mcode - key event revise for mwrap wrapper
# 
# SYNOPSIS
#       mcode.pl [-f] video_file [-c] [path_to_csv] events.csv
# 
# DESCRIPTION
# 
#       Extract single images (of the recorded events) from an analysed video file
#       Create subtitle file from events
#       Play video with subtitle
# 
# DEVELOPMENT
#       The R module is in early development stage. It is not too interesting at all.
#        
# 
# KNOWN BUGS
# 
# 
# AUTHOR
#  
#       Written by Bán Miklós (banm@vocs.unideb.hu) at 2011.12.01.
# 
# COPYRIGHT
# 
#       I don't know yet. Write an email if you have any question.
#
my $mwrap_version = 'Thu Apr 30 22:07:17 CEST 2015';

#use strict;
use warnings;

use Getopt::Long;
use File::Basename;
use File::Copy;
use Image::Magick;
use POSIX;
# 
# Set these variables as you need
# ---------------------------------------------------------------------------------------
# default parameters; Define it in user level in the ~/.mwrap.conf file
my($image, $x);
my $mplayer_params = '-vf scale=960:540 -ao null';
my $mplayer_path = 'mplayer';
my $cvlc_path = 'cvlc';
my $vlc_params = '';
my $vlc_host_port = '127.0.0.1:1234';
my $fs = ';';   # csv field separator
my $bin_path = '/usr/local/bin/';
my $conf = '';
my $mwrap_log = "/tmp/mwrap.log";
my $R_statistics = 0; # set it true if the Statistics::R package installed - IT NOT WORKS CURRENTLY
my $create_subtitle = 1;
my $video_player;
my $vpa = 'MPLAYER';
# ---------------------------------------------------------------------------------------
# Do not change these variables
my $args = ''; # mplayer args like -vo x11
my $name = $0;
my ($answer,$time);
my $player = '';
my $filename = '';
my $mcode_pl = $bin_path.'mcode.pl';
my $version='';
my $ll = '';
my $project_dir = '';
my $csv_file = '';
my $red = "\033[0;31m";
my $green = "\033[0;32m";
my $yellow = "\033[1;33m";
my $blue = "\033[0;34m";
my $lblue = "\033[1;34m";
my $gray = "\033[1;30m";
my $NC = "\033[0m";
my $bold = "\e[1m";

# ---------------------------------------------------------------------------------------
# Command line options
GetOptions ('c:s' => \$csv_file, 'f:s' => \$filename, 's:s' => \$create_subtitle, 'v' => \$version,'<>' => \&args);
sub args {
    my $p1 = shift(@_);
    if ($filename eq '') { $filename = $p1; }
    elsif ($csv_file eq '') { $csv_file = $p1; }
}
if ($filename ne '') {
    $project_dir = "$filename.dir";
    $csv_file = "$project_dir/".basename("$csv_file");
}
print $csv_file."\n";
print $filename."\n";
# ---------------------------------------------------------------------------------------
# Version information
if ($version) {
    print "$mwrap_version\n";
    exit 1;
}
# ---------------------------------------------------------------------------------------
# Help text
if ($csv_file eq '') {
    print "A result csv file name nedeed!\n";
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
if (-e "./mwrap.conf") {
    $conf = "./mwrap.conf";
    print "-------------------------------------\n";
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
        print $lblue;
        printf "\t$var $value\n";
        print $NC;
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
if(exists $User_Preferences{'mwrap_log'}) {
    $mwrap_log =  $User_Preferences{'mwrap_log'};
}
if(exists $User_Preferences{'vlc_params'}) {
    $vlc_params =  $User_Preferences{'vlc_params'};
}
if(exists $User_Preferences{'vlc_host_port'}) {
    $vlc_host_port =  $User_Preferences{'vlc_host_port'};
}
if(exists $User_Preferences{'cvlc_path'}) {
    $cvlc_path =  $User_Preferences{'vlc_path'};
}
if(exists $User_Preferences{'vpa'}) {
    $vpa =  $User_Preferences{'vpa'};
}
# Control commands
if ($vpa eq "MPLAYER") {
    $video_player = $mplayer_path.' '.$mplayer_params;
} else {
    $video_player = $cvlc_path.' '.$vlc_params;
}

###--------------------------------------------------------- START HERE -------------------------###

printf STDOUT $green,"mcode processing...\n",$NC;

if ($create_subtitle) {
    # sorba kell rendezni a csv tartalmát idő szerint
    # és kell fejléc a sub fileba


    print $green,"Creating subtitle using the CSV file...\n",$NC;
    # create event subtitle - not works properly for more than one hour
    #`cat '$csv_file' | awk -F \\; 'function round(A){return int(A+0.5)}{printf "%.2d:%.2d:%2.2f",round(\$4/3600),round(\$4/60),\$4%60}{printf ",%.2d:%.2d:%2.2f\\n",round(\$4/3600),round(\$4/60),\$4%60+1}{print \$2}'>'$csv_file.sub'`;
    open(CSV, '<', "$csv_file") or die $red,"No path defined for $csv_file?",$NC;
    @ll = <CSV>;
    close(CSV);
    open(SUB,'>',"$csv_file.sub") or die "ÁÁááááááoüüüüüüúúúúúúúúúúúu";
    printf SUB "[INFORMATION] project / video 
[TITLE] Title of film.
[AUTHOR] Author of film.
[SOURCE] Arbitrary text
[FILEPATH] Arbitrary text
[DELAY] (time in frames to delay all subtitles
[COMMENT] Arbitrary text
[END INFORMATION]
[SUBTITLE] <-- beginning of subtitle section, no closing tag required.
[COLF]&HFFFFFF,[SIZE]12,[FONT]Times New Roman\n";
    while(@ll) {
       $ll = shift @ll;
       if ($ll =~ /^#/) { next; }
       my @bl = split /$fs/,$ll;
       my $hour = floor($bl[3]/3600);
       my $m = $bl[3]%3600;
       my $f = $bl[3]-floor($bl[3]);
       my $minutes = floor($m/60);
       my $seconds = $m%60+$f;
    
       printf SUB '%1$.2d:%2$.2d:%3$.2f,%1$.2d:%2$.2d:%4$.2f%6$s%5$s%6$s%6$s',$hour,$minutes,$seconds,$seconds+1,$bl[1],"\n";
    }
    close(SUB);
    print $green,"Done\n",$NC;
}

#if video file name given
if (-e $filename) {
    # create event snapshots
    print $yellow,"Do you want to make snapshot images about the events? (y,n)\n",$NC;
    $answer = <STDIN>;
    chop $answer;
    if ($answer eq 'y' || $answer eq 'i') {
        open(CSV, '<', "$csv_file") or die $!;
        $id = '';
        while (<CSV>) {
            if ($id eq '') {
                $_ =~ /^#Project ID: (.+)$/;
                $id = $1;
                next;
            }
            if (/^#/) {
                next;
            }
            @bl = split /;/,$_;
            $pos = $bl[0];
            $seek = $bl[3];
            $event = $bl[1];
            if ($pos =~ /^\d+?$/) {
                chop $seek;

                $fn = sprintf "%s_%s_%s.jpg",$id,$event,$seek;
                if ( ! -e $fn ) {
                    print "grab the $seek position\n";
                    if ($vpa eq 'MPLAYER') {
                        `$video_player '$filename' -ss $seek -frames 1 -vo jpeg -ao null 2>/dev/null`;
                        if ( -e "00000001.jpg" ) {
                            move("00000001.jpg","$fn");
                        }
                    }
                    else {
                        my $seek_end = $seek+1;
                        `$video_player '$filename' --rate=1 --video-filter=scene --vout=dummy --start-time=$seek --stop-time=$seek_end --scene-format=jpg --scene-ratio=1 --scene-prefix=mwrap --scene-path=./ vlc://quit`;
                        if ( -e "mwrap00001.jpg" ) {
                            move("mwrap00001.jpg","$fn");
                            unlink glob "mwrap0*.jpg";
                        }
                    }
                    if ( -e $fn ) {
                        $image = Image::Magick->new;
                        $x = $image->Read("$fn");
                        $image->Annotate(gravity=>'south',antialias=>'true',x=>0,y=>10,pointsize=>14,stroke=>'#000C',strokewidth=>1,text=>"$event");
                        $image->Annotate(gravity=>'south',antialias=>'true',x=>0,y=>10,pointsize=>14,stroke=>'none',fill=>'white',text=>"$event");
                        $x = $image->Write("$fn");
                        warn "$x" if "$x";
                    } else {
                        print "The video file is not seekable! No picture output.\nIf you want to check it, use this command:\nmplayer '$filename' -ss $seek -frames 1 -vo jpeg -ao null 2>/dev/null\n";
                    }
                }
                #`convert $fn -gravity south -pointsize 14 -stroke '#000C' -strokewidth 1 -annotate +0+10 '$event' -stroke none -fill white -annotate +0+10 '$event' $fn`;
            }
        }
        if ($vpa eq 'MPLAYER') {
            print $yellow,"Do you want see the single images' of the recorded moments? (y,n)\n",$NC;
            $answer = <STDIN>;
            chop $answer;
            if ($answer eq 'y' || $answer eq 'i') {
                `$video_player $mplayer_params "mf://$id*.jpg" -mf fps=2`;
            }
        }
    }
    
    # play original video width its event subtitle
    print $yellow,"Do you want watch the subtitled video? (y,n)\n",$NC;
    $answer = <STDIN>;
    chop $answer;
    if ($vpa eq 'MPLAYER') {
        if ($answer eq 'y' || $answer eq 'i') {
            `$video_player $mplayer_params '$filename' -sub '$csv_file.sub' -geometry 0%:0% 2>$mwrap_log`;
        }
    } else {
        if ($answer eq 'y' || $answer eq 'i') {
            print "$video_player $vlc_params '$filename' --sub-file='$csv_file.sub'";
            `$video_player $vlc_params '$filename' --sub-file='$csv_file.sub' 2>$mwrap_log`;
        }

    }
}

if ($R_statistics) {
    require $bin_path.'mwrap_modules.pl';
    our $R;
    my $mwrap_R = $bin_path.'mwrap.R';
  
    print $csv_file;
    print `pwd`;

    $R->startR ;
    $R->send(qq`csv = '$csv_file'`);
    $R->send(q`source('$mwrap_R')`);
  
    my $ret = $R->read ;
    $R->stopR() ;
    system('evince "plots.pdf"');

    # R
    # a<-read.csv2('P1060509.MOV.events.csv',sep=';',header=F,comment.char='#')
}

print $NC;
exit 0;
