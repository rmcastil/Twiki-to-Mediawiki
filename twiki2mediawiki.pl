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

# Options that are disabled/empty by default
my ($verbose,
    $dataDir,
    $pubDir,
    $useStdout,
    @varFiles,
    $deletePages,
    $importPages,
    $renamePages,
    $keepPageFiles,
    $user,
    $uploadAttachments,
    $dryRun);

# Mediawiki globals & options
my $mwdir = "/var/www/wiki";
my $outdir = ".";
my $php = "php";
my $summary = "Imported from TWiki";

my $importScript = "importTextFiles.php";
my $uploadScript = "importImages.php";
my $moveScript = "moveBatch.php";
my $deleteScript = "deleteBatch.php";

# TWiki globals
my $web = "Main";

# Parse command line
my $usage = "Usage: $0 [OPTIONS] <TWiki file(s)>\n"
    . " -data <dir>     Convert all .txt files in directory\n"
    . " -out <dir>      Output directory (default '$outdir')\n"
    . " -stdout         Print to stdout instead of file\n"
    . " -vars <file>    Parse TWiki variable definitions from file\n"
    . " -delete         Delete using $deleteScript\n"
    . " -import         Run MediaWiki $importScript script\n"
    . " -pub <dir>      Location of TWiki pub dir (default datadir/../../pub)\n"
    . " -rename         Rename (CamelCase -> Camel_Case) using $moveScript\n"
    . " -keep           Keep MediaWiki file after import\n"
    . " -user <name>    Username for import (overrides TWiki author)\n"
    . " -summary <desc> Summary of edit (default '$summary')\n"
    . " -mwdir <dir>    Location of MediaWiki (default '$mwdir')\n"
    . " -upload         Run MediaWiki $uploadScript script\n"
    . " -dryrun         Don't run MediaWiki scripts or save files\n"
    . " -verbose        Print more stuff\n"
    ;

GetOptions ("data=s" => \$dataDir,
	    "pub=s" => \$pubDir,
	    "out=s" => \$outdir,
	    "stdout" => \$useStdout,
	    "vars=s" => \@varFiles,
	    "delete" => \$deletePages,
	    "rename" => \$renamePages,
	    "import" => \$importPages,
	    "keep" => \$keepPageFiles,
	    "user=s" => \$user,
	    "summary=s" => \$summary,
	    "mwdir=s" => \$mwdir,
	    "upload" => \$uploadAttachments,
	    "dryrun" => \$dryRun,
	    "verbose" => \$verbose)
  or die("Error in command line arguments\n" . $usage);
die $usage unless @ARGV or $dataDir;

my $no_file = ($useStdout && !$importPages) || $dryRun;

# Build list of files
my @twikiFiles;
if ($dataDir) {
    opendir DIR, $dataDir or die "Couldn't open $dataDir: $!";
    @twikiFiles = map ("$dataDir/$_", grep (/\.txt$/, readdir(DIR)));
    closedir DIR;
    push @varFiles, getTwikiPrefsFiles($dataDir);
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
my ($topic, $author, $date, @attachments, @linkedAttachments, %twikiVar, %warned, $currentText);  # global variables used by parser
my @rules= ( 

    # Set variable
    q#s/^\s+\* +Set +([A-Za-z]+) += +(.*)/setTwikiVar($1,$2)/ge#,

    # %TOPIC% and %SPACEDTOPIC%
    q#s/%TOPIC%/$topic/g#,
    q#s/%SPACEDTOPIC%/spaceWikiWord($topic)/ge#,

    # %WEB%, %MAINWEB%, %TWIKIWEB%
    q#s/%WEB%/$web/g#,
    q#s/%MAINWEB%/Main/g#,
    q#s/%TWIKIWEB%/TWiki/g#,

    # ATTACHURL, PUBURL
    q#s/%ATTACHURL%\//attachmentLinkPrefix($web,$topic)/ge#,
    q#s/%ATTACHURLPATH%\//attachmentLinkPrefix($web,$topic)/ge#,
    q#s/%PUBURL%\/([^\/]+)\/([^\/]+)\/([^\"\s\]]+)/attachmentLink($1,$2,$3)/ge#,
    q#s/%PUBURLPATH%\/([^\/]+)\/([^\/]+)\/([^\"\s\]]+)/attachmentLink($1,$2,$3)/ge#,
    
    # %DATE% and %DISPLAYTIME%
    q#s/%DATE%/{{CURRENTYEAR}}-{{CURRENTMONTH}}-{{CURRENTDAY}}/g#,
    q#s/%DISPLAYTIME%/{{CURRENTYEAR}}-{{CURRENTMONTH}}-{{CURRENTDAY}} {{CURRENTTIME}/g#,
    
    # %META%
    q#s/^%META:TOPICINFO{author="(.*?)" date="(.*?)".*/setTopicInfo($1,$2)/ge#,  # %META:TOPICINFO
    q#s/^%META:FILEATTACHMENT{(.*)}%/addAttachment($1,$web,$topic)/ge#,  # %META:FILEATTACHMENT
    q#s/^%META.*//g#, # Remove remaining meta tags 
    
    # %INCLUDE%
    q#s/%INCLUDE\{"?$web\.(.*?)"?\}%/{{<nop>$1}}/g#, # %INCLUDE{$web.XXX}% --> {{X}}
    q#s/%INCLUDE\{.*?\}%//g#, # remove remaining %INCLUDE{...}%'s
    q#s/%STARTINCLUDE%/<onlyinclude>/#,
    q#s/%STOPINCLUDE%/<\/onlyinclude>/#,

    # EfetchPlugin -> Extension:PubmedParser
    q@s/%PMID[LC]?\{\s*(\S+?)\s*\}%/{{\#pmid:$1}}/g@,
    q@s/%PMIDL\{.*?pmid="?(\d+)"?.*?\}%/{{\#pmid:$1}}/g@,
    
    # LatexModePlugin -> Extension:Math
    q#s/%\$(.*?)\$%/<math>$1</math>/#,

    # DirectedGraphPlugin -> Extension:GraphViz
    q#s/<(\/?)dot>/<$1graphviz>/g#,
    
    # 
    # Links 
    # 
    q%s/\[\[(https?\:.*?)\]\[(.*?)\]\]/\[$1 $2\]/g%, # external link [[http:...][label]] 
    q%s/\[\[([^\]]*)\]\]/makeLink(makeWikiWord($1),$1)/ge%, # [[link]] -> link
    q%s/\[\[([^\]]*)\]\[(.*?)\]\]/makeLink($1,$2)/ge%, # [[link][text]] -> link

    # 
    # Wiki Tags 
    # 
    q#s/<(\/?)verbatim>/<$1nowiki>/g#, # update verbatim tag. 
    q#s/([A-Z][a-z]+[A-Z][A-Za-z]*:)/<nop>$1/g#, # avoid auto-linking InterWiki links
    q#s/$web\.([A-Z][a-z]+[A-Z][A-Za-z]*)/makeLink($1)/ge#, # $web.WikiWord -> link
    q#s/([A-Z][A-Za-z0-9]*)\.([A-Z][a-z]+[A-Z][A-Za-z]*)/<nop>$1.<nop>$2/g#, # OtherWebName.WikiWord -> <nop>OtherWebName.<nop>WikiWord
    q#s/<nop>([A-Z]{1}\w+?[A-Z]{1})/!$1/g#, # change <nop> to ! in front of Twiki words. 
    q#s/(?<[\s\[\(!])\b([A-Z][a-z]+[A-Z][A-Za-z]*)/makeLink($1,spaceWikiWord($1))/ge#, # WikiWord -> link
    q#s/!([A-Z]{1}\w+?[A-Z]{1})/$1/g#, # remove ! in front of Twiki words.
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

    # Lookup variable
    q#s/%([A-Z]+)%/getTwikiVar($1,'')/ge#,
    q#s/%([A-Z]+)(\{.*?\})%/getTwikiVar($1,$2)/ge#
    
    );

# Variables and pages to ignore
my @ignoredVars = qw(ADDTOHEAD ALLOWLOGINNAME ALLVARIABLES AUTHREALM BASETOPIC BASEWEB CALENDAR CHARSET COMMENT CONTENTMODE CRYPTTOKEN DEFAULTURLHOST DISKID EDITFORMFIELD ENCODE ENDSECTION ENTITY ENV FORMFIELD GMTIME GROUPS HEADLINES HIDE HIDEINPRINT HOMETOPIC HTTP HTTPS HTTP_HOST IF INCLUDINGTOPIC INCLUDINGWEB INTURLENCODE LABLOG LANG LANGUAGE LANGUAGES LOCALSITEPREFS MAKETEXT MDREPO METASEARCH NOFOLLOW NOP NOTIFYTOPIC PARENTTOPIC PLUGINVERSION QUERYPARAMS QUERYSTRING REDIRECT RELATIVETOPICPATH REMOTE_ADDR REMOTE_PORT REMOTE_USER RENDERHEAD REVARG REVINFO REVTITLE SCRIPTNAME SCRIPTSUFFIX SCRIPTURL SCRIPTURLPATH SEARCH SEP SERVERTIME SESSIONLOGON SITESTATISTICSTOPIC SPACEOUT STARTSECTION STATISTICSTOPIC SYSTEMWEB TABLE TGPOPUP TOC TOPICLIST TOPICMAP TOPICTITLE TRASHWEB TWIKIADMINLOGIN URLENCODE URLPARAM USERINFO USERNAME USERPREFSTOPIC USERSWEB VAR VARIABLES WEBLIST WEBPREFSTOPIC WIKINAME WIKIPREFSTOPIC WIKIUSERNAME WIKIUSERSTOPIC WIKIVERSION WIKIWEBMASTER WIKIWEBMASTERNAME);
my %ignoreVar = map (($_ => 1), @ignoredVars);

my @ignoredPages = qw(AllAuthUsersGroup AllUsersGroup ChangeProfilePicture NobodyGroup PatternSkinUserViewTemplate TWikiAdminGroup TWikiAdminUser TWikiContributor TWikiGroups TWikiGroupTemplate TWikiGuest TWikiPreferences TWikiRegistration TWikiRegistrationAgent TWikiUsers TWikiVariables UnknownUser UserListByDateJoined UserListByLocation UserListHeader UserList UserProfileHeader UserViewTemplate WebAtom WebChanges WebCreateNewTopic WebHome WebIndex WebLeftBar WebNotify WebPreferences WebRss WebSearchAdvanced WebSearchAttachments WebSearch WebStatistics WebTopicList WebTopMenu);
my %ignorePage = map (($_ => 1), @ignoredPages);

# TODO: implement...
# ICON ICONURL ICONURLPATH

grep (parseTwikiVars($_), @varFiles);
my %twikiVarBase = %twikiVar;

my @found;
for my $twikiFile (@twikiFiles) {
    if ($ignorePage{getStub($twikiFile)}) {
	warn "Ignoring TWiki page $twikiFile\n" if $verbose;
    } elsif (-e $twikiFile) {
	push @found, $twikiFile;
    } else {
	warn "Can't find $twikiFile\n";
	next;
    }
}
@twikiFiles = @found;

# Delete
if ($deletePages) {
    my $tmp = File::Temp->new();
    print $tmp map (getStub($_)."\n", @twikiFiles);
    if ($renamePages) {
	print $tmp map (spaceWikiWord(getStub($_))."\n", @twikiFiles);
    }
    close $tmp;
    my $tmpFilename = $tmp->filename;
	run_maintenance_script ("$deleteScript $tmpFilename");
}

# Convert
for my $twikiFile (@twikiFiles) {
    warn "Processing $twikiFile\n" if $verbose;
    # Get file & dir names
    my $twikiFileDir = dirname(abs_path($twikiFile));
    my $stub = getStub($twikiFile);
    my $mediawikiFile = abs_path($outdir) . '/' . $stub;

    # Reset page-specific globals
    $author = $date = undef;
    $topic = $stub;
    %twikiVar = %twikiVarBase;

    # Parse prefs files unless -data was specified (in which case we've already parsed them)
    unless ($dataDir) {
	grep (parseTwikiVars($_), getTwikiPrefsFiles($twikiFileDir));
    }

    # Open input & output files
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
	    printMediawiki ("|}\n\n"); 
	    $convertingTable = 0; 
	} 
	# 
	# Handle Tables 
	# * todo: Convert to multi-line regular expression 
	# as table data doesn't get run through the list of rules currently 
	# 
	if (/\|/) { 	# Is this the first row of the table? If so, add header 
	    if (!$convertingTable) { 
		printMediawiki ("{| border=\"1\"\n"); 
		$convertingTable = 1; 
	    } 		# start new row 
	    printMediawiki ("|-\n"); 
	    my $arAnswer = $_; 
	    $arAnswer =~ s/\|$//; 		#remove end pipe. 
	    $arAnswer =~ s/(.)\|(.)/$1\|\|$2/g; 		#Change single pipe to double pipe. 
	    my $text = _translateText($arAnswer); 
	    printMediawiki ("$text\n"); 
	    # 
	    # Handle blank lines.. 
	    # 
	} 
	elsif (/^$/) { 
	    printMediawiki ("$_\n");
	    # 
	    # Handle anything else... 
	    # 
	} 
	else { 
	    my $text = _translateText($_); 
	    printMediawiki ("$text\n"); 
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

    # Do Mediawiki import
    if ($importPages) {
	my $mwUser = ($user or $author);
	if ($useStdout) { system "cat $mediawikiFile" }
	run_maintenance_script ("$importScript --bot --overwrite --user='$mwUser' --summary='$summary' $use_timestamp");
	unlink($mediawikiFile) unless $keepPageFiles;
    }
}

# Rename
if ($renamePages) {
    my $tmp = File::Temp->new();
    print $tmp map ($_."|".spaceWikiWord($_)."\n", map (getStub($_), @twikiFiles));
    close $tmp;
    my $tmpFilename = $tmp->filename;
    run_maintenance_script ("$moveScript --r='Rename from TWiki to MediaWiki style' $tmpFilename");
}

# Upload
if ($uploadAttachments && (@attachments || @linkedAttachments)) {

    # Try to find attachment directory, if relevant
    my $twikiPubDir;
    if (defined $pubDir) {
	$twikiPubDir = $pubDir;
    } else {
	# try to guess the TWiki pub directory
	$twikiPubDir = abs_path(dirname(abs_path($twikiFiles[0]))."/../../pub");
    }

    unless (-d $twikiPubDir) {
	warn "TWiki pub directory not found: $twikiPubDir\n";
    } else {
	# Auto-add any linked attachments
	my %gotWebTopicFile;
	for my $info (@attachments) { ++$gotWebTopicFile{"$info->{web} $info->{topic} $info->{name}"} }
	for my $info (@linkedAttachments) {
	    unless ($gotWebTopicFile{"$info->{web} $info->{topic} $info->{name}"}++) {
		push @attachments, $info;
	    }
	}

	# Upload
	my %uploaded;
	for my $info (@attachments) {
	    my $attachName = $info->{name};
	    my $attachWeb = $info->{web};
	    my $attachTopic = $info->{topic};
	    my $path = "$twikiPubDir/$attachWeb/$attachTopic/$attachName";
	    unless (-e $path) {
		warn "Attachment not found: $path\n";
	    } else {
		my $tempdir = File::Temp->newdir();
		my $filename = "$attachTopic.$attachName";  # we include the topic but not the web name in the autogenerated attachment filename, so we need to check for duplicates
		warn "Duplicate attachment file $filename\n" if $uploaded{$filename}++;
		system "cp $path $tempdir/$filename";
		my $extensions = "";
		if ($attachName =~ /\.([^\.]+)$/) { $extensions = "--extensions=" . $1 }
		my $comment = $info->{comment};
		my $epoch = $info->{date} || time();
		my $dt = DateTime->from_epoch( epoch => $epoch );
		my $mwDate = $dt->ymd('') . $dt->hms('');
		my $mwUser = ($user or (defined($info->{user}) ? spaceWikiWord($info->{user}) : undef));
		my $userArg = defined($mwUser) ? "--user='$mwUser'" : "";
		my $commentArg = defined($comment) ? "--comment='$comment'" : "";
		warn "Uploading $filename\n" if $verbose;
		run_maintenance_script ("$uploadScript $extensions --overwrite $userArg $commentArg --summary='$summary' --timestamp=$mwDate $tempdir");
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
	$currentText = $text;  # for errors/warnings
	eval( "\$text =~ $rule;" ); 
    } 
    return $text; 
} 
# ================================================================

sub makeLink {
    my ($link, $text) = @_;
    return $link =~ /^[A-Za-z0-9\.]+$/ ? makeInternalLink($link,$text) : makeExternalLink($link,$text);
}

sub makeInternalLink {
    my ($link, $text) = @_;
    if ($renamePages) { $link = spaceWikiWord($link) }
    $text = $text || $link;
    return ($link eq $text) ? "[[<nop>$link]]" : "[[<nop>$link|<nop>$text]]";
}

sub makeExternalLink {
    my ($link, $text) = @_;
    $text = $text || $link;
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
    my ($info, $web, $topic) = @_;
    if ($uploadAttachments) {
	my %info = ('web' => $web, 'topic' => $topic);
	while ($info =~ /([a-z]+)="(.*?)"/g) { $info{$1} = $2 }
	push @attachments, \%info;
    }
    return "";
}

sub attachmentLink {
    my ($web, $topic, $name) = @_;
    push @linkedAttachments, {'name' => $name, 'web' => $web, 'topic' => $topic};
    return attachmentLinkPrefix($web,$topic) . $name;
}

sub attachmentLinkPrefix {
    my ($web, $topic) = @_;
    return "Media:$topic.";
}

sub run_maintenance_script {
    my ($script) = @_;
    my $cmd = "$php $script";
    warn "$cmd\n";
    unless ($dryRun) {
	system "cd $mwdir/maintenance; $cmd";
    }
}

sub setTwikiVar {
    my ($var, $def) = @_;
    $twikiVar{$var} = $def;
    warn "Set $var = $def\n" if $verbose;
    return "";
}

sub getTwikiVar {
    my ($var, $args) = @_;
    my $ret;
    if (exists $twikiVar{$var}) {
	$ret = _translateText($twikiVar{$var});
    } elsif ($ignoreVar{$var}) {
	$ret = "";
    } else {
	my $orig = "\%$var$args\%";
	unless ($warned{$orig}++) {
	    warn "Unknown variable: $orig\t($topic)\n";
	    warn " Source:\t$_\nCurrent:\t$currentText\n" if $verbose;
	}
	$ret = $orig;
    }
    return $ret;
}

sub parseTwikiVars {
    my ($twikiVarFile) = @_;
    unless (-e $twikiVarFile) {
	warn "Can't find $twikiVarFile\n";
	next;
    }
    warn "Reading variable definitions from $twikiVarFile\n" if $verbose;

    open(TWIKI,"<$twikiVarFile") or die("unable to open $twikiVarFile - $!");
    while (<TWIKI>) {
	if (/\* +Set +([A-Za-z]+) += +(.*)/) {
	    setTwikiVar($1,$2);
	}
    }
    close(TWIKI);
}

sub getTwikiPrefsFiles {
    my ($dir) = @_;
    return map ((-e) ? abs_path($_) : (),
		"$dir/../TWiki/TWikiPreferences.txt",
		"$dir/TWikiPreferences.txt",
		"$dir/WebPreferences.txt");
}
    
sub printMediawiki {
    my (@text) = @_;
    unless ($dryRun && !$useStdout) {
	print MEDIAWIKI @text;
    }
}

sub getStub {
    my ($twikiFile) = @_;
    my $stub = basename($twikiFile);
    $stub =~ s/.txt$//;
    return $stub;
}

1;
