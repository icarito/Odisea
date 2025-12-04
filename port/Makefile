GODOT_BIN = /usr/bin/godot3-bin
PROJECT_PATH = ..
EXPORT_PRESET = "Linux/X11 ARM64"
PCK_PATH = port/third/third.pck
REMOTE = root@angel:/roms/ports/

.PHONY: export scp all

all: export scp

export:
	$(GODOT_BIN) --no-window --path $(PROJECT_PATH) --profiling --export-debug $(EXPORT_PRESET) $(PCK_PATH)

scp: export
	rsync -avz third Third.sh $(REMOTE)
