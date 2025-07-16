#!/bin/bash
set -e  # Exit on any error

CURRENT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
IMGDIR="${CURRENT_DIR}/../../images/${IMAGE_OS}"

# Check if /imagegeneration already exists, delete if so, and recreate
if [ -d "${image_folder}" ]; then
    echo "Directory ${image_folder} exists. Deleting and recreating it."
    sudo rm -rf "${image_folder}"
fi

sudo mkdir -p "${installer_script_folder}"
sudo cp -r ${IMGDIR}/scripts/helpers/. "${helper_script_folder}"
sudo cp -r ${CURRENT_DIR}/. "${helper_script_folder}"
sudo cp -r ${CURRENT_DIR}/../assets/. "${installer_script_folder}"
sudo cp ${CURRENT_DIR}/../../patches/${PATCH_FILE} "${image_folder}/runner-sdk-8.patch"
sudo cp ${IMGDIR}/toolsets/${toolset_file_name} "${installer_script_folder}/toolset.json"
sudo cp -r ${IMGDIR}/scripts/build/. "${installer_script_folder}"
sudo cp -r ${IMGDIR}/assets/post-gen "${image_folder}"

if [ ! -d "${image_folder}/post-generation" ]; then
    sudo mv "${image_folder}/post-gen" "${image_folder}/post-generation"
fi
sudo chmod -R 0755 "${image_folder}"

# --- PowerShell version/arch support ---
# Set these variables as needed, or pass them in from the environment
POWERSHELL_VERSION=${POWERSHELL_VERSION:-v7.5.2}
POWERSHELL_NATIVE_VERSION=${POWERSHELL_NATIVE_VERSION:-v7.4.0}
POWERSHELL_ARCH=${ARCH:-$(uname -m)}
POWERSHELL_CONTEXT="${image_folder}/PowerShell/${POWERSHELL_ARCH}/${POWERSHELL_VERSION}"
echo "[DEBUG] Creating PowerShell build context at: $POWERSHELL_CONTEXT"
sudo mkdir -p "$POWERSHELL_CONTEXT/patches"
sudo mkdir -p "$POWERSHELL_CONTEXT/helpers"

# Copy PowerShell patch files and tarballs
for f in \
    ${CURRENT_DIR}/../../patches/powershell-native-${POWERSHELL_NATIVE_VERSION}.patch \
    ${CURRENT_DIR}/../../patches/powershell-${POWERSHELL_ARCH}-${POWERSHELL_VERSION}.patch \
    ${CURRENT_DIR}/../../patches/powershell-gen-${POWERSHELL_VERSION}.tar.gz
do
    if [ -f "$f" ]; then
        echo "[DEBUG] Copying $f to $POWERSHELL_CONTEXT/patches/"
        sudo cp "$f" "$POWERSHELL_CONTEXT/patches/"
    else
        echo "[WARNING] PowerShell patch/tarball not found: $f"
    fi
done

# Copy PowerShell helper scripts
for f in \
    ${IMGDIR}/scripts/helpers/dotnet-install.py \
    ${IMGDIR}/scripts/helpers/update-dotnet-sdk-and-tfm.sh
do
    if [ -f "$f" ]; then
        echo "[DEBUG] Copying $f to $POWERSHELL_CONTEXT/helpers/"
        sudo cp "$f" "$POWERSHELL_CONTEXT/helpers/"
    else
        echo "[WARNING] PowerShell helper not found: $f"
    fi
done

sudo chmod -R 0755 "$POWERSHELL_CONTEXT"