"""Cube de statut - agent pour Mac et Windows.

- Se connecte au cube en Bluetooth et le garde connecte.
- Passe le cube en "en appel" automatiquement quand le micro ou la camera sont utilises.
- Icone dans la barre de menus (Mac) / zone de notification (Windows) pour choisir un statut a la main.

Lancement :  python cube_agent.py          (ou pythonw cube_agent.py sous Windows, sans fenetre)
"""
import asyncio
import json
import sys
import threading
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner
from PIL import Image, ImageDraw
import pystray

import detect

SVC_UUID = "7c0be000-5a7e-4b1d-9c3a-2f6d8e1b4a00"
STATUS_UUID = "7c0be001-5a7e-4b1d-9c3a-2f6d8e1b4a00"
CMD_UUID = "7c0be002-5a7e-4b1d-9c3a-2f6d8e1b4a00"

STATUS_LABEL = {0: "Éteint", 1: "Disponible", 2: "Concentré", 3: "En appel"}
SOURCE_LABEL = {0: "face posée", 1: "choix manuel", 2: "appel détecté"}
STATUS_RGB = {None: (140, 140, 140), 0: (90, 90, 90), 1: (0, 170, 70), 2: (240, 140, 0), 3: (220, 30, 30)}

CONFIG_PATH = Path.home() / ".cube_statut.json"
POLL_S = 2          # frequence de detection micro/camera
KEEPALIVE_S = 10    # le cube oublie l'appel apres 30 s sans nouvelles


def load_config() -> dict:
    try:
        return json.loads(CONFIG_PATH.read_text())
    except Exception:
        return {"address": None, "auto_detect": True, "brightness": 25}


def save_config(cfg: dict) -> None:
    try:
        CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    except Exception:
        pass


class CubeAgent:
    def __init__(self):
        self.cfg = load_config()
        self.loop = asyncio.new_event_loop()
        self.client: BleakClient | None = None
        self.connected = False
        self.status: int | None = None
        self.source: int | None = None
        self.battery: int | None = None
        self.charging = False
        self.in_call = False
        self.call_reason = ""
        self.icon: pystray.Icon | None = None
        self.stop = False

    # ------------------------------------------------------------------ BLE
    async def find_cube(self):
        if self.cfg.get("address"):
            dev = await BleakScanner.find_device_by_address(self.cfg["address"], timeout=8)
            if dev:
                return dev
        devices = await BleakScanner.discover(timeout=8, service_uuids=[SVC_UUID])
        for d in devices:
            if (d.name or "").startswith("Cube-Statut"):
                return d
        return devices[0] if devices else None

    def on_status(self, _char, data: bytearray):
        if len(data) >= 4:
            self.status, self.source, self.battery = data[0], data[1], data[2]
            self.charging = bool(data[3] & 1)
            self.refresh_icon()

    async def send(self, cmd: int, val: int):
        if self.client and self.client.is_connected:
            try:
                await self.client.write_gatt_char(CMD_UUID, bytes([cmd, val]), response=False)
            except Exception:
                pass

    async def ble_main(self):
        last_keepalive = 0.0
        while not self.stop:
            try:
                dev = await self.find_cube()
                if not dev:
                    self.connected = False
                    self.refresh_icon()
                    await asyncio.sleep(10)
                    continue
                async with BleakClient(dev, disconnected_callback=lambda _c: self.refresh_icon()) as client:
                    self.client = client
                    self.connected = True
                    if self.cfg.get("address") != dev.address:
                        self.cfg["address"] = dev.address
                        save_config(self.cfg)
                    await client.start_notify(STATUS_UUID, self.on_status)
                    self.on_status(None, await client.read_gatt_char(STATUS_UUID))
                    await self.send(0x03, int(self.cfg.get("brightness", 25)))
                    while client.is_connected and not self.stop:
                        call, reason = detect.in_call() if self.cfg.get("auto_detect", True) else (False, "")
                        now = time.monotonic()
                        if call != self.in_call or now - last_keepalive > KEEPALIVE_S:
                            self.in_call, self.call_reason = call, reason
                            await self.send(0x02, 1 if call else 0)
                            last_keepalive = now
                            self.refresh_icon()
                        await asyncio.sleep(POLL_S)
            except Exception:
                pass
            self.client = None
            self.connected = False
            self.refresh_icon()
            await asyncio.sleep(5)

    def run_ble(self):
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self.ble_main())

    def command(self, cmd: int, val: int):
        asyncio.run_coroutine_threadsafe(self.send(cmd, val), self.loop)

    # ------------------------------------------------------------------ icone
    def make_image(self) -> Image.Image:
        size = 64
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        st = self.status if self.connected else None
        d.rounded_rectangle((6, 6, 58, 58), radius=12, fill=STATUS_RGB.get(st, STATUS_RGB[None]))
        # symbole en plus de la couleur (lisible pour les daltoniens)
        w = (255, 255, 255, 255)
        if st == 1:
            d.line((20, 33, 29, 42, 45, 22), fill=w, width=6)          # coche
        elif st == 2:
            d.ellipse((20, 20, 44, 44), outline=w, width=5)            # anneau
        elif st == 3:
            d.rectangle((26, 16, 38, 36), fill=w)                      # micro
            d.arc((20, 24, 44, 46), 0, 180, fill=w, width=4)
            d.line((32, 46, 32, 50), fill=w, width=4)
        elif st == 0:
            d.line((20, 32, 44, 32), fill=w, width=6)                  # tiret
        else:
            d.text((27, 20), "?", fill=w)
        return img

    def title(self) -> str:
        if not self.connected:
            return "Cube : recherche…"
        t = f"Cube : {STATUS_LABEL.get(self.status, '?')}"
        if self.source is not None:
            t += f" ({SOURCE_LABEL.get(self.source, '')})"
        if self.battery is not None:
            t += f" - batterie {self.battery} %" + (" en charge" if self.charging else "")
        return t

    def refresh_icon(self):
        if self.icon:
            self.icon.icon = self.make_image()
            self.icon.title = self.title()
            try:
                self.icon.update_menu()
            except Exception:
                pass

    def build_menu(self):
        def set_status(v):
            return lambda _i, _it: self.command(0x01, v)

        def set_brightness(v):
            def f(_i, _it):
                self.cfg["brightness"] = v
                save_config(self.cfg)
                self.command(0x03, v)
            return f

        def toggle_auto(_i, _it):
            self.cfg["auto_detect"] = not self.cfg.get("auto_detect", True)
            save_config(self.cfg)
            if not self.cfg["auto_detect"]:
                self.command(0x02, 0)

        def toggle_startup(_i, _it):
            set_autostart(not autostart_enabled())

        def quit_app(icon, _it):
            self.stop = True
            self.command(0x02, 0)
            time.sleep(0.3)
            icon.stop()

        M, I = pystray.Menu, pystray.MenuItem
        return M(
            I(lambda _i: self.title(), None, enabled=False),
            I(lambda _i: ("Appel détecté : " + self.call_reason) if self.in_call else "Aucun appel détecté", None, enabled=False),
            M.SEPARATOR,
            I("Disponible", set_status(1)),
            I("Concentré", set_status(2)),
            I("En appel", set_status(3)),
            I("Revenir à la face du cube", set_status(0)),
            M.SEPARATOR,
            I("Détection automatique des appels", toggle_auto, checked=lambda _i: self.cfg.get("auto_detect", True)),
            I("Luminosité", M(*[I(f"{v} %", set_brightness(v), radio=True,
                                 checked=lambda _i, v=v: self.cfg.get("brightness", 25) == v) for v in (10, 25, 40)])),
            I("Lancer au démarrage", toggle_startup, checked=lambda _i: autostart_enabled()),
            M.SEPARATOR,
            I("Quitter", quit_app),
        )

    def run(self):
        threading.Thread(target=self.run_ble, daemon=True).start()
        self.icon = pystray.Icon("cube_statut", self.make_image(), self.title(), self.build_menu())
        self.icon.run()


# ---------------------------------------------------------------------- demarrage auto
def _launch_cmd() -> list[str]:
    exe = sys.executable
    if getattr(sys, "frozen", False):           # version empaquetee (PyInstaller)
        return [exe]
    if sys.platform == "win32" and exe.lower().endswith("python.exe"):
        exe = exe[:-10] + "pythonw.exe"
    return [exe, str(Path(__file__).resolve())]


_PLIST = Path.home() / "Library/LaunchAgents/com.diy.cubestatut.plist"


def autostart_enabled() -> bool:
    if sys.platform == "darwin":
        return _PLIST.exists()
    if sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as k:
                winreg.QueryValueEx(k, "CubeStatut")
                return True
        except OSError:
            return False
    return False


def set_autostart(on: bool) -> None:
    cmd = _launch_cmd()
    if sys.platform == "darwin":
        if on:
            args = "".join(f"<string>{a}</string>" for a in cmd)
            _PLIST.parent.mkdir(parents=True, exist_ok=True)
            _PLIST.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                '<plist version="1.0"><dict><key>Label</key><string>com.diy.cubestatut</string>'
                f'<key>ProgramArguments</key><array>{args}</array>'
                '<key>RunAtLoad</key><true/></dict></plist>\n')
        elif _PLIST.exists():
            _PLIST.unlink()
    elif sys.platform == "win32":
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0,
                            winreg.KEY_SET_VALUE) as k:
            if on:
                winreg.SetValueEx(k, "CubeStatut", 0, winreg.REG_SZ, " ".join(f'"{a}"' for a in cmd))
            else:
                try:
                    winreg.DeleteValue(k, "CubeStatut")
                except OSError:
                    pass


if __name__ == "__main__":
    if "--test-detection" in sys.argv:
        while True:
            print(detect.in_call())
            time.sleep(2)
    CubeAgent().run()
