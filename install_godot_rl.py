#!/usr/bin/env python3
import os
import subprocess
import shutil

src_dir = os.path.dirname(os.path.abspath(__file__))
addons_dir = os.path.join(src_dir, "addons")
tmp_dir = os.path.join(src_dir, "tmp_godot_rl")

print("Cloning godot_rl_agents (godot3 branch)...")
if os.path.exists(tmp_dir):
    shutil.rmtree(tmp_dir)

subprocess.run(["git", "clone", "-b", "godot3", "https://github.com/edbeeching/godot_rl_agents.git", tmp_dir], check=True)

plugin_src = os.path.join(tmp_dir, "godot_rl_agents", "core", "addons", "godot_rl_agents")
if not os.path.exists(plugin_src):
    # Try alternate location if layout changed
    plugin_src = os.path.join(tmp_dir, "addons", "godot_rl_agents")

plugin_dst = os.path.join(addons_dir, "godot_rl_agents")

print(f"Copying plugin from {plugin_src} to {plugin_dst}...")
if os.path.exists(plugin_dst):
    shutil.rmtree(plugin_dst)
shutil.copytree(plugin_src, plugin_dst)

print("Cleaning up...")
shutil.rmtree(tmp_dir)
print("Done! Installed godot_rl_agents plugin.")

