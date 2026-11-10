"""Detection micro / camera en cours d'utilisation, sans dependance externe.

- Windows : registre "CapabilityAccessManager" (le meme que l'icone micro/camera de la barre des taches).
- macOS   : CoreAudio (micro) et CoreMediaIO (camera), propriete "IsRunningSomewhere".

Fonctionne avec n'importe quelle application : Teams, Zoom, Meet, WhatsApp, FaceTime...
"""
import sys
import ctypes
import ctypes.util


# --------------------------------------------------------------------------- Windows
def _windows_in_use(capability: str) -> list[str]:
    import winreg

    base = r"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore" + "\\" + capability
    users: list[str] = []

    def check(key, name):
        try:
            start, _ = winreg.QueryValueEx(key, "LastUsedTimeStart")
            stop, _ = winreg.QueryValueEx(key, "LastUsedTimeStop")
            if start and stop == 0:
                users.append(name.split("#")[-1])
        except OSError:
            pass

    def walk(path, depth):
        try:
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, path)
        except OSError:
            return
        with key:
            i = 0
            while True:
                try:
                    sub = winreg.EnumKey(key, i)
                except OSError:
                    break
                i += 1
                subpath = path + "\\" + sub
                if sub == "NonPackaged" and depth == 0:
                    walk(subpath, depth + 1)
                    continue
                try:
                    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, subpath) as sk:
                        check(sk, sub)
                except OSError:
                    pass

    walk(base, 0)
    return users


# --------------------------------------------------------------------------- macOS
def _fourcc(s: str) -> int:
    return int.from_bytes(s.encode("ascii"), "big")


class _PropAddr(ctypes.Structure):
    _fields_ = [("mSelector", ctypes.c_uint32), ("mScope", ctypes.c_uint32), ("mElement", ctypes.c_uint32)]


_GLOBAL = _fourcc("glob")
_INPUT = _fourcc("inpt")
_DEVICES = _fourcc("dev#")
_STREAMS = _fourcc("stm#")
_RUNNING_SOMEWHERE = _fourcc("gone")
_SYSTEM_OBJECT = 1

_ca = None
_cmio = None


def _load_mac():
    global _ca, _cmio
    if _ca is None:
        _ca = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreAudio"))
        _ca.AudioObjectGetPropertyDataSize.argtypes = [ctypes.c_uint32, ctypes.POINTER(_PropAddr), ctypes.c_uint32,
                                                       ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        _ca.AudioObjectGetPropertyData.argtypes = [ctypes.c_uint32, ctypes.POINTER(_PropAddr), ctypes.c_uint32,
                                                   ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p]
    if _cmio is None:
        _cmio = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreMediaIO"))
        _cmio.CMIOObjectGetPropertyDataSize.argtypes = [ctypes.c_uint32, ctypes.POINTER(_PropAddr), ctypes.c_uint32,
                                                        ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        _cmio.CMIOObjectGetPropertyData.argtypes = [ctypes.c_uint32, ctypes.POINTER(_PropAddr), ctypes.c_uint32,
                                                    ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32),
                                                    ctypes.c_void_p]


def _ca_devices() -> list[int]:
    addr = _PropAddr(_DEVICES, _GLOBAL, 0)
    size = ctypes.c_uint32(0)
    if _ca.AudioObjectGetPropertyDataSize(_SYSTEM_OBJECT, ctypes.byref(addr), 0, None, ctypes.byref(size)) != 0:
        return []
    n = size.value // 4
    arr = (ctypes.c_uint32 * n)()
    if _ca.AudioObjectGetPropertyData(_SYSTEM_OBJECT, ctypes.byref(addr), 0, None, ctypes.byref(size), arr) != 0:
        return []
    return list(arr)


def _mac_mic_in_use() -> bool:
    for dev in _ca_devices():
        # le peripherique a-t-il des flux d'entree ?
        addr = _PropAddr(_STREAMS, _INPUT, 0)
        size = ctypes.c_uint32(0)
        if _ca.AudioObjectGetPropertyDataSize(dev, ctypes.byref(addr), 0, None, ctypes.byref(size)) != 0 or size.value == 0:
            continue
        addr = _PropAddr(_RUNNING_SOMEWHERE, _GLOBAL, 0)
        val = ctypes.c_uint32(0)
        size = ctypes.c_uint32(4)
        if _ca.AudioObjectGetPropertyData(dev, ctypes.byref(addr), 0, None, ctypes.byref(size), ctypes.byref(val)) == 0 and val.value:
            return True
    return False


def _mac_camera_in_use() -> bool:
    addr = _PropAddr(_DEVICES, _GLOBAL, 0)
    size = ctypes.c_uint32(0)
    if _cmio.CMIOObjectGetPropertyDataSize(_SYSTEM_OBJECT, ctypes.byref(addr), 0, None, ctypes.byref(size)) != 0:
        return False
    n = size.value // 4
    if n == 0:
        return False
    arr = (ctypes.c_uint32 * n)()
    used = ctypes.c_uint32(0)
    if _cmio.CMIOObjectGetPropertyData(_SYSTEM_OBJECT, ctypes.byref(addr), 0, None, size.value, ctypes.byref(used), arr) != 0:
        return False
    for dev in arr:
        a = _PropAddr(_RUNNING_SOMEWHERE, _GLOBAL, 0)
        val = ctypes.c_uint32(0)
        if _cmio.CMIOObjectGetPropertyData(dev, ctypes.byref(a), 0, None, 4, ctypes.byref(used), ctypes.byref(val)) == 0 and val.value:
            return True
    return False


# --------------------------------------------------------------------------- API
def in_call() -> tuple[bool, str]:
    """Retourne (en_appel, explication)."""
    try:
        if sys.platform == "win32":
            mic = _windows_in_use("microphone")
            cam = _windows_in_use("webcam")
            if mic or cam:
                return True, "micro/camera : " + ", ".join(sorted(set(mic + cam)))[:80]
            return False, ""
        if sys.platform == "darwin":
            _load_mac()
            mic, cam = _mac_mic_in_use(), _mac_camera_in_use()
            if mic or cam:
                return True, " + ".join(x for x, on in (("micro", mic), ("camera", cam)) if on)
            return False, ""
    except Exception as exc:  # la detection ne doit jamais faire tomber l'agent
        return False, f"detection indisponible ({exc})"
    return False, "systeme non pris en charge"


if __name__ == "__main__":
    import time
    print("Test de detection - parlez en visio pour voir le changement (Ctrl+C pour quitter)")
    while True:
        print(in_call())
        time.sleep(2)
