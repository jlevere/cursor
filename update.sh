#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.json"

log() { echo "[$(date -Iseconds)] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Fetch latest version from Cursor's JSON API
log "Fetching latest version..."
API_URL="https://api2.cursor.sh/updates/api/download/stable/linux-x64/cursor"
RESPONSE=$(curl -fsSL "$API_URL") || die "Failed to query API"

VERSION=$(echo "$RESPONSE" | jq -r '.version')
DOWNLOAD_URL=$(echo "$RESPONSE" | jq -r '.downloadUrl')

[ -n "$VERSION" ] || die "Failed to parse version"
[ -n "$DOWNLOAD_URL" ] || die "Failed to parse download URL"

log "Found version: $VERSION"

# Check if already up to date
if [ -f "$VERSIONS_FILE" ]; then
    CURRENT=$(jq -r '.latest' "$VERSIONS_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT" = "$VERSION" ]; then
        log "Already up to date: $VERSION"
        exit 0
    fi
    log "Updating $CURRENT → $VERSION"
fi

# Compute hash
log "Computing hash..."
HASH=$(nix-prefetch-url "$DOWNLOAD_URL" 2>&1 | tail -n1) || die "Failed to compute hash"

# Update versions.json
log "Updating versions.json..."
NEW_ENTRY=$(jq -n --arg v "$VERSION" --arg u "$DOWNLOAD_URL" --arg h "$HASH" \
    '{version: $v, url: $u, sha256: $h}')

if [ ! -f "$VERSIONS_FILE" ]; then
    jq -n --argjson e "$NEW_ENTRY" --arg l "$VERSION" '{versions: [$e], latest: $l}' > "$VERSIONS_FILE"
else
    TMP=$(mktemp)
    # Check if version already exists
    if jq -e ".versions[] | select(.version == \"$VERSION\")" "$VERSIONS_FILE" &>/dev/null; then
        log "Version $VERSION already exists, skipping add"
        jq --arg l "$VERSION" '.latest = $l' "$VERSIONS_FILE" > "$TMP"
    else
        log "Adding version $VERSION to history"
        jq --argjson e "$NEW_ENTRY" --arg l "$VERSION" \
            '.versions += [$e] | .latest = $l' "$VERSIONS_FILE" > "$TMP"
    fi
    mv "$TMP" "$VERSIONS_FILE"
fi

log "✓ Updated to $VERSION"
log "  URL: $DOWNLOAD_URL"
log "  SHA256: $HASH"
