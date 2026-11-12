# Shared Operator Instructions

## Workflow

- `AGENTS.md` (raíz) es la fuente canónica de reglas para todos los agentes; `docs/agents/` es su mapa operativo (tooling, skills, agent-map). Este archivo es un adaptador: no duplica ni redefine esas reglas. Ante conflicto, manda `AGENTS.md`.
- Una regla que aplique a todos los agentes se escribe en `AGENTS.md` o `docs/agents/`, nunca solo aquí.

## Rules

- Leer `AGENTS.md` antes de tocar código; los contratos duros del Core están en su §5.

## Style

- Ver `AGENTS.md` §2.2 (GDScript 1.x, Godot 3.6 fork).
- Documentos del brain en español neutro.

## Private / Shared Policy

- Se comparte: el índice del proyecto, y specs, guías e investigación durables sobre el código y el diseño del juego.
- Los Feature Docs siguen viviendo en `docs/features/`; el brain no los duplica: las specs registran contratos e invariantes y enlazan al FD.
- Nada compartido referencia rutas de `.operator/` ni datos locales de una máquina.
