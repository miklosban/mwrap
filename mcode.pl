#!/usr/bin/perl
#  
# NAME 
#       mcode - key event revise for mwrap wrapper
# 
# SYNOPSIS
#       mwrap.pl video_file [keys file]
#       mcode.pl video_file events.csv
# 
# DESCRIPTION
# 
#       You can extract single images from the event recorded video...
#       Play 
# 
# DEVELOPMENT
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
#
# DEVELOPMENT INFO
#       last modication: 2014.jul.17
#
#

#use strict;
use warnings;


use File::Basename;
use File::Copy;
use Image::Magick;
my($image, $x);
my $mplayer_path = 'mplayer';
my $conf = $ENV{"HOME"} . '/.mwrap.conf';
my %User_Preferences = ();
my $mplayer_params = '-vf scale=960:540';
my $bin_path = '/usr/local/bin/';

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
my ($char, $key, $value, @ll, $ll, @bl, $seek, $answer, $pos, $c, %hash, $keydef, $project_dir ,$filename, $pid, $time, $duration,@f,$hexchar,$rehexchar,$pause,$event,$id);
my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
my $rand_name = join("", @chars[ map { rand @chars } ( 1 .. 8 ) ]);
my $events_csv = "$rand_name.csv";
#my $mcode_pl = $bin_path.'mcode.pl';
#my $mwrap_R = $bin_path.'mwrap.R';

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
}

printf STDOUT "mwrap images processing...\n";

if (@ARGV < 2) {
    print "A video file and the event csv file path nedeed!\n";

    open(FILE, $name) or die("Unable to open myself");
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
}
my $video_file = $ARGV[0];
my $csv_file = $ARGV[1];

# create event snapshots

print "Do you want to make snapshot images about the events? (y,n)\n";
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
            `$mplayer '$video_file' -ss $seek -frames 1 -vo jpeg -ao null 2>/dev/null`;
            move("00000001.jpg","$fn");
            $image = Image::Magick->new;
            $x = $image->Read("$fn");
            $image->Annotate(gravity=>'south',antialias=>'true',x=>0,y=>10,pointsize=>14,stroke=>'#000C',strokewidth=>1,text=>"$event");
            $image->Annotate(gravity=>'south',antialias=>'true',x=>0,y=>10,pointsize=>14,stroke=>'none',fill=>'white',text=>"$event");
            $x = $image->Write("$fn");
            warn "$x" if "$x";
        }
        #`convert $fn -gravity south -pointsize 14 -stroke '#000C' -strokewidth 1 -annotate +0+10 '$event' -stroke none -fill white -annotate +0+10 '$event' $fn`;
        
    }
}
print "Do you want see the single images of recorded moments? (y,n)\n";
$answer = <STDIN>;
chop $answer;
if ($answer eq 'y' || $answer eq 'i') {
    `$mplayer $mplayer_params "mf://$id*.jpg" -mf fps=2`;
}
}


# create event subtitle
`cat '$csv_file' | awk -F \\; 'function round(A){return int(A+0.5)}{printf "%.2d:%.2d:%2.2f",round(\$4/3600),round(\$4/60),\$4%60}{printf ",%.2d:%.2d:%2.2f\\n",round(\$4/3600),round(\$4/60),\$4%60+1}{print \$2}'>'$csv_file.sub'`;

# play original video width its event subtitle
print "Do you want watch the subtitled video? (y,n)\n";
$answer = <STDIN>;
chop $answer;
if ($answer eq 'y' || $answer eq 'i') {
    `mplayer $mplayer_params '$video_file' -sub '$csv_file.sub' -geometry 0%:0% 2>/dev/null`;
}

#use Statistics::R ;
  
#my $R = Statistics::R->new() ;
  
#print $csv_file;
#print `pwd`;

#$R->startR ;

#$R->send(qq`csv = '$csv_file'`);
#$R->send(q`source('$mwrap_R')`);
  
#my $ret = $R->read ;
  
#$R->stopR() ;

#system('evince "plots.pdf"');

# R
# a<-read.csv2('P1060509.MOV.events.csv',sep=';',header=F,comment.char='#')
