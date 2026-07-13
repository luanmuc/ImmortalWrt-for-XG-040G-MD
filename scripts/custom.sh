#!/bin/sh
# ImmortalWrt custom build script for Nokia XG-040G-MD
# Runs in openwrt source root directory

echo ">>> Preparing custom packages directory"
mkdir -p package/custom
cd package/custom

echo ">>> Removing duplicate packages from feeds"
# Remove duplicate packages from all feeds directories
find ../../feeds/luci/ ../../feeds/packages/ -maxdepth 3 -type d -iname "*luci-theme-argon*" -exec rm -rf {} + 2>/dev/null
find ../../feeds/luci/ ../../feeds/packages/ -maxdepth 3 -type d -iname "*luci-app-argon-config*" -exec rm -rf {} + 2>/dev/null
find ../../feeds/luci/ ../../feeds/packages/ -maxdepth 3 -type d -iname "*luci-app-airoha-npu*" -exec rm -rf {} + 2>/dev/null

echo ">>> Cloning Argon theme (3 retries)"
for i in 1 2 3; do
  rm -rf luci-theme-argon
  git clone --depth 1 --single-branch --branch master https://github.com/jerrykuku/luci-theme-argon.git && break
  sleep 5
done

echo ">>> Cloning Argon config (3 retries)"
for i in 1 2 3; do
  rm -rf luci-app-argon-config
  git clone --depth 1 --single-branch --branch master https://github.com/jerrykuku/luci-app-argon-config.git && break
  sleep 5
done

echo ">>> Cloning Airoha NPU plugin (3 retries)"
for i in 1 2 3; do
  rm -rf luci-app-airoha-npu
  git clone --depth 1 --single-branch --branch main https://github.com/oyk470p/luci-app-airoha-npu.git && break
  sleep 5
done

echo ">>> Back to source root"
cd ../..

echo ">>> Fixing LuCI Makefile paths"
# Fix relative luci.mk includes in all custom packages
find package -name "Makefile" | xargs sed -i 's|include \.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|g'
find package -name "Makefile" | xargs sed -i 's|include \.\./\.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|g'

echo ">>> Applying cpufreq DTS patch for Airoha AN7581"
DTS_FILE="target/linux/airoha/dts/airoha-an7581-nokia-xg-040g-md.dts"
if [ -f "$DTS_FILE" ]; then
  # Check if patch already applied (idempotent)
  if ! grep -q "reg = <0x10210000 0x1000>;" "$DTS_FILE"; then
    sed -i '/compatible = "airoha,en7581-cpufreq";/a \	reg = <0x10210000 0x1000>;\n	reg-names = "cpufreq";' "$DTS_FILE"
    echo "cpufreq DTS patch applied successfully"
  else
    echo "cpufreq DTS patch already applied, skipping"
  fi
else
  echo "Info: DTS file not found, cpufreq patch skipped (already supported in newer versions)"
fi

echo ">>> Setting default LuCI theme to Argon"
# Official standard method: modify LuCI collection Makefile to set default theme
COLLECTION_MAKEFILE=$(find feeds/luci/collections/ -type f -name "Makefile" | head -1)
if [ -n "$COLLECTION_MAKEFILE" ]; then
  sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" "$COLLECTION_MAKEFILE"
  echo "Default theme set to Argon successfully"
else
  echo "Warning: LuCI collection Makefile not found, falling back to .config setting"
  sed -i 's/CONFIG_PACKAGE_luci-theme-bootstrap=y/# CONFIG_PACKAGE_luci-theme-bootstrap is not set/g' .config
  if ! grep -q "CONFIG_PACKAGE_luci-theme-argon=y" .config; then
    echo "CONFIG_PACKAGE_luci-theme-argon=y" >> .config
  fi
fi

echo ">>> Custom script completed successfully"
