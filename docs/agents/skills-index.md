# Skills And Commands Index

Catalogo neutral de skills/comandos. Los docs canonicos viven en `docs/skills/` cuando son
workflows generales. Las integraciones especificas de agente pueden envolverlos.

## Feature Design

| Comando | Canonico | Kilo | Proposito |
| --- | --- | --- | --- |
| `/fd-explore` | `docs/skills/fd-explore.md` | `.kilo/command/fd-explore.md` | Cargar contexto del proyecto. |
| `/fd-new` | `docs/skills/fd-new.md` | `.kilo/command/fd-new.md` | Crear un FD numerado. |
| `/fd-status` | `docs/skills/fd-status.md` | `.kilo/command/fd-status.md` | Ver estado de features. |
| `/fd-verify` | `docs/skills/fd-verify.md` | `.kilo/command/fd-verify.md` | Verificar implementacion contra spec. |
| `/fd-close` | `docs/skills/fd-close.md` | `.kilo/command/fd-close.md` | Archivar FD y actualizar changelog. |

## Ejecucion de Features (enrich → deliver)

| Comando | Canonico | Claude | Kilo | Proposito |
| --- | --- | --- | --- | --- |
| `/enrich` | `docs/skills/enrich.md` | `.claude/skills/enrich/SKILL.md` | `.kilo/command/enrich.md` | Enriquecer un FD: assets verificados, riesgos, preguntas y plan de tareas con ejecutor. |
| `/deliver` | `docs/skills/deliver.md` | `.claude/skills/deliver/SKILL.md` | `.kilo/command/deliver.md` | Ejecutar el plan: despachar a Sonnet y a Jules, revisar, checkpoints en vivo. |
| `/jules` | `docs/skills/jules.md` | `.claude/skills/jules/SKILL.md` | `.kilo/command/jules.md` | Delegar tareas asincronas a Jules via `bin/jules-cli` y gestionar la sesion hasta el PR. |

Ciclo completo de una feature: `/fd-new` → `/enrich` → `/deliver` → `/fd-verify` → `/fd-close`.

## Odisea runtime y validacion

| Comando/skill | Canonico | Claude | Kilo | Proposito |
| --- | --- | --- | --- | --- |
| `run-odisea` | `docs/agents/tooling.md` | `.claude/skills/run-odisea/SKILL.md` | `.kilo/command/odisea-test.md`, `.kilo/command/odisea-eval.md` | Tests, eval headless, UI, props, runtime. |
| `odisea-telemetry` | `docs/agents/tooling.md` | `.claude/skills/odisea-telemetry/SKILL.md` | `.kilo/command/odisea-telemetry.md` | Peer `:4999`, status, eval, inspect, screenshot. |
| `prop-visualizer` | `docs/agents/tooling.md` | `.claude/skills/prop-visualizer/SKILL.md` | `.kilo/command/odisea-prop.md` | Crear e iterar props con screenshots. |

## Como agregar un workflow nuevo

1. Crear el doc canonico en `docs/skills/<nombre>.md` si aplica a mas de un agente.
2. Agregarlo a este indice.
3. Crear adaptadores especificos solo si la herramienta los necesita:
   - Kilo: `.kilo/command/<nombre>.md` con front matter y enlace al canonico.
   - Claude: `.claude/skills/<nombre>/SKILL.md` si debe ser autodescubierto como skill.
   - Otros agentes: shim raiz o doc corto que apunte al canonico.
4. Evitar copiar reglas largas desde `AGENTS.md`.

