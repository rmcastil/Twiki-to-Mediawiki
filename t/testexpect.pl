#!/usr/bin/env perl

use warnings;
use File::Temp;
use File::Basename;
use Cwd qw(abs_path);

my $dir = dirname(abs_path($0));
my $prog = abs_path("$dir/../twiki2mediawiki.pl");
my $t2mw = basename($prog);
opendir DIR, $dir;
my @txt = grep (/\.txt$/, readdir DIR);
closedir DIR;

my $passed = 0;
my @failed;
for my $n (0..$#txt) {
    my $desc = desc($n+1);
    my $txt = $txt[$n];
    my $mw = $txt;
    $mw =~ s/txt$/mw/;
    die "Can't find file $mw" unless -e "$dir/$mw";

    my $fh = File::Temp->new();
    my $fname = $fh->filename;

    system "$prog $dir/$txt -stdout >$fname";
    my $diff = `diff $fname $dir/$mw`;

    if (length $diff) {
	print "`$t2mw $txt` does not match $mw:\n";
	print `diff -y $fname $dir/$mw`;
	print "not ok ($desc): $txt\n";
	push @failed, $txt;
    } else {
	print "ok ($desc): $txt\n";
	++$passed;
    }
}

if ($passed == @txt) {
    print "ok: passed ", desc($passed), " tests\n";
} else {
    print "Failed tests: @failed\n";
    die "not ok: passed ", desc($passed), " tests\n";
}

sub desc {
    my ($n) = @_;
    return $n . "/" . (@txt + 0);
}
