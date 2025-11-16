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

# check architecture
regex="^(arm(64)?|x(86|64))$"
if ! [[ "$ARCH" =~ $regex ]]; then
  abort "! Unsupported platform: $ARCH"
else
  ui_print "- Device platform: $ARCH"
fi

ui_print "- Extracting module files"
unzip -qq -o "$ZIPFILE" 'module.prop' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'post-fs-data.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'service.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH"
unzip -qq -o "$ZIPFILE" 'webroot/*' -d "$MODPATH"
mkdir -p "$MODPATH/system/bin"

if ! test -f "$MODPATH/module.cfg"; then
  {
  echo "port=1314"
  echo "parameters="
  echo "status=1"
  echo "version=1603"
   } >> "$MODPATH/module.cfg"
fi

# Handle architecture-specific files - Install both versions
case "$ARCH" in
  arm)
    BINARY_FILE_1603="florida-arm.gz"
    BINARY_FILE_17_5_1="florida-arm.gz"
    ;;
  arm64)
    BINARY_FILE_1603="florida-1603.gz"
    BINARY_FILE_17_5_1="florida-17.5.1.gz"
    ;;
  x86)
    BINARY_FILE_1603="florida-x86.xz"
    BINARY_FILE_17_5_1="florida-x86.xz"
    ;;
  x86_64)
    BINARY_FILE_1603="florida-x86.xz"
    BINARY_FILE_17_5_1="florida-x86.xz"
    ;;
  *)
    abort "! Unsupported architecture: $ARCH"
    ;;
esac

# Install version 16.0.3
ui_print "- Installing Florida 16.0.3 for $ARCH platform"
if unzip -l "$ZIPFILE" | grep -q "bin/$BINARY_FILE_1603"; then
  unzip -qq -o -j "$ZIPFILE" "bin/$BINARY_FILE_1603" "$TMPDIR"
  if [[ "$BINARY_FILE_1603" == *.gz ]]; then
    gzip -d "$TMPDIR/$BINARY_FILE_1603"
    mv "$TMPDIR/florida-1603" "$MODPATH/system/bin/florida-1603"
  fi
  ui_print "  ✓ Florida 16.0.3 installed"
else
  ui_print "  ⚠ Florida 16.0.3 not found in package"
fi

# Install version 17.5.1
ui_print "- Installing Florida 17.5.1 for $ARCH platform"
if unzip -l "$ZIPFILE" | grep -q "bin/$BINARY_FILE_17_5_1"; then
  unzip -qq -o -j "$ZIPFILE" "bin/$BINARY_FILE_17_5_1" "$TMPDIR"
  if [[ "$BINARY_FILE_17_5_1" == *.gz ]]; then
    gzip -d "$TMPDIR/$BINARY_FILE_17_5_1"
    mv "$TMPDIR/florida-17.5.1" "$MODPATH/system/bin/florida-17.5.1"
  fi
  ui_print "  ✓ Florida 17.5.1 installed"
else
  ui_print "  ⚠ Florida 17.5.1 not found in package"
fi

# Create symlink to default version (1603)
ln -sf florida-1603 "$MODPATH/system/bin/florida"

ui_print "- Setting permissions"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/bin/florida-1603 0 2000 0755 u:object_r:system_file:s0
set_perm $MODPATH/system/bin/florida-17.5.1 0 2000 0755 u:object_r:system_file:s0