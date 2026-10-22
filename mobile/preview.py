"""Run the phone app on this PC in a phone-sized window, to try changes without building the .apk.

    ..\\.venv\\Scripts\\python.exe preview.py

It keeps its own data in mobile\\.preview-data (not the PC app's deadlines, not the phone's).
"""
import sys
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QSettings, QUrl
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

HERE = Path(__file__).resolve().parent


def use_app_font(app):
    """The rounded font as every text's default, at the phone's 15px (as main.cpp does)."""
    family = "Segoe UI"
    for name in ("NunitoRounded-Regular.ttf", "NunitoRounded-Bold.ttf"):
        font_id = QFontDatabase.addApplicationFont(str(HERE / "fonts" / name))
        if font_id >= 0:
            family = QFontDatabase.applicationFontFamilies(font_id)[0]
    font = QFont(family)
    font.setPixelSize(15)
    app.setFont(font)


def main():
    QSettings.setDefaultFormat(QSettings.IniFormat)
    QSettings.setPath(QSettings.IniFormat, QSettings.UserScope, str(HERE / ".preview-data"))
    QCoreApplication.setOrganizationName("Deadlines")
    QCoreApplication.setApplicationName("Deadlines")
    app = QGuiApplication(sys.argv)
    use_app_font(app)
    engine = QQmlApplicationEngine()
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
