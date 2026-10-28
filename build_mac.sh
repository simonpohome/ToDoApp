#!/bin/bash
# Builds dist/Deadlines.app and dist/Deadlines.dmg: the Mac version (macOS 13 or newer), no Python
# needed to run it. Run on a Mac from anywhere:  bash build_mac.sh
# (What goes into the app is decided in Deadlines.spec; GitHub can also build it, see
# .github/workflows/mac.yml.)
set -euo pipefail
cd "$(dirname "$0")"

[ -d .venv ] || python3 -m venv .venv
.venv/bin/python -m pip install --quiet -r requirements.txt
.venv/bin/python -m PyInstaller --noconfirm --clean --distpath dist --workpath build Deadlines.spec

# Signed "ad hoc" (no Apple developer account): enough for the app to start on Apple silicon.
codesign --force --deep --sign - dist/Deadlines.app

# The installer: the app next to a link to Applications, to drag it across.
rm -rf build/dmg dist/Deadlines.dmg
mkdir -p build/dmg
cp -R dist/Deadlines.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname Deadlines -srcfolder build/dmg -format UDZO dist/Deadlines.dmg

echo "Built: dist/Deadlines.app and dist/Deadlines.dmg"
