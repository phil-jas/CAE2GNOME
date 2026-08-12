#!/bin/bash

# Integrate applications from $APPLBIN_DIR into the GNOME desktop environment.
# Scans softlinks in $APPLBIN_DIR, presents a checklist, and syncs
# ~/.local/share/applications/<app_name>.desktop files.

set -euo pipefail

APPLBIN_DIR="${APPLBIN_DIR:-/applbin}"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_PATH="/usr/share/icons/Adwaita/symbolic/mimetypes/application-x-appliance-symbolic.svg"
TITLE="CAE2GNOME"

die() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="$TITLE" --text="$msg" --width=400 2>/dev/null || true
  fi
  echo "Error: $msg" >&2
  exit 1
}

require_zenity() {
  command -v zenity >/dev/null 2>&1 || {
    echo "Error: zenity is required (Please contact your support)." >&2
    exit 1
  }
}

# Write a minimal .desktop file for an application softlink.
write_desktop_file() {
  local app_name="$1"
  local exec_path="$2"
  local desktop_file="$DESKTOP_DIR/${app_name}.desktop"

  cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=${app_name}
Exec=${exec_path} %f
Icon=${ICON_PATH}
Terminal=true
Categories=Application;
EOF
}

# Collect application softlinks from APPLBIN_DIR.
# Populates parallel arrays APP_NAMES and APP_PATHS.
scan_applications() {
  APP_NAMES=()
  APP_PATHS=()

  local entry name
  # Sort for a stable checklist order
  while IFS= read -r -d '' entry; do
    name="$(basename "$entry")"
    # Skip hidden entries and empty names
    [[ -z "$name" || "$name" == .* ]] && continue
    APP_NAMES+=("$name")
    APP_PATHS+=("$entry")
done < <(find "$APPLBIN_DIR" -maxdepth 1 -type l -print0 2>/dev/null | sort -z)
}

# Return 0 if a matching .desktop file already exists.
is_registered() {
local app_name="$1"
[[ -f "$DESKTOP_DIR/${app_name}.desktop" ]]
}

main() {
require_zenity

[[ -d "$APPLBIN_DIR" ]] || die "Directory not found: $APPLBIN_DIR"

mkdir -p "$DESKTOP_DIR"

scan_applications

if [[ ${#APP_NAMES[@]} -eq 0 ]]; then
die "No application softlinks found in $APPLBIN_DIR"
fi

# Build zenity checklist arguments:
# TRUE  = already registered (checked)
# FALSE = not registered (unchecked)
local zenity_args=()
local i checked
for i in "${!APP_NAMES[@]}"; do
if is_registered "${APP_NAMES[$i]}"; then
checked="TRUE"
else
checked="FALSE"
fi
zenity_args+=("$checked" "${APP_NAMES[$i]}")
done

local selection
# Zenity returns selected (checked) rows, pipe-separated by default.
# Cancel / Esc exits with non-zero.
if ! selection="$(zenity --list \
--checklist \
--title="$TITLE" \
--text="Select <b>CAE applications</b> to integrate in <b>your</b> GNOME desktop environment.\n\n<b>Checked</b> = keep or add\n<b>Unchecked</b> = remove if present\n" \
--column="Add" \
--column="Application" \
--width=480 \
--height=500 \
--separator='|' \
"${zenity_args[@]}" 2>/dev/null)"; then
echo "Cancelled."
exit 0
fi

# Build a set of selected application names
declare -A SELECTED=()
if [[ -n "$selection" ]]; then
local IFS='|'
local name
for name in $selection; do
[[ -n "$name" ]] && SELECTED["$name"]=1
done
fi

local added=0 removed=0 updated=0

for i in "${!APP_NAMES[@]}"; do
local app_name="${APP_NAMES[$i]}"
local exec_path="${APP_PATHS[$i]}"
local desktop_file="$DESKTOP_DIR/${app_name}.desktop"

if [[ -n "${SELECTED[$app_name]+x}" ]]; then
# User wants this application registered (always rewrite to keep template current)
if is_registered "$app_name"; then
write_desktop_file "$app_name" "$exec_path"
updated=$((updated + 1))
else
write_desktop_file "$app_name" "$exec_path"
added=$((added + 1))
fi
else
# User does not want this application registered
if is_registered "$app_name"; then
rm -f "$desktop_file"
removed=$((removed + 1))
fi
fi
done

# Refresh the desktop application database for the user applications dir
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$DESKTOP_DIR"
  else
    zenity --warning --title="$TITLE" \
      --text="update-desktop-database not found; desktop cache was not refreshed." \
      --width=400 2>/dev/null || true
  fi

  zenity --info --title="$TITLE" \
    --text="Done.\n\nAdded: ${added}\nUpdated: ${updated}\nRemoved: ${removed}\n\nMenu entries: $DESKTOP_DIR" \
    --width=400 2>/dev/null || true
}

main "$@"
