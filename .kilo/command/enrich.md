---
description: Enriquecer un FD hasta dejarlo ejecutable — assets verificados, riesgos, preguntas y plan de tareas con ejecutor
---

# /enrich — Enriquecer un FD hasta que sea ejecutable

Fuente canonica compartida: `docs/skills/enrich.md`. Leerla completa antes de actuar.

## Resumen del flujo

0. **Contexto** — el FD (y su familia), `AGENTS.md` §1/§2/§5/§10, `FEATURE_INDEX.md`.
1. **Inventario de assets** — verificar en disco cada path que el FD menciona
   (`ls`, `git grep -il`), clasificar `EXISTE` / `EXISTE-OTRO-ROL` / `FALTA` / `AMBIGUO`.
2. **Viabilidad** — determinismo/replay, gravedad, camara, GLES2 (`CPUParticles`), culling
   FD-224, presupuesto de draw calls, escenas compartidas.
3. **Preguntas** — solo las que cambian el trabajo, todas juntas, con opciones y recomendacion.
   Nunca inventar diseno, arte ni balance.
4. **Escribir en el FD** — secciones `## Inventario de assets`, `## Riesgos y contratos`,
   `## Decisiones`, `## Plan de ejecucion` (tabla con ejecutor JULES/LOCAL/HUMANO),
   `## Checkpoints en vivo`.
   Criterio de asignacion: el eje es como se verifica. Logica sustancial juzgable por diff +
   tests ⇒ JULES (hasta 3 sesiones en paralelo). Todo lo visual (props, materiales, escala,
   luz) y lo que necesita el repo vivo ⇒ LOCAL, con capturas. Lo que se juzga jugando ⇒ HUMANO.
5. **Aprobacion** — sin OK explicito de Sebastian no se pasa a `/deliver` ni se cambia
   `Status:` a `Open`.

Esta skill no escribe codigo de juego: lee, verifica y edita el FD.
Continua en `/deliver` (`docs/skills/deliver.md`).
