DESTDIR =
SUBDIR = locale

all:
	$(MAKE) -C $(SUBDIR) $@ DESTDIR=$(DESTDIR)

clean:
	rm -f *~
	$(MAKE) -C $(SUBDIR) $@ DESTDIR=$(DESTDIR)

distclean: clean
	$(MAKE) -C $(SUBDIR) $@ DESTDIR=$(DESTDIR)

install:
	mkdir -p $(DESTDIR)/usr/share/screenruler
	for f in *.rb *.png *.glade utils; do \
	  cp -a $$f $(DESTDIR)/usr/share/screenruler; \
	done
	mkdir -p $(DESTDIR)/usr/bin
	cp screenruler.rb $(DESTDIR)/usr/bin/screenruler
	mkdir -p $(DESTDIR)/usr/share/pixmaps
	cp screenruler-icon-64x64.png $(DESTDIR)/usr/share/pixmaps/screenruler.png
	mkdir -p $(DESTDIR)/usr/share/applications
	cp screenruler.desktop $(DESTDIR)/usr/share/applications
	$(MAKE) -C $(SUBDIR) $@ DESTDIR=$(DESTDIR)

.PHONY: all clean install distclean
