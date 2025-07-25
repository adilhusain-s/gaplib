#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# CONFIGURATION
# ---------------------------
UBUNTU_VERSION="${1:-24.04}"
POWERSHELL_VERSION="${POWERSHELL_VERSION:-v7.5.2}"
POWERSHELL_NATIVE_VERSION="${POWERSHELL_NATIVE_VERSION:-v7.4.0}"
TARGETARCH="${ARCH:-$(dpkg --print-architecture)}"
POWERSHELL_CONTEXT="/var/tmp/imagegeneration/PowerShell/${TARGETARCH}/${POWERSHELL_VERSION}"
PATCH_DIR="${POWERSHELL_CONTEXT}/patches"
HELPER_DIR="${POWERSHELL_CONTEXT}/helpers"
DOTNET_DIR="/usr/share/dotnet"
INSTALLED_BY_SCRIPT=()

echo "[DEBUG] Using PowerShell build context: $POWERSHELL_CONTEXT"
echo "[DEBUG] Patch dir: $PATCH_DIR"
echo "[DEBUG] Helper dir: $HELPER_DIR"
ls -l "$PATCH_DIR" || echo "[WARNING] Patch dir missing: $PATCH_DIR"
ls -l "$HELPER_DIR" || echo "[WARNING] Helper dir missing: $HELPER_DIR"

# Check for required patch files
for required in "powershell-native-${POWERSHELL_NATIVE_VERSION}.patch" "powershell-${TARGETARCH}-${POWERSHELL_VERSION}.patch" "powershell-gen-${POWERSHELL_VERSION}.tar.gz"; do
  if [ ! -f "$PATCH_DIR/$required" ]; then
    echo "[ERROR] Required file missing: $PATCH_DIR/$required" >&2
    exit 1
  else
    echo "[DEBUG] Found required file: $PATCH_DIR/$required"
  fi
done

# Check for required helper scripts
for helper in "dotnet-install.py" "update-dotnet-sdk-and-tfm.sh"; do
  if [ ! -f "$HELPER_DIR/$helper" ]; then
    echo "[ERROR] Required helper missing: $HELPER_DIR/$helper" >&2
    exit 1
  else
    echo "[DEBUG] Found helper: $HELPER_DIR/$helper"
  fi
done

# ---------------------------
# UTILS
# ---------------------------
install_if_missing() {
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
  echo "Installing: $pkg"
      sudo apt-get install -y --no-install-recommends "$pkg"
      INSTALLED_BY_SCRIPT+=("$pkg")
    else
  echo "Already installed: $pkg"
    fi
  done
}

log_and_run() {
  echo "$*"
  "$@"
}

# ---------------------------
# PREPARE SYSTEM
# ---------------------------
echo "Building PowerShell $POWERSHELL_VERSION from source on Ubuntu $UBUNTU_VERSION ($TARGETARCH)"
sudo apt-get update -qq
install_if_missing git curl ca-certificates cmake g++ gcc make patch unzip sudo \
  libicu-dev python3 python3-pip python3-typer dpkg-dev build-essential

# ---------------------------
# BUILD NATIVE LIB
# ---------------------------
WORKDIR_NATIVE="/tmp/PowerShell-Native"
log_and_run git clone https://github.com/PowerShell/PowerShell-Native.git "$WORKDIR_NATIVE"
cd "$WORKDIR_NATIVE"
git checkout "tags/$POWERSHELL_NATIVE_VERSION" -b "${TARGETARCH}"
git apply "${PATCH_DIR}/powershell-native-${POWERSHELL_NATIVE_VERSION}.patch"
git submodule update --init
cd src/libpsl-native
cmake -DCMAKE_BUILD_TYPE=Debug .
make
(make test || cat Testing/Temporary/LastTest.log || true)
# Find and copy libpsl-native.so from anywhere in the tree
LIBPSL_PATH=$(find ../../ -name 'libpsl-native.so' | head -n1)
if [ -z "$LIBPSL_PATH" ]; then
  echo "[ERROR] libpsl-native.so not found after build!" >&2
  exit 1
fi
echo "[DEBUG] Copying $LIBPSL_PATH to /usr/lib/"
sudo cp "$LIBPSL_PATH" /usr/lib/


# ---------------------------
# BUILD POWERSHELL
# ---------------------------
# The PowerShell repo must be at /PowerShell for packaging to work
sudo rm -rf /PowerShell
log_and_run git clone https://github.com/PowerShell/PowerShell.git /PowerShell
cd /PowerShell
git checkout "tags/$POWERSHELL_VERSION" -b "${TARGETARCH}-${POWERSHELL_VERSION}"
# Now copy patch and tarball after clone
cp "$PATCH_DIR/powershell-${TARGETARCH}-${POWERSHELL_VERSION}.patch" pwsh.patch
cp "$PATCH_DIR/powershell-gen-${POWERSHELL_VERSION}.tar.gz" .
# Copy helpers directly from build context
cp "$HELPER_DIR/dotnet-install.py" .
cp "$HELPER_DIR/update-dotnet-sdk-and-tfm.sh" .
chmod +x update-dotnet-sdk-and-tfm.sh

# Use SDK verssion from global.json, install to /usr/share/dotnet, symlink to /usr/bin/dotnet
SDK_VERSION=$(python3 -c "import json; print(json.load(open('global.json'))['sdk']['version'])")
python3 ./dotnet-install.py --tag $SDK_VERSION
sudo ln -sf "$DOTNET_DIR/dotnet" /usr/bin/dotnet

git apply ./pwsh.patch
./update-dotnet-sdk-and-tfm.sh -g
tar -xzf ./powershell-gen-${POWERSHELL_VERSION}.tar.gz -C .

cd /PowerShell/src/powershell-unix
dotnet restore --source https://api.nuget.org/v3/index.json
dotnet publish . \
  -p:GenerateFullPaths=true \
  -p:ErrorOnDuplicatePublishOutputFiles=false \
  -p:IsWindows=false \
  -p:PublishReadyToRun=false \
  -p:WarnAsError=false \
  -p:RunAnalyzers=false \
  -p:SDKToUse=Microsoft.NET.Sdk \
  --self-contained \
  --configuration Release \
  --framework "net$(dotnet --version | cut -d. -f1,2)" \
  --runtime "linux-$(uname -m)"
# Ensure freshly built pwsh is available in PATH for packaging
PWSH_BIN=$(find "$(pwd)/bin/Release" -type f -path "*/linux-*/publish/pwsh" | head -n1)
if [ -z "$PWSH_BIN" ] || [ ! -x "$PWSH_BIN" ]; then
  echo "[ERROR] Built pwsh binary not found or not executable at expected location!" >&2
  find "$(pwd)/bin/Release" -type f -name pwsh
  exit 1
fi
echo "[DEBUG] Linking freshly built $PWSH_BIN to /usr/bin/pwsh for packaging"
sudo ln -sf "$PWSH_BIN" /usr/bin/pwsh
ls -l /usr/bin/pwsh

cd /PowerShell
pwsh -Command "
  Set-Location .;
  Import-Module ./build.psm1 -ArgumentList \$true;
  Import-Module ./tools/packaging/packaging.psm1;
  Start-PSBootstrap -Scenario Package;
  Start-PSBuild -Clean -PSModuleRestore -Runtime linux-${TARGETARCH} -Configuration Release -UseNuGetOrg;
  Start-PSBuild -UseNuGetOrg -Configuration Release;
  Start-PSPackage -Type deb -Version \"${POWERSHELL_VERSION#v}\"
"

# Remove the symlink to freshly built pwsh after packaging, before installing the .deb
echo "[DEBUG] Removing /usr/bin/pwsh symlink after packaging"
sudo rm -f /usr/bin/pwsh

DEB_FILE="powershell_${POWERSHELL_VERSION#v}-1.deb_$(dpkg --print-architecture).deb"
cp "$DEB_FILE" /tmp/powershell.deb

# ---------------------------
# INSTALL .deb PACKAGE
# ---------------------------
echo "Installing PowerShell DEB"
sudo apt-get install -y /tmp/powershell.deb
pwsh --version

# ---------------------------
# CLEANUP
# ---------------------------
echo "Cleaning up temp files..."
sudo rm -rf \
  /tmp/PowerShell* \
  /tmp/pwsh.* \
  "$DOTNET_DIR" \
  /usr/bin/dotnet \
  ~/.dotnet \
  ~/.nuget

echo "Removing apt packages installed by this script..."
for pkg in "${INSTALLED_BY_SCRIPT[@]}"; do
  echo "Removing: $pkg"
  sudo apt-get purge -y "$pkg"
done

sudo apt-get autoremove -y
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "PowerShell installed cleanly and system restored."
