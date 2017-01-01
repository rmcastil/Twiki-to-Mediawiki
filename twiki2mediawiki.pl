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
use Encode;

# Options that are disabled/empty by default
my ($verbose,
    $dataDir,
    $outDir,
    $pubDir,
    $useStdout,
    @varFiles,
    $deletePages,
    $importPages,
    $renamePages,
    $keepPageFiles,
    $user,
    $wwwUser,
    $uploadAttachments,
    $deleteAttachments,
    $dryRun);

# Mediawiki globals & options
my $mwDir = "/var/www/wiki";
my $php = "php";
my $summary = "Imported from TWiki";

my $importScript = "importTextFiles.php";
my $uploadScript = "importImages.php";
my $moveScript = "moveBatch.php";
my $deleteScript = "deleteBatch.php";

# TWiki globals
my $web = "Main";

# Other globals
my $tmpRootDir = "/tmp";

# Parse command line
my $usage = "Usage: $0 [OPTIONS] <TWiki file(s)>\n"
    . " -data <dir>     Convert all .txt files in directory\n"
    . " -out <dir>      Output directory\n"
    . " -stdout         Print to stdout instead of file\n"
    . " -vars <file>    Parse TWiki variable definitions from file\n"
    . " -delete         Delete pages using $deleteScript\n"
    . " -import         Import pages with $importScript\n"
    . " -pub <dir>      Location of TWiki pub dir (default datadir/../../pub)\n"
    . " -rename         Rename (CamelCase -> Camel_Case) using $moveScript\n"
    . " -keep           Keep MediaWiki file after import\n"
    . " -user <name>    Username for import (overrides TWiki author)\n"
    . " -summary <desc> Summary of edit (default '$summary')\n"
    . " -mw <dir>       Location of MediaWiki (default '$mwDir')\n"
    . " -unattach       Delete attachments with $deleteScript\n"
    . " -attach         Upload attachments with $uploadScript\n"
    . " -replace        Shorthand for '-delete -import -rename'\n"
    . " -reattach       Shorthand for '-unattach -attach'\n"
    . " -renew          Shorthand for '-replace -reattach'\n"
    . " -wwwuser <user> httpd user (e.g. apache, www-data)\n"
    . " -dryrun         Don't run MediaWiki scripts or save files\n"
    . " -verbose        Print more stuff\n"
    ;

GetOptions ("data=s" => \$dataDir,
	    "pub=s" => \$pubDir,
	    "out=s" => \$outDir,
	    "stdout" => \$useStdout,
	    "vars=s" => \@varFiles,
	    "delete" => \$deletePages,
	    "rename" => \$renamePages,
	    "import" => \$importPages,
	    "keep" => \$keepPageFiles,
	    "user=s" => \$user,
	    "summary=s" => \$summary,
	    "mw=s" => \$mwDir,
	    "attach" => \$uploadAttachments,
	    "unattach" => \$deleteAttachments,
	    "replace" => sub { $deletePages = $importPages = $renamePages = 1},
	    "reattach" => sub { $deleteAttachments = $uploadAttachments = 1},
	    "renew" => sub { $deletePages = $importPages = $renamePages = $deleteAttachments = $uploadAttachments = 1},
	    "wwwuser=s" => \$wwwUser,
	    "dryrun" => \$dryRun,
	    "verbose" => \$verbose)
  or die("Error in command line arguments\n" . $usage);
die $usage unless @ARGV or $dataDir;

my $no_file = ($useStdout && !$importPages) || ($dryRun && !$keepPageFiles);
$outDir = "." if !defined($outDir) && !$importPages && !$dryRun && !$useStdout;

# Build list of files
my @twikiFiles;
if ($dataDir) {
    opendir DIR, $dataDir or die "Couldn't open $dataDir: $!";
    @twikiFiles = map ("$dataDir/$_", grep (/\.txt$/, sort {$a cmp $b} readdir(DIR)));
    closedir DIR;
    push @varFiles, getTwikiPrefsFiles($dataDir);
    $web = basename($dataDir);
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
my ($topic, $author, $date, @attachments, @linkedAttachments, %twikiVar, %warned, $currentText, %pageNonempty);  # global variables used by parser
my @rules= ( 

    # Remove variable-setting lines (they will already have been parsed)
    q#/^\* +Set +([A-Za-z]+) += +(.*)//#,

    # %TOPIC% and %SPACEDTOPIC%
    q#s/%TOPIC%/$topic/g#,
    q#s/%SPACEDTOPIC%/spaceWikiWord($topic)/ge#,

    # %WEB%, %MAINWEB%, %TWIKIWEB%
    q#s/%WEB%/$web/g#,
    q#s/%MAINWEB%/Main/g#,
    q#s/%TWIKIWEB%/TWiki/g#,

    # ICON
    q#s/%ICON{\"?(.+?)\"?}%/<img src="%ICONURLPATH{$1}%"\/>/g#,   # will get expanded again by %ICONURLPATH% rule
    q#s/%ICONURL{\"?(.+?)\"?}%/%ICONURLPATH{$1}%/g#,   # will get expanded again by %ICONURLPATH% rule
    q#s/%ICONURLPATH{\"?(.+?)\"?}%/%PUBURL%\/TWiki\/TWikiDocGraphics\/$1.gif/g#,   # will get expanded again by %PUBURL% rule

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
    q#s/%INCLUDE\{"?$web\.(.*?)"?\}%/{{:<nop>$1}}/g#, # %INCLUDE{$web.XXX}% --> {{XXX}}
    q#s/%INCLUDE\{"?(.*?)"?\}%/{{:<nop>$1}}/g#, # %INCLUDE{XXX}% --> {{XXX}}
    q#s/%INCLUDE\{.*?\}%//g#, # remove remaining %INCLUDE{...}%'s
    q#s/%STARTINCLUDE%/<onlyinclude>/#,
    q#s/%STOPINCLUDE%/<\/onlyinclude>/#,

    # %REDIRECT%
    q@s/%REDIRECT{"$web.(\S+?)"}%.*/"#REDIRECT ".makeInternalLink($1)/e@,
    q@s/%REDIRECT{"?(\S+?)"?}%.*/"#REDIRECT ".makeInternalLink($1)/e@,
    q@s/%REDIRECT.*?%//@,

    # Remove some tags with quirky patterns
    q#s/%A_\w+%//g#,
    q#s/%PARAM\d+%//g#,
    q#s/%POS:(.*?)%//g#,
    q#s/%SECTION\d+%//g#,
    q#s/%TMPL:[A-Z]+{.*?}%//g#,

    # EfetchPlugin -> Extension:PubmedParser
    q@s/%PMID[LC]?\{\s*(\S+?)\s*\}%/{{\#pmid:$1}}/g@,
    q@s/%PMIDL\{.*?pmid="?(\d+)"?.*?\}%/{{\#pmid:$1}}/g@,
    
    # LatexModePlugin -> Extension:Math
    q#s/%\$(.*?)\$%/<math>$1<\/math>/g#,

    # DirectedGraphPlugin -> Extension:GraphViz
    q#s/<(\/?)dot>/<$1graphviz>/g#,

    # Anchors
    q%s/^\s*#(\S+)\s*$/<div id="<nop>$1"><\/div>/g%,  # replace anchors with empty div's
    
    # 
    # Links 
    # 
    q%s/\[\[(https?\:.*?)\]\[(.*?)\]\]/makeLink($1,$2)/ge%, # external link [[http(s):...][label]] 
    q%s/\[\[(ftp\:.*?)\]\[(.*?)\]\]/makeLink($1,$2)/ge%, # external link [[ftp:...][label]] 
    q%s/\[\[([^\]<>]*)\]\]/makeLink(makeWikiWord($1),$1)/ge%, # [[link]] -> link
    q%s/\[\[([^\]<>]*)\]\[(.*?)\]\]/makeLink($1,$2)/ge%, # [[link][text]] -> link
    q%s/<a.*?href="(.*?)".*?>\s*(.*?)\s*<\/a>/makeLink($1,$2)/ge%, # external link

    # 
    # Wiki Tags 
    # 
    q#s/<(\/?)verbatim>/<$1nowiki>/g#, # update verbatim tag. 
    q#s/(?<=[\s\(])([A-Z][A-Za-z0-9]+):((?:'[^']*')|(?:\"[^\"]*\")|(?:[A-Za-z0-9\_\~\%\/][A-Za-z0-9\.\/\+\_\~\,\&\;\:\=\!\?\%\#\@\-]*))/makeLink("$1:$2")/ge#,  # InterWiki links
    q#s/(?<=[\s\(])([A-Z][A-Za-z0-9]+):((?:'[^']*')|(?:\"[^\"]*\")|(?:[A-Za-z0-9\_\~\%\/][A-Za-z0-9\.\/\+\_\~\,\&\;\:\=\!\?\%\#\@\-]*))/<nop>$1:$2/g#,  # avoid linking remaining InterWiki links
    q#s/$web\.([A-Z][a-z]+[A-Z][A-Za-z]*)/makeLink($1)/ge#, # $web.WikiWord -> link
    q#s/([A-Z][A-Za-z0-9]*)\.([A-Z][a-z]+[A-Z][A-Za-z]*)/<nop>$1.<nop>$2/g#, # OtherWebName.WikiWord -> <nop>OtherWebName.<nop>WikiWord
    q#s/<nop>([A-Z]{1}\w+?[A-Z]{1})/!$1/g#, # change <nop> to ! in front of Twiki words. 
    q#s/(?<![\!:])\b([A-Z][a-z]+[A-Z][A-Za-z]*)/makeLink($1,spaceWikiWord($1))/ge#, # WikiWord -> link
    q#s/!([A-Z]{1}\w+?[A-Z]{1})/$1/g#, # remove ! in front of Twiki words.
    q#s/<nop>//g#, # remove <nop>

    # Images (attachments only) and links wrapped around images
    q#s/<img .*?src="Media:(.+?)".*?\/>/[[File:$1]]/g#,  # inline images
    q#s/\[\[\s*(.+?)\s*\|\s*\[\[File:(.*?)\]\]\s*\]\]/[[File:$2|link=$1]]/g#,  # external links around images
    q#s/\[\s*(.+?)\s+\[\[File:(.*?)\]\]\s*\]/[[File:$2|link=$1]]/g#,  # internal links around images

    # 
    # Formatting 
    # 
    q%s/(^|[\s\(])\*(\S+?|\S[^\n]*?\S)\*($|(?=[\s\)\.\,\:\;\!\?]))/$1'''$2'''/g%, # bold 
    q%s/(^|[\s\(])\_\_(\S+?|\S[^\n]*?\S)\_\_($|(?=[\s\)\.\,\:\;\!\?]))/$1''<b>$2<\/b>''/g%, # italic bold 
    q%s/(^|[\s\(])\_(\S+?|\S[^\n]*?\S)\_($|(?=[\s\)\.\,\:\;\!\?]))/$1''$2''/g%, # italic 
    q%s/(^|[\s\(])==(\S+?|\S[^\n]*?\S)==($|(?=[\s\)\.\,\:\;\!\?]))/$1'''<tt>$2<\/tt>'''/g%, # monospaced bold 
    q%s/(^|[\s\(])=(\S+?|\S[^\n]*?\S)=($|(?=[\s\)\.\,\:\;\!\?]))/$1<tt>$2<\/tt>/g%, # monospaced 
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
my @ignoredVars = qw(ACTIVATEDPLUGINS ADDTOHEAD ALLOWLOGINNAME ALLVARIABLES A_TITLE ATTACHTABLE ATTACHURL AUTHENTICATED AUTHOR AUTHREALM A_VALUE BACKUPRESTORE BASE_REV BASETOPIC BASEWEB BLACKLISTPLUGIN BR BUTTON CALC CALCULATE CALENDAR CANLOGIN CHARSET CLEAR CMD COLORPICKER COMMENT COMMENTFORMEND COMMENTFORMSTART COMMENTPROMPT CONTENTMODE CRYPTTOKEN CS CUR_REV CURRREV DATE DATEPICKER DEFAULTURLHOST DET DISABLED DISKID DONTNOTIFYCHECKBOX EDITACTION EDITCELL EDITFORMFIELD EDITPREFERENCES EMAILADDRESS EMAIL_FROM EMAIL_OUTPUT EMAILTO EMAIL_TO ENCODE ENDSECTION ENDTAB ENDTABPANE ENDTWISTY ENDTWISTYTOGGLE ENTITY ENV EXAMPLEVAR EXEC FAILEDPLUGINS FILECOMMENT FILENAME FILEPATH FILEUSER FIRSTLASTNAME FORCENEWREVISIONCHECKBOX FORMFIELD FORMFIELDS FORMLIST FORMTEMPLATE FORMTITLE GET GLOBAL_SEARCH GMTIME GROUPS HEADLINES HIDDENTEXT HIDE HIDEFILE HIDEINPRINT HOMETOPIC HTML_TEXT HTTP HTTP_HOST HTTPS IF INCLUDINGTOPIC INCLUDINGWEB INSTANTIATE INTRODUCTION INTURLENCODE JAVASCRIPT_TEXT JQBUTTON JQCLEAR JQENDTAB JQENDTABPANE JQIMAGESURLPATH JQSCRIPT JQTAB JQTABPANE JQTHEME JQTOGGLE LABLOG LANG LANGUAGE LANGUAGES LASTDATE LOCAL_SEARCH LOCALSITEPREFS LOGIN LOGINNAME LOGINURL LOGOUT LOGOUTURL MAKETEXT MATHMODE MAXREV MDREPO MESSAGE METAPREFERENCES METASEARCH MOVE_LOCKED NEW_PARENTWEB NEW_SUBWEB NEWTOPIC NEW_TOPIC NEW_WEB NOFOLLOW NONWIKIWORDFLAG NOP NOTIFYTOPIC NTOPICS ORIGINALREV OTOPIC OWEB PARENTTOPIC PASSWORD PLAIN_TEXT PLUGINDESCRIPTIONS PLUGINVERSION PMID PMIDC PMIDL PUBURL QUERYPARAMS QUERYPARAMSTRING QUERYSTRING REDIRECTTO REF_DENIED REF_LOCKED RELATIVETOPICPATH REMOTE_ADDR REMOTE_PORT REMOTE_USER RENAMEWEB_SUBMIT RENDERHEAD RENDERLIST RESULT REVARG REVINFO REVINFO1 REVINFO2 REVISION REVISIONS REVTITLE REVTITLE1 REVTITLE2 ROWEXTRA ROWTITLE ROWVALUE SCRIPTNAME SCRIPTSUFFIX SCRIPTURL SCRIPTURLPATH SEARCH SEARCHSTRING SEP SERVERTIME SESSIONLOGON SESSION_VARIABLE SET SETGETDUMP SITESTATISTICSTOPIC SKINSELECT SLIDECOMMENT SLIDEMAX SLIDENAV SLIDENAVALL SLIDENAVFIRST SLIDENAVLAST SLIDENAVNEXT SLIDENAVPREV SLIDENUM SLIDESHOW SLIDETEXT SLIDETITLE SMILIES SPACEOUT STARTSECTION STATISTICSTOPIC SYSTEMWEB TAB TABLE TABPANE TAGME TAGMEPLUGIN_USER_AGNOSTIC TAIL TEMPLATETOPIC TEXT TEXTHEAD TGPOPUP TIME TOC TOGGLE TOPICLIST TOPICMAP TOPICNAME TOPICPARENT TOPICTITLE TRASHWEB TWIKIADMINLOGIN TWISTY TWISTYBUTTON TWISTYHIDE TWISTYSHOW TWISTYTOGGLE UNENCODED_TEXT URLENCODE URLPARAM USERINFO USERMANAGER USERNAME USERPREFSTOPIC USERSWEB VAR VARIABLES VERIFICATIONCODE WATCHCHANGESTEXT WATCHDATE WATCHLIST WATCHLISTTO WATCHLISTUSER WATCHREV WATCHTITLE WATCHTOPIC WATCHUSER WATCHWEB WEBBGCOLOR WEBLIST WEBPREFSTOPIC WIKINAME WIKIPREFSTOPIC WIKISPAMWORD WIKITOOLNAME WIKIUSERNAME WIKIUSERSTOPIC WIKIVERSION WIKIWEBMASTER WIKIWEBMASTERNAME WYSIWYG_SECRET_ID WYSIWYG_TEXT);
my %ignoreVar = map (($_ => 1), @ignoredVars);

my @ignoredPages = qw(AllAuthUsersGroup AllUsersGroup ChangeProfilePicture NobodyGroup PatternSkinUserViewTemplate TWikiAdminGroup TWikiAdminUser TWikiAdminUserWatchlist TWikiContributor TWikiGroups TWikiGroupTemplate TWikiGuest TWikiPreferences TWikiRegistration TWikiRegistrationAgent TWikiUsers TWikiVariables UnknownUser UserListByDateJoined UserListByLocation UserListHeader UserList UserProfileHeader UserViewTemplate WebAtom WebChanges WebCreateNewTopic WebHome WebIndex WebLeftBar WebNotify WebPreferences WebRss WebSearchAdvanced WebSearchAttachments WebSearch WebStatistics WebTopicList WebTopMenu);
my %ignorePage = map (($_ => 1), @ignoredPages);

# TODO: implement...
# ICON ICONURL ICONURLPATH

grep (parseTwikiVars($_), @varFiles);
my %twikiVarBase = %twikiVar;

my @found;
for my $twikiFile (@twikiFiles) {
    unless ($twikiFile =~ /\.txt$/) {
	warn "Ignoring non-TWiki file $twikiFile\n";
    } elsif ($ignorePage{getStub($twikiFile)}) {
	warn "Ignoring TWiki page $twikiFile\n" if $verbose;
    } elsif (-e $twikiFile) {
	push @found, $twikiFile;
    } else {
	warn "Can't find $twikiFile\n";
    }
}
@twikiFiles = @found;

# Delete
if ($deletePages) {
    deletePages (map (getPageTitles($_), @twikiFiles));
}

# Create temp dir for pages, if appropriate
my $mwOutDir;
if ($outDir) {
    $mwOutDir = abs_path($outDir);
} else {
    $mwOutDir = createWorldReadableTempDir (CLEANUP => !$keepPageFiles);
}

# Convert
for my $twikiFile (@twikiFiles) {
    warn "Processing $twikiFile\n" if $verbose;
    # Get file & dir names
    my $twikiFileDir = dirname(abs_path($twikiFile));
    my $stub = getStub($twikiFile);
    my $mediawikiFile = "$mwOutDir/$stub";

    # Reset page-specific globals
    $author = $date = undef;
    $topic = $stub;
    %twikiVar = %twikiVarBase;

    # Parse prefs files unless -data was specified (in which case we've already parsed them)
    unless ($dataDir) {
	grep (parseTwikiVars($_), getTwikiPrefsFiles($twikiFileDir));
    }

    # Give the file a quick once-over for variable settings
    # since %META:PREFERENCE{...}% tags at the end of the file are retroactive
    parseTwikiVars ($twikiFile);

    # Open input file & initialize output array
    open(TWIKI,"<$twikiFile") or die("unable to open $twikiFile - $!"); 
    my @output;

    # Initialize state
    my $convertingTable = 0;  # are we in the middle of a table conversion?
    while(<TWIKI>) { 
	$_ = decode('Windows-1251', $_);
	chomp;
	# 
	# Handle Table Endings 
	# 
	if ($convertingTable && /^[^\|]/) { 
	    push @output, "|}\n\n"; 
	    $convertingTable = 0; 
	} 
	# 
	# Handle Tables 
	# * todo: Convert to multi-line regular expression 
	# as table data doesn't get run through the list of rules currently 
	# 
	if (/^\s*\|.*\|\s*$/) { 	# Is this the first row of the table? If so, add header 
	    if (!$convertingTable) { 
		push @output, "{| border=\"1\"\n"; 
		$convertingTable = 1; 
	    } 		# start new row 
	    push @output, "|-\n"; 
	    my $arAnswer = $_; 
	    $arAnswer =~ s/\|\s*$//; 		#remove end pipe. 
	    $arAnswer =~ s/(.)\|(.)/$1\|\|$2/g; 		#Change single pipe to double pipe. 
	    my $text = _translateText($arAnswer); 
	    push @output, "$text\n"; 
	    # 
	    # Handle blank lines.. 
	    # 
	} 
	elsif (/^$/) { 
	    push @output, "$_\n";
	    # 
	    # Handle anything else... 
	    # 
	} 
	else { 
	    my $text = _translateText($_); 
	    push @output, "$text\n"; 
	}
    } # end while. 
    close(TWIKI); 

    # close <onlyinclude> tag, if necessary
    my $gotStartInclude = grep (/<onlyinclude>/, @output);
    my $gotStopInclude = grep (/<\/onlyinclude>/, @output);
    if ($gotStartInclude && !$gotStopInclude) { push @output, "</onlyinclude>\n" }
    elsif (!$gotStartInclude && $gotStopInclude) { unshift @output, "<onlyinclude>\n" }

    # print output
    if ($no_file) {
	if ($useStdout) { binmode STDOUT, ":utf8"; print @output }
    } else {
	unless ($dryRun && !$useStdout && !$keepPageFiles) {
	    open(MEDIAWIKI,">$mediawikiFile") or die("unable to open $mediawikiFile - $!");
	    binmode MEDIAWIKI, ":utf8";	
	    print MEDIAWIKI @output;
	    close(MEDIAWIKI) or die("unable to close $mediawikiFile - $!");
	    if ($useStdout) { system "cat $mediawikiFile" }
	}
    }

    $pageNonempty{$stub} = grep /\S/, @output;
    
    # Change file timestamp
    my $use_timestamp = "";
    if ($date) {
	utime ($date, $date, $mediawikiFile);
	$use_timestamp = "--use-timestamp";
    }

    # Do Mediawiki import
    if ($importPages && $pageNonempty{$stub}) {
	my $mwUser = ($user or $author or "");
	my $userArg = length($mwUser) ? "--user='$mwUser'" : "";
	run_maintenance_script ("$importScript --bot --overwrite $userArg --summary='$summary' $use_timestamp", $mediawikiFile);
	unlink($mediawikiFile) unless $keepPageFiles;
    }
}

# Rename
if ($renamePages) {
    my @rename = map (spaceWikiWord($_) eq $_ ? () : ($_."|".spaceWikiWord($_)."\n"),
		      grep ($pageNonempty{$_},
			    map (getStub($_),
				 @twikiFiles)));
    if (@rename) {
	my $tmp = createWorldReadableTempFile();
	print $tmp @rename;
	close $tmp;
	run_maintenance_script ("$moveScript --r='Rename from TWiki to MediaWiki style'", $tmp->filename);
    } else {
	warn "No pages to rename\n";
    }
}

# Auto-add any linked attachments
my %gotWebTopicFile;
for my $info (@attachments) { ++$gotWebTopicFile{"$info->{web} $info->{topic} $info->{name}"} }
for my $info (@linkedAttachments) {
    unless ($gotWebTopicFile{"$info->{web} $info->{topic} $info->{name}"}++) {
	push @attachments, $info;
    }
}

# Delete attachments
if ($deleteAttachments && @attachments) {
    deletePages (map ("File:".makeAttachmentFilename ($_->{topic}, $_->{name}), @attachments));
}

# Upload attachments
if ($uploadAttachments && @attachments) {

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
		my $tempdir = createWorldReadableTempDir();
		my $filename = makeAttachmentFilename ($attachTopic, $attachName);
		# we include the topic but not the web name in the autogenerated attachment filename, so we need to check for duplicates
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
		run_maintenance_script ("$uploadScript $extensions --overwrite $userArg $commentArg --summary='$summary' --timestamp=$mwDate", $tempdir);
	    }
	}
    }
}

# Show location of page files
if ($keepPageFiles && !$outDir) {
    warn "Page files are in $mwOutDir\n";
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
    my $isAnchor = ($link =~ /^#/);
    my $isInternal = ($link =~ /^[A-Za-z0-9\.]+$/);
    my $isInterwiki = ($link =~ /([A-Z][A-Za-z0-9]+):((?:'[^']*')|(?:\"[^\"]*\")|(?:[A-Za-z0-9\_\~\%\/][A-Za-z0-9\.\/\+\_\~\,\&\;\:\=\!\?\%\#\@\-]*?))/);
    return ($isAnchor || $isInternal || $isInterwiki) ? makeInternalLink($link,$text) : makeExternalLink($link,$text);
}

sub makeInternalLink {
    my ($link, $text) = @_;
    $link =~ s/^$web\.//;
    if ($renamePages && $link =~ /^[A-Za-z0-9_]+$/) { $link = spaceWikiWord($link) }
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
    my %info = ('web' => $web, 'topic' => $topic);
    while ($info =~ /([a-z]+)="(.*?)"/g) { $info{$1} = $2 }
    unless ($info{'name'} =~ /^(graph|latex)[a-f0-9]{32}\.png$/) {  # skip attachments that look like they were made by MathModePlugin or DirectedGraphPlugin
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
    my ($script, $target) = @_;
    $target = "" unless $target;
    unless (defined $wwwUser) {
	$wwwUser = `ps -ef | egrep '(httpd|apache2|apache)' | grep -v \`whoami\` | grep -v root | head -n1 | awk '{print \$1}'`;
	chomp $wwwUser;
	warn "Guessing: -wwwuser $wwwUser\n" unless $wwwUser eq '0';
    }
    my $sudo = $wwwUser eq '0' ? "" : "sudo -u $wwwUser ";
    my $cmd = "$sudo$php $script $target";
    warn "$cmd\n";
    unless ($dryRun) {
	system "chmod -R a+r $target" if length $target;
	system "cd $mwDir/maintenance; $cmd";
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
	} elsif (/^%META:PREFERENCE{name="(.+?)".*type="Set".*value="(.*?)"/) {
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

sub getStub {
    my ($twikiFile) = @_;
    my $stub = basename($twikiFile);
    $stub =~ s/.txt$//;
    return $stub;
}

sub createWorldReadableTempFile {
    return File::Temp->new (DIR => $tmpRootDir);
}

sub createWorldReadableTempDir {
    my @opts = @_;
    my $tempdir = File::Temp->newdir (DIR => $tmpRootDir, @opts);
    system "chmod a+rx $tempdir";
    return $tempdir;
}

sub getPageTitles {
    my ($twikiFile) = @_;
    my $stub = getStub($twikiFile);
    return $renamePages ? ($stub, spaceWikiWord($stub)) : ($stub);
}

sub deletePages {
    my @pages = @_;
    my $tmp = createWorldReadableTempFile();
    print $tmp map ("$_\n", @pages);
    close $tmp;
    run_maintenance_script ($deleteScript, $tmp->filename);
}

sub makeAttachmentFilename {
    my ($attachTopic, $attachName) = @_;
    return "$attachTopic.$attachName";
}

1;
