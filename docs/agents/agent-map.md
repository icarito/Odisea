# Agent Map

Mapa de archivos para que cualquier agente encuentre las mismas instrucciones sin depender de
convenciones internas de una herramienta particular.

## Entradas por agente

| Agente | Entrada primaria | Proposito |
| --- | --- | --- |
| Codex | `AGENTS.md` | Reglas del proyecto y contratos criticos. |
| Claude | `CLAUDE.md` y `.claude/skills/` | Shim de entrada + skills nativas. |
| Gemini | `GEMINI.md` | Shim de entrada para Gemini CLI/agents. |
| Kilo | `KILO.md` y `.kilo/command/` | Shim de entrada + comandos slash con front matter. |
| Generico | `docs/agents/README.md` | Ruta neutral para cargar contexto. |

## Donde editar

- Cambia reglas de desarrollo, contratos, camara, determinismo, assets o scope: editar `AGENTS.md`.
- Cambia un workflow reusable como `/fd-new`, `/fd-verify`, `/fd-close`: editar `docs/skills/<nombre>.md`.
- Cambia el resumen de herramientas de runtime/test: editar `docs/agents/tooling.md`.
- Cambia un comando de Kilo: mantener `.kilo/command/<nombre>.md` como adaptador breve y enlazar al doc canonico.
- Cambia una skill de Claude: mantener `.claude/skills/<skill>/SKILL.md` como skill nativa, pero no duplicar reglas que ya estan en `AGENTS.md`.

## Contexto minimo para una tarea

1. Leer `AGENTS.md`.
2. Leer este mapa.
3. Leer `docs/agents/tooling.md` si la tarea requiere ejecutar, testear, inspeccionar runtime, UI o props.
4. Leer el workflow de `docs/skills/` si la tarea es de FD o proceso.
5. Leer specs del FD y archivos de codigo relevantes antes de cambiar nada.

## Politica anti-deriva

No copiar bloques largos entre herramientas. Si Claude, Gemini o Kilo necesitan el mismo contenido,
el archivo especifico de agente debe apuntar al doc canonico. La excepcion son snippets cortos que
la herramienta necesita para descubrir el comando o skill.

