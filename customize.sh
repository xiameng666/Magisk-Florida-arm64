# shellcheck disable=SC2034
SKIPUNZIP=1

DEBUG=false
MIN_KSU_VERSION=10940
MIN_KSUD_VERSION=11575
MAX_KSU_VERSION=20000
MIN_APATCH_VERSION=10700
MIN_MAGISK_VERSION=20400

if [ "$ensure_bb" ]; then
    abort "! BusyBox not properly setup"
fi

# Installing from ksu
if [ "$BOOTMODE" ] && [ "$KSU" ]; then
  ui_print "- Installing from KernelSU app"
  ui_print "- KernelSU version: $KSU_KERNEL_VER_CODE (kernel) + $KSU_VER_CODE (ksud)"
  if ! [ "$KSU_KERNEL_VER_CODE" ] || [ "$KSU_KERNEL_VER_CODE" -lt "$MIN_KSU_VERSION" ]; then
    ui_print "! KernelSU version is too old!"
    abort "! Please update KernelSU to latest version!";
    elif [ "$KSU_KERNEL_VER_CODE" -ge "$MAX_KSU_VERSION" ]; then
    ui_print "! KernelSU version abnormal!"
    ui_print "! Please integrate KernelSU into your kernel"
    abort "as submodule instead of copying the source code.";
  fi
  if ! [ "$KSU_VER_CODE" ] || [ "$KSU_VER_CODE" -lt "$MIN_KSUD_VERSION" ]; then
    print_title "! ksud version is too old!" "! Please update KernelSU Manager to latest version"
    abort;
  fi

# installing from APatch
elif [ "$BOOTMODE" ] && [ "$APATCH" ]; then
  ui_print "- Installing from APatch app version $APATCH_VER_CODE"
  if ! [ "$APATCH_VER_CODE" ] || [ "$APATCH_VER_CODE" -lt "$MIN_APATCH_VERSION" ]; then
    ui_print "! APatch version is too old!"
    abort "! Please update APatch to latest version"
  fi

# Installing from magisk v20.4+
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
  if [[ "$MAGISK_VER_CODE" -lt "$MIN_MAGISK_VERSION" ]]; then
    ui_print "*******************************"
    ui_print " Please install Magisk v20.4+! "
    ui_print "*******************************"
    abort;
  fi
  else
    print_title "- Installing from Magisk!"
fi

VERSION=$(grep_prop version "${TMPDIR}/module.prop")
print_title "- Installing Magisk Florida on boot $VERSION"

# check architecture - only support arm64
if [ "$ARCH" != "arm64" ]; then
  abort "! Unsupported platform: $ARCH (Only arm64 is supported)"
fi
ui_print "- Device platform: $ARCH"

ui_print "- Extracting module files"
unzip -qq -o "$ZIPFILE" 'module.prop' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'post-fs-data.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'service.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'webroot/*' -d "$MODPATH"
mkdir -p "$MODPATH/system/bin"

# Auto-scan and install all Florida versions from bin/
ui_print "- Scanning for Florida binaries..."

# List all florida-* files in the zip (support both compressed and raw)
FLORIDA_FILES=$(unzip -l "$ZIPFILE" | grep "bin/florida-" | awk '{print $4}' | sed 's|.*/||')

if [ -z "$FLORIDA_FILES" ]; then
  abort "! No Florida binaries found in package"
fi

INSTALLED_COUNT=0
FIRST_VERSION=""

# Install each version
for BINARY_FILE in $FLORIDA_FILES; do
  # Extract version name from filename
  # Supports: florida-1603, florida-1603.gz, florida-17.5.1, florida-17.5.1.gz
  VERSION_NAME=$(echo "$BINARY_FILE" | sed 's/^florida-//; s/\.gz$//')

  ui_print "  Installing Florida $VERSION_NAME..."

  # Extract file
  unzip -qq -o -j "$ZIPFILE" "bin/$BINARY_FILE" -d "$TMPDIR"

  if [ ! -f "$TMPDIR/$BINARY_FILE" ]; then
    ui_print "    ⚠ Failed to extract $BINARY_FILE"
    continue
  fi

  # Decompress if it's a .gz file
  if [[ "$BINARY_FILE" == *.gz ]]; then
    gzip -d "$TMPDIR/$BINARY_FILE"
    SOURCE_FILE="$TMPDIR/florida-$VERSION_NAME"
  else
    SOURCE_FILE="$TMPDIR/$BINARY_FILE"
  fi

  # Move to final location
  if [ -f "$SOURCE_FILE" ]; then
    mv "$SOURCE_FILE" "$MODPATH/system/bin/florida-$VERSION_NAME"
    ui_print "    ✓ $VERSION_NAME installed"

    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))

    # Remember first version as default
    if [ -z "$FIRST_VERSION" ]; then
      FIRST_VERSION="$VERSION_NAME"
    fi
  else
    ui_print "    ⚠ Failed to process $BINARY_FILE"
  fi
done

if [ $INSTALLED_COUNT -eq 0 ]; then
  abort "! No Florida versions were successfully installed"
fi

ui_print "- Installed $INSTALLED_COUNT Florida version(s)"

# Create default config if not exists
if ! test -f "$MODPATH/module.cfg"; then
  {
  echo "port=1314"
  echo "parameters="
  echo "status=1"
  echo "version=$FIRST_VERSION"
   } >> "$MODPATH/module.cfg"
  ui_print "- Default version: $FIRST_VERSION"
fi

# Create symlink to default version
ln -sf "florida-$FIRST_VERSION" "$MODPATH/system/bin/florida"

ui_print "- Setting permissions"
set_perm_recursive $MODPATH 0 0 0755 0644

# Set permissions for all installed Florida binaries
for FLORIDA_BIN in $MODPATH/system/bin/florida-*; do
  if [ -f "$FLORIDA_BIN" ]; then
    set_perm "$FLORIDA_BIN" 0 2000 0755 u:object_r:system_file:s0
  fi
done