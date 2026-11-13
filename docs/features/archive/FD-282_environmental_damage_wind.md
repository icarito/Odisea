### FD-282: Daños Ambientales, Escalas de Temperatura Realistas y Zonas de Viento
**Status:** Draft / Design **Priority:** High **Effort:** Medium **Created:** 2026-08-28 **Parent:** FD-255 (Maestro), FD-269 (Room3D) **Reusa:** GasArea3D (FD-045), RadiatorProp (FD-272), WindTunnelV2 (FD-023, archive)

> **Notas de Odiseo:**
> 1. **Renumerado a FD-282** (el 280 ya existía — linterna de casco).
> 2. **El viento ya existe:** el componente se llama **`WindTunnelV2`** (`core_v2/components/WindTunnelV2.gd`, Area reusable con `wind_velocity` + snapshot `replay_sync`), no "WindZone" literal. El `FD-023_windzone.md` está en `docs/features/archive/` con estado Complete. `IndustrialFan` y `VentilationTurbine` ya lo usan. Este FD **reusa/extiende** ese componente, no crea uno nuevo.
> 3. **Giro de dirección de diseño:** este FD revierte la regla *"ciega, no daña"* del módulo de criogenia (pasa a daño térmico directo + vapor letal). Es un cambio intencional, no de rebote; confirmar con Sebastián antes de cerrar.

### 1. Problema y Objetivos de Diseño
Actualmente, el sistema de **Criocoolant** en *Odisea* se comporta principalmente como un obstáculo de visibilidad (niebla densa que ciega pero no daña directamente). Si bien esto respeta la lección de diseño inicial de "ciega, no daña" en el módulo de criogenia, limita la tensión de supervivencia y resulta físicamente inverosímil:
* **Falta de verosimilitud térmica:** El umbral de congelamiento nominal está fijado a 0°C. En la realidad física, una temperatura de 0°C congelaría el agua ambiental pero no dañaría rápidamente un traje espacial de alta tecnología. Las fugas de refrigerantes criogénicos operan a temperaturas extremas (por debajo de -150°C a -196°C) que colapsarían la integridad térmica del traje casi instantáneamente.
* **Peligros estáticos:** La atmósfera de la nave carece de amenazas cinéticas dinámicas continuas que afecten tanto al jugador como al entorno físico de manera constante (como corrientes de aire/viento que alteren el movimiento y la física de objetos rígidos).

**Objetivo:** Rediseñar la lógica física de **`Room3D`** para introducir un modelo de temperatura realista y estructurar un nuevo marco de peligros ambientales. Además, se definirá e integrará el comportamiento de la mecánica de **`WindZone`** (viento continuo) aportando una justificación de lore verosímil y mecánicas de juego interactivas.

---

### 2. Escala de Temperaturas Realistas y Daño Térmico en `Room3D`
El nodo **`Room3D`** actúa como un agregador determinista de variables de sala (temperatura, presión y contaminación). Para dotar de mayor realismo y tensión al bucle, se reconfiguran los umbrales de temperatura y se asocian a efectos físicos y de daño concretos:

#### A. Umbrales Discretos de Temperatura Rediseñados
1. **Zona de Confort Térmico (15°C a 20°C):**
 * *Estado:* Nominal y seguro (temperatura habitual en áreas templadas o en el Domo Intro por defecto).
 * *Efecto:* Sin acumulación de hielo, regeneración pasiva de sistemas térmicos del traje.
2. **Punto de Hielo (0°C a -10°C):**
 * *Estado:* Congelando.
 * *Efecto:* Comienza la condensación y congelación ambiental. El valor de `IceLevel` empieza a crecer sobre las superficies y mallas de la sala. La escarcha ligera se acumula en las juntas y cristales del casco sin restar integridad de salud directamente.
3. **Frío Crítico / Declinación Térmica (-50°C a -100°C):**
 * *Estado:* Frío Extremo / Superación de la Resistencia Térmica Pasiva (`SuitThermalResistance`).
 * *Efecto:* El frío extremo supera la protección pasiva del traje de Elías. Comienza a consumir de forma constante la integridad térmica de la batería/calefacción del traje (`suit_breached`). El jugador recibe avisos sensoriales (congelación densa en el visor, zumbido sutil, latidos del corazón acelerados).
4. **Ruptura Criogénica Absoluta (<= -150°C):**
 * *Estado:* Exposición Directa / Choque Térmico Catastrófico.
 * *Efecto:* Ocurre al estar a menos de 3 metros de una fuga de Criocoolant activa y presurizada (`LeakPatchPoint` sin sellar) o directamente bajo la pluma de un extractor criogénico (`CryoVent` / `CryoVent_D`). El traje se congela de inmediato, restando salud directamente al jugador. Si la salud llega a cero, se gatilla instantáneamente el desplome físico con *ragdoll* antes del respawn.

#### B. Evaporación y Vapor Letal
Se mantiene la regla de tensión de que "evaporar no es gratis":
* Si el jugador activa los radiadores de pared de alta temperatura (**`RadiatorProp`**) para derretir el hielo acumulado (`IceLevel`) sin abrir previamente las compuertas de ventilación, la evaporación rápida incrementa drásticamente la variable de `contamination` (humedad/vapor denso) por encima del `hazard_threshold` (0.7).
* Al superarse el umbral de contaminación, la niebla se transforma en vapor sobrecalentado letal controlado por el subsistema **`GasArea3D`**. Este vapor inflige un daño constante por segundo de `20.0` puntos en zonas densas. El jugador debe seguir la secuencia estricta: **Sellar la fuga → Ventilar la sala → Calentar/Derretir**.

---

### 3. Justificación Narrativa de Corrientes de Viento Continuas (`WindZone`)
Integrar corrientes de aire continuas y violentas en los interiores metálicos de la *Odisea* (una nave estanca de 8 km) requiere explicaciones físicas coherentes con su arquitectura industrial:

#### Justificación 1: Lazo de Convección Térmica Masiva (Efecto Chimenea)
La nave presenta contrastes térmicos extremos: reactores centrales y tuberías de plasma que operan a miles de grados en el núcleo de energía, junto a masivos sumideros criogénicos y tanques de Criocoolant a temperaturas hiperfrías.
* *Física del fenómeno:* El aire caliente asciende rápidamente hacia los niveles superiores, mientras que el aire helado y denso desciende hacia la popa por los pozos de elevación vertical y conductos de mantenimiento. Esto genera ráfagas y corrientes de aire continuas de alta velocidad (viento de convección térmica) a través de pasillos estrechos y rejillas industriales.

#### Justificación 2: Sistema de Recirculación de Domo (HVAC Loop)
Para evitar que en los gigantescos Bio-Hábitats y esferas de Bio-Granjas geodésicas se acumulen bolsas estáticas de dióxido de carbono pesado (CO₂) que asfixien los cultivos y a la tripulación, la nave emplea turbinas gigantes de ventilación (`VentilationTurbine` / `IndustrialFan`).
* *Física del fenómeno:* Estas turbinas empujan millones de metros cúbicos de aire a gran velocidad a través de conductos de retorno. Si la IA sabotea las compuertas de bypass o se rompe una sección de conducto, se genera un chorro de viento violento, unidireccional y continuo en los pasadizos adyacentes.

#### Justificación 3: Descompresión Pasiva por Micro-fugas
La *Odisea* ha sufrido daños estructurales y sabotajes sutiles. Pequeñas grietas en los mamparos exteriores o sellos defectuosos en compuertas de esclusas (`AirlockChamber`) provocan un flujo continuo de aire que escapa de forma constante hacia el vacío del espacio o hacia sectores despresurizados.
* *Física del fenómeno:* Sin llegar a una descompresión explosiva instantánea (blowout), esta succión de aire continua genera corrientes de viento persistentes que arrastran objetos y empujan físicamente al jugador hacia la grieta o esclusa.

---

### 4. Mecánicas de Juego e Interacciones de `WindZone`
El elemento **`WindZone`** no es puramente estético; interactúa directamente con la física del juego de manera determinista y reproducible bajo el contrato de `core_v2`:

#### A. Empuje sobre el Jugador y Cuerpos Rígidos
* **Efecto Cinético:** Aplica una fuerza direccional constante basada en un vector de velocidad de viento (`wind_velocity` y `wind_force`).
* **Efecto en la Locomoción:**
 * *A favor del viento:* Incrementa la velocidad de carrera y la distancia de salto horizontal (Dmax). Reduce la fricción de frenado.
 * *En contra del viento:* Ralentiza drásticamente al jugador, reduce la fricción en el salto y requiere esprintar para avanzar.
* **Interacción con Cajas Empujables (`PushableBoxV2`):** El viento continuo empuja físicamente las cajas sueltas que estén en modo dinámico. Esto permite diseñar puzles donde el jugador debe empujar una caja pesada para bloquear una rejilla de ventilación, apagando la corriente de viento en el pasillo para poder realizar saltos de precisión sobre abismos.

#### B. Telegrafiado Sensorial (Lectura de Sala)
Siguiendo la regla de oro de que "un peligro debe ser legible antes de sufrirlo", las corrientes de viento se telegrafían mediante:
1. **Partículas de Humo/Niebla Arrastradas (Flipbook Particles):** El viento interactúa con la niebla criogénica acumulada o el polvo suspendido. El shader de gas/humo de `GasParticleManager` deforma y alinea las partículas en la dirección del flujo de aire.
2. **Audio Dinámico (Transición de SFX Component):** Emisión de un zumbido sutil, siseos metálicos o el sonido de un fuerte vendaval silbando a través de rejillas de ventilación. El volumen aumenta proporcionalmente a la cercanía de la fuente del viento.
3. **Animación de Props:** Las aspas de ventiladores industriales cercanos (`IndustrialFan`) giran a velocidades asociadas al caudal del viento.

---

### 5. Contrato de Integración y Código Técnico
Para que este sistema funcione de forma determinista y sobreviva al replay, se deben respetar las siguientes directrices en los scripts:

* **Lógica Síncrona en `step(dt)`:** Todo el cálculo de la fuerza aplicada por el `WindZone` sobre el jugador y las cajas rígidas debe realizarse de manera síncrona en el paso de física fijo (`_physics_process(delta)`). Queda terminantemente prohibido usar el delta variable de `_process(delta)`.
* **Uso de `set_external_velocity`:** El área de `WindZone` aplica su fuerza sobre el `PlayerControllerV2` a través del método público `set_external_velocity(v)` con la bandera `external_source_is_static = false`. Esto garantiza que el momentum y las fuerzas acumulativas se sumen correctamente al vector final de movimiento.
* **Contrato de Snapshots (`replay_sync`):** El estado de la turbina o el interruptor que apaga el viento debe registrarse en el grupo `replay_sync` e implementar los métodos `get_snapshot()` y `restore_snapshot()`. Esto asegura que si una ráfaga empuja una caja a mitad de un replay, la caja se mueva exactamente a la misma posición en cada reproducción.
