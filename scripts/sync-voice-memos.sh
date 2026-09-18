#!/usr/bin/env bash
# ==============================================================================
# sync-voice-memos.sh
#
# Copies new recordings out of the Apple Voice Memos container and into the
# transcription intake folder, ready for the voice-to-vault skill to process.
#
# Voice Memos does not only write .m4a. Depending on the recording format your
# device is set to, it also writes QuickTime audio (.qta) — commonly seen with
# stereo / spatial capture. Both are copied by default. The skill converts .qta
# to .m4a during intake.
#
# This script only ever COPIES. Nothing is deleted from Voice Memos, ever.
# ==============================================================================

set -euo pipefail

# Determine script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load configuration if available
if [ -f "$REPO_ROOT/config.env" ]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/config.env"
fi

# Fallback defaults
SOURCE_DIR="${VOICE_MEMOS_DIR:-$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings}"
DEST_DIR="${AUDIO_INGESTION_DIR:-$HOME/Documents/Audio/transcription}"
LOG_FILE="${LOG_FILE:-$HOME/Library/Logs/voice-memo-sync.log}"
SYNC_EXTENSIONS="${SYNC_EXTENSIONS:-m4a,qta}"

# Ensure directories exist
mkdir -p "$DEST_DIR/processed"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log "Sync triggered"

if [ ! -d "$SOURCE_DIR" ]; then
    log "Error: Voice Memos source directory not found or inaccessible: $SOURCE_DIR"
    log "Ensure Full Disk Access has been granted to your terminal / runner."
    log "See scripts/setup-permissions.md for the Automator wrapper approach."
    exit 1
fi

# macOS `cp -X` omits extended attributes (quarantine flags, restrictive MACLs)
# that can otherwise follow a recording out of the Voice Memos container and
# block other processes from reading it. GNU cp has no -X, so probe for support
# rather than assuming a BSD userland.
CP_XATTR_FLAG=""
xattr_probe="$DEST_DIR/.cp-xattr-probe"
if cp -X /dev/null "$xattr_probe" 2>/dev/null; then
    CP_XATTR_FLAG="-X"
fi
rm -f "$xattr_probe"

# Index every filename already in the intake tree (including processed/ and
# errors/) so a recording is never copied twice. Built once up front, then kept
# current as we copy, rather than re-scanning per file.
#
# Matching is done on exact whole lines with `grep -Fxq`, not with `find -name`:
# a filename containing glob characters would otherwise be treated as a pattern
# and silently fail to match itself.
existing_index="$(mktemp -t v2v-index)"
trap 'rm -f "$existing_index"' EXIT
find "$DEST_DIR" -type f -print 2>/dev/null | sed 's|.*/||' > "$existing_index"

copied_count=0
duplicate_count=0
placeholder_count=0
ignored_count=0
future_count=0

# Today, as YYYYMMDD, for the future-date sanity check below. Voice Memos
# filenames lead with the same compact form, so a plain integer compare works.
today_compact="$(date '+%Y%m%d')"

# nullglob: an unmatched pattern expands to nothing rather than to itself.
# nocaseglob: tolerate .M4A / .QTA from non-Apple recorders and manual drops.
shopt -s nullglob nocaseglob

# Split the configured extension list on commas.
IFS=',' read -r -a SYNC_EXT_ARRAY <<< "$SYNC_EXTENSIONS"

for raw_ext in "${SYNC_EXT_ARRAY[@]}"; do
    # Trim whitespace and any leading dot, so "m4a", " m4a" and ".m4a" all work.
    ext="$(echo "$raw_ext" | tr -d '[:space:]')"
    ext="${ext#.}"
    [ -n "$ext" ] || continue

    for file in "$SOURCE_DIR"/*."$ext"; do
        [ -f "$file" ] || continue

        filename="$(basename "$file")"

        if grep -Fxq "$filename" "$existing_index"; then
            duplicate_count=$((duplicate_count + 1))
            continue
        fi

        # Sanity-check the date Apple stamped into the filename. A recording
        # cannot have been made in the future, so a future date means the name
        # is wrong — most often the classic week-year bug, where a formatter
        # used YYYY (ISO week-year) instead of yyyy (calendar year) and rolled
        # late-December recordings into the following year.
        #
        # The file is still copied; the skill corrects the date at intake. This
        # is an early warning so a bad batch is visible before transcription.
        file_date="$(echo "$filename" | sed -n 's/^\([0-9]\{8\}\).*/\1/p')"
        if [ -n "$file_date" ] && [ "$file_date" -gt "$today_compact" ]; then
            log "Warning: future-dated filename, will be corrected at intake: $filename"
            future_count=$((future_count + 1))
        fi

        # shellcheck disable=SC2086 # CP_XATTR_FLAG is a single literal flag or empty
        cp $CP_XATTR_FLAG "$file" "$DEST_DIR/$filename"
        log "Copied: $filename"
        echo "$filename" >> "$existing_index"
        # Deliberately not ((copied_count++)): post-increment returns the old
        # value, so the first increment exits non-zero and aborts the whole run
        # under `set -e` on bash 4+ (Homebrew bash, most Linux distros).
        copied_count=$((copied_count + 1))
    done
done

# Recordings that iCloud has offloaded are not on disk — macOS leaves a hidden
# placeholder in their place. Copying one would yield a stub, not audio, so they
# are reported rather than copied. Open the recording in Voice Memos to download
# it, then re-run this script.
for stub in "$SOURCE_DIR"/.*.icloud; do
    [ -f "$stub" ] || continue
    placeholder_count=$((placeholder_count + 1))
    log "Not downloaded (iCloud placeholder), skipped: $(basename "$stub")"
done

# Anything else in the container — CloudRecordings.db and its -wal/-shm files,
# waveform caches, plists — is metadata, not audio, and is correctly left alone.
# It is counted so an unexpected new format cannot go unnoticed.
for entry in "$SOURCE_DIR"/*; do
    [ -f "$entry" ] || continue
    entry_ext="${entry##*.}"
    matched=0
    for raw_ext in "${SYNC_EXT_ARRAY[@]}"; do
        ext="$(echo "$raw_ext" | tr -d '[:space:]')"
        ext="${ext#.}"
        [ -n "$ext" ] || continue
        # Case-insensitive compare, for parity with nocaseglob above.
        if [ "$(echo "$entry_ext" | tr '[:upper:]' '[:lower:]')" = "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" ]; then
            matched=1
            break
        fi
    done
    [ "$matched" -eq 0 ] && ignored_count=$((ignored_count + 1))
done

shopt -u nullglob nocaseglob

log "Sync finished — copied $copied_count, already present $duplicate_count, not downloaded $placeholder_count, non-audio entries ignored $ignored_count"

if [ "$future_count" -gt 0 ]; then
    log "Warning: $future_count copied recording(s) carry a future date in their filename."
    log "The skill will correct these at intake and flag them in its run report."
fi

if [ "$placeholder_count" -gt 0 ]; then
    log "Warning: $placeholder_count recording(s) are in iCloud but not on this Mac."
    log "Open them in Voice Memos to download, then re-run to capture them."
fi
