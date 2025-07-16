echo "[DEBUG] Listing contents of ${helper_script_folder}/patch after copy:"
sudo ls -l "${helper_script_folder}/patch"

# Copy dotnet-install.py and update-dotnet-sdk-and-tfm.sh from helpers to patch dir for PowerShell build
if [ -f "${CURRENT_DIR}/dotnet-install.py" ]; then
  sudo cp "${CURRENT_DIR}/dotnet-install.py" "${helper_script_folder}/patch/"
fi
if [ -f "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" ]; then
  sudo cp "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" "${helper_script_folder}/patch/"
fi

# Debug: List all files in patch dir after copying
echo "[DEBUG] Final contents of ${helper_script_folder}/patch:"
sudo ls -l "${helper_script_folder}/patch"

# Debug: Check for specific required patch files
for required in powershell-native-*.patch powershell-*-*.patch powershell-gen-*.tar.gz; do
  found=$(ls "${helper_script_folder}/patch"/$required 2>/dev/null | wc -l)
  if [ "$found" -eq 0 ]; then
    echo "[ERROR] Required file pattern missing: $required in ${helper_script_folder}/patch" >&2
  else
    echo "[DEBUG] Found $found file(s) for pattern: $required"
  fi
done
#!/bin/bash
set -e  # Exit on any error


echo "[DEBUG] CURRENT_DIR: $(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
echo "[DEBUG] IMAGE_OS: ${IMAGE_OS}"
echo "[DEBUG] IMGDIR: ${CURRENT_DIR}/../../images/${IMAGE_OS}"
echo "[DEBUG] image_folder: ${image_folder}"
echo "[DEBUG] helper_script_folder: ${helper_script_folder}"
echo "[DEBUG] installer_script_folder: ${installer_script_folder}"
echo "[DEBUG] POWERSHELL_PATCH_DIR: ${CURRENT_DIR}/../../patches"

CURRENT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
IMGDIR="${CURRENT_DIR}/../../images/${IMAGE_OS}"


echo "[DEBUG] Creating patch directory: ${helper_script_folder}/patch"
sudo mkdir -p "${helper_script_folder}/patch"
echo "[DEBUG] Directory created: ${helper_script_folder}/patch (exit code $?)"

# Check if /imagegeneration already exists, delete if so, and recreate

echo "[DEBUG] Checking if image_folder exists: ${image_folder}"
if [ -d "${image_folder}" ]; then
    echo "Directory ${image_folder} exists. Deleting and recreating it."
    sudo rm -rf "${image_folder}"
    echo "[DEBUG] Deleted existing image_folder: ${image_folder} (exit code $?)"
fi

echo "[DEBUG] Creating installer_script_folder: ${installer_script_folder}"
sudo mkdir -p "${installer_script_folder}"
echo "[DEBUG] Copying IMGDIR/scripts/helpers to helper_script_folder"
sudo cp -r ${IMGDIR}/scripts/helpers/. "${helper_script_folder}"
echo "[DEBUG] Copying CURRENT_DIR to helper_script_folder"
sudo cp -r ${CURRENT_DIR}/. "${helper_script_folder}"
echo "[DEBUG] Copying assets to installer_script_folder"
sudo cp -r ${CURRENT_DIR}/../assets/. "${installer_script_folder}"
echo "[DEBUG] Copying PATCH_FILE to image_folder"
sudo cp ${CURRENT_DIR}/../../patches/${PATCH_FILE} "${image_folder}/runner-sdk-8.patch"
POWERSHELL_PATCH_DIR="${CURRENT_DIR}/../../patches"
## Copy all PowerShell patches and gen tar files to helper_script_folder/patch
for patchfile in powershell-*-*.patch powershell-native-*.patch; do
  if [ -f "${POWERSHELL_PATCH_DIR}/$patchfile" ]; then
    echo "[DEBUG] Copying $patchfile to patch dir"
    sudo cp "${POWERSHELL_PATCH_DIR}/$patchfile" "${helper_script_folder}/patch/"
    echo "[DEBUG] Copied $patchfile (exit code $?)"
  else
    echo "[DEBUG] Patch file not found: ${POWERSHELL_PATCH_DIR}/$patchfile"
  fi
done
for genfile in powershell-gen-*.tar.gz; do
  if [ -f "${POWERSHELL_PATCH_DIR}/$genfile" ]; then
    echo "[DEBUG] Copying $genfile to patch dir"
    sudo cp "${POWERSHELL_PATCH_DIR}/$genfile" "${helper_script_folder}/patch/"
    echo "[DEBUG] Copied $genfile (exit code $?)"
  else
    echo "[DEBUG] Gen tar file not found: ${POWERSHELL_PATCH_DIR}/$genfile"
  fi
done
# Copy dotnet-install.py and update-dotnet-sdk-and-tfm.sh from helpers to patch dir for PowerShell build
if [ -f "${CURRENT_DIR}/dotnet-install.py" ]; then
  echo "[DEBUG] Copying dotnet-install.py to patch dir"
  sudo cp "${CURRENT_DIR}/dotnet-install.py" "${helper_script_folder}/patch/"
  echo "[DEBUG] Copied dotnet-install.py (exit code $?)"
else
  echo "[DEBUG] dotnet-install.py not found in ${CURRENT_DIR}"
fi
if [ -f "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" ]; then
  echo "[DEBUG] Copying update-dotnet-sdk-and-tfm.sh to patch dir"
  sudo cp "${CURRENT_DIR}/update-dotnet-sdk-and-tfm.sh" "${helper_script_folder}/patch/"
  echo "[DEBUG] Copied update-dotnet-sdk-and-tfm.sh (exit code $?)"
else
  echo "[DEBUG] update-dotnet-sdk-and-tfm.sh not found in ${CURRENT_DIR}"
fi
sudo cp ${IMGDIR}/toolsets/${toolset_file_name} "${installer_script_folder}/toolset.json"
sudo cp -r ${IMGDIR}/scripts/build/. "${installer_script_folder}"
sudo cp -r ${IMGDIR}/assets/post-gen "${image_folder}"

if [ ! -d "${image_folder}/post-generation" ]; then
    sudo mv "${image_folder}/post-gen" "${image_folder}/post-generation"
fi
sudo chmod -R 0755 "${image_folder}"