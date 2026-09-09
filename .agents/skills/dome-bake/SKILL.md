---
name: dome-bake
description: Dominar el pipeline de horneado del domo de criogenia de Odisea (hub tower, criopods, scaffold, pipes, signage). Usar cuando se pida cambiar la geometria del domo — abrir aberturas o rutas en los pisos del hub, agregar o quitar criopods, mover pasarelas o pipes — o cuando haya que rehornear, splicear, o entender por que un cambio en una escena fuente no aparece en el juego.
---

Pipeline de horneado del domo. Paths relativos a `src/`.

Doc canonico con el mapa completo fuente → baker → producto:
`docs/agents/dome_source_mapping.md`. Esta skill es la capa operativa.

## La regla

**Nunca editar el producto. Editar la fuente y hornear.** Los `.mesh`/`.shape`/
`.material` de `core_v2/levels/interiors/` son salida de un baker; una edicion
ahi se pierde en el proximo horneado sin aviso.

Las fuentes son `DomeIntro_*Source.tscn`. Cada una tiene UN baker en `tools/`.

## El lazo, de mas rapido a mas lento

```sh
# 1. probar un patron — segundos, no escribe nada
make preview-dome-variant VARIANT=DomeIntro

# 2. hornear geometria — minutos
make bake-dome-geometry                       # pipes + scaffold + hub floors
godot3-bin --path . --no-window -s tools/bake_dome_intro_criopods.gd
python3 tools/splice_criopod_bake.py          # SOLO criopods, ver abajo

# 3. verificar
godot3-bin --path . --no-window -s tools/check_hub_ring_skipped_sides.gd
```

En el editor el lazo es inmediato: los `Floor_N` no sobreescriben `auto_build`,
asi que tocar `skipped_sides`/`outer_openings_deg` en el inspector reconstruye el
piso en el acto. El guard de `_ready()` solo evita el rebuild al ABRIR la escena.
Guardar la fuente es inofensivo — sus `CombinedMesh` embebidos son vista previa.

`ODISEA_BAKE_SOURCE` y `ODISEA_BAKE_PREFIX` cambian fuente y prefijo de salida de
cualquier baker. Util para hornear en paralelo sin pisar Dome_Intro; ojo que el
producto con otro prefijo **no tiene consumidor** salvo que se lo enchufe a mano.

## Trampas, todas verificadas en vivo

**El hub es compartido.** `Dome_Base.tscn` contiene el `ScaffoldHubTower` y lo
instancian Dome_Intro **y** Dome_Prologue. Hornear el hub cambia las dos escenas
sin editar ninguna. Hoy no pueden diferir.

**Los criopods necesitan splice, el resto no.** Las mallas se sobreescriben en su
sitio, asi que el hub/scaffold/pipes quedan aplicados solos. Pero la lista de
`CollisionShape` de los criopods cambia con el conteo, y eso vive en
`Dome_Intro.tscn`: hay que correr `splice_criopod_bake.py`. El splicer limpia
solo los `ext_resource` que quedan huerfanos.

**El conteo de criopods NO sale de los nodos `Item_N`.** Las rings traen
`rebuild_baked_items = true`, asi que `RadialScatter._ready()` los regenera antes
de que el baker los lea. Las perillas son `item_count` (40) y
`blocked_angle_ranges_deg`. Con 40 slots el paso es 9° = 5 pods por sector de 45°
del hub. Para sacar una ring entera hay que borrar su nodo `Criopods<N>`; poner
`item_count = 0` hace fallar el baker.

**Los criopods se paran sobre el deck del hub.** Estan a r=12 y el deck va de 6 a
13. `Criopods{N+1}` sobre `Floor_N` (y = 4.5*N); `Criopods1` esta en el suelo.
Un sector salteado en el hub sin su bloqueo en los criopods deja 5 pods por piso
flotando. `blocked_angle_ranges_deg` y `outer_openings_deg`/`skipped_sides`
comparten marco angular: el sector `k` se tapa con `Vector2(45k, 45(k+1))`.

**Tres cosas que hay que rehacer cada vez que cambia `skipped_sides`.** Ninguna
se ve en un diff ni en una foto. Corre las tres:

```sh
python3 tools/check_criopod_layout.py   # DESPUES de hornear criopods
```

- *Baranda atravesando un pod*: el borde radial de un sector salteado se cierra
  con baranda, que cruza donde hay pods. Hacen falta ~0.80 m de holgura a r=12
  (media caja 0.73 + tubo 0.07) = **4° de margen** a cada lado del bloqueo.
- *Pod suelto*: un slot aislado entre dos bloqueos contiguos queda como un
  criopod flotando solo. Se tapa con un `Vector2(ang-2, ang+2)`; los vecinos
  estan a 9°.
- *Techo sin donde pararse*: **el propósito de las aberturas es subir saltando**,
  asi que cada piso tiene que abrir al menos un sector que el piso de abajo
  tenga cerrado. Extender un hueco doble hacia ADELANTE tapa justo el sector que
  el piso de arriba abre y rompe esto; extenderlo hacia atras no.

**No reserializar `Dome_Intro.tscn` entero.** `PackedScene.pack()` sobre una
instancia viva se lleva puesto el estado de runtime y borra overrides. Por eso el
splicer hace reemplazo textual. Nunca reemplazarlo por un resave.

**Antes de culpar a un cambio, correr el verificador contra HEAD.**
`verify_dome_intro_contract.gd` viene fallando con "Terrace floor or dome shell
is missing" desde antes; confirmar con `git checkout HEAD -- <escena>` y volver a
correr en vez de perseguir un fantasma.

## Verificar de verdad

Una foto de la torre no prueba que la escena cargue la malla nueva. Lo que sirve:
cargar la escena headless y comparar los vertices por `Floor_N` contra el log del
baker, y contar los hijos del `StaticBody` de cada ring de criopods. Los numeros
del baker y los del runtime tienen que coincidir.
