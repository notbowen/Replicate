#!/usr/bin/env bash
set -euo pipefail

if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
  exit 0
fi

TOOLS_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Tools"
if [[ ! -d "${TOOLS_DIR}" ]]; then
  exit 0
fi

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" ]]; then
  SIGN_IDENTITY="-"
fi

sign_file() {
  local path="$1"
  [[ -f "${path}" ]] || return 0

  if [[ -n "${OTHER_CODE_SIGN_FLAGS:-}" ]]; then
    # OTHER_CODE_SIGN_FLAGS is supplied by Xcode as shell-style flags.
    # shellcheck disable=SC2086
    /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --options runtime ${OTHER_CODE_SIGN_FLAGS} "${path}"
  else
    /usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --options runtime "${path}"
  fi
}

while IFS= read -r dylib; do
  sign_file "${dylib}"
done < <(/usr/bin/find "${TOOLS_DIR}" -type f -name '*.dylib' -print | /usr/bin/sort)

while IFS= read -r executable; do
  sign_file "${executable}"
done < <(/usr/bin/find "${TOOLS_DIR}" -type f -perm +111 ! -name '*.dylib' -print | /usr/bin/sort)
