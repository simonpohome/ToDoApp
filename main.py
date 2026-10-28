"""Deadlines: a to-do list for assignments with steps, plus deadlines imported from Canvas.

The interface is in Main.qml (Qt Quick: GPU-rendered, smooth scrolling); this file starts it
and provides the Python side: saving/loading and syncing the Canvas feed (see core.py).
Build the .exe with build_exe.ps1.
"""

import ctypes
import json
import os
import subprocess
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent

try:
    import PySide6  # noqa: F401
except ImportError:
    # Started with a Python that doesn't have PySide6 (e.g. VS Code's selected interpreter):
    # run again with this folder's own environment, where it's installed.
    venv_python = (HERE / ".venv" / "Scripts" / "python.exe" if sys.platform == "win32"
                   else HERE / ".venv" / "bin" / "python")
    if venv_python.exists() and Path(sys.executable).resolve() != venv_python.resolve():
        sys.exit(subprocess.call([str(venv_python), str(Path(__file__).resolve()), *sys.argv[1:]]))
    sys.exit(f"PySide6 isn't installed. Run:  {venv_python} -m pip install pyside6")

from PySide6.QtCore import QObject, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QFontDatabase, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

import core

if getattr(sys, "frozen", False):
    # Running as the .exe (or the Mac .app): Main.qml, fonts/ and icon.ico are here (PyInstaller's _MEIPASS).
    HERE = Path(sys._MEIPASS)
BG, TEXT = "#e3eefb", "#1c1c1e"
WHEEL_SCROLL_LINES = 4  # Qt's default is 3; a bit faster per wheel notch / touchpad swipe


class Backend(QObject):
    """What the QML interface asks Python to do. Data travels as JSON strings."""

    syncFinished = Signal(str)  # {"assignments": [...]} or {"error": "..."}
    saveFailed = Signal(str)

    @Slot(result=str)
    def load(self):
        return json.dumps(core.load_data())

    @Slot(str)
    def save(self, data_json):
        try:
            core.save_data(json.loads(data_json))
        except OSError as err:
            self.saveFailed.emit(f"Could not save your deadlines: {err}")

    @Slot(str, result=str)
    def normalizeFeedUrl(self, text):
        try:
            return json.dumps({"url": core.normalize_feed_url(text)})
        except core.FeedError as err:
            return json.dumps({"error": str(err)})

    @Slot(str)
    def sync(self, url):
        """Download and read the feed in the background so the window never freezes."""
        def work():
            try:
                result = {"assignments": core.canvas_assignments(core.fetch_feed(url))}
            except core.FeedError as err:
                result = {"error": str(err)}
            except Exception as err:  # anything unexpected still shouldn't crash the app
                result = {"error": f"Sync failed: {err}"}
            self.syncFinished.emit(json.dumps(result))  # delivered to the UI thread by Qt
        threading.Thread(target=work, daemon=True).start()


def load_font():
    """The bundled rounded font (Nunito, see fonts/OFL.txt); falls back to the system's font."""
    family = "Segoe UI" if sys.platform == "win32" else ".AppleSystemUIFont"
    for name in ("NunitoRounded-Regular.ttf", "NunitoRounded-Bold.ttf"):
        font_id = QFontDatabase.addApplicationFont(str(HERE / "fonts" / name))
        if font_id >= 0:
            family = QFontDatabase.applicationFontFamilies(font_id)[0]
    return family


def color_title_bar(window):
    """Tint the Windows 11 title bar to match the background (ignored elsewhere)."""
    if sys.platform != "win32":
        return

    def colorref(hex_color):
        r, g, b = (int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
        return ctypes.c_int(r | g << 8 | b << 16)

    try:
        hwnd = int(window.winId())
        for attribute, color in ((35, BG), (36, TEXT), (34, BG)):  # caption, title text, border
            value = colorref(color)
            ctypes.windll.dwmapi.DwmSetWindowAttribute(hwnd, attribute, ctypes.byref(value),
                                                       ctypes.sizeof(value))
    except (AttributeError, OSError):
        pass


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")  # plain controls we can style
    if sys.platform == "win32":
        # Own taskbar entry with our icon (same ID as before, so pinned icons keep working).
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("Deadlines.App")
    app = QGuiApplication(sys.argv)
    if sys.platform == "darwin":
        # The app is light only (as on Windows): keep the Mac's title bar and menus light too, even
        # when the Mac is set to dark. (The Dock icon comes from the .app's own icon.)
        app.styleHints().setColorScheme(Qt.ColorScheme.Light)
    else:
        app.setWindowIcon(QIcon(str(HERE / "icon.ico")))
    app.styleHints().setWheelScrollLines(WHEEL_SCROLL_LINES)

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("appFont", load_font())
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    color_title_bar(engine.rootObjects()[0])
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
