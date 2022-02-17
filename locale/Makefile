DESTDIR =
POTFILE =   screenruler.pot
POFILES =   $(shell ls *.po)
LANGUAGES = $(patsubst %.po, %, $(POFILES))
MOFILES =   $(patsubst %.po, %/screenruler.mo, $(POFILES))

#SOURCES = $(shell ls ../*.rb ../*.glade)
SOURCES = $(shell ls ../*.rb)

all: $(POTFILE) $(MOFILES)

clean:
	rm -f *~

distclean: clean
	rm -f $(POTFILE) $(MOFILES)

install:
	mkdir -p $(DESTDIR)/usr/share/screenruler/locale
	cp -a screenruler $(DESTDIR)/usr/share/screenruler/locale

%/screenruler.mo: %.po
	msgfmt $< -o $@

%po: $(POTFILE)
	msgmerge --update $@ $(POTFILE)
	touch $@

$(POTFILE): $(SOURCES) Makefile
	rxgettext -o $(POTFILE) $(SOURCES)

.PHONY: all clean distclean install
