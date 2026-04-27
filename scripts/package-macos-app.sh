#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-PETVocabularyTrainer}"
BUNDLE_ID="${BUNDLE_ID:-com.xzhan.PETVocabularyTrainer}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
VERSION="${VERSION:-1.0.0}"
SHORT_VERSION="${SHORT_VERSION:-$VERSION}"
DIST_DIR="${DIST_DIR:-dist}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
INCLUDE_INITIAL_DATA="${INCLUDE_INITIAL_DATA:-1}"
CREATE_DATA_BACKUP="${CREATE_DATA_BACKUP:-1}"
APP_SUPPORT_SOURCE="${APP_SUPPORT_SOURCE:-${HOME}/Library/Application Support/${APP_NAME}}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$CREATE_DATA_BACKUP" == "1" && ( -f "${APP_SUPPORT_SOURCE}/store.json" || -f "${APP_SUPPORT_SOURCE}/imported_words.json" ) ]]; then
  BACKUP_TARGET="${ROOT_DIR}/${DIST_DIR}/data-backups/$(date +"%Y%m%d-%H%M%S")"
  mkdir -p "$BACKUP_TARGET"

  for DATA_FILE in store.json imported_words.json; do
    if [[ -f "${APP_SUPPORT_SOURCE}/${DATA_FILE}" ]]; then
      cp "${APP_SUPPORT_SOURCE}/${DATA_FILE}" "${BACKUP_TARGET}/${DATA_FILE}"
    fi
  done

  echo "Saved local data backup before packaging:"
  echo "  ${BACKUP_TARGET}"
fi

echo "Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "$BUILD_CONFIGURATION"

BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${APP_NAME}"
RESOURCE_SOURCE_DIR="${ROOT_DIR}/Sources/${APP_NAME}/Resources"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_SOURCE_DIR" ]]; then
  echo "Expected resource directory not found at ${RESOURCE_SOURCE_DIR}" >&2
  exit 1
fi

APP_DIR="${ROOT_DIR}/${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INITIAL_DATA_DIR="${RESOURCES_DIR}/InitialData"
ZIP_PATH="${ROOT_DIR}/${DIST_DIR}/${APP_NAME}-macOS.zip"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "${MACOS_DIR}/${APP_NAME}"
ditto "$RESOURCE_SOURCE_DIR" "$RESOURCES_DIR"

if [[ "$INCLUDE_INITIAL_DATA" == "1" && -f "${APP_SUPPORT_SOURCE}/store.json" ]]; then
  echo "Embedding sanitized initial import data from ${APP_SUPPORT_SOURCE}..."
  mkdir -p "$INITIAL_DATA_DIR"

  python3 - "${APP_SUPPORT_SOURCE}/store.json" "${APP_SUPPORT_SOURCE}/imported_words.json" "${INITIAL_DATA_DIR}/store.json" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

source_path, imported_words_path, destination_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(source_path, "r", encoding="utf-8") as source:
    data = json.load(source)

imported_words_file = Path(imported_words_path)
imported_word_count = 0
if imported_words_file.exists():
    try:
        imported_word_count = len(json.loads(imported_words_file.read_text(encoding="utf-8")))
    except Exception:
        imported_word_count = 0

imported_library = data.get("importedLibrary")
if imported_library is None and imported_word_count > 0:
    reusable_page_count = max(
        len(data.get("wordPages") or []),
        len(data.get("questPages") or []),
        len(data.get("readingQuests") or []),
    )
    if reusable_page_count < 10:
        raise SystemExit(
            "Refusing to embed initial data because the local store does not look like "
            "a reusable PET seed pack. Re-import Base/Quest/Reading first, or run with "
            "INCLUDE_INITIAL_DATA=0 for a clean build."
        )

    imported_library = {
        "name": "Imported PET Word Bank",
        "sourceFilename": "imported_words.json",
        "importedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "wordCount": imported_word_count,
        "source": "json",
    }

sanitized = {
    "activeWordBankMode": "imported" if imported_library else data.get("activeWordBankMode", "bundled"),
    "hasCompletedPlacement": False,
    "progressByWordID": {},
    "sessions": [],
    "dailyStreak": 0,
    "importedLibrary": imported_library,
    "wordPages": data.get("wordPages", []),
    "questPages": data.get("questPages", []),
    "currentQuestPageNumber": data.get("currentQuestPageNumber"),
    "completedQuestPages": [],
    "completedReadingQuestPages": [],
    "readingLibrary": data.get("readingLibrary"),
    "readingQuests": data.get("readingQuests", []),
}

sanitized = {key: value for key, value in sanitized.items() if value is not None}

with open(destination_path, "w", encoding="utf-8") as destination:
    json.dump(sanitized, destination, ensure_ascii=False, indent=2, sort_keys=True)
    destination.write("\n")
PY

  if [[ -f "${APP_SUPPORT_SOURCE}/imported_words.json" ]]; then
    cp "${APP_SUPPORT_SOURCE}/imported_words.json" "${INITIAL_DATA_DIR}/imported_words.json"
  fi
else
  echo "No initial import data embedded. Set INCLUDE_INITIAL_DATA=1 after importing resources locally to bundle seed data."
fi

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>PET Vocabulary Trainer listens briefly so the cat coach can check pronunciation practice.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>PET Vocabulary Trainer uses speech recognition to compare spoken PET words with the target word.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  echo "Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_DIR"
else
  echo "Signing with ${CODESIGN_IDENTITY}..."
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Created:"
echo "  App: ${APP_DIR}"
echo "  Zip: ${ZIP_PATH}"
echo
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  echo "This build uses ad-hoc signing."
  echo "People on other Macs can usually open it with Right Click -> Open once,"
  echo "but the best distribution flow is Developer ID signing plus notarization."
else
  echo "Developer ID signature applied."
  echo "Recommended next step: notarize the zip before sharing outside your team."
fi
