CRYSTAL ?= crystal
SHARDS ?= shards
CRFLAGS ?= -Dpreview_mt -Dexecution_context

.PHONY: build run test integration smoke clean deps

build: deps
	mkdir -p bin
	$(CRYSTAL) build $(CRFLAGS) ffmpeg_helper.cr -o bin/ffmpeg_helper

run: build
	./bin/ffmpeg_helper

test: deps
	$(CRYSTAL) spec $(CRFLAGS) spec

integration: deps
	FFMPEG_INTEGRATION=1 $(CRYSTAL) spec $(CRFLAGS) spec

smoke: deps
	$(CRYSTAL) run $(CRFLAGS) spec/gui_smoke.cr

deps:
	$(SHARDS) check || $(SHARDS) install

clean:
	rm -f bin/ffmpeg_helper
