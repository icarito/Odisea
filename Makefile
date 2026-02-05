# Makefile para Odisea Digest

render:
	gitingest ~/Proyectos/Odisea_Game/src -e addons/ -i "*.gd,*.md,*.oys" -e "replays/,reports/,archive/"


all: render

.PHONY: all
