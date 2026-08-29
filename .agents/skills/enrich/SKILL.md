---
name: enrich
description: Enriquecer técnicamente un Feature Doc (FD) de Odisea hasta dejarlo ejecutable — verificar assets en disco, evaluar viabilidad contra los contratos del Core, preguntar lo que falte, y escribir en el FD un plan de tareas con ejecutor asignado (Sonnet, Jules o Sebastián). Usar cuando se pida enriquecer, refinar, analizar viabilidad o planificar la ejecución de un FD, o al invocar /enrich.
---

# /enrich — Enriquecer un FD hasta que sea ejecutable

Fuente canónica: **`docs/skills/enrich.md`** — leerla completa antes de actuar.
Sigue después con `/deliver` (`docs/skills/deliver.md`).

## Adaptación para Codex

- **Fase 1 (inventario de assets):** verificar cada path con Glob/Grep/`ls`. No confiar en lo
  que el FD afirma; los FDs envejecen.
- **Fase 3 (preguntas):** usar `AskUserQuestion` — una tanda, máximo 4 preguntas, opciones
  concretas con la recomendada primero. Nunca inventar decisiones de diseño, arte o balance.
- **Búsqueda amplia:** si hay que barrer muchos directorios para el inventario, delegar al
  subagente `finder` o `Explore` y quedarse con la conclusión.
- **Escritura:** editar el FD con Edit, respetando su estilo y su idioma (español neutro).
- **Asignación de ejecutor:** el eje es cómo se verifica la tarea. Lógica sustancial que se
  juzga por diff + tests → JULES (hasta 3 sesiones en paralelo). Todo lo visual (props,
  materiales, escala, luz) y lo que necesita el repo vivo → LOCAL, con capturas y feedback de
  Sebastián. Lo que se juzga jugando → HUMANO.
- No escribir código de juego en esta skill. Solo lee, verifica y edita el FD.
- No cambiar `Status:` a `Open` ni pasar a `/deliver` sin OK explícito de Sebastián.
