# FD-170: Achievement / Milestone Detector Backend

**Status:** Design
**Priority:** Low
**Effort:** Small
**Created:** 2026-06-13

## Problem

The Odisea Central bridge tracks thousands of heartbeats but there's no celebration system. The developer (Sebastian) wants surprise push notifications when the game hits milestones: "100 users!", "1000 heartbeats!", "10 concurrent players!".

This should be a backend-only system — the bridge detects milestones and exposes them via an API. A separate process (Odiseo) will wire them into push notifications.

## Solution

### Milestone Detector

Add a `MilestoneDetector` class to `odisea_central.py` that:

1. **Tracks metrics over time:**
   - `total_unique_players` — count distinct player_ids seen ever
   - `total_heartbeats` — sum of all heartbeats received
   - `total_gameplay_seconds` — sum of session durations (approximate via heartbeat gaps)
   - `max_concurrent` — max players connected simultaneously in any given window
   - `consecutive_time_without_low_fps` — time since last low_fps alert
   - `total_sessions` — count distinct session_ids

2. **Checks milestones** every N heartbeats (configurable, default 50) against a predefined list:

```python
MILESTONES = [
    # Players
    ("players_10", "10 jugadores únicos", "users"),
    ("players_50", "50 jugadores únicos", "users"),
    ("players_100", "100 jugadores únicos", "users"),
    ("players_500", "500 jugadores únicos", "users"),
    ("players_1000", "1,000 jugadores únicos", "users"),
    # Concurrent
    ("concurrent_5", "5 jugadores simultáneos", "zap"),
    ("concurrent_10", "10 jugadores simultáneos", "zap"),
    ("concurrent_25", "25 jugadores simultáneos", "zap"),
    # Heartbeats
    ("heartbeats_10k", "10,000 heartbeats", "activity"),
    ("heartbeats_100k", "100,000 heartbeats", "activity"),
    ("heartbeats_1m", "1,000,000 heartbeats", "activity"),
    # Gameplay time
    ("gameplay_1h", "1 hora de gameplay acumulado", "clock"),
    ("gameplay_10h", "10 horas de gameplay acumulado", "clock"),
    ("gameplay_100h", "100 horas de gameplay acumulado", "clock"),
    # Performance
    ("nobadfps_1h", "1 hora sin FPS bajo", "heart"),
    ("nobadfps_24h", "24 horas sin FPS bajo", "heart"),
    # Sessions
    ("sessions_10", "10 sesiones de juego", "play"),
    ("sessions_100", "100 sesiones de juego", "play"),
]
```

3. **Persists achieved milestones** in a SQLite table so they never fire twice:
```sql
CREATE TABLE IF NOT EXISTS milestones (
    milestone_id TEXT PRIMARY KEY,
    title TEXT,
    icon TEXT,
    achieved_at REAL,
    value REAL
);
```

4. **Exposes API endpoint:**
   - `GET /api/milestones` — returns all milestones with `achieved: true/false`
   - `GET /api/milestones/achieved` — returns only achieved milestones
   - Milestones are checked every 50 heartbeats

### Integration

The milestone detector is called from `_process_heartbeat` — no external scheduler needed. It's lightweight (checking integers against thresholds, no expensive queries).

## Files

### Nuevos
- `odisea_central.py` — Add `MilestoneDetector` class (inline, ~100 lines)

### No tocar
- Everything else

## Verification
```bash
python3 -m py_compile odisea_central.py  # must pass
curl http://localhost:5003/api/milestones | jq
```
