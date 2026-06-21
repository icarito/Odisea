## Plan: FD-226 Sistema de Update Seguro

Redactar un FD completo para un updater seguro y eficiente, alineado al estilo del repo, reutilizando la infraestructura existente (version-check, notificación y carga de PCK) y extendiéndola con manifiestos firmados, canales release/nightly automáticos, política de actualización por severidad y estrategia de diffs por archivo/chunk (no monolítico). El resultado esperado es un documento implementable por backend, cliente y CI sin ambigüedades.

**Steps**
1. Fase 1 — Encabezado y framing del FD: crear el documento con metadata (Status/Priority/Effort/Created), problema actual y objetivos medibles (seguridad, ancho de banda, UX de canal/tag, rollback). 
2. Fase 1 — Alineación con estado actual: documentar explícitamente qué ya existe y qué falta, referenciando VersionChecker, VersionNotification, endpoint /game/version y reload_pck para dejar trazabilidad técnica.
3. Fase 2 — Arquitectura objetivo end-to-end: definir pipeline completo Cliente ↔ Central/CDN ↔ CI, con flujo de decisión por canal y por plataforma, incluyendo cuándo se usa full package vs delta por archivo/chunk. *Depende de 1-2*.
4. Fase 2 — Modelo de release/channels: establecer reglas automáticas de selección de canal: builds oficiales usan release; builds dev usan nightly; contemplar tag pinning opcional y fallback de canal. *Depende de 3*.
5. Fase 2 — Contrato de manifiesto de actualización: especificar schema de manifiesto (versiones, platform targets, artifacts, hashes, firma, key_id, min_supported_version, severity, rollout windows, rollback constraints). *Depende de 3*.
6. Fase 2 — Seguridad y trust model: definir firma asimétrica, clave pública embebida con rotación por key-id, validación de integridad (hash por artifact/chunk), anti-rollback, anti-replay y políticas de rechazo seguro. *Depende de 5*.
7. Fase 3 — Estrategia de diffs eficiente: definir formato delta por archivo/chunk para v1 (robusto), heurísticas de selección delta vs full, cache local, resume/retry y garbage collection de caché. *Depende de 5*.
8. Fase 3 — Política UX de actualización: especificar updates opcionales por defecto y forzadas solo en security_critical, copy de UI para nightly/release y comportamiento web vs nativo. *Depende de 4 y 6*.
9. Fase 3 — Comportamiento por plataforma: detallar matrix Linux/Windows/Android/HTML5/iOS con capacidades y limitaciones (HTML5 recarga página para runtime wasm; native puede aplicar paquetes diferidos). *Depende de 3 y 8*.
10. Fase 4 — Cambios por componente: listar archivos/sistemas a modificar (game, central, CI) y límites de alcance de FD-226 (incluye diseño y contratos; excluye implementación de parches de runtime binario del engine). *Depende de 3-9*.
11. Fase 4 — Plan de implementación por etapas: incluir rollout incremental (MVP seguro sin delta, luego delta por archivo/chunk, luego optimizaciones), criterios de go/no-go y backward compatibility. *Depende de 10*.
12. Fase 4 — Verificación exhaustiva: definir pruebas unitarias/integración/e2e/seguridad/performance, métricas de éxito (ahorro de ancho de banda, tasa de éxito de update, tiempo medio de aplicación, false rejects). *Depende de 11*.
13. Cierre — Riesgos y mitigaciones: registrar riesgos operativos (firma, key rotation, corrupción de caché, downgrade attack, inconsistencia de canal) con mitigación y ownership.

**Relevant files**
- /home/icarito/Proyectos/Odisea_Game/src/docs/features/TEMPLATE.md — plantilla base de estructura FD a respetar.
- /home/icarito/Proyectos/Odisea_Game/src/docs/features/FD-225-version-check.md — baseline de versión/notificación por plataforma y endpoint de central.
- /home/icarito/Proyectos/Odisea_Game/src/core_v2/systems/VersionChecker.gd — chequeo periódico y señal new_version_available.
- /home/icarito/Proyectos/Odisea_Game/src/core_v2/ui/VersionNotification.gd — UX actual de aviso de nueva versión.
- /home/icarito/Proyectos/Odisea_Game/src/core_v2/telemetry/ANNAV2.gd — comando reload_pck existente a endurecer con validación.
- /home/icarito/Proyectos/Odisea_Game/src/odisea_central.py — endpoint /game/version y base para futuros endpoints de manifiesto.
- /home/icarito/Proyectos/Odisea_Game/src/AGENTS.md — restricciones/plataformas y notas de HTML5/PCK injection.

**Verification**
1. Revisar que el FD final conserve todas las secciones obligatorias de TEMPLATE y agregue secciones técnicas sin romper formato.
2. Verificar que decisiones de producto ya cerradas estén explícitas: canal por defecto (release oficiales, nightly dev), update policy (opcional salvo security_critical), firma (clave pública embebida + key-id), diffs (archivo/chunk).
3. Verificar que el FD tenga contratos concretos (payloads, campos requeridos, reglas de decisión) y no solo texto conceptual.
4. Validar que cada plataforma tenga comportamiento definido y consistente con capacidades reales (especialmente HTML5/wasm).
5. Confirmar que el FD incluya límites de alcance, riesgos y plan de rollout incremental para ejecución segura.

**Decisions**
- Canal por defecto: release en builds oficiales y nightly en builds dev.
- Estrategia de diffs v1: delta por archivo/chunk (robusto), no delta monolítico de PCK.
- Política de update: opcional por defecto; forzada solo para severidad security_critical.
- Verificación criptográfica: clave pública embebida en cliente con rotación por key-id.
- Notificación al usuario: siempre avisar nueva versión según canal/tag; ofrecer acción clara por plataforma.

**Further Considerations**
1. Recomendación de alcance: FD-226 debe incluir diseño técnico completo + contratos API + rollout, dejando la implementación para FD de ejecución (sub-FDs) para reducir riesgo.
2. Recomendación de seguridad: agregar explicitamente estrategia de key rotation y ventana de coexistencia de claves para evitar lockout de clientes viejos.
3. Recomendación de performance: incorporar umbral dinámico para decidir delta vs full (ej. si delta > X% del full, descargar full).