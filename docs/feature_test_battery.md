## 1. Locomoción Básica (El "Feel")

Estos tests aseguran que la respuesta a los mandos sea fluida y predecible.

* **Aceleración desde cero:** Verificar que Elías alcanza su velocidad máxima en el tiempo previsto (que no sea instantáneo ni demasiado lento).
* **Fricción y frenado:** Comprobar la distancia de deslizamiento al soltar el mando. Elías no debe quedar "pegado" al suelo ni patinar como si fuera hielo.
* **Cambio de dirección (Flip):** Validar que al pulsar la dirección contraria, el personaje gire y mantenga la inercia correcta durante la transición.
* **Velocidad máxima (Terminal Velocity):** Asegurar que en caídas largas Elías no acelere infinitamente y atraviese el mapa.

## 2. Dinámica de Salto

El salto es el corazón de Odisea. Aquí es donde suelen aparecer los bugs más feos.

* **Salto de altura variable:** Comprobar que un "tap" rápido produce un salto corto y mantener el botón produce un salto alto.
* **Pico de parábola:** Verificar que en el punto más alto del salto () haya un pequeño momento de "suspensión" antes de caer.
* **Cancelación de salto:** Testear qué pasa si Elías choca con un enemigo en el aire: ¿se resetea la gravedad o mantiene el impulso?
* **Coyote Time:** Validar que el jugador puede saltar durante unos frames (milisegundos) después de haber dejado de tocar una plataforma.

## 3. Integridad Física (Colisiones)

Para que el mundo se sienta sólido.

* **Detección de "Grounded":** Elías debe detectar que está en el suelo incluso en los bordes de los tiles, para evitar que el estado de "caída" se active erróneamente.
* **Colisión de cabeza (Ceiling):** Al saltar y golpear un techo, la velocidad vertical debe ir a cero inmediatamente, sin que el personaje se quede "pegado" arriba.
* **Muros invisibles:** Asegurar que caminar contra una pared no permite que Elías "escale" por error debido a la fricción de la caja de colisión.
* **Pendientes (Slopes):** Si el mapa tiene rampas, testear que Elías no vaya dando saltitos al bajar, sino que se mantenga pegado al suelo.

## 4. Transiciones de Estado

Para que las animaciones y la lógica no se peleen entre sí.

* **Land Impact:** Verificar que al caer desde una gran altura, el estado pase correctamente de `falling` a `idle` o `running` sin saltarse frames.
* **Interrupción de acciones:** ¿Qué pasa si Elías intenta saltar mientras está en medio de una animación de daño? El test debe confirmar cuál tiene prioridad.
