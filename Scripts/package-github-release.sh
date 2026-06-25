#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${ROOT_DIR}/Archives/Replicate-${TIMESTAMP}.xcarchive"
EXPORT_DIR="${ROOT_DIR}/Exports/Replicate-${TIMESTAMP}"
ZIP_PATH="${ROOT_DIR}/Exports/Replicate-${TIMESTAMP}.zip"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/Replicate.app"
FSWATCH_PATH="${APP_PATH}/Contents/Resources/Tools/fswatch"
RCLONE_PATH="${APP_PATH}/Contents/Resources/Tools/rclone"

cd "${ROOT_DIR}"

if [[ ! -x "${ROOT_DIR}/BundledTools/Tools/fswatch" ]]; then
  "${ROOT_DIR}/Scripts/prepare-fswatch.sh"
fi

if [[ ! -x "${ROOT_DIR}/BundledTools/Tools/rclone" ]]; then
  "${ROOT_DIR}/Scripts/prepare-rclone.sh"
fi

xcodebuild archive \
  -project Replicate.xcodeproj \
  -scheme Replicate \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  -quiet

if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -q 'Developer ID Application'; then
  EXPORT_OPTIONS="$(/usr/bin/mktemp -t ReplicateDeveloperIDExportOptions).plist"
  /usr/libexec/PlistBuddy -c 'Clear dict' "${EXPORT_OPTIONS}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :method string developer-id' "${EXPORT_OPTIONS}"
  /usr/libexec/PlistBuddy -c 'Add :destination string export' "${EXPORT_OPTIONS}"
  /usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "${EXPORT_OPTIONS}"
  /usr/libexec/PlistBuddy -c 'Add :teamID string JLHW9H4BKV' "${EXPORT_OPTIONS}"
  /usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "${EXPORT_OPTIONS}"

  xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -allowProvisioningUpdates \
    -quiet

  APP_PATH="${EXPORT_DIR}/Replicate.app"
  FSWATCH_PATH="${APP_PATH}/Contents/Resources/Tools/fswatch"
  RCLONE_PATH="${APP_PATH}/Contents/Resources/Tools/rclone"
else
  printf 'warning: Developer ID Application certificate not found; packaging archive app without Developer ID export.\n' >&2
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

verify_hardened_runtime() {
  local tool_name="$1"
  local tool_path="$2"
  local signature

  signature="$(
    /usr/bin/codesign -dv --verbose=4 "${tool_path}" 2>&1
  )"
  if ! /usr/bin/grep -q 'flags=.*runtime' <<< "${signature}"; then
    printf 'error: bundled %s is not signed with the hardened runtime.\n' "${tool_name}" >&2
    exit 1
  fi
}

verify_hardened_runtime "fswatch" "${FSWATCH_PATH}"
verify_hardened_runtime "rclone" "${RCLONE_PATH}"

mkdir -p "${ROOT_DIR}/Exports"
rm -f "${ZIP_PATH}"
(
  cd "$(dirname "${APP_PATH}")"
  /usr/bin/ditto -c -k --keepParent "Replicate.app" "${ZIP_PATH}"
)

printf '%s\n' "${ZIP_PATH}"
