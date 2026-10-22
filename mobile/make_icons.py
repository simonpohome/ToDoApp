"""Draw the Android launcher icons (the green box with a white tick, as on the PC) into android/res.

    ..\\.venv\\Scripts\\python.exe make_icons.py

Writes an adaptive icon (green background + tick foreground, also used for themed icons) and
plain PNG icons for older launchers.
"""
from pathlib import Path

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter, QPainterPath, QPen

RES = Path(__file__).resolve().parent / "android" / "res"
GREEN, WHITE = QColor("#8fd6a5"), QColor("#ffffff")
TICK = [(0.27, 0.53), (0.44, 0.69), (0.74, 0.36)]   # the logo's tick, as fractions of the box
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def draw_tick(p, x, y, size):
    path = QPainterPath(QPointF(x + TICK[0][0] * size, y + TICK[0][1] * size))
    for u, v in TICK[1:]:
        path.lineTo(x + u * size, y + v * size)
    p.setPen(QPen(WHITE, size * 0.1, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
    p.drawPath(path)


def image(px, paint):
    img = QImage(px, px, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    paint(p, px)
    p.end()
    return img


def legacy(round_icon):
    def paint(p, s):
        p.setPen(Qt.NoPen)
        p.setBrush(GREEN)
        if round_icon:
            p.drawEllipse(QRectF(0, 0, s, s))
        else:
            p.drawRoundedRect(QRectF(0, 0, s, s), s * 0.28, s * 0.28)
        draw_tick(p, 0, 0, s)
    return paint


def foreground(p, s):
    # Adaptive icons are 108dp with the middle 66dp always visible: keep the tick in there.
    box = s * 60 / 108
    draw_tick(p, (s - box) / 2, (s - box) / 2, box)


def main():
    QGuiApplication([])
    for name, k in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        image(round(48 * k), legacy(False)).save(str(folder / "ic_launcher.png"))
        image(round(48 * k), legacy(True)).save(str(folder / "ic_launcher_round.png"))
        image(round(108 * k), foreground).save(str(folder / "ic_launcher_foreground.png"))
    adaptive = RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '</adaptive-icon>\n')
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (adaptive / name).write_text(xml, encoding="utf-8")
    print("icons written to", RES)


if __name__ == "__main__":
    main()
