
## Setup Testing Environment

To execute tests and benchmarks, you need to have Godot 3 installed. In this environment (Ubuntu), you can install it via:

```bash
sudo apt-get update && sudo apt-get install -y godot3
```

This installs the `godot3` binary, which can be used to run scripts and headless tests.

### Running Benchmarks
To run performance benchmarks (e.g., the group lookup optimization):

```bash
godot3 -s benchmark_group_lookup.gd --no-window
```
