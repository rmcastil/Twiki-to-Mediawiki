#!/usr/bin/env perl
# ================================================================ 
# 
# Perl script to covert Twiki files to MediaWiki format. 
# ( http://wiki.ittoolbox.com/index.php/Code:Twiki2mediawiki ) 
# 
# Copyright (C) 2006-2016 Authors: Anonymous, Betsy_Maz, bcmfh, Kevin Welker, Ian Holmes
# 
# Updates include the use of code from TWiki::Plugins::EditSyntaxPlugin, 
# a GPL'd Plugin from TWiki Enterprise Collaboration Platform, 
# http://TWiki.org/ written by Peter Thoeny 
# 
# This program is free software; you can redistribute it and/or 
# modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation; either version 2 
# of the License, or (at your option) any later version. 
# 
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the 
# GNU General Public License for more details. 
# 
# ================================================================ 

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use Cwd qw(abs_path);
use File::Temp;
use DateTime;

my ($verbose, $dir, $pubdir, $stdout, $imp, $keep, $user, $upload, $dryrun);
my $mwdir = "/var/www/wiki";
my $outdir = ".";
my $php = "php";
my $impScript = "importTextFiles.php";
my $uploadScript = "importImages.php";
my $summary = "Imported from TWiki";

my $usage = "Usage: $0 [OPTIONS] <TWiki file(s)>\n"
    . " -data <dir>     Convert all .txt files in directory\n"
    . " -pub <dir>      Location of TWiki pub directory\n"
    . " -out <dir>      Output directory (default '$outdir')\n"
    . " -stdout         Print to stdout instead of file\n"
    . " -import         Run MediaWiki $impScript script\n"
    . " -keep           Keep MediaWiki file after import\n"
    . " -user <name>    Username for import (overrides TWiki author)\n"
    . " -summary <desc> Summary of edit (default '$summary')\n"
    . " -mwdir <dir>    Location of MediaWiki (default '$mwdir')\n"
    . " -upload         Run MediaWiki $uploadScript script\n"
    . " -dryrun         Don't run MediaWiki scripts or save files\n"
    . " -verbose        Print more stuff\n"
    ;

GetOptions ("data=s" => \$dir,
	    "pub=s" => \$pubdir,
	    "out=s" => \$outdir,
	    "stdout" => \$stdout,
	    "import" => \$imp,
	    "keep" => \$keep,
	    "user=s" => \$user,
	    "summary=s" => \$summary,
	    "mwdir=s" => \$mwdir,
	    "upload" => \$upload,
	    "dryrun" => \$dryrun,
	    "verbose" => \$verbose)
  or die("Error in command line arguments\n" . $usage);
die $usage unless @ARGV or $dir;

my $no_file = ($stdout && !$imp) || $dryrun;

my @twikiFiles;
if ($dir) {
    opendir DIR, $dir;
    @twikiFiles = map ("$dir/$_", grep (/\.txt$/, readdir(DIR)));
    closedir DIR;
} else {
    @twikiFiles = @ARGV;
}

# List of rules to convert twiki lines to mediawiki, many/most 
# borrowed from TWiki::Plugins::EditSyntaxPlugin. 
# 
# See http://twiki.org/cgi-bin/view/Plugins/MediawikiEditSyntaxRegex 
# 
# *Quoting with a percent ("%") or hash ("#") sign. 
#
my ($author, $date, @attachments, $topic, %warned_unknown);  # global variables used by parser
my @rules= ( 

    # %TOPIC%
    q#s/%TOPIC%/$topic/g#,
    
    # %META%
    q#s/^%META:TOPICINFO{author="(.*?)" date="(.*?)".*/setTopicInfo($1,$2)/ge#,  # %META:TOPICINFO
    q#s/^%META:FILEATTACHMENT{(.*)}%/addAttachment($1)/ge#,  # %META:FILEATTACHMENT
    q#s/^%META.*//g#, # Remove remaining meta tags 
    
    # %INCLUDE%
    q#s/%INCLUDE\{"?Main\.(.*?)"?\}%/{{<nop>$1}}/g#, # %INCLUDE{Main.XXX}% --> {{X}}
    q#s/%INCLUDE\{.*?\}%//g#, # remove remaining %INCLUDE{...}%'s
    q#s/%STARTINCLUDE%/<onlyinclude>/#,
    q#s/%STOPINCLUDE%/<\/onlyinclude>/#,

    # EfetchPlugin -> Extension:PubmedParser
    q@s/%PMID\{\s*(\d+)\s*\}%/{{\#pmid:$1}}/g@,
    q@s/%PMIDC\{\s*(\d+)\s*\}%/{{\#pmid:$1}}/g@,
    q@s/%PMIDL\{.*?pmid="(\d+)".*?\}%/{{\#pmid:$1}}/g@,
    
    # LatexModePlugin -> Extension:Math
    q#s/%\$(.*?)\$%/<math>$1</math>/#,

    # DirectedGraphPlugin -> Extension:GraphViz
    q#s/<dot>/<graphviz>/g#,
    q#s/<\/dot>/<\/graphviz>/g#,
    
    # 
    # Links 
    # 
    q%s/\[\[(https?\:.*?)\]\[(.*?)\]\]/\[$1 $2\]/g%, # external link [[http:...][label]] 
    q#s/Main\.([A-Z][a-z]+[A-Z][A-Za-z]*)/$1/g#, # Main.WikiWord -> WikiWord
    q#s/([A-Z][A-Za-z0-9]*)\.([A-Z][a-z]+[A-Z][A-Za-z]*)/<nop>$1.<nop>$2/g#, # Webname.WikiWord -> <nop>Webname.<nop>WikiWord
    q%s/\[\[([^\]]*)\]\]/makeLink(makeWikiWord($1),$1)/ge%, # internal link [[WikiWord][WikiWord]] 
    q%s/\[\[([^\]]*)\]\[(.*?)\]\]/makeLink($1,$2)/ge%, # internal link [[WikiWord][label]]

    # 
    # Wiki Tags 
    # 
    q#s/^%TOC%//g#, # Remove Table of contents 
    q#s/^%BLOC%//g#, # Remove %BLOC%
    q#s/<(\/?)verbatim>/<$1nowiki>/g#, # update verbatim tag. 
    q#s/\!([A-Z]{1}\w+?[A-Z]{1})/<nop>$1/g#, # regularize ! to <nop> in front of Twiki words. 
    q#s/(?<[\s\[\(])\b([A-Z][a-z]+[A-Z][A-Za-z]*)/makeLink($1,spaceWikiWord($1))/ge#, # WikiWord -> [[WikiWord|WikiWord]]
    q#s/<nop>//g#, # remove <nop>

    # 
    # Formatting 
    # 
    q%s/(^|[\s\(])\*([^ ].*?[^ ])\*([\s\)\.\,\:\;\!\?]|$)/$1'''$2'''$3/g%, # bold 
    q%s/(^|[\s\(])\_\_([^ ].*?[^ ])\_\_([\s\)\.\,\:\;\!\?]|$)/$1''<b>$2<\/b>''$3/g%, # italic bold 
    q%s/(^|[\s\(])\_([^ ].*?[^ ])\_([\s\)\.\,\:\;\!\?]|$)/$1''$2''$3/g%, # italic 
    q%s/(^|[\s\(])==([^ ].*?[^ ])==([\s\)\.\,\:\;\!\?]|$)/$1'''<tt>$2<\/tt>'''$3/g%, # monospaced bold 
    q%s/(^|[\s\(])=([^ ].*?[^ ])=([\s\)\.\,\:\;\!\?]|$)/$1<tt>$2<\/tt>$3/g%, # monospaced 
    q%s/(^|[\n\r])---\+\+\+\+\+\+([^\n\r]*)/$1======$2 ======/%, # H6 
    q%s/(^|[\n\r])---\+\+\+\+\+([^\n\r]*)/$1=====$2 =====/%, # H5 
    q%s/(^|[\n\r])---\+\+\+\+([^\n\r]*)/$1====$2 ====/%, # H4 
    q%s/(^|[\n\r])---\+\+\+([^\n\r]*)/$1===$2 ===/%, # H3 
    q%s/(^|[\n\r])---\+\+([^\n\r]*)/$1==$2 ==/%, # H2 
    q%s/(^|[\n\r])----\+\+([^\n\r]*)/$1==$2 ==/%, # H2 (slightly misformed variant) 
    q%s/(^|[\n\r])---\+([^\n\r]*)/$1=$2 =/%, # H1 

    # 
    # Bullets 
    # 
    q%s/(^|[\n\r])[ ]{3}\* /$1\* /%, # level 1 bullet 
    q%s/(^|[\n\r])[\t]{1}\* /$1\* /%, # level 1 bullet: Handle single tabs (from twiki .txt files) 
    q%s/(^|[\n\r])[ ]{6}\* /$1\*\* /%, # level 2 bullet 
    q%s/(^|[\n\r])[\t]{2}\* /$1\*\* /%, # level 1 bullet: Handle double tabs 
    q%s/(^|[\n\r])[ ]{9}\* /$1\*\*\* /%, # level 3 bullet 
    q%s/(^|[\n\r])[\t]{3}\* /$1\*\*\* /%, # level 3 bullet: Handle tabbed version 
    q%s/(^|[\n\r])[ ]{12}\* /$1\*\*\*\* /%, # level 4 bullet 
    q%s/(^|[\n\r])[ ]{15}\* /$1\*\*\*\*\* /%, # level 5 bullet 
    q%s/(^|[\n\r])[ ]{18}\* /$1\*\*\*\*\*\* /%, # level 6 bullet 
    q%s/(^|[\n\r])[ ]{21}\* /$1\*\*\*\*\*\*\* /%, # level 7 bullet 
    q%s/(^|[\n\r])[ ]{24}\* /$1\*\*\*\*\*\*\*\* /%, # level 8 bullet 
    q%s/(^|[\n\r])[ ]{27}\* /$1\*\*\*\*\*\*\*\*\* /%, # level 9 bullet 
    q%s/(^|[\n\r])[ ]{30}\* /$1\*\*\*\*\*\*\*\*\*\* /%, # level 10 bullet 

    # 
    # Numbering 
    # 
    q%s/(^|[\n\r])[ ]{3}[0-9]\.? /$1\# /%, # level 1 bullet 
    q%s/(^|[\n\r])[\t]{1}[0-9]\.? /$1\# /%, # level 1 bullet: handle 1 tab 
    q%s/(^|[\n\r])[ ]{6}[0-9]\.? /$1\#\# /%, # level 2 bullet 
    q%s/(^|[\n\r])[\t]{2}[0-9]\.? /$1\#\# /%, # level 2 bullet: handle 2 tabs 
    q%s/(^|[\n\r])[ ]{9}[0-9]\.? /$1\#\#\# /%, # level 3 bullet 
    q%s/(^|[\n\r])[\t]{3}[0-9]\.? /$1\#\#\# /%, # level 3 bullet: handle 3 tabs 
    q%s/(^|[\n\r])[ ]{12}[0-9]\.? /$1\#\#\#\# /%, # level 4 bullet 
    q%s/(^|[\n\r])[ ]{15}[0-9]\.? /$1\#\#\#\#\# /%, # level 5 bullet 
    q%s/(^|[\n\r])[ ]{18}[0-9]\.? /$1\#\#\#\#\#\# /%, # level 6 bullet 
    q%s/(^|[\n\r])[ ]{21}[0-9]\.? /$1\#\#\#\#\#\#\# /%, # level 7 bullet 
    q%s/(^|[\n\r])[ ]{24}[0-9]\.? /$1\#\#\#\#\#\#\#\# /%, # level 8 bullet 
    q%s/(^|[\n\r])[ ]{27}[0-9]\.? /$1\#\#\#\#\#\#\#\#\# /%, # level 9 bullet 
    q%s/(^|[\n\r])[ ]{30}[0-9]\.? /$1\#\#\#\#\#\#\#\#\#\# /%, # level 10 bullet 
    q%s/(^|[\n\r])[ ]{3}\$ ([^\:]*)/$1\; $2 /g%, # $ definition: term 

    # Uncaught variables
    q#s/(%[A-Z]+%)/warn_unknown_var($1)/ge#
    
    );

for my $twikiFile (@twikiFiles) {
    unless (-e $twikiFile) {
	warn "Can't find $twikiFile\n";
	next;
    }
    warn "Processing $twikiFile\n" if $verbose;
    
    # Get file & dir names
    my $stub = basename($twikiFile);
    $stub =~ s/.txt$//;
    my $mediawikiFile = abs_path($outdir) . '/' . $stub;

    my $twikiPubDir;
    if ($upload) {
	if (defined $pubdir) {
	    $twikiPubDir = $pubdir;
	} else {
	    # try to guess the TWiki pub directory
	    warn $twikiFile;
	    warn abs_path($twikiFile);
	    my $dataDir = dirname(abs_path($twikiFile));
	    my $web = basename($dataDir);
	    $twikiPubDir = abs_path("$dataDir/../../pub/$web");
	}
    }

    # Reset globals
    $author = $date = undef;
    @attachments = ();
    $topic = $stub;
    
    # Open file
    open(TWIKI,"<$twikiFile") or die("unable to open $twikiFile - $!"); 
    if ($no_file) {
	*MEDIAWIKI = *STDOUT;
    } else {
	open(MEDIAWIKI,">$mediawikiFile") or die("unable to open $mediawikiFile - $!");
    }

    # Initialize state
    my $convertingTable = 0;  # are we in the middle of a table conversion?
    while(<TWIKI>) { 
	chomp; 
	# 
	# Handle Table Endings 
	# 
	if ($convertingTable && /^[^\|]/) { 
	    print_mediawiki ("|}\n\n"); 
	    $convertingTable = 0; 
	} 
	# 
	# Handle Tables 
	# * todo: Convert to multi-line regular expression 
	# as table data doesn't get run through the list of rules currently 
	# 
	if (/\|/) { 	# Is this the first row of the table? If so, add header 
	    if (!$convertingTable) { 
		print_mediawiki ("{| border=\"1\"\n"); 
		$convertingTable = 1; 
	    } 		# start new row 
	    print_mediawiki ("|-\n"); 
	    my $arAnswer = $_; 
	    $arAnswer =~ s/\|$//; 		#remove end pipe. 
	    $arAnswer =~ s/(.)\|(.)/$1\|\|$2/g; 		#Change single pipe to double pipe. 
	    my $text = _translateText($arAnswer); 
	    print_mediawiki ("$text\n"); 
	    # 
	    # Handle blank lines.. 
	    # 
	} 
	elsif (/^$/) { 
	    print_mediawiki ("$_\n");
	    # 
	    # Handle anything else... 
	    # 
	} 
	else { 
	    my $text = _translateText($_); 
	    print_mediawiki ("$text\n"); 
	}
    } # end while. 
    close(TWIKI); 
    unless ($no_file) {
	close(MEDIAWIKI) or die("unable to close $mediawikiFile - $!");
    }

    # Change file timestamp
    my $use_timestamp = "";
    if ($date) {
	utime ($date, $date, $mediawikiFile);
	$use_timestamp = "--use-timestamp";
    }

    # Do Mediawiki import/upload
    if ($imp) {
	my $mwUser = ($user or $author);
	if ($stdout) { system "cat $mediawikiFile" }
	run_maintenance_script ("$impScript --bot --overwrite --user='$mwUser' --summary='$summary' $use_timestamp");
	unlink($mediawikiFile) unless $keep;
    }

    if ($upload && @attachments) {
	unless (-d $twikiPubDir) {
	    warn "TWiki pub directory not found: $twikiPubDir\n";
	} else {
	    for my $info (@attachments) {
		my $name = $info->{name};
		my $path = "$twikiPubDir/$stub/$name";
		unless (-e $path) {
		    warn "Attachment not found: $name\n";
		} else {
		    my $tempdir = File::Temp->newdir();
		    system "cp $path $tempdir/$stub:$name";
		    my $extensions = "";
		    if ($name =~ /\.([^\.]+)$/) { $extensions = "--extensions=" . $1 }
		    my $comment = $info->{comment};
		    my $epoch = $info->{date};
		    my $dt = DateTime->from_epoch( epoch => $epoch );
		    my $mwDate = $dt->ymd('') . $dt->hms('');
		    my $mwUser = ($user or spaceWikiWord($info->{user}));
		    run_maintenance_script ("$uploadScript $extensions --overwrite --user='$mwUser' --summary='$summary' --comment='$comment' --timestamp=$mwDate $tempdir");
		}
	    }
	}
    }
}

# ================================================================ 
sub _translateText { 
    my ( $text, $editSyntax, $type ) = @_; 
    foreach my $rule (@rules) { 
	$rule =~ /^(.*)$/; 
	$rule = $1; 
	eval( "\$text =~ $rule;" ); 
    } 
	return $text; 
} 
# ================================================================

sub makeLink {
    my ($link, $text) = @_;
    return $link =~ /^http/ ? makeExternalLink($link,$text) : makeInternalLink($link,$text);
}

sub makeInternalLink {
    my ($link, $text) = @_;
    return ($link eq $text) ? "[[<nop>$link]]" : "[[<nop>$link|<nop>$text]]";
}

sub makeExternalLink {
    my ($link, $text) = @_;
    return ($link eq $text) ? "<nop>$link" : "[<nop>$link <nop>$text]";
}

sub makeWikiWord {
    my ($text) = @_;
    return join("", map (capitalize($_), split (/\s+/, $text)));
}

sub capitalize {
    my ($word) = @_;
    return uc(substr($word,0,1)) . substr($word,1);
}

sub spaceWikiWord {
    my ($text) = @_;
    $text =~ s/([a-z0-9])([A-Z])/$1 $2/g;
    return $text;
}

sub setTopicInfo {
    my ($a, $d) = @_;
    $author = spaceWikiWord($a);
    $date = $d;
    return "";
}

sub addAttachment {
    my ($info) = @_;
    my %info;
    while ($info =~ /([a-z]+)="(.*?)"/g) { $info{$1} = $2 }
    push @attachments, \%info;
    return "";
}

sub run_maintenance_script {
    my ($script) = @_;
    my $cmd = "$php $script";
    warn "$cmd\n";
    unless ($dryrun) {
	system "cd $mwdir/maintenance; $cmd";
    }
}

sub warn_unknown_var {
    my ($var) = @_;
    unless ($warned_unknown{$var}++) {
	warn "Unknown variable: $var\n";
    }
    return $var;
}

sub print_mediawiki {
    my (@text) = @_;
    unless ($dryrun) {
	print MEDIAWIKI @text;
    }
}

1;
