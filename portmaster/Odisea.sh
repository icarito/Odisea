#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR=/$directory/ports/odisea
CONFDIR="$GAMEDIR/conf"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

cd $GAMEDIR

mkdir -p "$CONFDIR"

# XDG apunta a conf/ para que los saves y la config queden dentro del port.
export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="/usr/lib:$GAMEDIR/lib:$LD_LIBRARY_PATH"

# El mando se lee nativo (Godot/FRT). Ningun dispositivo se detecta: si un firmware
# reporta los ejes al reves, el jugador lo corrige en Opciones -> Invertir X / Y.

# Handhelds lentos de la generacion RK3326 (Mali-G31, 1 GB): perfil bajo desde el
# arranque (SessionManager) y ajustes de render que solo pueden ir en override.cfg.
# En el resto de los dispositivos no se toca nada. Un override.cfg editado a mano
# (sin la marca de lowend.cfg) se respeta siempre.
if grep -qa "rockchip,rk3326" /proc/device-tree/compatible 2>/dev/null \
   || grep -qs "Mali-G31" /sys/class/misc/mali0/device/gpuinfo; then
  export ODISEA_EARLY_WEAK_HARDWARE=1
  # Modo plano (albedo unshaded por superficie, FlatFake.shader): sin PBR ni lightmap,
  # el color sale del material de cada superficie. Es la contraparte del gouraud que ya
  # aplica el tier LOW. Se puede pisar desde dev.sh (0 lo apaga, 2 = unshaded con textura).
  export ODISEA_UNSHADED="${ODISEA_UNSHADED:-3}"
  # Refresca el override.cfg generado por este archivo en cada arranque, para que un
  # paquete nuevo (p.ej. el bloque [audio] de FD-299) llegue a un handheld ya instalado.
  # Un override.cfg editado a mano (sin la marca FD-299) se respeta (linea 41).
  if [ ! -f override.cfg ] || grep -qs "odisea-lowend-cfg\|FD-299: ajustes de arranque" override.cfg; then
    cp lowend.cfg override.cfg
  fi
elif grep -qs "odisea-lowend-cfg\|FD-299: ajustes de arranque" override.cfg; then
  # Copia de este archivo o el override.cfg que traian los nightlies anteriores.
  rm -f override.cfg
fi

# Los updates llegan por PortMaster (fuente "Odisea Nightly"). El updater del
# juego no puede relanzar FRT, asi que se apaga.
export ODISEA_UPDATES_MANAGED_BY=PortMaster

# Motor. El paquete trae nuestro propio binario FRT con el modulo Box3D, que es
# el backend de fisica que el juego pide en project.godot. El runtime frt_3.6 de
# PortMaster es Godot stock: arranca igual, pero cae a Bullet en silencio.
# Borrar odisea.frt.aarch64 del dispositivo fuerza ese fallback, que es la forma
# de comparar Box3D contra Bullet en el mismo hardware.
ENGINE_BIN="$GAMEDIR/odisea.frt.aarch64"
mounted_runtime=""

if [ -f "$ENGINE_BIN" ]; then
  $ESUDO chmod +x "$ENGINE_BIN"
  ENGINE="$ENGINE_BIN"
  # pkill matchea /proc/<pid>/comm, truncado a 15 chars: el nombre completo
  # "odisea.frt.aarch64" nunca aparece entero y el kill switch queda muerto.
  KILL_NAME="odisea"
else
  runtime="frt_3.6"
  if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
      pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
      sleep 5
      exit 1
    fi
    $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}.squashfs"
  fi
  godot_dir="$HOME/godot"
  godot_file="$controlfolder/libs/${runtime}.squashfs"
  $ESUDO mkdir -p "$godot_dir"
  $ESUDO umount "$godot_file" || true
  $ESUDO mount "$godot_file" "$godot_dir"
  PATH="$godot_dir:$PATH"
  mounted_runtime="$godot_dir"
  ENGINE="$runtime"
  KILL_NAME="$runtime"
fi

# FRT usa Select como Force Quit por defecto; lo desactivamos.
export FRT_NO_EXIT_SHORTCUTS=FRT_NO_EXIT_SHORTCUTS

# gptokeyb2 no mapea nada a proposito (ver odisea.ini): el juego lee el pad
# nativo. gptokeyb2 solo aporta el kill switch Start+Select.
$GPTOKEYB2 "$KILL_NAME" -c "$GAMEDIR/odisea.ini" &

# Gancho de desarrollo. Si existe odisea/dev.sh se sourcea aca, despues de que
# PortMaster definio GODOT_OPTS y antes de lanzar el juego. Ahi van cosas como
#   GODOT_OPTS="$GODOT_OPTS --remote-debug 192.168.x.x:6007"
#   export ANNA_ENABLED=1
# El paquete publicado NO trae dev.sh; es un archivo que se copia a mano.
[ -f "$GAMEDIR/dev.sh" ] && source "$GAMEDIR/dev.sh"

pm_platform_helper "$ENGINE"

# Siempre GLES3: el juego es GLES3 y el paquete no trae texturas para GLES2.
# FRT habla EGL/SDL2, asi que el stub de libGL de ROCKNIX no importa.
"$ENGINE" $GODOT_OPTS --video-driver GLES3 --main-pack "odisea.pck"

if [ -n "$mounted_runtime" ] && [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "$mounted_runtime"
fi
pm_finish
