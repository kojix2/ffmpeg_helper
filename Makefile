CRYSTAL ?= crystal
CRFLAGS ?= -Dpreview_mt -Dexecution_context

.PHONY: build run test integration smoke clean

build:
	mkdir -p bin
	$(CRYSTAL) build $(CRFLAGS) ffmpeg_helper.cr -o bin/ffmpeg_helper

run: build
	./bin/ffmpeg_helper

test:
	$(CRYSTAL) spec $(CRFLAGS) spec

integration:
	FFMPEG_INTEGRATION=1 $(CRYSTAL) spec $(CRFLAGS) spec

smoke:
	$(CRYSTAL) run $(CRFLAGS) spec/gui_smoke.cr

clean:
	rm -f bin/ffmpeg_helper
