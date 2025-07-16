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
      echo "📦 Installing: $pkg"
      sudo apt-get install -y --no-install-recommends "$pkg"
      INSTALLED_BY_SCRIPT+=("$pkg")
    else
      echo "✔️ Already installed: $pkg"
    fi
  done
}

log_and_run() {
  echo "🧾 $*"
  "$@"
}

# ---------------------------
# PREPARE SYSTEM
# ---------------------------
echo "🚀 Building PowerShell $POWERSHELL_VERSION from source on Ubuntu $UBUNTU_VERSION ($TARGETARCH)"
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
sudo cp libpsl-native.so /usr/lib/

# ---------------------------
# BUILD POWERSHELL
# ---------------------------
cd /tmp
cp "$HELPER_DIR/dotnet-install.py" .
cp "$HELPER_DIR/update-dotnet-sdk-and-tfm.sh" .
chmod +x update-dotnet-sdk-and-tfm.sh
cp "$PATCH_DIR/powershell-${TARGETARCH}-${POWERSHELL_VERSION}.patch" pwsh.patch
cp "$PATCH_DIR/powershell-gen-${POWERSHELL_VERSION}.tar.gz" .

log_and_run git clone https://github.com/PowerShell/PowerShell.git PowerShellSrc
cd PowerShellSrc
git checkout "tags/$POWERSHELL_VERSION" -b "${TARGETARCH}-${POWERSHELL_VERSION}"
python3 ../dotnet-install.py --install-dir "$DOTNET_DIR"
sudo ln -s "$DOTNET_DIR/dotnet" /usr/bin/dotnet

git apply ../pwsh.patch
cp ../update-dotnet-sdk-and-tfm.sh .
./update-dotnet-sdk-and-tfm.sh -g
tar -xzf ../powershell-gen-${POWERSHELL_VERSION}.tar.gz -C .

# ---------------------------
# BUILD .deb PACKAGE
# ---------------------------
cd src/powershell-unix
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

sudo ln -sf "$(pwd)/bin/Release/net*/linux-*/publish/pwsh" /usr/bin/pwsh

cd ../..
pwsh -Command "
  Set-Location .;
  Import-Module ./build.psm1 -ArgumentList \$true;
  Import-Module ./tools/packaging/packaging.psm1;
  Start-PSBootstrap -Scenario Package;
  Start-PSBuild -Clean -PSModuleRestore -Runtime linux-${TARGETARCH} -Configuration Release -UseNuGetOrg;
  Start-PSBuild -UseNuGetOrg -Configuration Release;
  Start-PSPackage -Type deb -Version \"${POWERSHELL_VERSION#v}\"
"

DEB_FILE="powershell_${POWERSHELL_VERSION#v}-1.deb_$(dpkg --print-architecture).deb"
cp "$DEB_FILE" /tmp/powershell.deb

# ---------------------------
# INSTALL .deb PACKAGE
# ---------------------------
echo "📦 Installing PowerShell DEB"
sudo apt-get install -y /tmp/powershell.deb
pwsh --version

# ---------------------------
# CLEANUP
# ---------------------------
echo "🧹 Cleaning up temp files..."
sudo rm -rf \
  /tmp/PowerShell* \
  /tmp/pwsh.* \
  "$DOTNET_DIR" \
  /usr/bin/dotnet \
  ~/.dotnet \
  ~/.nuget

echo "🧽 Removing apt packages installed by this script..."
for pkg in "${INSTALLED_BY_SCRIPT[@]}"; do
  echo "❌ Removing: $pkg"
  sudo apt-get purge -y "$pkg"
done

sudo apt-get autoremove -y
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "✅ PowerShell installed cleanly and system restored."
