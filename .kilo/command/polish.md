---
description: "Pulido iterativo: Sebastián suelta observaciones de a una, se consolidan en plan, se delega y se itera en local y Anbernic"
---

# /polish — Pulido iterativo (iterative-list-hacking)

Fuente canonica: `.agents/skills/iterative-list-hacking/SKILL.md`. Leerla completa antes de actuar.

Sesión de continuidad en `docs/agents/sessions/` (retomar con contexto fresco). Estado en disco, no en el chat.

## Regla de oro

Cada mensaje del usuario puede traer 1..N items sin relación. **No implementar al bote:** consolidar
en un plan numerado (A, B1..Bn), anclar cada item a `archivo:linea` real (`rg`/`read`), y recién ahí
ejecutar. Si el usuario dice "modo planear", devolver plan + decisiones abiertas sin tocar código.

## Ciclo

1. **Capturar** cada observación como item (síntoma/pedido, sin inferir la solución).
2. **Anclar** a archivos/nodos/uniforms/funciones/tests reales. Nunca proponer sin citar `archivo:linea`.
3. **Planear** numerado (A, B1..), agrupado por afinidad de archivo, con enfoque y riesgo; preguntar
   solo lo que bloquea (una pasada, con opciones).
4. **Repartir** clusters a subagentes con **archivos disjuntos**; documentar el ownership map.
5. **Verificar** — cada subagente corre solo sus tests puntuales (pytest delegate) y reporta
   archivos/diff/test/blocker. No commitear.
6. **Entregar** — commit + push (dispara nightly), rebuild PCK ARM64, deploy al Anbernic, verificar md5.
7. **Documentar** — actualizar `docs/agents/sessions/YYYY-MM-DD_<tema>.md` para retomar.

## Loop vivo

Mientras corren los agentes **no te duermas**: comentá en el chat qué hace/descubre cada uno, seguí
recibiendo items nuevos (anclados y sumados al plan sin cortar la tanda), no bloquees el turno
esperando resultados, y reportá hitos (agente terminó, test verde/rojo, blocker que cambia el plan).

## Devolución

Cada tanda cierra con una **lista breve de qué probar**: qué acción, dónde (device/touch/mando/desktop,
tier flat vs normal) y qué debería pasar. No es un resumen del diff; marcá lo que no se puede validar
headless para que lo pruebe el usuario.

Tests y build/deploy: ver el skill (secciones "Tests" y "Build + deploy al Anbernic") y la skill
`run-odisea`. Determinismo y convenciones de input en el skill.
