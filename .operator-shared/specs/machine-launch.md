# Lanzamiento del jugador por piezas rígidas

Contrato entre `PlayerControllerV2` y cualquier `RigidBody` sobre el que el jugador se
para (FD-320). Lo que el código no dice solo.

## Invariantes

- **Box3D no ancla joints al mundo.** Todo joint necesita dos cuerpos; un pivote fijo es un
  `StaticBody` propio (`MachineHinge` lo crea). Un `HingeJoint` con solo `node_a` no sostiene
  nada y no avisa.
- **El jugador kinemático frena a los rígidos.** Para el solver un `KinematicBody` es masa
  infinita: parado sobre un brazo, lo clava. Toda pieza móvil que el jugador pueda pisar
  registra una excepción de colisión **desde la pieza** (`part.add_collision_exception_with(player)`).
  Es unilateral a propósito: el solver deja de ver al jugador, pero las consultas de
  `move_and_slide` usan la lista de excepciones del jugador y siguen viendo la pieza.
- **Sobre `RigidBody` no hay acarreo por delta de transform.** `move_and_slide` ya suma la
  velocidad del piso en el punto de contacto; sumar el delta duplica el movimiento. Las
  plataformas kinemáticas (ascensor, `MovingPlatformV2`) conservan el acarreo por delta.
- **El jugador va un tick detrás de la pieza** (procesa antes que el solver). Al
  desprenderse se recupera ese tramo (`v * dt`) o el slide siguiente arranca incrustado y
  frena en seco.
- **`velocity` sola no transfiere momentum.** Al tick siguiente la pisan `movement_logic`
  (horizontal) y `jump_logic` (vertical). Todo impulso externo que deba conservarse entra
  por `_apply_launch_momentum()`.

## Reglas de desprendimiento

- **Inercial:** si la velocidad vertical de la pieza en el punto de contacto cae más rápido
  que la gravedad del jugador (y venía subiendo a más de 1.5 m/s), el jugador sale con la
  velocidad del tick anterior.
- **Voluntario:** saltar o caerse de la pieza hereda la velocidad del punto de contacto.
- **Vuelo balístico:** sin input no hay fricción de aire; con input se redirige la
  velocidad sin perder rapidez.
- **Histéresis de 3 ticks** en el contacto: una pieza que acelera hacia arriba se incrusta
  en la cápsula y el contacto de piso parpadea.

## No resuelto

- No hay desprendimiento por aceleración horizontal (un carro que frena en seco no tira al
  jugador hacia adelante).
- El jugador no ejerce peso sobre la pieza: pararse en un balancín no lo inclina.
- El estado de vuelo no viaja en los snapshots de replay.
