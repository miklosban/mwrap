#!/usr/bin/perl -w

my @modules=('File::Basename','File::Copy','File::Find','Image::Magick','IO::Handle','POSIX','Term::ReadKey','Statistics::R');
my @binaries=('mplayer');

foreach (@modules) {
    my $module = $_;

    my $output = `perl -M$module -e 0 2>&1`;
    chop($output);
    if ($output !~ /^$/) {
        if ($_ eq "Statistics::R") {
            print "The optional $_ module is missing. You can install it by: cpan $module\n";
        }
        else {
            print "The required $_ perl module is missing. You can install it by: cpan $module\n";
            exit;
        }
    } else {
        print "$_ OK\n";
    }
}
foreach (@binaries) {
    my $bin = $_;
    my $output = `whereis -b $bin`;
    chop($output);
    if ($output !~ /\w+: (.+)$/) {
        print "$bin MISSING\n";
        exit;
    }
}

if (getlogin() eq 'root' || $< == 0) {
    @files = ('mwrap.pl','mcode.pl','mwrap.R');
    $path = '/usr/local/bin/';
    print "Trying to copy mwrap files to $path\n";
    print "You can specify an other path (or press enter): ";
    $pathi = <>;
    chop $pathi;
    if ($pathi !~ /^$/) {
        $path = $pathi;
    }
    if (! -d $path) {
        print "Invalid path: :$path:\n";
        exit;
    }
    
    use File::Copy;
    use File::Basename;
    
    $ldir = dirname $0;

    foreach(@files) {
        if (-e "$ldir/$_") {
            # the separator is not OS independent (File::Spec)
            copy("$ldir/$_","$path");
            system("chmod +x $path/$_");
            print "copy $ldir/$_ --> /usr/local/bin/ OK\n";
        } else {
            print "$_ not found here: $ldir\n";
        }
    }
    print "You can specify a config file for override the default paramters. E.g.:\n";
    print "touch ~/.mwrap.conf; ";
    print "echo 'mplayer_params = -vf scale=960:540' >  ~/.mwrap.conf\n";
} else {
    print "You need root privileges to copy mwrap files to a system path\n";
}
