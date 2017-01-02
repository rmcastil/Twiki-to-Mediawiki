test:
	t/testexpect.pl

t/%.mw: t/%.txt
	./twiki2mediawiki.pl -stdout $< >$@

mw: $(subst .txt,.mw,$(wildcard t/*.txt))
