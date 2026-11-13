# RingHub + Bahía — bitácora de cierre, 2026-11-13

## Alcance aprobado

Traversal con las cuatro máquinas existentes; caída/rearme/Continuar confiables, válvula y final inequívocos, retorno al RingHub sin repetir despertar. Sin editor de construcción, domos nuevos ni reescritura del controlador. Candidata revisable, no aceptación humana automática.

## Base y cuidado del árbol

Rama `feat/vs-bahia-maquinas`. Hay cambios previos de otras sesiones en movimiento, interacción, props, escenas, materiales e imports. No se han reseteado ni incluido indiscriminadamente. Inventario detallado y logs intermedios en `/tmp/prospero-1000/20261113-040247-689a/` (temporales, no evidencia durable).

## Implementado y comprobado

- `4aa156bc`: Continue restaura mundo; nueva partida limpia progreso deliberadamente.
- `f859f472`: checkpoints seguros y recuperación mecánica consistente.
- `aa7de4f9`: cierre ligado a válvula, sin bypass administrativo; reloj del rotor unificado.
- `a7423e73`: payload de regreso con pose/estado, sin repetir despertar.
- `591a7fc0`: láser evita orientar partículas con normal cero; conserva lógica del haz/hit.
- `d5ab933f`: regresión de independencia del payload en snapshot.

Última validación focalizada antes de retomar el bloque nocturno:

```text
pytest tests/test_odisea_runner.py -q -k 'test_machine_level or test_machine_bay or test_ringhub_wakeup or test_ringhub_light_state or test_menu_checkpoint_flow'
5 suites passed, 170 deselected, 128.12s
pytest tests/test_odisea_runner.py -q -k test_multitool_laser
1 suite passed (3 casos), 174 deselected
check_tracked_imports.py: 952 manifests correctos
check_critical_import_artifacts.py: 19 críticos correctos
```

La prueba de checkpoints usa caída real, nuevo Pilot y consulta de su cápsula en cuatro estaciones. Las pruebas balísticas por estación no equivalen al recorrido continuo: algunas quitan checkpoints/killzones para aislar trayectorias.

## Reanudación nocturna

- Delegación a Kilo / DeepSeek V4.1 Flash, solicitada por Sebastián: auditoría solo lectura y prueba nueva de segmento por input en archivos disjuntos.
- Intentos anteriores de captura en Xvfb/llvmpipe dieron timeout: no acreditan pulido visual.
- Display actual `:0`, Mesa Intel Iris Xe acelerada: captura real de MachineBay conseguida a 960×540 y abierta para revisión.
- Poses de inspección: spawn `(0, 0.65, -2)`, yaw PI, pitch -0.12; aproximación `(0, 3.5, 14)`. Son teletransportes de inspección, NO prueba de tránsito.
- Observación: superficies oscuras, textura metálica de gran escala en carcasa, señales lejanas ilegibles. No inferir geometría ni corrección del recorrido de esos píxeles. No cambiar física para corregir composición.
- HUD informa 1 fps en instancia sin foco: no usarlo como presupuesto de rendimiento del dispositivo final.
- Ensayo visual de carcasa: desactivar el albedo usado como normal y aumentar tiling redujo ruido de pared en spawn/péndulo; suites machine_bay y machine_level pasaron (101.14s). Se revirtió exclusivamente ese ensayo: la función de materiales completa era trabajo previo sin commit y no se debe incorporarla por accidente. Queda propuesta visual, no cambio entregado.
- La captura `night_sign1_close` tuvo input de hardware activo (láser/disparos y subtítulos de otras estaciones): no es comparativa controlada y se descarta para aceptación. En futuras capturas deshabilitar hardware_input_enabled antes de fijar poses. No inferir juego correcto de esta evidencia contaminada.

## Segundo bloque: integración y señalética

- `2eb0943b`: FD-320 e índice reconciliados con alcance vigente; se separan backlog, implementación y aceptación humana.
- `47fb1cf6`: dos casos prueban productores reales de payload de entrada/regreso a través de la cola real de SceneManager, sin swap ni escritura de saves. pytest focalizado: 1 suite correcta en 0.77s. No equivale a probar el fade/swap completo.
- Capturas controladas a 960×540, Intel Iris Xe: rotor `(0,13.6,61)` y válvula `(0,10.6,80)`, yaw PI/pitch -0.12, hardware input deshabilitado. Se abrieron ambas. Válvula/controles visibles; letreros pequeños y textura de carcasa aún ruidosa.
- Señalética: alternar material de una/dos caras y opacidad no arregló por sí solo la lectura (ensayos solo runtime). El viewport de origen sí contiene letras completas: no atribuir el fallo al texto sin evidencia.
- `848dd6d9`: corregida escala de carteles que `_place` borraba al asignar transform; ahora escala escalar/array se conserva al colocar y rearmar. Regresión inicial/reset y machine_level: 2 suites correctas en 7.58s. Captura posterior a arranque limpio abierta; runtime confirmó `SignStation1.scale == (1.6,1.6,1)`. Aumenta tamaño correcto, pero no resuelve por sí solo lectura/contraste ni saturación del HUD.
- Precaución de captura: las suites comparten el player_id persistido con el juego gráfico; no enviar comandos mientras otro proceso esté conectado con la misma identidad. La instancia gráfica puede ser desplazada del peer por el runner. Seleccionar/reconectar y verificar sesión antes de actuar.
- Test adicional de lanzamiento `test_machine_launch`: 1 suite correcta en 12.10s. Manifests revalidados: 952 y 19 críticos, sin limpieza de imports.
- No quedó aplicada ninguna modificación nueva de luz/carcasa. Se cerraron las instancias gráficas propias al acabar las comparativas; no se cerró el editor del usuario.

## Auditoría HUD (siguiente bloque)

Diagnóstico solo lectura de Kilo: `_place_context` limita fit por altura, no por ancho; las labels del widget no envuelven texto. Una descripción larga puede exceder el área segura. Subtítulos y contexto se anclan independientemente cerca del borde inferior: limitar ancho no resolverá por sí solo la colisión vertical. Se encargó regresión y fix mínimo de contención horizontal, sin cambiar slots de esquina ni subtítulos. Revisión de aislamiento concluida: `e1eb77ac` restaura iluminación mediante setters (incluye uniforms de materiales cacheados) y explicita la precondición FREE/sin latch del segmento por input. Ambas suites verdes en 2.99s. No se encontró defecto bloqueante en el payload.

`bb058ec0`: límite horizontal uniforme del contexto HUD, conservando centro/ancla inferior. La regresión de texto largo falló antes (bordes x=-14547..15507 en viewport 960) y pasó con el fix; suite host: 24 casos, pytest 1 suite correcta en 2.26s. Captura posterior abierta a 960×540: contenido dentro de pantalla, pero sigue colisión con Modo Láser/debug y proximidad a subtítulos. No declarar cerrado el HUD. Texto excesivo puede quedar pequeño: pendiente presentación legible, no añadir más shrink como solución estética.

## Regresión combinada al cerrar el bloque

`pytest tests/test_odisea_runner.py -q -k 'test_machine_bay or test_machine_level or test_machine_sign_scale or test_ringhub_wakeup or test_ringhub_light_state or test_menu_checkpoint_flow or test_multitool_laser'`: **9 suites correctas, 169 excluidas, 129.21s**. Incluye retorno y ruta de entrada por coincidencia del nombre `test_machine_bay`. No se ejecutó suite completa.

## Pendiente / aceptación humana

1. Extender segmentos reproducibles por input público hacia abordaje/aterrizajes. Primer segmento entregado en `d4be0d54`: spawn → aproximación de palanca 1 caminando con InputMap/InputProvider reales, checkpoint y KillFloor activos, sin teleport al destino ni velocidades privadas. Con retorno: 2 suites correctas en 3.02s. Esto NO prueba las cuatro estaciones de corrido.
2. Comparativas controladas de aproximación/acción/llegada en las cuatro estaciones y válvula.
3. Revisar transición real menú → hub → bahía → regreso, no solo productor/consumidor aislados.
4. Dos recorridos completos con gamepad sin consola; claridad del destino, abordaje, ventana de salto y rearme.
5. Reiniciar/Continuar a mitad del recorrido y comprobar mundo/pose/objetivo.
6. Aprobar capturas y medir rendimiento en hardware elegido.

No declarar terminado el slice antes del checkpoint humano. La restricción inicial de no push/merge fue reemplazada por autorización explícita de Sebastián: incluir todo el trabajo pendiente, integrar en main y hacer push para un release nuevo. No cambiar el motor adicionalmente.

## Preintegración autorizada

- 14 suites focalizadas correctas (146.47s): máquinas, lanzamiento/roll, ruta/retorno, multitool, guardado, despertar/luces, HUD.
- `--oys test_salto_desplazamiento`: grabación/replay correctos, drift posicional y rotacional dentro de umbral. El JSON generado se restauró a su versión previa: no es un cambio de producto.
- Invocación directa de `test_determinism_v2` sin flag ejecuta skip, por eso NO se cuenta como cobertura de determinismo; se usó el OYS explícito anterior.
- Smoke rápido de imports con fork correcto, sin limpieza de cache. Manifests: 952/19 críticos correctos; 8 presets coherentes.
- Incluye cambios pendientes autorizados de movimiento/traversal, tractor/corte, props, escenas y artefactos versionados. El cascarón `build/machine_bay/bay_shell.glb` continúa opcional/ignorado: la captura local con carcasa no demuestra su presencia en release.
