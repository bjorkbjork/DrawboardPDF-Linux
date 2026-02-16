#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKGNAME="drawboard-pdf"
SRC_DIR="$PROJECT_ROOT/src"

# --- Dependency checks ---
for cmd in tar sha256sum makepkg jq gh; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is not installed"; exit 1; }
done

# --- Parse arguments ---
BUMP="patch"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m)  BUMP="major"; shift ;;
        -mi) BUMP="minor"; shift ;;
        -p)  BUMP="patch"; shift ;;
        -h|--help)
            echo "Usage: $0 [-m | -mi | -p]"
            echo "  -m   Bump major version (X.0.0)"
            echo "  -mi  Bump minor version (0.X.0)"
            echo "  -p   Bump patch version (0.0.X) [default]"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# --- Read current version and compute new version ---
CURRENT_VERSION=$(jq -r '.version' "$SRC_DIR/package.json")
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
TARBALL_NAME="${PKGNAME}-${VERSION}.tar.gz"
TARBALL_PATH="$PROJECT_ROOT/release_tars/$TARBALL_NAME"

echo "==> Version: $CURRENT_VERSION -> $VERSION ($BUMP bump)"

# --- Check source files exist ---
REQUIRED_FILES=(
    "$SRC_DIR/main.js"
    "$SRC_DIR/package.json"
    "$SRC_DIR/package-lock.json"
    "$SRC_DIR/assets/icon.png"
    "$PROJECT_ROOT/drawboard-pdf.desktop"
)
for f in "${REQUIRED_FILES[@]}"; do
    [[ -f "$f" ]] || { echo "Error: missing required file: $f"; exit 1; }
done

# --- Check if tarball already exists ---
if [[ -f "$TARBALL_PATH" ]]; then
    echo "Warning: $TARBALL_PATH already exists."
    read -rp "Overwrite? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# --- Update version in package.json and package-lock.json ---
jq --arg v "$VERSION" '.version = $v' "$SRC_DIR/package.json" > "$SRC_DIR/package.json.tmp" \
    && mv "$SRC_DIR/package.json.tmp" "$SRC_DIR/package.json"
echo "  Updated src/package.json"

jq --arg v "$VERSION" '.version = $v | .packages[""].version = $v' "$SRC_DIR/package-lock.json" > "$SRC_DIR/package-lock.json.tmp" \
    && mv "$SRC_DIR/package-lock.json.tmp" "$SRC_DIR/package-lock.json"
echo "  Updated src/package-lock.json"

# --- Create tarball ---
mkdir -p "$PROJECT_ROOT/release_tars"

tar czf "$TARBALL_PATH" \
    -C "$PROJECT_ROOT" \
    drawboard-pdf.desktop \
    src/package.json \
    src/package-lock.json \
    src/main.js \
    src/assets/icon.png

echo "==> Created $TARBALL_PATH"

# --- Compute checksum ---
CHECKSUM=$(sha256sum "$TARBALL_PATH" | awk '{print $1}')
echo "==> SHA256: $CHECKSUM"

# --- Verify tarball contents ---
echo "==> Tarball contents:"
tar tzf "$TARBALL_PATH"

# --- Verify build in a temp directory ---
echo "==> Verifying build with makepkg..."
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

sed -e "s/^pkgver=.*/pkgver=${VERSION}/" \
    -e "s/^pkgrel=.*/pkgrel=1/" \
    -e "s/^sha256sums=.*/sha256sums=('${CHECKSUM}')/" \
    -e "s|^source=.*|source=(\"file://${TARBALL_PATH}\")|" \
    "$PROJECT_ROOT/PKGBUILD" > "$TMPDIR/PKGBUILD"

(cd "$TMPDIR" && makepkg -f) || { echo "Error: makepkg build failed!"; exit 1; }

echo ""
echo "=== Build verified successfully ==="

# --- Upload to GitHub ---
echo ""
echo "==> Uploading to GitHub..."
gh release create "v${VERSION}" "$TARBALL_PATH" \
    --repo bjorkbjork/DrawboardPDF-Linux \
    --title "v${VERSION}" \
    || { echo "Error: GitHub upload failed!"; exit 1; }

echo ""
echo "=== Tarball created and uploaded ==="
echo "  Version:  $VERSION"
echo "  File:     $TARBALL_PATH"
echo "  SHA256:   $CHECKSUM"
echo ""
echo "Next steps:"
echo "  ./scripts/update-pkgbuild.sh"
