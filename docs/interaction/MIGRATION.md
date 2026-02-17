# Documentation Migration Plan

This document tracks the consolidation of scattered interaction-related documentation into the unified `docs/interaction/` directory.

## Current State

### Files to Migrate

| Source File | Content | Status | Destination |
|-------------|---------|--------|-------------|
| `docs/feature_odyssey_logic_circuit_system.md` | OLCS technical spec | 🔄 Partial | `docs/interaction/OLCS.md` |
| `docs/feature_props_v2.md` | Prop pipeline & validation | 🔄 Partial | `docs/interaction/PROP_VALIDATION.md` |
| `docs/canon/feature_interactables.md` | Unified Interaction Framework | 🔄 Partial | `docs/interaction/CONTRACT.md` |
| `docs/canon/feature_interact.md` | Deterministic Interactable System | 🔄 Partial | `docs/interaction/CONTRACT.md` |
| `docs/feature_automatic_prop_zoo.md` | Prop Zoo testing | ⏳ Pending | `docs/interaction/PROP_ZOO.md` |
| `core_v2/systems/circuit/README.md` | OLCS user guide | 🔄 Partial | `docs/interaction/OLCS.md` |

### Status Legend
- ⏳ Pending - Not yet migrated
- 🔄 Partial - Content extracted and enhanced, source can be archived
- ✅ Complete - Source archived or deleted

## New Documentation Structure

```
docs/interaction/
├── README.md              # Overview and quick reference
├── CONTRACT.md            # InteractableBaseV2 technical contract
├── OLCS.md                # Odyssey Logic Circuit System
├── HIERARCHY_LINKING.md   # Scene tree patterns
├── PROP_VALIDATION.md     # test_prop.sh pipeline
├── PROP_ZOO.md            # (Planned) Prop Zoo test scene
└── MIGRATION.md           # This file
```

## Content Mapping

### From `feature_interactables.md`

| Section | Migrated To |
|---------|-------------|
| Architectural Concept | `README.md` - Overview |
| Component Architecture | `CONTRACT.md` - Class Hierarchy |
| Integration with Existing Features | `HIERARCHY_LINKING.md` - Patterns |

### From `feature_interact.md`

| Section | Migrated To |
|---------|-------------|
| Core Architecture | `CONTRACT.md` - State Machine |
| Implementation Types | `CONTRACT.md` - Subclass Patterns |
| Replay & Determinism | `CONTRACT.md` - Determinism Checklist |

### From `feature_odyssey_logic_circuit_system.md`

| Section | Migrated To |
|---------|-------------|
| Architecture Overview | `OLCS.md` - Overview |
| Core Components | `OLCS.md` - Core Components |
| Visual Editor | `OLCS.md` - Visual Editor |
| Cable Generation | `OLCS.md` - CircuitCable |

### From `feature_props_v2.md`

| Section | Migrated To |
|---------|-------------|
| Prop Contract | `CONTRACT.md` - Implementation |
| Switch Composability | `HIERARCHY_LINKING.md` - Auto-Wiring |
| Automation Pipeline | `PROP_VALIDATION.md` - Full pipeline |

## Recommended Actions

### Immediate

1. **Archive processed files** - Move migrated files to `docs/archive/`:
   ```bash
   mkdir -p docs/archive
   mv docs/feature_props_v2.md docs/archive/
   mv docs/canon/feature_interact.md docs/archive/
   mv docs/canon/feature_interactables.md docs/archive/
   ```

2. **Update cross-references** - Find and update any links pointing to old locations

### Future

1. **Create PROP_ZOO.md** - Document the Prop Zoo test scene from `feature_automatic_prop_zoo.md`

2. **Consolidate canon/** - Review remaining files in `docs/canon/` for migration

3. **Update AGENTS.md** - Add reference to `docs/interaction/` for AI agents

## Cross-Reference Audit

Search for references to migrated files:

```bash
# Find references to old docs
grep -r "feature_interact" --include="*.md" .
grep -r "feature_props_v2" --include="*.md" .
grep -r "feature_odyssey_logic" --include="*.md" .
```

## Quality Checklist

For each migrated document:

- [ ] All technical content preserved
- [ ] Mermaid diagrams added where helpful
- [ ] Code examples updated to current API
- [ ] Cross-links to other docs/interaction/ files
- [ ] Removed redundant/outdated information
- [ ] Consistent formatting and style

## Post-Migration Structure

After migration, the `docs/` directory should be organized as:

```
docs/
├── interaction/           # ✅ Unified interaction system docs
│   ├── README.md
│   ├── CONTRACT.md
│   ├── OLCS.md
│   ├── HIERARCHY_LINKING.md
│   ├── PROP_VALIDATION.md
│   └── MIGRATION.md
├── canon/                 # Keep for other canon specs
│   ├── feature_odisea_script.md
│   ├── feature_odyssey_script_replay.md
│   └── ...
├── feature_*.md           # Other feature specs (non-interaction)
├── archive/               # Migrated/deprecated docs
└── STATE_OF_*.md          # Project status documents
```

## Notes

- The `core_v2/systems/circuit/README.md` should remain as a quick-start guide, but reference `docs/interaction/OLCS.md` for full documentation
- `docs/canon/` files are considered "canonical" - preserve them until explicitly archived
- This migration plan should be deleted once complete
