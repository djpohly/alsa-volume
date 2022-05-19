SRC=alsa-volume.c
EXE=alsa-volume

all: $(EXE)

$(EXE): $(SRC)
	gcc -lasound -lm $< -o $@

clean:
	rm -f $(EXE)

install: $(EXE)
	install -d $(DESTDIR)/usr/local/bin
	install $(EXE) $(DESTDIR)/usr/local/bin

uninstall:
	rm -f $(DESTDIR)/usr/local/bin/$(EXE)
