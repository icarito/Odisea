tool
extends Spatial
class_name DomeIntroPipeNetworkSource

# Authoring switches consumed by `make bake`. The runtime keeps its gameplay
# NodePaths and positions; these flags define the radial presentation.
export(bool) var orient_leaks_inward: bool = true
export(bool) var orient_valves_inward: bool = true
