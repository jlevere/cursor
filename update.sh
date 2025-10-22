#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.json"

log() { echo "[$(date -Iseconds)] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Platform mapping: nix-system -> cursor-api-platform
declare -A platforms=(
    [x86_64-linux]='linux-x64'
)

log "Fetching latest versions for all platforms..."

# Fetch version info for all platforms
declare -A platform_data
first_version=""
for nix_platform in "${!platforms[@]}"; do
    api_platform="${platforms[$nix_platform]}"
    api_url="https://api2.cursor.sh/updates/api/download/stable/$api_platform/cursor"
    
    log "  Querying $nix_platform ($api_platform)..."
    response=$(curl -fsSL "$api_url") || die "Failed to query $api_platform"
    
    version=$(echo "$response" | jq -r '.version')
    download_url=$(echo "$response" | jq -r '.downloadUrl')
    
    [ -n "$version" ] || die "Failed to parse version for $nix_platform"
    [ -n "$download_url" ] || die "Failed to parse download URL for $nix_platform"
    
    # Verify all platforms have the same version
    if [ -z "$first_version" ]; then
        first_version="$version"
    elif [ "$version" != "$first_version" ]; then
        die "Version mismatch: $first_version vs $version for $nix_platform"
    fi
    
    platform_data[$nix_platform]="$download_url"
done

VERSION="$first_version"
log "Found version: $VERSION (consistent across all platforms)"

# Check if already up to date
if [ -f "$VERSIONS_FILE" ]; then
    CURRENT=$(jq -r '.latest' "$VERSIONS_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT" = "$VERSION" ]; then
        log "Already up to date: $VERSION"
        exit 0
    fi
    log "Updating $CURRENT → $VERSION"
fi

# Compute hashes for all platforms
log "Computing hashes..."
declare -A platform_hashes
for nix_platform in "${!platforms[@]}"; do
    url="${platform_data[$nix_platform]}"
    log "  Prefetching $nix_platform..."
    hash=$(nix-prefetch-url "$url" 2>&1 | tail -n1) || die "Failed to compute hash for $nix_platform"
    platform_hashes[$nix_platform]="$hash"
    log "    ✓ $hash"
done

# Build new version entry
log "Updating versions.json..."
NEW_ENTRY=$(jq -n \
    --arg v "$VERSION" \
    --arg x64_url "${platform_data[x86_64-linux]}" \
    --arg x64_hash "${platform_hashes[x86_64-linux]}" \
    '{
        version: $v,
        "x86_64-linux": {url: $x64_url, sha256: $x64_hash}
    }')

if [ ! -f "$VERSIONS_FILE" ]; then
    jq -n \
        --argjson e "$NEW_ENTRY" \
        --arg l "$VERSION" \
        '{"_comment": "Version history maintained automatically. Pin via: cursor.lib.buildVersion system version", versions: [$e], latest: $l}' \
        > "$VERSIONS_FILE"
else
    TMP=$(mktemp)
    # Check if version already exists
    if jq -e ".versions[] | select(.version == \"$VERSION\")" "$VERSIONS_FILE" &>/dev/null; then
        log "Version $VERSION already exists, updating latest pointer"
        jq --arg l "$VERSION" '.latest = $l' "$VERSIONS_FILE" > "$TMP"
    else
        log "Adding version $VERSION to history"
        jq --argjson e "$NEW_ENTRY" --arg l "$VERSION" \
            '.versions += [$e] | .latest = $l' "$VERSIONS_FILE" > "$TMP"
    fi
    mv "$TMP" "$VERSIONS_FILE"
fi

log "✓ Updated to $VERSION"
for nix_platform in "${!platforms[@]}"; do
    log "  $nix_platform:"
    log "    URL: ${platform_data[$nix_platform]}"
    log "    SHA256: ${platform_hashes[$nix_platform]}"
done
