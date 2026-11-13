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

## Pendiente / aceptación humana

1. Segmentos reproducibles por input público con checkpoints activos.
2. Comparativas controladas de aproximación/acción/llegada en las cuatro estaciones y válvula.
3. Revisar transición real menú → hub → bahía → regreso, no solo productor/consumidor aislados.
4. Dos recorridos completos con gamepad sin consola; claridad del destino, abordaje, ventana de salto y rearme.
5. Reiniciar/Continuar a mitad del recorrido y comprobar mundo/pose/objetivo.
6. Aprobar capturas y medir rendimiento en hardware elegido.

No declarar terminado el slice antes del checkpoint humano. No push, merge ni cambios del motor en este bloque.
