#!/bin/bash
# PORTMASTER: odisea.zip, Odisea.sh
#
# Basado en la plantilla canonica de PortMaster para runtime Godot 3.6 (frt_3.6).
# No agregar aca banderas de desarrollo: para eso existe odisea/dev.sh (ver abajo),
# que no viaja en el paquete publicado.

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

# Perfil de input/graficos del handheld: InputProviderV2 invierte los ejes del
# joystick y SessionManager baja el perfil grafico cuando ve este valor.
export ODISEA_DEVICE=anbernic

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
fi

# FRT usa Select como Force Quit por defecto; lo desactivamos.
export FRT_NO_EXIT_SHORTCUTS=FRT_NO_EXIT_SHORTCUTS

$GPTOKEYB "$(basename "$ENGINE")" -c "./odisea.gptk" &

# Gancho de desarrollo. Si existe odisea/dev.sh se sourcea aca, despues de que
# PortMaster definio GODOT_OPTS y antes de lanzar el juego. Ahi van cosas como
#   GODOT_OPTS="$GODOT_OPTS --remote-debug 192.168.x.x:6007"
#   export ANNA_ENABLED=1
# El paquete publicado NO trae dev.sh; es un archivo que se copia a mano.
[ -f "$GAMEDIR/dev.sh" ] && source "$GAMEDIR/dev.sh"

pm_platform_helper "$ENGINE"

# Driver de video. ROCKNIX no tiene GL de escritorio (su libGL.so.1 es un stub y
# glxinfo falla), asi que por defecto va GLES2. Pero FRT habla EGL/SDL2, no GLX:
# que glxinfo falle no dice nada sobre GLES3, y la Mali-G31 soporta GLES 3.2.
# ODISEA_VIDEO_DRIVER (tipicamente desde dev.sh) fuerza uno u otro para probar.
if [ -z "$ODISEA_VIDEO_DRIVER" ]; then
  if [[ "$CFW_NAME" = "ROCKNIX" ]] && ! glxinfo | grep -q "OpenGL version string"; then
    ODISEA_VIDEO_DRIVER="GLES2"
  fi
fi

if [ -n "$ODISEA_VIDEO_DRIVER" ]; then
  echo "[Odisea] video driver: $ODISEA_VIDEO_DRIVER"
  "$ENGINE" $GODOT_OPTS --video-driver "$ODISEA_VIDEO_DRIVER" --main-pack "odisea.pck"
else
  echo "[Odisea] video driver: (default del motor)"
  "$ENGINE" $GODOT_OPTS --main-pack "odisea.pck"
fi

if [ -n "$mounted_runtime" ] && [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "$mounted_runtime"
fi
pm_finish
