#!/bin/bash
# Daily verified snapshot of the claude-mem local store.
#
# Safe to run while the worker is live: sqlite3 .backup takes a consistent
# point-in-time image, unlike cp, which can tear a database with a hot WAL.
#
# Primary destination is ~/Library/Application Support, which a launchd agent
# can always write. It then tries to mirror the newest snapshot into
# ~/Documents (iCloud-synced, so off-machine). macOS TCC blocks background
# agents from Documents until /bin/bash is granted Full Disk Access, so that
# step is best-effort: it logs and carries on rather than failing the backup.

set -uo pipefail

SRC_DB="$HOME/.claude-mem/claude-mem.db"
SRC_CHROMA="$HOME/.claude-mem/chroma"
ROOT="$HOME/Library/Application Support/claude-mem-backups"
MIRROR="$HOME/Documents/claude-mem-backups"
LOG="$HOME/Library/Logs/claude-mem-backup.log"
KEEP=7
SQLITE=/usr/bin/sqlite3

mkdir -p "$ROOT" "$(dirname "$LOG")"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -n 400 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

if [ ! -f "$SRC_DB" ]; then
  log "ERROR source database missing: $SRC_DB"
  exit 1
fi

DEST="$ROOT/$(date +%Y-%m-%d)"
mkdir -p "$DEST"
TMP="$DEST/.claude-mem.db.partial"
rm -f "$TMP"

# 1. consistent snapshot to a temp file
if ! "$SQLITE" "$SRC_DB" ".backup '$TMP'" 2>>"$LOG"; then
  log "ERROR .backup failed; previous snapshot left intact"
  rm -f "$TMP"
  exit 1
fi

# 2. verify before letting it replace today's good copy
INTEG="$("$SQLITE" "$TMP" 'PRAGMA integrity_check;' 2>/dev/null)"
if [ "$INTEG" != "ok" ]; then
  log "ERROR integrity_check=$INTEG; discarding bad snapshot"
  rm -f "$TMP"
  exit 1
fi

OBS="$("$SQLITE" "$TMP" 'SELECT COUNT(*) FROM observations;' 2>/dev/null || echo '?')"
SUM="$("$SQLITE" "$TMP" 'SELECT COUNT(*) FROM session_summaries;' 2>/dev/null || echo '?')"
mv -f "$TMP" "$DEST/claude-mem.db" || { log "ERROR could not install snapshot"; exit 1; }
# sqlite leaves sidecar journals next to the temp file; they are not part of the snapshot
rm -f "$TMP-shm" "$TMP-wal"

# 3. vector index: keep it only alongside the newest snapshot
if [ -d "$SRC_CHROMA" ]; then
  rm -rf "$DEST/.chroma.partial"
  if cp -R "$SRC_CHROMA" "$DEST/.chroma.partial" 2>>"$LOG"; then
    rm -rf "$DEST/chroma"
    mv "$DEST/.chroma.partial" "$DEST/chroma"
  else
    log "WARN chroma copy failed (database snapshot is still good)"
    rm -rf "$DEST/.chroma.partial"
  fi
fi
for old in "$ROOT"/*/; do
  [ "${old%/}" = "$DEST" ] && continue
  rm -rf "${old}chroma" 2>/dev/null
done

# 4. retention: keep the newest $KEEP dated snapshots
ls -1d "$ROOT"/20*/ 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | while read -r dir; do
  rm -rf "$dir" && log "pruned $(basename "$dir")"
done

SIZE="$(du -sh "$DEST" 2>/dev/null | cut -f1 | tr -d ' ')"
TOTAL="$(du -sh "$ROOT" 2>/dev/null | cut -f1 | tr -d ' ')"
log "OK $(basename "$DEST") observations=$OBS summaries=$SUM size=$SIZE total=$TOTAL"

# 5. best-effort off-machine mirror of the newest snapshot only
if mkdir -p "$MIRROR/latest" 2>/dev/null &&
   cp -f "$DEST/claude-mem.db" "$MIRROR/latest/claude-mem.db" 2>/dev/null; then
  date '+%Y-%m-%d %H:%M:%S' >"$MIRROR/latest/snapshot-taken.txt" 2>/dev/null
  log "mirrored to iCloud Documents"
else
  log "NOTE iCloud mirror skipped (grant /bin/bash Full Disk Access to enable)"
fi
