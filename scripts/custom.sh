#!/bin/bash
# ImmortalWrt custom build script
# This script runs in the openwrt source directory

# Add custom feeds
echo "Adding custom feeds..."
cat >> feeds.conf.default <<EOF
src-git-full packages https://github.com/immortalwrt/packages.git;openwrt-23.05
src-git-full luci https://github.com/immortalwrt/luci.git;openwrt-23.05
src-git-full routing https://github.com/immortalwrt/routing.git;openwrt-23.05
src-git-full telephony https://github.com/immortalwrt/telephony.git;openwrt-23.05
# Third-party feeds
src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main
src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main
src-git openclash https://github.com/vernesong/OpenClash.git;master
src-git adguardhome https://github.com/rufengsuixing/luci-app-adguardhome.git;master
EOF

# Clone additional packages manually
echo "Cloning additional packages..."
mkdir -p package/custom
cd package/custom

# Clone common plugins
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git
git clone --depth 1 https://github.com/tty228/luci-app-wechatpush.git
git clone --depth 1 https://github.com/ilxp/luci-app-ikoolproxy.git
git clone --depth 1 https://github.com/sbwml/luci-app-mosdns.git mosdns
git clone --depth 1 https://github.com/sbwml/v2ray-geodata.git

# Fix Makefile paths for packages that have nested directories
echo "Fixing Makefile paths..."
for dir in */; do
  if [ -f "$dir/Makefile" ]; then
    # Some packages have their source in a subdirectory, move them up if needed
    continue
  fi
  # Check if there's a subdirectory with Makefile
  for subdir in "$dir"*/; do
    if [ -f "$subdir/Makefile" ]; then
      mv "$subdir"* "$dir"
      rm -rf "$subdir"
    fi
  done
done

# Go back to openwrt root
cd ../..

# Apply cpufreq patch for MediaTek MT7981/MT7986 devices
echo "Applying cpufreq patch..."
if [ -f target/linux/mediatek/patches-5.4/999-cpufreq-fix.patch ] || [ -f target/linux/mediatek/patches-6.1/999-cpufreq-fix.patch ]; then
  echo "cpufreq patch already exists, skipping"
else
  # Create cpufreq patch for MT7981 to fix frequency scaling issues
  cat > target/linux/mediatek/patches-6.1/999-mt7981-cpufreq-fix.patch <<'PATCH_EOF'
--- a/drivers/cpufreq/mediatek-cpufreq-hw.c
+++ b/drivers/cpufreq/mediatek-cpufreq-hw.c
@@ -186,7 +186,7 @@ static int mtk_cpufreq_hw_target_index(struct cpufreq_policy *policy,
 	writel_relaxed(reg, &cpu_reg->cpu_peri_volt);
 
 	/* Wait for voltage to stabilize */
-	udelay(10);
+	udelay(100);
 
 	/* Set the new frequency */
 	reg = readl_relaxed(&cpu_reg->cpu_pll_div);
PATCH_EOF
fi

# Fix NPU driver build issues if needed
echo "Checking NPU driver configuration..."
if [ -d package/kernel/mtk-npu ]; then
  # Fix Makefile path for NPU driver
  sed -i 's|^MAKE_FLAGS.*|MAKE_FLAGS += KERNEL_DIR=$(LINUX_DIR)|' package/kernel/mtk-npu/Makefile
fi

# Fix common build errors
echo "Applying common build fixes..."
# Fix for golang packages on 32-bit systems
if grep -q "GO_ARCH" package/lang/golang/golang-values.mk; then
  echo "golang config already fixed"
else
  echo "CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=y" >> .config 2>/dev/null || true
fi

# Set default optimization flags
echo "Setting build optimization flags..."
echo "CONFIG_CCACHE=y" >> .config 2>/dev/null || true
echo "CONFIG_CCACHE_DIR=\"$HOME/.ccache\"" >> .config 2>/dev/null || true
echo "CONFIG_CCACHE_MAXSIZE=\"2G\"" >> .config 2>/dev/null || true

echo "Custom script completed successfully!"
