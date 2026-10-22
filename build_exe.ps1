# Builds dist\Deadlines.exe: one file that runs on any 64-bit Windows 10/11 PC, no Python needed.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File build_exe.ps1
# (What goes into the .exe is decided in Deadlines.spec.)
$here = $PSScriptRoot
$python = Join-Path $here ".venv\Scripts\python.exe"

& $python -m PyInstaller --noconfirm --clean `
    --distpath (Join-Path $here "dist") `
    --workpath (Join-Path $here "build") `
    (Join-Path $here "Deadlines.spec")
