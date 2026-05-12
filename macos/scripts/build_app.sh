#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")"/../.. && pwd)"
APP_NAME="FrigateDetector"
APP_DIR="$PROJECT_DIR/macos/${APP_NAME}.app"
BUILD_DIR="$PROJECT_DIR/.build/macos"
PY_VENV="$BUILD_DIR/pyinstaller-venv"
PYINSTALLER_WORK="$BUILD_DIR/pyinstaller-work"
PYINSTALLER_DIST="$BUILD_DIR/pyinstaller-dist"
RES_DIR="$APP_DIR/Contents/Resources"
MODEL_RES_DIR="$RES_DIR/Models"
SWIFT_SRC="$PROJECT_DIR/macos/App/Sources/FrigateDetectorApp.swift"
DEFAULT_MODEL="$PROJECT_DIR/yolo/yolov8n.onnx"

cd "$PROJECT_DIR"

choose_python() {
  if command -v python3.11 >/dev/null 2>&1; then
    echo "python3.11"
    return
  fi

  if command -v python3 >/dev/null 2>&1 && python3 - <<'PYVER' 2>/dev/null; then
import sys
sys.exit(0 if sys.version_info >= (3, 11) else 1)
PYVER
    echo "python3"
    return
  fi

  echo "ERROR: Python 3.11+ is required only for building the app bundle." >&2
  echo "Install it on the build machine, then rerun this script." >&2
  exit 1
}

create_build_venv() {
  if [ -x "$PY_VENV/bin/python" ]; then
    return
  fi

  rm -rf "$PY_VENV"

  if command -v uv >/dev/null 2>&1; then
    uv venv "$PY_VENV" --python 3.11
    return
  fi

  local python_bin
  python_bin="$(choose_python)"
  "$python_bin" -m venv "$PY_VENV"
}

echo "==> Recreating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$RES_DIR" "$MODEL_RES_DIR" "$BUILD_DIR"

echo "==> Preparing isolated build venv"
create_build_venv
if [ -x "$PY_VENV/bin/pip" ]; then
  "$PY_VENV/bin/pip" install --upgrade pip
  "$PY_VENV/bin/pip" install -r "$PROJECT_DIR/requirements.txt" pyinstaller
elif command -v uv >/dev/null 2>&1; then
  uv pip install --python "$PY_VENV/bin/python" -r "$PROJECT_DIR/requirements.txt" pyinstaller
else
  "$PY_VENV/bin/python" -m ensurepip --upgrade
  "$PY_VENV/bin/python" -m pip install --upgrade pip
  "$PY_VENV/bin/python" -m pip install -r "$PROJECT_DIR/requirements.txt" pyinstaller
fi

echo "==> Building bundled detector runtime"
rm -rf "$PYINSTALLER_WORK" "$PYINSTALLER_DIST"
"$PY_VENV/bin/python" -m PyInstaller \
  --clean \
  --noconfirm \
  --onefile \
  --name detector-runner \
  --paths "$PROJECT_DIR/detector" \
  --collect-all onnxruntime \
  --hidden-import model_util \
  --workpath "$PYINSTALLER_WORK" \
  --distpath "$PYINSTALLER_DIST" \
  "$PROJECT_DIR/detector/zmq_onnx_client.py"

cp "$PYINSTALLER_DIST/detector-runner" "$RES_DIR/detector-runner"
chmod +x "$RES_DIR/detector-runner"

if [ -f "$DEFAULT_MODEL" ]; then
  echo "==> Bundling default model: yolo/yolov8n.onnx"
  cp "$DEFAULT_MODEL" "$MODEL_RES_DIR/yolov8n.onnx"
else
  echo "WARNING: Default model not found at $DEFAULT_MODEL; app will default to AUTO model mode." >&2
fi

echo "==> Compiling native macOS wrapper"
swiftc \
  "$SWIFT_SRC" \
  -O \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if [ -f "$PROJECT_DIR/macos/AppIcon.icns" ]; then
  cp "$PROJECT_DIR/macos/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi

cp "$PROJECT_DIR/README.md" "$RES_DIR/README.md" 2>/dev/null || true
cp "$PROJECT_DIR/LICENSE" "$RES_DIR/LICENSE" 2>/dev/null || true

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FrigateDetector</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.FrigateDetector</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FrigateDetector</string>
    <key>CFBundleDisplayName</key>
    <string>Frigate Detector</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  echo "==> Applying ad-hoc code signature"
  codesign --force --deep --sign - "$APP_DIR"
fi

if command -v xattr >/dev/null 2>&1; then
  find "$APP_DIR" -print0 | xargs -0 xattr -d com.apple.quarantine 2>/dev/null || true
fi

echo "==> App bundle created: macos/${APP_NAME}.app"
echo "    Runtime data will be stored in ~/Library/Application Support/FrigateDetector"
