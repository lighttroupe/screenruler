DESTDIR =
POTFILE =   screenruler.pot
POFILES =   $(shell ls *.po)
LANGUAGES = $(patsubst %.po, %, $(POFILES))
MOFILES =   $(patsubst %.po, %/screenruler.mo, $(POFILES))
MODIRS =    $(patsubst %.po, %, $(POFILES))
#SOURCES = $(shell ls ../*.rb ../*.glade)
SOURCES = $(shell ls ../*.rb)

all: $(POTFILE) $(MODIRS) $(MOFILES)



clean:
	rm -f *~

distclean: clean
	rm -f $(POTFILE) $(MOFILES)
	rm -rf $(MODIRS)

install:
	mkdir -p $(DESTDIR)/usr/share/screenruler/locale
	for l in $(LANGUAGES); do \
	  cp -a $$l $(DESTDIR)/usr/share/screenruler/locale; \
	done

$(MODIRS):
	for d in $(MODIRS); do mkdir -p $$d; done

%/screenruler.mo: %.po
	msgfmt $< -o $@

%po: $(POTFILE)
	msgmerge --update $@ $(POTFILE)
	touch $@

$(POTFILE): $(SOURCES) Makefile
	rxgettext -o $(POTFILE) $(SOURCES)

.PHONY: all clean distclean install
