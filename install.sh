#!/bin/sh
set -eu

REPOSITORY=${LONGWAVE_RELEASE_REPOSITORY:-longwaverun/longwave-releases}
INSTALL_ROOT=${LONGWAVE_INSTALL_ROOT:-"$HOME/.local/share/longwave"}
BIN_DIRECTORY=${LONGWAVE_BIN_DIRECTORY:-"$HOME/.local/bin"}

case "$(uname -s)" in
  Linux) PLATFORM=linux ;;
  Darwin) PLATFORM=darwin ;;
  *) echo "Longwave supports Linux and macOS." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCHITECTURE=x64 ;;
  arm64|aarch64) ARCHITECTURE=arm64 ;;
  *) echo "Longwave supports x64 and arm64." >&2; exit 1 ;;
esac

# The desktop app is Apple Silicon only, and so are the releases for macOS.
if [ "$PLATFORM" = darwin ] && [ "$ARCHITECTURE" = x64 ]; then
  echo "Longwave supports Macs with Apple silicon; Intel Macs are not supported." >&2
  exit 1
fi

VERSION=${LONGWAVE_VERSION:-}
if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPOSITORY/releases?per_page=50" \
    | sed -n 's/.*"tag_name": "runtime-v\([^"]*\)".*/\1/p' \
    | head -n 1)
fi
if [ -z "$VERSION" ]; then
  echo "Could not find a Longwave runtime release. Set LONGWAVE_VERSION and retry." >&2
  exit 1
fi

ASSET="longwave-$PLATFORM-$ARCHITECTURE.tar.gz"
# LONGWAVE_RELEASE_BASE_URL serves the same assets from elsewhere; the local
# cloud-init test points it at a locally packaged Runtime.
BASE_URL=${LONGWAVE_RELEASE_BASE_URL:-"https://github.com/$REPOSITORY/releases/download/runtime-v$VERSION"}
TEMPORARY=$(mktemp -d "${TMPDIR:-/tmp}/longwave-install.XXXXXX")
trap 'rm -rf "$TEMPORARY"' EXIT HUP INT TERM

echo "Downloading Longwave $VERSION for $PLATFORM-$ARCHITECTURE..."
curl -fL "$BASE_URL/$ASSET" -o "$TEMPORARY/$ASSET"
curl -fL "$BASE_URL/$ASSET.sha256" -o "$TEMPORARY/$ASSET.sha256"
(
  cd "$TEMPORARY"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$ASSET.sha256"
  else
    EXPECTED=$(awk '{print $1}' "$ASSET.sha256")
    ACTUAL=$(shasum -a 256 "$ASSET" | awk '{print $1}')
    [ "$EXPECTED" = "$ACTUAL" ] || { echo "Checksum verification failed." >&2; exit 1; }
  fi
)

tar -xzf "$TEMPORARY/$ASSET" -C "$TEMPORARY"
mkdir -p "$INSTALL_ROOT/versions" "$BIN_DIRECTORY"
DESTINATION="$INSTALL_ROOT/versions/$VERSION"
if [ ! -d "$DESTINATION" ]; then
  mv "$TEMPORARY/longwave" "$DESTINATION"
fi
ln -sfn "versions/$VERSION" "$INSTALL_ROOT/current"
ln -sfn "$INSTALL_ROOT/current/longwave" "$BIN_DIRECTORY/longwave"

echo "Installed Longwave $VERSION."
case ":$PATH:" in
  *":$BIN_DIRECTORY:"*) ;;
  *) echo "Add $BIN_DIRECTORY to PATH, then open a new shell." ;;
esac
echo "No service or remote access was enabled. Continue with: longwave setup"
