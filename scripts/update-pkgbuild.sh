#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKGNAME="drawboard-pdf"
SRC_DIR="$PROJECT_ROOT/src"
PKGBUILD_PATH="$PROJECT_ROOT/PKGBUILD"
SRCINFO_PATH="$PROJECT_ROOT/.SRCINFO"

# --- Dependency checks ---
for cmd in sha256sum makepkg jq sed; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is not installed"; exit 1; }
done

# --- Parse arguments ---
PKGREL=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pkgrel) PKGREL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--pkgrel N]"
            echo "  --pkgrel N  Set pkgrel (default: 1)"
            echo ""
            echo "Reads version from src/package.json. Run make-tarball.sh first."
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# --- Read version from package.json ---
VERSION=$(jq -r '.version' "$SRC_DIR/package.json")
echo "==> Version from src/package.json: $VERSION"

# --- Locate tarball and compute checksum ---
TARBALL_NAME="${PKGNAME}-${VERSION}.tar.gz"
TARBALL_PATH="$PROJECT_ROOT/release_tars/$TARBALL_NAME"

if [[ ! -f "$TARBALL_PATH" ]]; then
    echo "Error: tarball not found at $TARBALL_PATH"
    echo "Run ./scripts/make-tarball.sh first."
    exit 1
fi

CHECKSUM=$(sha256sum "$TARBALL_PATH" | awk '{print $1}')
echo "==> SHA256: $CHECKSUM"

# --- Update PKGBUILD ---
sed -i "s/^pkgver=.*/pkgver=${VERSION}/" "$PKGBUILD_PATH"
sed -i "s/^pkgrel=.*/pkgrel=${PKGREL}/" "$PKGBUILD_PATH"
sed -i "s/^sha256sums=.*/sha256sums=('${CHECKSUM}')/" "$PKGBUILD_PATH"
echo "==> Updated PKGBUILD (pkgver=$VERSION, pkgrel=$PKGREL)"

# --- Regenerate .SRCINFO ---
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

cp "$PKGBUILD_PATH" "$TMPDIR/PKGBUILD"
(cd "$TMPDIR" && makepkg --printsrcinfo) > "$SRCINFO_PATH"
echo "==> Regenerated .SRCINFO"

# --- Verify build in temp directory ---
echo "==> Verifying build with makepkg..."

sed -e "s|^source=.*|source=(\"file://${TARBALL_PATH}\")|" \
    "$PKGBUILD_PATH" > "$TMPDIR/PKGBUILD"

(cd "$TMPDIR" && makepkg -f) || { echo "Error: makepkg build failed!"; exit 1; }

echo ""
echo "=== PKGBUILD updated and build verified ==="
echo "  Version:  $VERSION"
echo "  Pkg Rel:  $PKGREL"
echo "  SHA256:   $CHECKSUM"
echo ""
echo "Files modified:"
echo "  - PKGBUILD"
echo "  - .SRCINFO"
echo ""
echo "Next steps:"
echo "  git diff PKGBUILD .SRCINFO"
echo "  git add PKGBUILD .SRCINFO"
echo "  git commit -m 'Update to v${VERSION}'"
echo "  git push AUR main"
