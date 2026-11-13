# FD-172: Mapamundi 3D Interactivo

**Status:** Draft
**Priority:** Medium
**Effort:** Medium
**Created:** 2026-06-13

## Problem

El mapamundi actual (`GlobeView.tsx`) usa `react-simple-maps` que renderiza un SVG 2D plano. Es funcional pero no tiene impacto visual — no hay profundidad, rotación, ni animaciones. Los dots aparecen estáticos.

Queremos un globo 3D real con efectos y animaciones que haga justicia a la estética sci-fi de Odisea.

## Solution

Reemplazar `GlobeView.tsx` con un componente basado en **Three.js** (ya instalado: `three`, `@react-three/fiber`, `@react-three/drei`).

### Visual Target

Globo 3D oscuro estilo sci-fi con:
- Esfera wireframe/translúcida que gira lentamente
- Atmósfera glow alrededor
- Dots geo pulsantes en las ubicaciones de jugadores
- Partículas flotando cerca de la superficie
- Fondo espacial con estrellas

### Interactividad

- **Rotación libre** con drag del mouse/touch (orbit controls)
- **Zoom** con scroll/pinch
- **Auto-rotación lenta** cuando no se interactúa (3-5 segundos de idle)
- **Hover** sobre dots: tooltip con ciudad, país, cantidad de jugadores
- **Click** sobre dot: deep-link al player focus

### Efectos y animaciones

| Efecto | Descripción |
|--------|-------------|
| Rotación idle | Globo gira ~0.15 rad/s sobre eje Y cuando no hay interacción |
| Atmósfera glow | Esfera semitransparente exterior con gradient azul/cyan |
| Dots pulsantes | Círculos en la superficie que escalan rítmicamente (sine wave) |
| Partículas orbitales | Pequeños puntos que orbitan el globo a diferentes altitudes |
| Aparición de dots | Nuevos dots hacen scale-in con easing |
| Transición de status | Dot cambia de color con lerp (connected→amber, recent→gray) |
| Estrellas de fondo | Particle system de fondo con parallax sutil |
| Grid lines | Líneas de latitud/longitud sutiles en la superficie |

### Performance

- InstancedMesh para dots (>100 sin problema)
- LOD: reducir segmentos de esfera en mobile
- `frameloop="demand"` cuando no hay animaciones activas

## Technical Spec

### Dependencias (ya instaladas)

```
three: ^0.184.0
@react-three/fiber: ^9.6.1
@react-three/drei: ^10.7.7
@types/three: ^0.184.1
```

### Componentes nuevos

```
dashboard/src/components/
├── Globe3D/
│   ├── Globe3D.tsx          — contenedor principal (Canvas + suspenso)
│   ├── GlobeSphere.tsx      — esfera del planeta (wireframe + superficie)
│   ├── Atmosphere.tsx       — glow exterior
│   ├── GeoDots.tsx          — dots geo como InstancedMesh
│   ├── OrbitalParticles.tsx  — partículas orbitando
│   ├── Starfield.tsx        — fondo de estrellas
│   ├── GridLines.tsx        — lat/long lines
│   └── useGlobeAnimation.ts — lógica de animación (idle rotation, pulses)
├── GlobeView.tsx            — wrapper que reemplaza el actual, mantiene misma interfaz
```

### Data interface (sin cambios)

```ts
interface GeoPlayer {
  player_id: string;
  country: string;
  country_code: string;
  city: string;
  latitude: number;
  longitude: number;
  status: 'connected' | 'recent' | 'old';
  display_name?: string;
  color?: string;
}
```

### Conversión lat/lng → coordenadas 3D en esfera

```ts
function latLngToVec3(lat: number, lng: number, radius: number): [number, number, number] {
  const phi = (90 - lat) * (Math.PI / 180);
  const theta = (lng + 180) * (Math.PI / 180);
  return [
    -radius * Math.sin(phi) * Math.cos(theta),
    radius * Math.cos(phi),
    radius * Math.sin(phi) * Math.sin(theta),
  ];
}
```

### Estados del dot

- **connected** (verde `#3fb950`): pulso rápido, glow exterior
- **recent** (ámbar `#d29922`): pulso medio
- **old** (gris `#8b949e`): estático, opacidad reducida

### Tooltip

Usar `<Html>` de drei para tooltip HTML sobre dots en hover:
```
🇧🇷 Brasiléia, Brazil
3 jugadores
```

## Scope

**In scope:**
- Globe3D con todos los componentes listados
- Interactividad completa (orbit, zoom, hover, click)
- Animaciones: rotación idle, dots pulsantes, estrellas, atmósfera
- Reemplazo drop-in de GlobeView actual

**Backlog:**
- Efecto de transición cámara cuando se hace click en un dot (fly-to)
- Heatmap 3D sobre la superficie
- Modo VR/daydream

## Files Changed

- `dashboard/src/components/GlobeView.tsx` — wrapper hacia Globe3D
- `dashboard/src/components/Globe3D/*` — 7 archivos nuevos
- `dashboard/src/App.tsx` — sin cambios (misma interfaz)
- `dashboard/package.json` — sin cambios (deps ya instaladas)

## Acceptance Criteria

1. Globo 3D visible en pestaña Mapa con rotación idle
2. Dots aparecen en ubicaciones correctas (validar con datos reales de `/api/geo-players`)
3. Drag rota el globo, scroll hace zoom
4. Hover muestra tooltip con país/ciudad
5. Dots conectados pulsan en verde
6. No baja de 30fps con 200+ dots
7. Degrada bien en mobile (menos segmentos, sin partículas orbitales)
