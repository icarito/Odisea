# Makefile para Odisea Digest

render:
	gitingest ~/Proyectos/Odisea_Game/src -e addons/ -i "*.gd,*.tscn,*.json,*.md" -e "replays/,reports/,archive/,core_v2/scenes/AnimationPlayer.tscn,core_v2/scenes/Pilot_v2.tscn"


all: render

.PHONY: all
