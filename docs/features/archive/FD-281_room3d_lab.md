### FD-281: Laboratorio de Ambientes Unificado (Room3DLab)
**Status:** Design **Priority:** High **Effort:** Medium **Created:** 2026-08-28
**Parent:** FD-255 (Maestro) / FD-269 (Room3D) / FD-270 (Caudal) **Reusa:** Room3D, AirlockChamber, HoloTerminalV2, VCameraSystem, OysCameras, RoomDialsPanel

> **Nota de scope (Odiseo):** Este laboratorio es **infraestructura de diagnóstico/tooling** (escena de simulación y telemetría en vivo), no un nivel jugable del Vertical Slice del Acto I. Sirve para validar físicas y esclusas antes de mudarlas a los domos de campaña. Numerado FD-281 (el 280 ya estaba ocupado por la linterna de casco).

#### 1. Problema y Contexto
El desarrollo de las físicas de entornos en *Odisea* ha alcanzado un alto nivel de madurez matemática y determinismo (temperatura, presión, contaminación, y caño/caudal por tramo). Sin embargo, el equipo de diseño y programación carece de una **escena de simulación integrada de grado industrial** que permita validar los tres estados de sala, las tres esclusas del triángulo navegable y la interacción remota antes de mudar estas lógicas a los domos de campaña.

La escena de prueba actual (`TestShipSystems.tscn`) funciona como un "zoológico de props", y `CoolantLab.tscn` está estrictamente limitada a puzles aislados de coolant. Se requiere un **laboratorio modular de tres salas (`Room3DLab.tscn`)** que simule los ambientes hostiles de forma segura y sirva como herramienta de diagnóstico visual en vivo (telemetría y cámaras).

---

#### 2. Solución: Estructura del Laboratorio de Ambientes (`Room3DLab.tscn`)
El laboratorio se compone de tres salas estancas dispuestas en triángulo, separadas físicamente por mamparos de acero con **ventanales de observación transparentes** y conectadas por **tres esclusas neumáticas (`AirlockChamber`)**.

```
 [ SALA DE CONTROL ] (Segura)
 / \
 Airlock 1 Airlock 2
 / \
[ CÁMARA CRYO (A) ] === Airlock 3 === [ CÁMARA PLASMA (B) ]
 (Frío/Niebla) (Calor/Presión)
```

##### 2.1. Las Tres Salas (`Room3D` Autónomos)
Cada sala posee su propio nodo `Room3D` con umbrales independientes para evitar que las físicas se mezclen de forma irreal:
1. **Sala de Control (Central de Monitoreo):** Estado nominal y seguro. Temperatura templada (20°C), presión estable (1.0 bar) y aire 100% libre de contaminación (0.0). Es el refugio donde el jugador analiza la situación.
2. **Cámara Cryo (Sector A):** Banco de pruebas criogénicas. Contiene tanques de Criocoolant, tuberías, válvulas y puntos de fisura (`LeakPatchPoint`). Su simulación de `Room3D` acumula frío extremo (hasta -150°C) y niebla densa de refrigerante cuando hay fugas activas.
3. **Cámara Plasma (Sector B):** Banco de pruebas térmicas y energéticas. Contiene conducciones de plasma (`PlasmaConduit`), radiadores (`RadiatorProp`) y paneles de circuitos lógicos (`LogicCircuitManager`). Su simulación acumula calor extremo por sobrecalentamiento de plasma y sobrepresión por fallos de ventilación.

---

#### 3. Especificación Técnica de los Componentes Clave

##### 3.1. Ventanales de Observación y el Desafío de Transparencia GLES2
Para permitir que el jugador observe los peligros de las Cámaras A y B desde la seguridad de la Sala de Control sin exponerse físicamente, los mamparos divisorios incorporan ventanales transparentes de vidrio reforzado.

**Riesgo Técnico de Orden de Dibujo (Sorting Bug):**
En Godot 3.6 bajo renderizado GLES2, los materiales con transparencia (*Alpha Blend*) se ordenan en base al centro del cuadro delimitador (*AABB*) del `MeshInstance` completo. Si creamos un ventanal gigante o unificado que abarque todo el muro, su AABB colosal se ordenará mal contra los terminales holográficos (`HoloTerminalV2`) que también usan shaders transparentes (`HoloGlass`), provocando parpadeos bruscos (*flickering*) u ocultamientos indeseados.

**Mitigación Obligatoria en Escena:**
* **Segmentación de Malla:** Los ventanales se construirán dividiendo la geometría en **paneles individuales pequeños de 2m x 2m**. Cada panel tendrá su propio `MeshInstance` y colisionador. Esto reduce drásticamente el tamaño del AABB de cada malla de vidrio, permitiendo que el motor de renderizado de Godot los ordene espacialmente de forma impecable y dinámica según la distancia de la cámara.
* **Material de Vidrio Neutro:** El material del vidrio (`GlassPanel.tres`) será un `SpatialMaterial` con `flags_transparent = true`, un color base casi transparente (`alpha = 0.1` a `0.15`), `roughness = 0.15` y `metallic = 0.9` para reflejar sutilmente las luces de neón del entorno sin tapar la visión del interior de las cámaras.

##### 3.2. Holoterminales de Monitoreo Remoto
La Sala de Control aloja un gran pedestal holográfico que proyecta tres consolas virtuales (`HoloTerminalV2`) con aplicaciones táctiles de telemetría y diagnóstico:

1. **Terminal de Cámaras (`OysCameras`):**
 * Muestra un feed de video en tiempo real de las tres salas utilizando cámaras virtuales (`VCameraSystem`) colocadas estratégicamente en las esquinas de cada cámara de monitoreo.
 * Permite al jugador inspeccionar visualmente dónde se localiza la ruptura de una tubería o el estado de una esclusa antes de cruzar los mamparos.
2. **Terminal de Telemetría Ambiental (`RoomDialsPanel`):**
 * Este panel lee directamente los tres floats lógicos de las instancias de `Room3D` (`temperature`, `pressure`, `contamination`).
 * Dibuja de forma procedural e interactiva tres diales analógicos (arcos de color usando `Control._draw()`) por cada una de las tres salas.
 * Los diales cambian dinámicamente de color según los umbrales cruzados: verde para rangos seguros, azul/cian para el frío extremo/niebla de la Cámara A, y naranja/rojo para el calor y la sobrepresión crítica de la Cámara B.
3. **Terminal de Esclusas y Seguridad:**
 * Muestra un esquema interactivo de la topología del laboratorio y el estado físico de las tres esclusas (`AirlockChamber`).
 * Permite iniciar ciclos de purga o igualar presiones a distancia para desbloquear esclusas trabadas por presión crítica antes de acercarse con el cuerpo.

##### 3.3. Monitoreo y Lógica de las Tres Esclusas (`AirlockChamber`)
Las esclusas conectan las tres salas en un anillo cerrado:
* **Airlock 1:** Conecta la Sala de Control con la Cámara Cryo (A).
* **Airlock 2:** Conecta la Sala de Control con la Cámara Plasma (B).
* **Airlock 3:** Conecta la Cámara Cryo (A) con la Cámara Plasma (B) de forma directa.

**Mecánica de Bloqueo por Presión:**
Siguiendo las especificaciones de `FD-258`, si la Cámara A o B sufre sobrepresión (presión > 2.4 bar) o sobrepresión crítica debido a fallos de simulación, la compuerta de la esclusa correspondiente se bloquea magnéticamente por seguridad.
* El jugador no podrá interactuar directamente con la manija de la puerta desde el exterior. El terminal del holograma mostrará la esclusa en estado `LOCKED` (con el texto *"Bloqueo de Presión Crítica"*).
* Para cruzar, el jugador debe operar el dial de purga (`PurgeDial`) o usar el holoterminal de control de esclusas para equilibrar las presiones entre ambas salas. Una vez igualadas, se libera el pestillo neumático y se permite la apertura.

---

#### 4. Integración y Cableado Lógico (OCLS + Prop Setup)
El laboratorio de ambientes utiliza el `LogicCircuitManager` para cablear las lógicas de seguridad y las esclusas sin necesidad de acoplar scripts:

1. **Monitoreo del Estado de Esclusas:**
 * Cada `AirlockChamber` emite señales `airlock_opened` y `airlock_closed`. Estas señales alimentan nodos `PROP` en el grafo del circuito para actualizar el mapa interactivo en la Sala de Control.
2. **Deltas Ambientales Activos:**
 * Si se abre el Airlock 3 (que conecta directamente las dos cámaras de peligro) estando la Cámara A congelada y la Cámara B caliente, los `Room3D` de ambas salas recibirán impulsos térmicos y de contaminación opuestos. Esto simula la **propagación por vecindad inmediata** de manera determinista y predecible (equilibrando las salas paulatinamente por ticks de física mientras la esclusa permanezca abierta).

---

#### 5. Verificación del Laboratorio
1. **Test de Carga Headless:** Cargar la escena `Room3DLab.tscn` mediante `godot3-bin --headless`. Asegurar que no existan errores de referencia de NodePath rotos al inicializar las conexiones de los tres `Room3D` y las tres esclusas.
2. **Verificación de Visuales en GLES2:** Validar que los ventanales de vidrio pequeños (mallas segmentadas) y los terminales holográficos se ordenen correctamente sin saltos visuales ni parpadeos al rotar la cámara de Elías en tercera persona.
3. **Test del Bucle de Esclusas:**
 * Provocar un fallo de presión en la Cámara B.
 * Verificar que la esclusa 2 y la esclusa 3 se bloqueen físicamente.
 * Comprobar que el indicador holográfico en la Sala de Control muestre las esclusas como bloqueadas en color rojo de alerta.
 * Utilizar el terminal para purgar la sala y verificar que las esclusas se desbloqueen al volver a la presión nominal.
