# Odisea: El Arca Silenciosa — MVP Acto I


Odisea es un juego de plataformas 3D en tercera persona ambientado en una nave espacial, enfocado en el Acto I: “El Sepulcro Criogénico”. Controlas a Elías explorando la nave Odisea con mecánicas de movimiento, plataformas móviles y narrativa ambiental.

## Estructura del Proyecto (2026)

- **src/core_v2/**: Todo el código fuente activo y refactorizado (componentes, sistemas, player_controller, UI, autoloads, simulación, utilidades, tests).
- **docs/canon/**: Especificaciones y features fundacionales implementados (OdysseyScript, interactuables, pushable box, gamefeel, sidescroller, test battery, test runner, etc).
- **docs/archived/**: Features descartados o legacy (ver notas en cada archivo).
- **AGENTS.md**: Contratos de desarrollo, determinismo y normas de trabajo.

## Contratos y Normas

Consulta **AGENTS.md** para reglas de determinismo, contratos de agentes, y normas de desarrollo (commits pequeños, tests con GdUnit3, todo en core_v2, etc).

## Features Fundacionales (Canon)

Las siguientes features están implementadas y documentadas en `docs/canon/`:
- OdysseyScript DSL y replay determinista
- Sistema de interactuables y sensores
- PushableBox híbrido determinista
- Refinamiento de gamefeel y mecánicas
- Transición 2.5D sidescroller
- Test battery y runner de regresión determinista

## Descarga e Instalación

### Requisitos y Ejecución
1. Descarga Godot 3.6.x desde el sitio oficial: [godotengine.org/download](https://godotengine.org/download).
2. Abre el proyecto en Godot 3.6.x y ejecuta la escena principal: `res://scenes/Menu.tscn`.

### Testing determinista
Para validar determinismo y replays:
```sh
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```
Consulta los features canonizados en `docs/canon/` para ejemplos de scripts y tests.
