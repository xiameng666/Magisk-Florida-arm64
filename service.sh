#!/system/bin/sh

DEBUG=false
MODDIR=${0%/*}
MODULE_PROP="/data/adb/modules/magisk-hluda/module.prop"
MODULE_CFG="/data/adb/modules/magisk-hluda/module.cfg"

# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != 1 ]; do
   sleep 1
done

# Additional stabilization delay
sleep 5

# Sync status from module.cfg to module.prop
if [ ! -f "$MODULE_CFG" ]; then
   sed -i 's/^description=.*/description=[Error: Config Missing ⚠️]/' "$MODULE_PROP"
   exit 1
fi

# Source config and update initial status
. "$MODULE_CFG"
# Determine version display
VERSION_DISPLAY="${version:-1603}"
if [ "$VERSION_DISPLAY" = "17.5.1" ] || [ "$VERSION_DISPLAY" = "1751" ]; then
   VERSION_DISPLAY="17.5.1"
else
   VERSION_DISPLAY="16.0.3"
fi

if [ "$status" = "1" ]; then
   sed -i "s/^description=.*/description=[Running✅ | v$VERSION_DISPLAY]/" "$MODULE_PROP"
else
   sed -i "s/^description=.*/description=[Stopped❌ | v$VERSION_DISPLAY]/" "$MODULE_PROP"
fi

# Read configuration from module.cfg
if [ -f "$MODULE_CFG" ]; then
   # Source the config file to get variables
   . "$MODULE_CFG"

   # Check if service should start (status=1)
   if [ "$status" = "1" ]; then
       # Determine which binary to use based on version parameter
       FLORIDA_BIN="florida-1603"  # Default version
       if [ "$version" = "17.5.1" ] || [ "$version" = "1751" ]; then
           FLORIDA_BIN="florida-17.5.1"
       elif [ "$version" = "1603" ] || [ "$version" = "16.0.3" ]; then
           FLORIDA_BIN="florida-1603"
       fi

       # Start service if not running
       if ! pgrep -x "$FLORIDA_BIN" > /dev/null; then
           # Build command with port and parameters
           CMD="$FLORIDA_BIN -D -l 0.0.0.0:$port"

           # Add additional parameters if specified
           if [ -n "$parameters" ]; then
               CMD="$CMD $parameters"
           fi

           # Execute the command and check result
           if ! $CMD; then
               sed -i 's/^description=.*/description=[Start Failed ⚠️]/' "$MODULE_PROP"
           fi
       fi
   else
       # Update module.prop to show stopped status
       sed -i 's/^description=.*/description=[Stopped❌]/' "$MODULE_PROP"
   fi
else
   # Log error if config file is missing
   echo "Error: module.cfg not found";
fi