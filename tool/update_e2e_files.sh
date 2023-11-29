#!/bin/sh

set -e

ROOT_DIR=$(realpath .)
DART_E2E_BAK="$ROOT_DIR"/e2e.bak
ELECTRIC_REPO_PATH="$DART_E2E_BAK"/electric_repo

ELECTRIC_COMMIT=$(tool/extract_electric_commit.sh)

echo "Electric commit: $ELECTRIC_COMMIT"

rm -rf "$DART_E2E_BAK"
mv e2e "$DART_E2E_BAK"

pushd "$DART_E2E_BAK"
make clone_electric
popd

# Start with the base e2e from main electric
cp -r "$ELECTRIC_REPO_PATH"/e2e e2e

SATELLITE_CLIENT_PATH=e2e/satellite_client
rm -r "$SATELLITE_CLIENT_PATH"
cp -r "$DART_E2E_BAK"/satellite_client "$SATELLITE_CLIENT_PATH"

# Copy original from the electric e2e client that are in the patch file
# so that we can apply the patch
# base_satellite_client_path="$ELECTRIC_REPO_PATH"/e2e/satellite_client
# cp "$base_satellite_client_path"/Dockerfile "$SATELLITE_CLIENT_PATH"/Dockerfile
# cp "$base_satellite_client_path"/.gitignore "$SATELLITE_CLIENT_PATH"/.gitignore
# cp "$base_satellite_client_path"/Makefile "$SATELLITE_CLIENT_PATH"/Makefile

# Restore lux config
cp -rf "$DART_E2E_BAK"/lux e2e/lux
# Restore electric clone
cp -rf "$DART_E2E_BAK"/electric_repo e2e/electric_repo
# Restore run_client_e2e_with_retries.sh
cp "$DART_E2E_BAK"/run_client_e2e_with_retries.sh e2e

pushd "$ROOT_DIR/e2e"

# Apply patch ignoring first level (p1) from the diff (electric and dart subfolders)
# --merge is used so that it creates a "git compatible" merge conflict
# --no-backup-if-mismatch is used so that it doesn't create .orig files
patch -p1 --merge --no-backup-if-mismatch < "$ROOT_DIR"/patch/e2e.patch

popd
