Summary
-------

Run `twiki2mediawiki.pl` to convert a TWiki web to MediaWiki.
- Process individual TWiki `.txt` files, or trawl through entire data directory
    - Special TWiki pages are ignored (TWikiPreferences, WebStatistics, etc.)
- Save the MediaWiki files locally, or import them using [importTextFiles.php](https://www.mediawiki.org/wiki/Manual:ImportTextFiles.php)
    - Optionally delete pages from database (e.g. to undo previous import) using [deleteBatch.php](https://www.mediawiki.org/wiki/Manual:DeleteBatch.php)
    - Optionally rename to Mediawiki-style links using [moveBatch.php](https://www.mediawiki.org/wiki/Manual:MoveBatch.php)
- Optionally import attachments using [importImages.php](https://www.mediawiki.org/wiki/Manual:ImportImages.php)
    - Attachments from other pages & webs are automatically included
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
- [DateTime](http://search.cpan.org/~drolsky/DateTime-1.42/lib/DateTime.pm)

License
-------

This program (like the original twiki2mediawiki.pl source, and @rmcastil's derivative) are under the GPL license.

The original sources can be found here:
- https://github.com/rmcastil/Twiki-to-Mediawiki
- http://it.toolbox.com/wiki/index.php/Twiki2mediawiki

Disclaimers
-----------

This source is NOT thoroughly tested, and will not be supported. Use at your own risk. I needed a simple solution and this is what I came up with.

This code should not be seen as a statement of wiki-engine advocacy.
TWiki has given me great service over the years, and the community is helpful.
However, sometimes you have to move.
My hope is that easing migration to Mediawiki will ultimately make TWiki itself more appealing, as well as rescuing content from some TWikis that might otherwise be abandoned.
