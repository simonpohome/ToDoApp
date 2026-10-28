# PyInstaller recipe for dist\Deadlines.exe (run build_exe.ps1 rather than this directly), and on a
# Mac for dist/Deadlines.app (run build_mac.sh).
# PySide6 brings every Qt module it has (a web browser, 3D, PDF, ...); the app only needs Qt Quick
# with the Basic controls, Layouts and Shapes, so everything else is left out to keep the .exe small.
import os
import sys

HERE = SPECPATH
MAC = sys.platform == "darwin"

# Left out when any of these appears in a bundled file's path (lowercase, forward slashes).
UNUSED = [
    "webengine", "webview", "webchannel", "websockets", "pdf", "quick3d", "qt63d", "/qt3d",
    "multimedia", "spatialaudio", "charts", "graphs", "datavisualization", "location", "positioning",
    "sensors", "texttospeech", "scxml", "statemachine", "remoteobjects", "virtualkeyboard",
    "serialport", "bluetooth", "nfc", "designer", "uitools", "qt6help", "qt6sql", "sqldrivers",
    "qt6test", "/qttest/", "/translations/", "shadertools", "timeline", "particles", "scene2d",
    "/qt/labs/", "qt6labs", "stylekit", "lottie", "vectorimage", "quickdialogs", "/dialogs/",
    "quickwidgets", "qt6svg", "opcua", "httpserver", "protobuf", "grpc", "quickeffects", "/effects/",
    # Control styles other than Basic (main.py picks Basic).
    "controls2imagine", "controls2fluentwinui3", "controls2material", "controls2universal",
    "controls2fusion", "controls2windowsstyle", "controls/imagine", "controls/fluentwinui3",
    "controls/material", "controls/universal", "controls/fusion", "controls/windows",
    "controls/macos", "controls/ios",
]


def used(entry):
    path = entry[0].replace("\\", "/").lower()
    return not any(word in path for word in UNUSED)


a = Analysis(
    [os.path.join(HERE, "main.py")],
    datas=[
        (os.path.join(HERE, "Main.qml"), "."),
        (os.path.join(HERE, "fonts"), "fonts"),
        (os.path.join(HERE, "icon.ico"), "."),
    ],
    # certifi is only for the Mac (see core.ssl_context); Windows checks HTTPS with its own store.
    excludes=["tkinter"] + ([] if MAC else ["certifi"]),
)
a.binaries = [b for b in a.binaries if used(b)]
a.datas = [d for d in a.datas if used(d)]

pyz = PYZ(a.pure)

if not MAC:
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.datas,
        name="Deadlines",
        icon=os.path.join(HERE, "icon.ico"),
        console=False,
        upx=False,
    )
else:
    # A normal Mac app: Deadlines.app, with the icon made from icon.ico (needs Pillow).
    exe = EXE(
        pyz,
        a.scripts,
        [],
        exclude_binaries=True,
        name="Deadlines",
        console=False,
        upx=False,
    )
    coll = COLLECT(exe, a.binaries, a.datas, name="Deadlines", upx=False)
    app = BUNDLE(
        coll,
        name="Deadlines.app",
        icon=os.path.join(HERE, "icon.ico"),
        bundle_identifier="com.deadlinesapp.deadlines.desktop",
        info_plist={
            "CFBundleDisplayName": "Deadlines",
            "CFBundleShortVersionString": "1.0",
            "NSHighResolutionCapable": True,
            "NSRequiresAquaSystemAppearance": True,   # light, like the app (see main.py)
            "LSMinimumSystemVersion": "13.0",
        },
    )
