# Resumen Ejecutivo — Odisea (Archivado / Referencia)

Nota: Este documento no forma parte del alcance del MVP Acto I (2026) y se mantiene como referencia estratégica. Ver `docs/STATE_OF_ODISEA_20260107.md` y `docs/TODO.md` para el estado actual y roadmap.

# Resumen Ejecutivo: Odisea MVP - Guía Técnica Exhaustiva
## Estado: 01/12/2025 | Godot 3.6.x GLES2

---

## 📋 Índice de Documentos Generados

### 1. **odisea_mvp_guideline.md** (PRINCIPAL)
   - Investigación exhaustiva de 9 sistemas técnicos
   - ~35 referencias documentadas (YouTube, Godot Docs, GitHub, Reddit)
   - Código GDScript completo para cada sistema
   - Cronograma de 6 semanas de implementación
   - **Contenido:** 10,000+ palabras, casos de uso reales

### 2. **odisea_api_cheatsheet.md** (REFERENCIA RÁPIDA)
   - Interfaces públicas de clases clave
   - Patrones comunes en Godot 3.x
   - Configuración crítica de Editor
   - Troubleshooting y performance tips
   - **Contenido:** 2,500+ palabras, acceso rápido

---

## 🎯 Ranking de Prioridades para MVP (Acto I)

### CRÍTICO (Semana 1-2)
1. **Transferencia de velocidad plataforma** ✅
   - `set_external_velocity()` en PlayerController
   - `move_and_slide_with_snap()` con snap_len configurable
   - MovingPlatform comunica velocidad instantánea
   - **Impacto:** Jugabilidad base no frustante
   - **Refs:** web:16, web:17, web:25, web:20

2. **Coyote Time + Input Buffering** ✅
   - Timers de 120ms (coyote) y 100ms (buffer)
   - Permite saltos perdonadores
   - **Impacto:** Control responsivo, "feel" satisfactorio
   - **Refs:** web:18, web:21, web:24


### ALTA (Semana 3-4)

5. **Conveyor** ⚠️
   - Area3D que llama `set_external_velocity()` en jugador
   - Stripe animation opcional
   - **Impacto:** Puzzle de Criogenia
   - **Refs:** web:60, web:66

6. **FSM Enemigos (DDC)** ⚠️
   - 3 estados: Patrol → Alert → Search
   - Visión cónica con raycast
   - Material rojo/amarillo para feedback
   - **Impacto:** Sigilo Acto I
   - **Refs:** web:61, web:64, web:67, web:62, web:65, web:68

### MEDIA (Semana 5+)

7. **PathFollow Curvas** (preparación Acto II)
8. **Aceleración Curves** (pulido final)
9. **Audio 3D Posicional** (inmersión narrativa)

---

## 📊 Estado Actual vs. Objetivo MVP

| Componente | Actual | Objetivo MVP | Complejidad | Horas Est. |
|-----------|--------|-------------|-------------|-----------|
| PlayerController | KinematicBody básico | + Snap + Platform Velocity | MEDIA | 6 |
| MovingPlatform | A↔B lineal | Comunica velocidad | BAJA | 4 |
| Conveyor | Prototipo sin velocidad | Integrado con jugador | MEDIA | 3 |
| Cámara | Básica | Spring-damper + colisión | MEDIA | 5 |
| Enemy_DDC | No existe | FSM simple + visión | MEDIA | 8 |
| Diálogos | No existe | JSON + AudioStreamPlayer | BAJA | 6 |
| Coyote Time | No existe | Timer 120ms | BAJA | 2 |
| **Total MVP** | **~60%** | **100%** | **MEDIA** | **~34 horas** |

---

### Documentación
14. **odisea_mvp_guideline.md** (~12,000 palabras)
15. **odisea_api_cheatsheet.md** (~3,000 palabras)
16. **Este resumen ejecutivo**

---

## 💡 Insights Clave de la Investigación

### Patrones Confirmados en Godot 3.x

1. **`move_and_slide_with_snap` es fundamental**
   - Sin snap: jitter en plataformas móviles
   - Con snap: adhesión suave a superficies
   - **Restricción:** `stop_on_slope` causa bugs (deshabilitar)

2. **Velocidad externa requiere interfaz consistente**
   - KinematicBody NO hereda velocidad de plataformas automáticamente
   - Solución: `set_external_velocity()` llamado por plataforma/conveyor
   - Decaimiento por frame: `lerp(platform_velocity, 0, 6.0 * delta)`

3. **Coyote Time & Input Buffering son críticos para "feel"**
   - Estándar en juegos modernos: 120-150ms coyote, 100-120ms buffer
   - Diferencia entre "frustante" y "satisfactorio"
   - Fácil de implementar (~20 líneas de código)

4. **PathFollow es reutilizable pero requiere cuidado**
   - Perfecto para Bio-Granjas (Acto II) y Núcleo 0G (Acto III)
   - Requiere Curve3D con puntos de control + tangentes
   - Reparametrización por longitud para velocidad consistente

5. **GLES2 restringe pero es viable**
   - Máximo 2-3 luces dinámicas por objeto
   - Materiales complejos requieren workarounds
   - AudioStreamPlayer3D funciona bien (posicional 3D)

---

## ⚠️ Riesgos y Mitigaciones

| Riesgo | Probabilidad | Mitigación |
|--------|------------|-----------|
| Jitter en plataformas | ALTA | Implementar snap correctamente |
| Control "no feels right" | MEDIA | Tiempos coyote/buffer correctos |
| Performance Android GLES2 | MEDIA | LOD, reducir luces, test temprano |
| Audio lag 3D | BAJA | AudioListener en camera, bus configurado |

---

## 📈 Métricas de Éxito (MVP)

| Métrica | Objetivo | Criterio |
|---------|----------|----------|
| **Playtime Feel** | "Satisfactory" | Tester sin frustración en 10 min |
| **Performance** | 60 FPS (desktop) | Monitor Godot: F1 |
| **Performance** | 30+ FPS (Android) | Test en device real |
| **Completitud** | 100% Acto I | Criogenia + primera mitad Mantenimiento |
| **Control** | Responsive | Coyote: ✓, Buffer: ✓, Precision: ✓ |

---

## 🚀 Próximos Pasos Post-MVP

### Fase 2 (Semana 3-4)
- [ ] PathFollow curvas para Acto II
- [ ] Gravedad fluctuante (volúmenes)
- [ ] Vehículo 4x4 básico

### Fase 3 (Semana 5-6)
- [ ] Acto II completo (Bio-Granjas)
- [ ] Propulsor 0G avanzado
- [ ] Múltiples enemigos DDC

### Fase 4+ (Acto III & Finales)
- [ ] Núcleo 0G 3D completo
- [ ] Finales múltiples (5 ramificaciones)
- [ ] Pulido visual y audio

---

## 📞 Asistencia Técnica Rápida

### Preguntas Frecuentes Esperadas

**P: ¿Por qué no Godot 4?**  
R: Tu codebase es 3.x; migración sería más costosa que optimizar 3.6.x.

**P: ¿Es realista 34 horas?**  
R: Sí, con las APIs propuestas y código prototipo. Ajusta si hay bloqueos.

**P: ¿Qué si GLES2 no rinde en Android?**  
R: LOD + reducir luces dinámicas. Evaluar temprano (semana 4).

**P: ¿Conveyor vs Plataforma móvil?**  
R: Conveyor: empuje continuo. Plataforma: desplazamiento + llevarte. Ambos necesarios.

**P: ¿Cómo testear feel sin designer?**  
R: lab_movement.tscn + Debug Overlay + valores exportados en editor.

---

## 📝 Licencias y Atribuciones

Todas las referencias documentadas respetan licencias CC-By 4.0 (GDQuest, Godot Docs, etc.).

Código GDScript propuesto: GPL-compatible (tu licencia del proyecto).

---

**Documento Compilado:** 01/12/2025 12:52 UTC  
**Para:** Odisea: El Arca Silenciosa | MVP Phase  


**Comenzar con el documento principal: `odisea_mvp_guideline.md`**