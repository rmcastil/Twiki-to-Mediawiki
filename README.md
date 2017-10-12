[![Build Status](https://travis-ci.org/ihh/Twiki-to-Mediawiki.svg?branch=master)](https://travis-ci.org/ihh/Twiki-to-Mediawiki)

Summary
-------

Run `twiki2mediawiki.pl` to convert a TWiki web to MediaWiki.
- Process individual TWiki `.txt` files, or trawl through entire data directory
    - Special TWiki pages are ignored (TWikiPreferences, WebStatistics, etc.)
- Save the MediaWiki files locally, or import them using [importTextFiles.php](https://www.mediawiki.org/wiki/Manual:ImportTextFiles.php)
    - Optionally delete pages from database (e.g. to undo previous import) using [deleteBatch.php](https://www.mediawiki.org/wiki/Manual:DeleteBatch.php)
    - Optionally rename to Mediawiki-style links using [moveBatch.php](https://www.mediawiki.org/wiki/Manual:MoveBatch.php)
- Optionally import attachments using [importImages.php](https://www.mediawiki.org/wiki/Manual:ImportImages.php)
    - Optionally delete old versions first using [deleteBatch.php](https://www.mediawiki.org/wiki/Manual:DeleteBatch.php)
    - Attachments from other pages & webs are automatically included
- Optionally import all your InterWiki links (uses the bundled [addInterwiki.php](https://github.com/ihh/Twiki-to-Mediawiki/blob/master/addInterwiki.php) maintenance script)
- Preserves timestamps (but not revision history) and usernames (but doesn't create users)
- Converts most formatting including lists & tables
- Converts some built-in TWiki variables including e.g. `%TOPIC%`, `%INCLUDE%`, `%ICON%`, `%ATTACHURL%`, `%DATE%`
- Handles TWiki variables that are defined in the page, or in TWikiPreferences or WebPreferences
- Includes some mappings from TWiki plugins to Mediawiki extensions:
    - Converts [EFetchPlugin](http://twiki.org/cgi-bin/view/Plugins/EFetchPlugin) to [Extension:PubmedParser](https://www.mediawiki.org/wiki/Extension:PubmedParser)
    - Converts [LatexModePlugin](http://twiki.org/cgi-bin/view/Plugins/LatexModePlugin) to [Extension:Math](https://www.mediawiki.org/wiki/Extension:Math)
    - Converts [DirectedGraphPlugin](http://twiki.org/cgi-bin/view/Plugins/DirectedGraphPlugin) to [Extension:GraphViz](https://www.mediawiki.org/wiki/Extension:GraphViz)

For help/options: `twiki2mediawiki.pl -h`

Installation
------------

Requires:
- Perl

Run the tests: `make test`

License
-------

This program (like the original twiki2mediawiki.pl source, and @rmcastil's derivative) are under the GPL license.

The original sources can be found here:
- https://github.com/rmcastil/Twiki-to-Mediawiki
- http://it.toolbox.com/wiki/index.php/Twiki2mediawiki

Disclaimers
-----------

There are no guarantees made about this software, and it will not be supported for free.

Use at your own risk, and be prepared for some rough edges.
The conversion will almost certainly be flawed, and you may need to iterate a few times, fixing bugs as you go.
I found it helpful to keep both TWiki and MediaWiki up in parallel during the migration, editing the TWiki pages to fix some glitches and editing this software to fix others.

This code should not be seen as a statement of wiki-engine advocacy.
TWiki has given me great service over the years, and the community is helpful.
However, sometimes you have to move.
My hope is that the possibility of an easier migration to Mediawiki will ultimately make TWiki itself more appealing, as well as rescuing content from some TWikis that might otherwise be abandoned.
