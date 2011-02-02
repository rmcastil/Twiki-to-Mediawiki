#!/usr/bin/perl -w 
# ================================================================ 
# 
# Perl script to covert Twiki files to MediaWiki format. 
# ( http://wiki.ittoolbox.com/index.php/Code:Twiki2mediawiki ) 
# 
# Copyright (C) 2006-2008 Authors: Anonymous, Betsy_Maz, bcmfh, Kevin Welker 
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
# Output goes to stdout. 
# 
# Todo: 
# * Convert from MediaWiki to TWiki. 
# * Support additional Twiki tags. 
# * Consider getting conversion rules straight from 
# TWiki::Plugins::EditSyntaxPlugin's rule's page instead of duplicating 
# them within in this code. 
# 
# ================================================================ 
use strict; 
# List of rules to convert twiki lines to mediawiki, many/most 
# borrowed from TWiki::Plugins::EditSyntaxPlugin. 
# 
# See http://twiki.org/cgi-bin/view/Plugins/MediawikiEditSyntaxRegex 
# 
# *Quoting with a percent ("%") or hash ("#") sign. 
# 
my @rules= ( 
	# 
	# Wiki Tags 
	# 
	q#s/^%TOC%//g#, # Remove Table of contents 
	q#s/^%META.*//g#, # Remove meta tags 
	q#s/<(\/?)verbatim>/<$1nowiki>/g#, # update verbatim tag. 
	q#s/\!([A-Z]{1}\w+?[A-Z]{1})/$1/g#, # remove ! from Twiki words. 
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
	# Links 
	# 
	q%s/\[\[(https?\:.*?)\]\[(.*?)\]\]/\[$1 $2\]/g%, # external link [[http:...][label]] 
	q%s/\[\[([^\]]*)\]\]/\[\[$1\|$1\]\]/g%, # internal link [[WikiWord][WikiWord]] 
	q%s/\[\[([^\]]*)\]\[(.*?)\]\]/\[\[$1\|$2\]\]/g%, # internal link [[WikiWord][label]] 
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
	q%s/(^|[\n\r])[ ]{3}\$ ([^\:]*)/$1\; $2 /g% # $ definition: term 
	); 
	
my $f_szFile=shift; 
my $convertingTable = 0; 

# are we in the middle of a table conversion. 
# ================================================================ 
open(TWIKI,"<$f_szFile") or die("unable to open $f_szFile - $!"); 
while(<TWIKI>) { 
	chomp; 
	# 
	# Handle Table Endings 
	# 
	if ($convertingTable && /^[^\|]/) { 
		print ("|}\n\n"); 
		$convertingTable = 0; 
	} 
	# 
	# Handle Tables 
	# * todo: Convert to multi-line regular expression 
	# as table data doesn't get run through the list of rules currently 
	# 
	if (/\|/) { 	# Is this the first row of the table? If so, add header 
		if (!$convertingTable) { 
			print "{| border=\"1\"\n"; 
			$convertingTable = 1; 
		} 		# start new row 
		print "|-\n"; 
		my $arAnswer = $_; 
		$arAnswer =~ s/\|$//; 		#remove end pipe. 
		$arAnswer =~ s/(.)\|(.)/$1\|\|$2/g; 		#Change single pipe to double pipe. 
		my $text = _translateText($arAnswer); 
		print "$text\n"; 
		# 
		# Handle blank lines.. 
		# 
	} 
	elsif (/^$/) { 
		print"$_\n"; 
		# 
		# Handle anything else... 
		# 
	} 
	else { 
		my $text = _translateText($_); 
		print "$text\n"; 
	}
} # end while. 
close(TWIKI); 
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
1;