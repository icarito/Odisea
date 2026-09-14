# FD-229 — Gate de TheGates servido por el deploy nocturno

## Contexto

TheGates (https://thegates.io) es un browser 3D cuyo launcher carga "gates"
desde URLs. Con el PR `thegatesbrowser/thegates#1` el launcher soporta gates
que declaran `godot_version = "3.6"` y les baja un renderer nativo desde el
backend; el renderer compatible ya se publica como asset `linux-3.6` en el
release nocturno de `icarito/godot-box3d-3` (Godot 3.6 + Box3D + module
`the_gates`).

Falta la pieza Odisea: que el deploy nocturno normal publique un `.gate`
accesible por URL para que el launcher lo abra sin nigun paso manual.

## Contrato del launcher

- El usuario pega una URL; `fix_gate_url` agrega `world.gate` si la URL no
  termina en `.gate`.
- Los campos del `.gate` se resuelven **relativos al directorio del .gate**
  (`Url.join`), o absolutos si empiezan con `http`.
- `godot_version = "3.6"` selecciona el renderer 3.6.

## Implementación

Nada de servidores nuevos: el stage `HTML5 Stage TheGates` del workflow
`export_all.yml` escribe en la raíz de Pages (que ya publica `index.pck` en
cada nocturno):

- `world.gate` — `resource_pack = "index.pck"` resuelve same-origin, sin
  duplicar el pack; `godot_version = "3.6"`.
- `thegates-icon.png` / `thegates-image.png` — el icono del proyecto
  (`assets/odisea_icon.png`, el mismo que usa de favicon el shell web) y el
  splash (`assets/splash_HI-RES.png`).

URLs resultantes:

- `https://icarito.github.io/Odisea/world.gate`
- `https://icarito.github.io/Odisea` (el launcher agrega `world.gate` solo)

Los otros destinos no tienen el `index.pck` crudo (Netlify lo toma de Pages;
Vercel solo sube el `.gz` por el límite de 1 GiB por archivo), así que su
`world.gate` lleva `resource_pack`, `icon` e `image` absolutos a Pages:

- `https://odisea-game.netlify.app/world.gate` y `https://odisea-ios.vercel.app/world.gate`
  — el mismo stage los escribe en `build/netlify/` y `build/vercel/`.
- `https://odisea.educa.juegos/world.gate` — la landing del VPS no pasa por
  este workflow: `scripts/nightly-refresh.sh` (instalado como
  `/usr/local/bin/odisea-nightly-refresh`, cron + webhook de release) lo
  escribe junto a `nightly.json` con la versión de la release. Tras cambiar el
  script hay que reinstalarlo en el VPS.

El pack del preset HTML5 Threads es portable: mismos filtros de recursos que
los presets desktop y `script_export_mode=0` (scripts fuente), y la física
Box3D viaja en el binario del renderer, no en el pack.

## Notas

- `discoverable = false`: el gate se carga por URL directa; no se anuncia en
  el feed de descubrimiento del backend hasta que haya backend que lo haga.
- El renderer 3.6 todavía no está en el backend de TheGates: para probar end
  to end, el harness `serve.py` del PR hace de backend apuntando al asset
  `linux-3.6` del nocturno de godot-box3d-3.
- Desde `v0.2.6-nightly5` el fork publica también `macos-3.6` y `windows-3.6`
  (thegatesbrowser/thegates#2 y #3). Compilan, pero no se probaron aún contra un
  launcher en Mac ni en Windows; en Linux Odisea corre completo.
