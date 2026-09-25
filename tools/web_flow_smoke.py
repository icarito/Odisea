#!/usr/bin/env python3
"""Smoke web de Odisea con Playwright: conduce el flujo real y reporta donde se traba.

Flujo: Menu -> NUEVA PARTIDA -> CONTINUAR (aviso de privacidad) -> SI, ACEPTO
(arranca la carga de "Preparando el primer nivel...", con el warmup de shaders
detras) -> espera a RingHub_Level -> TAB + W (salir de la capsula) -> L (linterna).
En cada paso saca screenshot, junta los logs del motor (consola del navegador,
capturada en la pagina para no depender del timing de CDP), guarda el volcado
completo de la consola y cuenta los errores GL.

Ojo con el orden: el nivel NO empieza a cargar al tocar CONTINUAR, sino recien con
la decision de privacidad (FirstRunConsent._on_choice -> loading_requested -> Menu).
Si se espera a RingHub antes de aceptar, la espera se agota contra el aviso quieto.

Objetivo: detectar si la build web llega a RingHub_Level. Si no, el reporte dice en
que paso se quedo y con que ultimos logs.

Firefox: usa el Firefox de Playwright (--browser firefox), no el del sistema: el
Playwright de Firefox necesita su build con el protocolo juggler y un Firefox de
sistema no lo trae. Para apuntar a un binario propio, --executable.

Uso:
  python3 tools/web_flow_smoke.py --browser firefox \
      --url http://127.0.0.1:8768/index.html --outdir /tmp/odisea-web-smoke
"""

import argparse
import json
import os
import re
import sys
import time
import traceback

try:
    from playwright.sync_api import sync_playwright
except Exception as exc:  # pragma: no cover
    print("[fatal] falta playwright: pip install playwright && playwright install firefox", exc)
    sys.exit(2)

COORD = {
    "menu_new_game": (512, 334),
    "consent_continue": (512, 357),
    "consent_accept": (750, 515),
}

WARMUP_DONE = re.compile(r"\[ShaderCacheManager\] compiled:.*RingHubShaderCache")
WARMUP_START = re.compile(r"\[ShaderCacheManager\] compiling:.*RingHubShaderCache")
RINGHUB_READY = re.compile(r"RingHub_Level\.tscn (scene_ready|completed)")
MENU_READY = re.compile(r"Menu\.tscn completed")
KEY = re.compile(
    r"\[ShaderCacheManager\]|\[SceneStartup\]|\[SceneManager\]|\[SessionManager\]|"
    r"\[PerformanceMonitor\]|\[GLES3VendorGate\]|\[MobileLightBudget\]|\[TeleportSystem\]|"
    r"\[LoaderProfile\]|\[UpdateManager\]|\[GLES|ODiSEA|OYS PRINT|SceneManager"
)
GL_ERR = re.compile(r"GL_INVALID_OPERATION|unbound uniform buffer|Feedback loop|too many errors")


def log(*a):
    print(*a, flush=True)


class Smoke:
    def __init__(self, args):
        self.args = args
        self.logs = []          # [page_ms, kind, text]
        self.gl = {"unbound_ubo": 0, "feedback_loop": 0, "other": 0, "total": 0}
        self.events = []
        self.page = None
        self.report = {"browser": args.browser, "url": args.url, "steps": [], "reached_ringhub": False}

    # --- callbacks -------------------------------------------------------
    def on_console(self, msg):
        text = msg.text
        if GL_ERR.search(text):
            self.gl["total"] += 1
            if "unbound uniform buffer" in text:
                self.gl["unbound_ubo"] += 1
            elif "Feedback loop" in text:
                self.gl["feedback_loop"] += 1
            else:
                self.gl["other"] += 1

    # --- helpers ---------------------------------------------------------
    def logs_snapshot(self):
        try:
            return self.page.evaluate("window.__logs") or []
        except Exception:
            return list(self.logs)

    def seen(self, regex):
        return any(regex.search(e[2]) for e in self.logs_snapshot())

    def wait_seen(self, regex, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if self.seen(regex):
                return True
            time.sleep(0.3)
        return False

    def snap(self, name):
        try:
            self.page.screenshot(path=os.path.join(self.args.outdir, name + ".png"))
            return True
        except Exception as exc:
            self.events.append([round(time.time(), 2), "snap_fail " + name + " " + str(exc)[:80]])
            return False

    def step(self, name, note="", snap=True, wait=0.0):
        if wait:
            time.sleep(wait)
        ok = self.snap(name) if snap else True
        entry = {"step": name, "note": note, "t": self.page_ms(), "snap": ok}
        self.report["steps"].append(entry)
        log("[step] %-28s t=%.0fms %s" % (name, entry["t"], note))

    def page_ms(self):
        try:
            return self.page.evaluate("performance.now()")
        except Exception:
            return -1

    def click(self, key):
        x, y = COORD[key]
        self.page.mouse.move(x, y)
        self.page.mouse.click(x, y)

    # --- run -------------------------------------------------------------
    def run(self):
        args = self.args
        with sync_playwright() as pw:
            browser_type = getattr(pw, args.browser)
            launch_kwargs = {"headless": args.headless, "args": []}
            if args.browser == "chromium":
                launch_kwargs["args"] = [
                    "--no-sandbox",
                    "--autoplay-policy=no-user-gesture-required",
                    "--disable-gpu-watchdog",
                    "--disable-features=CalculateNativeWinOcclusion",
                    "--disable-background-timer-throttling",
                    "--disable-renderer-backgrounding",
                ]
                if args.executable:
                    launch_kwargs["executable_path"] = args.executable
            elif args.executable:
                launch_kwargs["executable_path"] = args.executable
            if args.browser == "firefox":
                # Firefox tarda mas en arrancar el motor wasm; sin esto el context
                # corta antes de que el shell termine de cargar el pck.
                # Ademas hay que apagarle el throttling de pestana en segundo plano /
                # ocluida: un frame del primer dibujado de RingHub bloquea el hilo
                # principal decenas de segundos y, si Firefox considera la ventana
                # ocluida o sin foco, suspende requestAnimationFrame. El bucle del
                # motor se detiene despues de first_idle_frame y la escena nunca llega
                # a scene_ready ("Preparando el primer nivel..." para siempre). Chromium
                # no lo sufre porque el tool le pasa los flags anti-throttling de arriba.
                launch_kwargs["firefox_user_prefs"] = {
                    "dom.max_script_run_time": 0,
                    "dom.max_chrome_script_run_time": 0,
                    "dom.timeout.enable_budget_timer_throttling": False,
                    "dom.timeout.background_throttling_max_budget": -1,
                    "dom.min_background_timeout_value": 4,
                    "dom.suspend_inactive.enabled": False,
                    "widget.windows.window_occlusion_tracking.enabled": False,
                    "privacy.reduce_timer_precision": False,
                }

            browser = browser_type.launch(**launch_kwargs)
            ctx = browser.new_context(viewport={"width": 1024, "height": 576}, service_workers="block")
            self.page = ctx.new_page()
            self.page.on("console", self.on_console)
            self.page.on("pageerror", lambda e: self.events.append([round(time.time(), 2), "pageerror " + str(e)[:200]]))
            self.page.on("crash", lambda: self.events.append([round(time.time(), 2), "PAGE CRASH"]))
            self.page.add_init_script(
                """
                window.__logs = [];
                window.__odTiming = {maxGap: 0, last: performance.now(), gaps: [], rafCount: 0};
                ['log','warn','error','info'].forEach(function(m){
                    var o = console[m];
                    console[m] = function(){
                        try {
                            window.__logs.push([Math.round(performance.now()), m,
                                Array.prototype.slice.call(arguments).join(' ').slice(0, 500)]);
                            if (window.__logs.length > 40000) window.__logs.splice(0, 10000);
                        } catch(e) {}
                        return o.apply(console, arguments);
                    };
                });
                (function loop(){
                    var now = performance.now();
                    var gap = now - window.__odTiming.last;
                    if (gap > window.__odTiming.maxGap) window.__odTiming.maxGap = gap;
                    if (gap > 100 && window.__odTiming.gaps.length < 600) window.__odTiming.gaps.push([Math.round(now), Math.round(gap)]);
                    window.__odTiming.last = now;
                    window.__odTiming.rafCount++;
                    requestAnimationFrame(loop);
                })();
                window.__odFocus = function(){
                    return {hasFocus: document.hasFocus(), visibility: document.visibilityState};
                };
                """
            )

            self.page.goto(args.url, wait_until="domcontentloaded", timeout=args.goto_timeout * 1000)
            try:
                self.page.bring_to_front()
            except Exception:
                pass

            self.step("00_loaded", "domcontentloaded")

            if not self.wait_seen(MENU_READY, args.menu_timeout):
                self.step("01_menu_timeout", "no llego '[SceneStartup] Menu.tscn completed'", wait=0.5)
                self.finish("menu_timeout")
                return
            self.step("01_menu", "menu listo", wait=2.0)

            self.click("menu_new_game")
            self.step("02_new_game_clicked", "NUEVA PARTIDA", wait=2.0)

            self.click("consent_continue")
            self.step("03_continue_clicked", "CONTINUAR -> aviso de privacidad", wait=1.5)

            # Aceptar el aviso es lo que ARRANCA la carga: el nivel no se carga hasta
            # la decision (FirstRunConsent._on_choice -> loading_requested). Los botones
            # nacen inertes y se arman 0.5s despues de aparecer (_arm_choice), por eso
            # se espera un poco antes de clickear. Click + Enter por si el foco alcanza.
            time.sleep(0.8)
            for _ in range(3):
                self.click("consent_accept")
                time.sleep(0.6)
                try:
                    self.page.keyboard.press("Enter")
                except Exception:
                    pass
                time.sleep(0.6)
            self.step("04_accepted", "SI, ACEPTO -> arranca la carga", wait=1.0)

            # El warmup es informativo y puede no correr (sin trigger horneado, o
            # porque el codigo nuevo lo movio): no debe bloquear el flujo. Se registra
            # si aparece mientras se espera a que la escena del nivel cargue.
            warmup_started = warmup_done = False
            reached = False
            end = time.time() + args.ringhub_timeout
            while time.time() < end:
                snapshot = self.logs_snapshot()
                if not warmup_started and any(WARMUP_START.search(x) for _, _, x in snapshot):
                    warmup_started = True
                    self.step("05_warmup", "compiling: RingHubShaderCache", wait=0.2, snap=False)
                if not warmup_done and any(WARMUP_DONE.search(x) for _, _, x in snapshot):
                    warmup_done = True
                    self.step("05b_warmup_done", "compiled: RingHubShaderCache", wait=0.2, snap=False)
                if any(RINGHUB_READY.search(x) for _, _, x in snapshot):
                    reached = True
                    break
                time.sleep(0.5)
            self.step("06_ringhub_ready",
                      "cargado=%s warmup=%s/%s" % (reached, warmup_started, warmup_done), wait=3.0)

            # Salir de la capsula y encender la linterna.
            try:
                self.page.keyboard.press("Tab")
                time.sleep(1.0)
                self.page.keyboard.down("w")
                time.sleep(2.5)
                self.page.keyboard.up("w")
                time.sleep(2.0)
            except Exception as exc:
                self.events.append([round(time.time(), 2), "input_fail " + str(exc)[:120]])
            self.step("08_walked", "TAB + W", wait=0.5)

            try:
                self.page.keyboard.press("l")
            except Exception:
                pass
            self.step("09_flashlight", "L", wait=3.0)

            # Correr un rato y ver si el nivel sigue vivo.
            time.sleep(args.settle)
            self.step("10_settle", "%.0fs despues" % args.settle)

            self.report["reached_ringhub"] = reached
            self.finish("ringhub" if reached else "no_ringhub")

    def finish(self, reason):
        try:
            timing = self.page.evaluate("window.__odTiming")
        except Exception:
            timing = None
        try:
            focus = self.page.evaluate("window.__odFocus ? window.__odFocus() : null")
        except Exception:
            focus = None
        logs = self.logs_snapshot()
        keys = [[t, "log", x] for t, m, x in logs if KEY.search(x)]
        first_warmup = next((t for t, m, x in logs if WARMUP_START.search(x)), None)
        ring_t = next((t for t, m, x in logs if RINGHUB_READY.search(x)), None)
        errors = [x for t, m, x in logs if m == "error" or "ERROR:" in x]
        last = [[t, m, x[:200]] for t, m, x in logs[-40:]]

        # Volcado completo para diagnostico: el reporte JSON recorta a los ultimos
        # tramos, esto guarda todo con su t de performance.now().
        log_path = os.path.join(self.args.outdir, "engine_console.log")
        try:
            with open(log_path, "w") as fh:
                for t, m, x in logs:
                    fh.write("%9d %-5s %s\n" % (t, m, x))
        except Exception:
            log_path = None

        self.report.update({
            "reason": reason,
            "gl": self.gl,
            "warmup_start_ms": first_warmup,
            "ringhub_ms": ring_t,
            "timing": timing,
            "focus": focus,
            "engine_console_log": log_path,
            "events": self.events,
            "errors_tail": errors[-30:],
            "logs_tail": last,
            "keys": keys[-120:],
        })
        out = os.path.join(self.args.outdir, "web_flow_report.json")
        with open(out, "w") as fh:
            json.dump(self.report, fh, indent=2)
        log("")
        log("[result] reason=%s reached_ringhub=%s gl=%s" % (reason, self.report["reached_ringhub"], self.gl))
        if timing:
            log("[result] maxFrameGap=%.0fms rafCount=%s" % (timing.get("maxGap", -1), timing.get("rafCount")))
        log("[result] report=%s" % out)
        if errors:
            log("[result] ultimos errores de consola:")
            for e in errors[-8:]:
                log("   " + e[:180])
        if not self.report["reached_ringhub"]:
            log("[result] ultimos logs del motor:")
            for t, m, x in last[-15:]:
                log("   %8d %s" % (t, x[:170]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--browser", choices=["chromium", "firefox", "webkit"], default="chromium")
    ap.add_argument("--url", default="http://127.0.0.1:8768/index.html?nothr=1")
    ap.add_argument("--outdir", default="/tmp/odisea-web-smoke")
    ap.add_argument("--executable", default=None, help="binario del navegador (opcional)")
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--goto-timeout", type=int, default=120)
    ap.add_argument("--menu-timeout", type=int, default=120)
    ap.add_argument("--warmup-timeout", type=int, default=120)
    ap.add_argument("--ringhub-timeout", type=int, default=200)
    ap.add_argument("--settle", type=float, default=12.0)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    smoke = Smoke(args)
    try:
        smoke.run()
    except Exception:
        smoke.events.append([round(time.time(), 2), "EXCEPTION\n" + traceback.format_exc()[:1500]])
        try:
            smoke.finish("exception")
        except Exception:
            traceback.print_exc()
            sys.exit(1)


if __name__ == "__main__":
    main()
