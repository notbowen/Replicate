#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${ROOT_DIR}/BundledTools/Tools"

mkdir -p "${TOOLS_DIR}"

find_fswatch() {
  if [[ -n "${FSWATCH_BIN:-}" && -x "${FSWATCH_BIN}" ]]; then
    printf '%s\n' "${FSWATCH_BIN}"
    return
  fi

  if command -v fswatch >/dev/null 2>&1; then
    command -v fswatch
    return
  fi

  if command -v nix >/dev/null 2>&1; then
    local out_path
    out_path="$(nix build nixpkgs#fswatch --no-link --print-out-paths)"
    printf '%s/bin/fswatch\n' "${out_path}"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    brew install fswatch
    command -v fswatch
    return
  fi

  printf 'fswatch was not found. Install Nix or Homebrew, or set FSWATCH_BIN.\n' >&2
  exit 1
}

copy_local_dependency_closure() {
  local binary="$1"
  local queue=("${binary}")
  local seen=""

  while ((${#queue[@]} > 0)); do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")

    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      case "${dep}" in
        /System/*|/usr/lib/*)
          continue
          ;;
      esac

      if [[ " ${seen} " == *" ${dep} "* ]]; then
        continue
      fi

      seen="${seen} ${dep}"
      cp -f "${dep}" "${TOOLS_DIR}/$(basename "${dep}")"
      chmod 755 "${TOOLS_DIR}/$(basename "${dep}")"
      queue+=("${dep}")
    done < <(otool -L "${current}" | awk 'NR > 1 { print $1 }')
  done
}

rewrite_install_names() {
  local files=("${TOOLS_DIR}"/*)

  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    if [[ "${file}" == *.dylib ]]; then
      install_name_tool -id "@loader_path/$(basename "${file}")" "${file}" || true
    fi
  done

  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      local bundled_dep="${TOOLS_DIR}/$(basename "${dep}")"
      if [[ -f "${bundled_dep}" ]]; then
        install_name_tool -change "${dep}" "@loader_path/$(basename "${dep}")" "${file}" || true
      fi
    done < <(otool -L "${file}" | awk 'NR > 1 { print $1 }')
  done
}

sign_tools() {
  for file in "${TOOLS_DIR}"/*; do
    [[ -f "${file}" ]] || continue
    codesign --force --sign - --options runtime "${file}" >/dev/null 2>&1 || true
  done
}

FSWATCH="$(find_fswatch)"
cp -f "${FSWATCH}" "${TOOLS_DIR}/fswatch"
chmod 755 "${TOOLS_DIR}/fswatch"

copy_local_dependency_closure "${FSWATCH}"
rewrite_install_names
sign_tools

printf 'Prepared bundled fswatch tools in %s\n' "${TOOLS_DIR}"
