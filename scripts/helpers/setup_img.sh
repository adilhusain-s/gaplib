#!/bin/bash
set -e  # Exit on any error

CURRENT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
IMGDIR="${CURRENT_DIR}/../../images/${IMAGE_OS}"

# Ensure patch directory exists in helper_script_folder
sudo mkdir -p "${helper_script_folder}/patch"

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
POWERSHELL_PATCH_DIR="${CURRENT_DIR}/../../patches"
## Copy all PowerShell patches and gen tar files to helper_script_folder/patch
for patchfile in powershell-*-*.patch powershell-native-*.patch; do
  if [ -f "${POWERSHELL_PATCH_DIR}/$patchfile" ]; then
    sudo cp "${POWERSHELL_PATCH_DIR}/$patchfile" "${helper_script_folder}/patch/"
  fi
done
for genfile in powershell-gen-*.tar.gz; do
  if [ -f "${POWERSHELL_PATCH_DIR}/$genfile" ]; then
    sudo cp "${POWERSHELL_PATCH_DIR}/$genfile" "${helper_script_folder}/patch/"
  fi
done
# Copy dotnet-install.py and update-dotnet-sdk-and-tfm.sh from helpers to patch dir for PowerShell build
if [ -f "${CURRENT_DIR}/dotnet-install.py" ]; then
  sudo cp "${CURRENT_DIR}/dotnet-install.py" "${helper_script_folder}/patch/"
fi
if [ -f "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" ]; then
  sudo cp "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" "${helper_script_folder}/patch/"
fi
sudo cp ${IMGDIR}/toolsets/${toolset_file_name} "${installer_script_folder}/toolset.json"
sudo cp -r ${IMGDIR}/scripts/build/. "${installer_script_folder}"
sudo cp -r ${IMGDIR}/assets/post-gen "${image_folder}"

if [ ! -d "${image_folder}/post-generation" ]; then
    sudo mv "${image_folder}/post-gen" "${image_folder}/post-generation"
fi
sudo chmod -R 0755 "${image_folder}"