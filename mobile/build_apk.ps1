# Builds Deadlines.apk for Android phones (64-bit ARM, i.e. practically every phone from the last years).
#   powershell -ExecutionPolicy Bypass -File mobile\build_apk.ps1
# Uses the tools in %USERPROFILE%\AndroidDev (Qt 6.12 for Android, Android SDK/NDK, JDK 17, OpenSSL).
# The finished app is copied to dist\Deadlines.apk.
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$T = Join-Path $env:USERPROFILE "AndroidDev"
$qt = "$T\Qt\6.12.0\android_arm64_v8a"
$ndk = "$T\sdk\ndk\27.2.12479018"
$build = "$here\build-android"

$env:JAVA_HOME = "$T\jdk17"
# CMake and Ninja from the Android SDK: they're signed (by Google), so Windows' Smart App Control
# lets them run, unlike the unsigned ninja.exe from pip.
$cmakeBin = "$T\sdk\cmake\4.1.2\bin"
$env:PATH = "$cmakeBin;$T\jdk17\bin;$env:PATH"

cmake -S $here -B $build -G Ninja `
    -DCMAKE_MAKE_PROGRAM="$cmakeBin/ninja.exe" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_TOOLCHAIN_FILE="$qt/lib/cmake/Qt6/qt.toolchain.cmake" `
    -DQT_CHAINLOAD_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" `
    -DQT_HOST_PATH="$T/Qt/6.12.0/msvc2022_64" `
    -DANDROID_SDK_ROOT="$T/sdk" `
    -DANDROID_NDK_ROOT="$ndk" `
    -DANDROID_ABI=arm64-v8a `
    -DOPENSSL_ROOT_DIR="$T/openssl"
if ($LASTEXITCODE) { exit $LASTEXITCODE }

cmake --build $build --target apk
if ($LASTEXITCODE) { exit $LASTEXITCODE }

# Sign it: Android only installs signed apps, and only accepts an update signed with the same key.
# The key is made once and kept in AndroidDev (not in the project, so it never goes to GitHub).
# Back up both files: without them you can't publish updates that install over this version.
$keystore = "$T\deadlines-release.keystore"
$passFile = "$T\deadlines-release-password.txt"
if (-not (Test-Path $keystore)) {
    $pass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
    Set-Content $passFile $pass -Encoding ascii
    & "$T\jdk17\bin\keytool.exe" -genkeypair -keystore $keystore -alias deadlines -keyalg RSA -keysize 2048 `
        -validity 10000 -storepass $pass -keypass $pass -dname "CN=Deadlines"
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
$pass = (Get-Content $passFile -Raw).Trim()
$tools = "$T\sdk\build-tools\37.0.0"
$unsigned = "$build\android-build\build\outputs\apk\release\android-build-release-unsigned.apk"
$aligned = "$build\deadlines-aligned.apk"
New-Item -ItemType Directory -Force "$here\..\dist" | Out-Null
$out = "$here\..\dist\Deadlines.apk"
& "$tools\zipalign.exe" -P 16 -f 4 $unsigned $aligned
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& "$tools\apksigner.bat" sign --ks $keystore --ks-key-alias deadlines --ks-pass "pass:$pass" --key-pass "pass:$pass" --out $out $aligned
if ($LASTEXITCODE) { exit $LASTEXITCODE }
"Built: dist\Deadlines.apk"
