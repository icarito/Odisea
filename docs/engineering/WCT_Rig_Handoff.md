# WCT Rig — Handoff (andador de carga, rig procedural)

> Handoff del rig procedural del andador de carga (walking cargo transporter).
> Estado al 2026-09-07: **el rig funciona**; la canilla desprendida y la cadena
> degenerada están resueltas.

## Objetivo

Rig procedural con **cuatro articulaciones por pierna** para el andador de carga:
cadera → primera rodilla invertida → segunda rodilla → tobillo. El andador camina
proceduralmente en `Dome_Default.tscn`.

## Estado actual

- El rig se genera con `tools/build_wct_rig.gd` desde la malla fusionada del
  modelo (`core_v2/props/machinery/walking_cargo_transporter.tscn`, importada del
  GLB/DAE original en `assets/models/Drones/`). El DAE fuente
  (`/home/icarito/Descargas/walking-cargo-transporter/source/model/model.dae`)
  confirma: el artista entregó UNA sola malla fusionada (`LegsJoined`, escala
  0.313, traslación (2.6, 250.6, 1.06)) **sin esqueleto** — el rig se construye
  desde la malla, no hay jerarquía que rescatar.
- El IK procedural vive en `core_v2/props/machinery/WalkingCargoTransporterRig.gd`.
- `tools/validate_wct_walk.gd` valida y **falla con código de salida 1** si algo
  se rompe. Estado verde: pie levanta 0.250 m, perno dobla 0.369 rad, drift
  determinista 0.000000000, avance 0.7 m/s, cadena unida en ambas piernas.

## Los dos bugs que estaban abiertos (resueltos)

### 1. La canilla desprendida — el pivote del horneado

`build_wct_rig.gd` horneaba la malla del shin alrededor del pivote del **perno**
(50, 287) mientras el nodo `ShinL/R` se colocaba en el de la **gota** (−80, −120).
La malla se dibujaba desplazada exactamente `GOTA − PERNO = (−130, −407)`. El IK
cerraba perfecto (los nodos estaban bien) y por eso la validación de marcha
nunca lo vio: era un desfase malla↔nodo, no un error de cinemática.

Fix: la excepción desapareció; cada pieza se hornea alrededor del pivote de su
propia articulación, el mismo punto donde se coloca su nodo.

### 2. La cadena degenerada — tres huesos que eran dos

El IK viejo resolvía el triángulo cadera–perno–gota con los **tres lados fijos**
(`l_arm`, `l_link` y `l_upper` constantes): un triángulo así es un cuerpo rígido,
así que `knee.rotation.x` salía `0.000` en todos los frames y la pierna era en
realidad una cadena de dos huesos con el perno de adorno.

Fix: el perno pasó a ser un grado de libertad real. Dobla en función del alcance
que se le pide a la pierna (`knee_bend`, export, 0 = triángulo rígido) y con eso
el hueso virtual cadera→gota tiene **largo variable**; el 2-huesos se resuelve
sobre ese largo. Sigue siendo exacto y sin iteración: el pie cae en el objetivo
con drift 0. Además el paso 2 viejo (intersección de círculos para ubicar el
perno) sobra y se borró — el perno queda ubicado por construcción.

## La geometría medida (CIERTA — verificada con mapas de densidad y renders)

El modelo original es UNA sola malla fusionada. Todas las medidas están en
**coordenadas de malla** (mesh-local = local de LegsJoined). Eje Y = arriba,
eje Z = adelante del andador (el modelo camina hacia +Z).

| Punto | (y, z) | Qué es |
|---|---|---|
| **Eje 1 cadera** | (338, −37) | el eje del disco lateral (la cadera) |
| **Eje 2 primera rodilla** | (50, 287) | el perno donde cuelga la biela (la rodilla invertida) |
| **Eje 3 segunda rodilla** | (−80, −120) | la gota negra (donde la biela encuentra la canilla) |
| **Eje 4 tobillo** | (−635, −42) | el eje del ski |

Los huesos: cadera→perno = **434**; perno→gota = **427**; gota→tobillo = **560**.
La pose de reposo es una **zigzag**: cadera → adelante-abajo (el perno) →
atrás-abajo (la gota) → adelante-abajo (el tobillo). Como la pata de un pájaro.

Otras medidas:
- La cintura cilíndrica (el collar del torso): y 455..555, |x| 90..160, z −240..+100.
- El eje dentro de la cintura: |x| ≤ 90, y 480..550, z −180..−120.
- El tanque trasero de la pelvis (con el anillo): |x| ≤ 90, y 240..440, z −460..−250.
- El hub block (el bloque central): |x| ≤ 136, y 136..426, z −309..259.
- La plataforma: y > 660. El ski: y −560..−746.

## La arquitectura del rig (la jerarquía de nodos)

```
Rig
├── Body (fija): plataforma + columna
├── Pelvis (fija, única): bloque central + cintura + collares + eje + tanque trasero
└── Hip (eje 1, y=338): primer fémur = discos + anillos + plato/brazo
    └── Knee (eje 2, y=50): primera rodilla invertida = alojamiento + biela
        └── Shin (eje 3, y=-80): segunda rodilla = gota + anillos + viga + riel
            └── Foot (tobillo, y=-635): ski + ruedas, se nivela solo
```

El IK (`WalkingCargoTransporterRig._solve_leg`) resuelve los 3 huesos + el pie:
1. El perno dobla según el alcance pedido:
   `knee_a = -knee_bend * (|target - cadera| - d_rest) / l_shin`, acotado a ±1.2.
2. El hueso virtual cadera→gota se arma ya doblado: `upper = k2off + rot(k3off, knee_a)`.
3. 2-huesos clásico sobre `(|upper|, l_shin)` → ubica la gota.
4. Rotaciones: la cadera gira `upper` hacia la gota, el perno lleva `knee_a`, la
   canilla apunta al tobillo, y el tobillo contrarrota para nivelar el ski.

Canario de reposo: con el objetivo en el tobillo de reposo, `knee_a = 0` y las
tres rotaciones dan ≈ 0 — el rig reproduce exactamente la pose del modelo.

## Las herramientas (en `tools/`, todas ejecutan con `godot3-bin --path . -s <script>`)

- `build_wct_rig.gd` — genera `walking_cargo_transporter_rig.tscn` desde la malla.
  Las reglas de corte son una lista corta y explícita de rangos (y, z, |x|) al
  inicio del bloque de clasificación — ajustar ahí.
- `view_wct_parts.gd` — renderiza el rig con colores por pieza (3 vistas).
  **LA HERRAMIENTA CLAVE para verificar el corte y la pose.**
- `view_wct_joints.gd` — la pierna del modelo fuente con marcadores en los
  candidatos a eje (rojo=cadera, amarillo=perno, cian=gota, verde=tapas traseras).
- `validate_wct_walk.gd` — corre la marcha 3 s dos veces y **falla (exit 1)** si:
  el pie levanta < 0.20 m, el perno dobla < 0.05 rad (la cadena degeneró en dos
  huesos), el drift entre corridas > 1e-6, o el pivote de un hijo cae fuera de la
  malla del padre (la pieza se dibuja desprendida). Los dos últimos chequeos son
  los que faltaban: son los que atrapan cada uno de los bugs de arriba.
- `view_wct_fix.gd` — captura la marcha en 8 fases (los frames del ciclo).
- `capture_wct_level.gd` — captura Dome_Default con cámara al andador.
- `wct_components.gd` — componentes conexas del mesh + detector de ejes.
- `map_wct_waist.gd`, `map_wct_rear.gd` — mapas de densidad ASCII de zonas.

## Los aprendizajes (las trampas que costaron iteraciones)

1. **Las costuras de UV parten la malla en slivers de 2 triángulos.** Los
   componentes conexas por vértices compartidos fragmentan las piezas (la biela
   quedó en ~40 slivers). Soldar vértices coincidentes en posición antes de
   analizar. PERO: el soldado por celda de 2 unidades fusiona piezas vecinas
   que solo se rozan (la biela se soldó al alojamiento) — usar soldado EXACTO.
2. **El albedo no sirve para separar L/R**: las islas de UV de cada lado
   muestrean regiones distintas de la textura y la clasificación por color es
   asimétrica. Usar bandas X simétricas o posición.
3. **La pose de reposo del IK debe reproducir EXACTAMENTE la pose del modelo**:
   con el objetivo en el tobillo de reposo, las rotaciones de los nodos deben
   ser ≈ 0. Si no lo son, el pivote o el hueso está mal — es el test canario.
4. **Los pivotes con offset grande respecto al hueso hacen que las piezas
   orbiten** (el desgarro). Cada mesh debe hornearse alrededor del pivote de SU
   articulación.
5. **La traslación de cada nodo = (su pivote) − (el pivote de su padre)** —
   en la cadena Hip→Knee→Shin→Foot. Si falta una, el IK degenera (l=0) o la
   pieza se desplaza (la canilla flotando a la altura de la cadera).
6. **El eje Y del mundo NO es el eje Y de la malla en el rig-local**: la
   traslación de LegsJoined (+250.6) desplaza todo el andador +2.5 m — las
   medidas de mundo incluyen ese shift; las de malla no.
7. **La rotación de los padres levanta los offsets de los hijos**: el origin de
   un nodo hijo = el origin del padre + rot(padres)·(offset). Analizar el
   encadenado completo, no solo el offset local.
8. **El riel frontal (la biela larga) baja hasta el tobillo** por el frente de
   la canilla — hay que partirlo a la altura de la gota: arriba va con el muslo,
   abajo con la canilla.
9. **El tanque trasero de la pelvis (con el anillo) es de la PELVIS** (fija),
   no de la cadera — el usuario lo marcó explícitamente.
10. **La canilla (Shin) es el eje 3**: la gota + los anillos + la viga + el riel
    pivota en la gota (−80,−120) — NO en el perno (50,287).

## Lo que queda por hacer

- Ajustar `knee_bend` a ojo si el doblado del perno se ve exagerado o pobre
  (default 1.0; 0 lo vuelve al triángulo rígido).
- Integrar el andador en el nivel definitivo (hoy vive en `Dome_Default.tscn`).
- Las reglas de corte de `build_wct_rig.gd` siguen siendo una lista de rangos
  (y, z, |x|); si alguna pieza queda con el dueño equivocado, se ajusta ahí y se
  vuelve a correr `view_wct_parts.gd` para verlo por colores.

## Las capturas de referencia

- `test_output/props/wct_parts_lado.png` — el último render por colores (la
  canilla desprendida visible en verde).
- `test_output/props/wct_joints_zoom.png` — el modelo fuente con los 4
  candidatos a eje marcados (el rojo=cadera ✓, el amarillo=perno ✓,
  el cian=gota ✓, el verde=tapas traseras=no es articulación).
- `test_output/props/wct_4joints.png` — la captura del nivel con la última
  arquitectura.
