#!/bin/bash
# Build build/drop/tcc/TCC.db: the phone's own privacy database (copied from the iOS disk in TWRP, read-only) with
# kTCCServicePhotos granted to assetsd and the Photos app. assetsd aborts with "assetsd requires TCCPhotosService
# access" although its signature has com.apple.private.tcc.allow = [kTCCServicePhotos]: tccd doesn't grant it here.
#   gracerlte/make-tcc.sh          (phone in TWRP)   then gracerlte/write-drop.sh tcc   (needs kernel patch 0404)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
T="$here/build/drop/tcc"; mkdir -p "$T" "$here/logs/tcc"
for f in TCC.db TCC.db-wal TCC.db-shm; do
    python3 "$here/gracerlte/hfs-read.py" get "/private/var/mobile/Library/TCC/$f" "$here/logs/tcc/$f" >/dev/null
done
rm -f "$T"/TCC.db*
cp "$here/logs/tcc/TCC.db" "$here/logs/tcc/TCC.db-wal" "$here/logs/tcc/TCC.db-shm" "$T/"
now=$(date +%s)
sqlite3 "$T/TCC.db" <<SQL
PRAGMA wal_checkpoint(TRUNCATE);
INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id,
    indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES
  ('kTCCServicePhotos',    'com.apple.assetsd', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $now),
  ('kTCCServicePhotosAdd', 'com.apple.assetsd', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $now),
  ('kTCCServicePhotos',    '/System/Library/Frameworks/AssetsLibrary.framework/Support/assetsd', 1, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $now),
  ('kTCCServicePhotos',    'com.apple.mobileslideshow', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $now),
  ('kTCCServicePhotosAdd', 'com.apple.mobileslideshow', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $now);
PRAGMA wal_checkpoint(TRUNCATE);
PRAGMA integrity_check;
SQL
sqlite3 "$T/TCC.db" "select service, client, client_type, auth_value from access where service like 'kTCCServicePhotos%';"
# A zero-length WAL and shm next to the checkpointed database: nothing old for SQLite to replay.
: > "$T/TCC.db-wal"; : > "$T/TCC.db-shm"
ls -l "$T"
