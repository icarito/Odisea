# Kilo Entry Point For Odisea

Leer primero `AGENTS.md`. Los comandos slash de Kilo estan en `.kilo/command/`, pero la
documentacion canonica compartida esta en:

- `docs/agents/README.md`
- `docs/agents/tooling.md`
- `docs/agents/skills-index.md`
- `docs/skills/`

Cuando un comando de `.kilo/command/` duplique un workflow de `docs/skills/`, tratar
`docs/skills/` como fuente canonica y el archivo de Kilo como adaptador.

## Uso headless desde un orquestador

Para subagentes batch, la guia canonica esta en `docs/agents/tooling.md`, seccion
"Kilo CLI como subagente batch". Resumen:

```bash
timeout 120 /usr/bin/kilo run \
  --dir /home/icarito/Proyectos/Odisea_Game/src \
  --agent code \
  -m kilo/deepseek/deepseek-v4.1-flash \
  --auto --format json \
  --title "titulo corto" \
  "prompt con write set explicito, sin commit ni deploy"
```

Usar `--agent ask` para exploracion/lectura y `--agent code` para cambios. Ejecutar
delegaciones en serie; varias corridas simultaneas pueden chocar en credenciales Kilo.
