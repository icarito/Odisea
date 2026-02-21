# Performance Monitor

**Source:** `core_v2/autoloads/PerformanceMonitor.gd`

The `PerformanceMonitor` is a global autoload for telemetry, profiling, and debugging in the OdiseaOS project. It tracks CPU usage, FPS, and potential lag spikes.

## Key Features

-   **Lag Spike Detection:** Monitors framerate drops exceeding `LAG_SPIKE_THRESHOLD_FPS` (default 20 FPS).
-   **CPU Budget Logging:** Warns if CPU usage exceeds 70% of the target budget (16.6ms for 60 FPS).
-   **Snapshot System:** Saves detailed performance snapshots to `user://performance_snapshots.json` for regression testing.
-   **Instrumentation:** Allows specific nodes to be registered for detailed profiling via `measure_start()` and `measure_end()`.

## Usage

### Registering a Node
Call `register_monitored_node(self)` in `_ready()` or `_enter_tree()` to include a node in performance monitoring.

### Instrumentation
Wrap expensive code blocks to measure execution time:

```gdscript
PerformanceMonitor.measure_start(self, "AI_Pathfinding")
# ... expensive logic ...
PerformanceMonitor.measure_end(self, "AI_Pathfinding")
```

### Debug Actions
-   **Freeze Logic:** `debug_freeze_logic` pauses the game logic but keeps the monitor running.
-   **Disable AI:** `debug_disable_ai` stops AI processing globally.
-   **Step Frame:** `step_frame()` allows single-stepping the game loop.
-   **Cull Distance:** `debug_cull_distance_enabled` toggles visibility culling based on distance.

## Reports
Lag spike reports are automatically saved to `user://performance_log.json` when detected, containing timestamp, FPS drop, and top heavy nodes.
