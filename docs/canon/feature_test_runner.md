Especificación Técnica: Runner de Pruebas de Regresión Determinista

1. Objetivo

Implementar un sistema de pruebas automatizadas utilizando GDUnit3 que recorra recursivamente el directorio de tests, ejecute cada replay encontrado y valide que el resultado de la simulación coincida con el estado final grabado.

2. Convenciones de Archivos

Ubicación Base: res://core_v2/tests/

Patrón de Nombre: replay_test_[description].json

Estructura de Carpetas (Ejemplo):

tests/movement/replay_test_strafing_jump.json

tests/obstacles/replay_test_conveyor_push.json

tests/platforms/replay_test_vertical_elevator.json

3. Requerimientos del Runner (GDUnit3)

A. Escaneo de Datos (Data Provider)

El test debe implementar una función estática o interna que actúe como DataSource.

Lógica: Utilizar Directory para caminar recursivamente por res://core_v2/tests/.

Filtro: Solo procesar archivos que comiencen con replay_test_ y terminen en .json.

Retorno: Un array de paths (Strings) para ser inyectados en el test parametrizado.

B. Ciclo de Ejecución por Test

Para cada archivo path entregado por el Data Provider:

Instanciación: Cargar la escena de pruebas estándar (TestScene_v2.tscn).

Preparación: - Llamar a SessionManager.load_and_play(path).

Extraer la description del nombre del archivo para el reporte de GDUnit.

Simulación:

Dejar que el SessionManager tome el control.

Utilizar yield o esperar a que el SessionManager emita una señal de replay_finished.

Validación (Assertions):

Comparar player.global_transform.origin contra el final_state del JSON.

Umbral de éxito (Threshold): 0.0001.

Validar también rotación (yaw, pitch) si están presentes.

4. Reporte y Diagnóstico

Si el test falla, el mensaje de error de GDUnit debe incluir:
