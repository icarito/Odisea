# Spec: Reload de Escena via Inyección de PCK (ANNA V2)

Este documento describe la implementación del feature para recargar escenas dinámicamente inyectando archivos PCK desde el central.

## 1. Payload Format (WebSocket)

El central envía un comando al peer a través del WebSocket con el siguiente formato JSON:

```json
{
  "type": "command",
  "id": "abc12345",
  "action": "reload_pck",
  "args": {
    "url": "https://cdn.odisea.juegos/patches/new_feature.pck",
    "scene": "res://scenes/NewScene.tscn"
  }
}
```

- `id`: Identificador único del comando (para el callback de respuesta).
- `action`: Debe ser `reload_pck`.
- `args.url`: URL directa para descargar el archivo PCK.
- `args.scene`: (Opcional) Ruta de la escena a cargar después de montar el PCK. Si se omite, se recarga la escena actual.

## 2. Código del Peer (GDScript 1.x)

Implementado en `core_v2/telemetry/ANNAV2.gd`. El flujo es:
1. Recibir comando.
2. Descargar PCK a `user://temp_injection.pck` usando `HTTPRequest` (modo síncrono para HTML5).
3. Cargar PCK usando `ProjectSettings.load_resource_pack()`.
4. Cambiar a la nueva escena o recargar la actual.

```gdscript
func _cmd_reload_pck(id, args):
	var url = args.get("url")
	if not url or url == "":
		_send_response(id, false, {"error": "missing pck url"})
		return

	var target_scene = args.get("scene")
	var http = HTTPRequest.new()
	add_child(http)

	if OS.has_feature("web"):
		http.use_threads = false

	var temp_path = "user://temp_injection.pck"
	http.download_file = temp_path

	var err = http.request(url)
	if err != OK:
		_send_response(id, false, {"error": "failed to start http request"})
		http.queue_free()
		return

	var result = yield(http, "request_completed")
	var response_code = result[1]

	if response_code != 200:
		_send_response(id, false, {"error": "pck download failed: " + str(response_code)})
		http.queue_free()
		return

	http.queue_free()

	var success = ProjectSettings.load_resource_pack(temp_path)
	if not success:
		_send_response(id, false, {"error": "failed to load resource pack"})
		return

	var current = target_scene if target_scene else get_tree().current_scene.filename
	if current == "": current = "res://scenes/Main.tscn"

	get_tree().change_scene(current)
	_send_response(id, true, {"message": "pck loaded and scene reloaded"})
```

## 3. Código del Endpoint (Python / odisea_central.py)

El central utiliza un endpoint genérico `/command` que actúa como relay. Para enviar el comando `reload_pck` desde el dashboard:

```python
# odisea_central.py
async def handle_command(self, request):
    # ... validación de auth ...
    body = await request.json()
    player_id = body.get("player_id")
    action = body.get("action")
    args = body.get("args", {})

    cmd_id = str(uuid.uuid4())[:8]
    cmd = {
        "type": "command",
        "action": action,
        "args": args,
        "id": cmd_id
    }

    target_ws = self.peer_ws.get(player_id)
    if not target_ws:
        return web.json_response({"error": "player_not_found"}, status=404)

    await target_ws.send_json(cmd)
    # ... esperar respuesta ...
```

## 4. Interfaz Dashboard (React)

En `PlayerCard.tsx` se agregó un botón "Reload Scene" que despliega el formulario de inyección.

```typescript
const handleReload = async () => {
  const res = await sendCommand(hb.player_id, 'reload_pck', {
    url: pckUrl,
    scene: scenePath
  });
  if (res.ok) toast.success('Comando enviado');
};
```
