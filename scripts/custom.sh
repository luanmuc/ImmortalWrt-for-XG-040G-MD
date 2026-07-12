#!/bin/bash
# Install and update third-party packages
# This script runs in openwrt/package/ directory, executed after feeds install

set -euo pipefail

# ==========================================
# Package Version Configuration
# ==========================================
# Uncomment and set specific commit/revision to lock package versions
# Example: PKG_<NAME>_REVISION="abc123def"

# PKG_ARGON_THEME_REVISION=""
# PKG_ARGON_CONFIG_REVISION=""
# PKG_PASSWALL2_REVISION=""
# PKG_PASSWALL_PACKAGES_REVISION=""

# ==========================================
# Helper Functions
# ==========================================

log_info() {
    echo "  [INFO] $*"
}

log_warn() {
    echo "  [WARN] $*"
}

log_error() {
    echo "  [ERROR] $*" >&2
}

log_section() {
    echo ""
    echo "=========================================="
    echo "$*"
    echo "=========================================="
}

# Git clone with retry mechanism
# Usage: git_clone_with_retry <clone_args...>
git_clone_with_retry() {
    local max_retries=3
    local retry_delay=5
    local attempt=1

    while [ $attempt -le $max_retries ]; do
        log_info "Git clone attempt $attempt/$max_retries"
        if git clone "$@"; then
            log_info "Git clone succeeded"
            return 0
        fi

        if [ $attempt -lt $max_retries ]; then
            log_warn "Git clone failed, retrying in ${retry_delay}s..."
            sleep $retry_delay
        fi

        attempt=$((attempt + 1))
    done

    log_error "Git clone failed after $max_retries attempts"
    return 1
}

# ==========================================
# Package Update Function
# ==========================================

UPDATE_PACKAGE() {
    local PKG_NAME="$1"
    local PKG_REPO="$2"
    local PKG_BRANCH="$3"
    local PKG_SPECIAL="${4:-}"
    local PKG_EXTRA_NAMES="${5:-}"

    # Build package list array
    local -a PKG_LIST=("$PKG_NAME")
    if [ -n "$PKG_EXTRA_NAMES" ]; then
        # shellcheck disable=SC2206
        PKG_LIST+=($PKG_EXTRA_NAMES)
    fi

    local REPO_NAME="${PKG_REPO#*/}"

    log_section "Processing: $PKG_NAME from $PKG_REPO"

    # Remove conflicting packages from feeds
    for NAME in "${PKG_LIST[@]}"; do
        log_info "Searching for existing: $NAME"
        local FOUND_DIRS
        FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null || true)

        if [ -n "$FOUND_DIRS" ]; then
            while read -r DIR; do
                if [ -n "$DIR" ]; then
                    rm -rf "$DIR"
                    log_info "Removed: $DIR"
                fi
            done <<< "$FOUND_DIRS"
        else
            log_info "No existing directory found: $NAME"
        fi
    done

    # Clone GitHub repository
    log_info "Cloning repository: $PKG_REPO (branch: $PKG_BRANCH)"

    local CLONE_CMD=("git" "clone" "--depth=1" "--single-branch" "--branch" "$PKG_BRANCH")

    # Check if specific revision is locked
    local REVISION_VAR="PKG_$(echo "$PKG_NAME" | tr '[:lower:]-' '[:upper:]_')_REVISION"
    local REVISION_VAL="${!REVISION_VAR:-}"

    if [ -n "$REVISION_VAL" ]; then
        log_info "Locked to revision: $REVISION_VAL"
        CLONE_CMD+=("--no-single-branch")
    fi

    CLONE_CMD+=("https://github.com/$PKG_REPO.git")

    if ! git_clone_with_retry "${CLONE_CMD[@]:2}"; then
        log_error "Failed to clone $PKG_REPO after retries"
        return 1
    fi

    # Checkout specific revision if locked
    if [ -n "$REVISION_VAL" ] && [ -d "$REPO_NAME" ]; then
        (
            cd "$REPO_NAME"
            git checkout "$REVISION_VAL"
        )
        log_info "Checked out revision: $REVISION_VAL"
    fi

    if [ ! -d "$REPO_NAME" ]; then
        log_error "Clone succeeded but directory not found: $REPO_NAME"
        return 1
    fi

    # Process cloned repository
    case "$PKG_SPECIAL" in
        pkg)
            # Extract specific package from monorepo
            log_info "Extracting package from monorepo..."
            find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
            rm -rf "./$REPO_NAME/"
            ;;
        name)
            # Rename repository
            log_info "Renaming to: $PKG_NAME"
            mv -f "$REPO_NAME" "$PKG_NAME"
            ;;
        *)
            # Keep as-is
            log_info "Keeping original directory name: $REPO_NAME"
            ;;
    esac

    log_info "Done: $PKG_NAME"
}

# ==========================================
# Main Script
# ==========================================

echo "Starting package updates..."

# First remove sing-box related packages from feeds to avoid conflicts
log_section "Removing conflicting sing-box packages from feeds"

rm -rf ../feeds/packages/net/sing-box 2>/dev/null || true
rm -rf ../package/feeds/packages/sing-box 2>/dev/null || true

log_info "Done removing sing-box from feeds"

# ==========================================
# Argon Theme
# ==========================================

log_section "Installing Argon Theme"

UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master"
UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master"

# Set default LuCI theme to Argon (keep bootstrap package for coexistence)
log_section "Setting default LuCI theme to argon"

COLLECTION_MAKEFILES=$(find ../feeds/luci/collections/ -type f -name "Makefile" 2>/dev/null || true)

if [ -n "$COLLECTION_MAKEFILES" ]; then
    # shellcheck disable=SC2086
    sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $COLLECTION_MAKEFILES
    log_info "Default LuCI theme set to argon"
else
    log_warn "No LuCI collection Makefile found, skipping theme default patch"
fi

# ==========================================
# 【暂时禁用】PassWall2 科学上网插件，需要时取消下面的注释即可
: <<'DISABLED_PASSWALL2'

# PassWall2 (Proxy Software - Lightweight)
# ==========================================

log_section "Installing PassWall2"

UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# On OpenWrt 25.12, upstream archives for shadowsocksr-libev have changed,
# old MIRROR_HASH is invalid. Disable SSR component first to avoid download failures.
PASSWALL2_MAKEFILE="./luci-app-passwall2/Makefile"

if [ -f "$PASSWALL2_MAKEFILE" ]; then
    log_info "Patching PassWall2 defaults to disable broken ShadowsocksR components..."
    sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client/,/default y/s/default y/default n/' "$PASSWALL2_MAKEFILE"
    sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Server/,/default n/s/default n/default n/' "$PASSWALL2_MAKEFILE"

    # Verify the patch was applied successfully
    if grep -q "INCLUDE_ShadowsocksR_Libev_Client" "$PASSWALL2_MAKEFILE"; then
        if grep -A5 "INCLUDE_ShadowsocksR_Libev_Client" "$PASSWALL2_MAKEFILE" | grep -q "default y"; then
            log_warn "ShadowsocksR Client patch may not have been applied correctly"
        else
            log_info "ShadowsocksR Client successfully disabled"
        fi
    fi

    log_info "PassWall2 SSR components disabled"
else
    log_warn "PassWall2 Makefile not found, skipping SSR patch"
fi
DISABLED_PASSWALL2

# ==========================================
# 【暂时禁用】PassWall 依赖包，需要时取消下面的注释即可
: <<'DISABLED_PASSWALL_DEPS'

# PassWall Dependencies (shared by PassWall and PassWall2)
# ==========================================

log_section "Installing PassWall dependencies"

if ! git_clone_with_retry --depth=1 --single-branch --branch main "https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"; then
    log_error "Failed to clone passwall-packages repository after retries"
    exit 1
fi

if [ -d "openwrt-passwall-packages" ]; then
    for pkg in openwrt-passwall-packages/*/; do
        pkg_name=$(basename "$pkg")
        if [ -d "$pkg" ] && [ -f "$pkg/Makefile" ]; then
            log_info "Installing: $pkg_name"
            rm -rf "./$pkg_name"
            cp -rf "$pkg" ./
        fi
    done
    rm -rf openwrt-passwall-packages
    log_info "PassWall dependencies installed"
else
    log_error "passwall-packages directory not found after clone"
    exit 1
fi
DISABLED_PASSWALL_DEPS

# ==========================================
# dllkids & iStore Software Feeds (Built-in)
# ==========================================
log_section "Setting up software feeds (dllkids + iStore)"

# Create files directory structure (will be copied to firmware rootfs)
mkdir -p ../files/etc/apk/keys
mkdir -p ../files/etc/apk/repositories.d

# ==========================================
# 1. Public Keys
# ==========================================

# dllkids public key
cat > ../files/etc/apk/keys/dllkids-feed.pub.pem << 'EOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEwTKjlQgSu4H+uwQt5PlHsFsxMehB
JVXQOIgHzb6TOgvxY6nhY+e9SDWguPidN9V1o/6INgP/KT+yNvZo6ArTtg==
-----END PUBLIC KEY-----
EOF

# iStore public key
cat > ../files/etc/apk/keys/istore-apk.pem << 'EOF'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEybK5eaXsrK06Thc1dbA3FC45Tlp8
8X5Z831vU6JggiV6tJiwI/B05IsdklTaZE8SYh0XCHcnXSjzRMLtarBisg==
-----END PUBLIC KEY-----
EOF

# ==========================================
# 2. Feed Configuration (repositories.d)
# ==========================================
# Standard location for third-party feeds, clean separation from official feeds

cat > ../files/etc/apk/repositories.d/customfeeds.list << 'EOF'
# dllkids OpenWrt Feed
https://op.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb

# iStore Software Feed
https://istore.istoreos.com/repo-apk/all/store/packages.adb
https://istore.istoreos.com/repo-apk/all/nas_luci/packages.adb
https://istore.istoreos.com/repo-apk/aarch64_generic/nas/packages.adb
EOF

# ==========================================
# 3. Feed Configuration (main repositories file)
# ==========================================
# Dual insurance: also append to main repositories file
# Some UI tools only read the main file, not repositories.d/

# Only append if file doesn't already contain our feeds
if ! grep -q "dllkids.xyz" ../files/etc/apk/repositories 2>/dev/null; then
    cat >> ../files/etc/apk/repositories << 'EOF'

# Custom third-party feeds
# dllkids OpenWrt Feed
https://op.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb

# iStore Software Feed
https://istore.istoreos.com/repo-apk/all/store/packages.adb
https://istore.istoreos.com/repo-apk/all/nas_luci/packages.adb
https://istore.istoreos.com/repo-apk/aarch64_generic/nas/packages.adb
EOF
fi

log_info "Software feeds configured (built-in)"
log_info "  - dllkids feed: https://op.dllkids.xyz/openwrt-feed/25.12/aarch64_cortex-a53/packages.adb"
log_info "  - iStore feed: https://istore.istoreos.com/repo-apk/"
log_info "  - Public keys: /etc/apk/keys/"
log_info "  - Feed config: /etc/apk/repositories.d/customfeeds.list"
log_info "  - Also appended to: /etc/apk/repositories (dual insurance)"
log_info "  - Feeds are available immediately after flashing, no first-boot script needed"

# ==========================================
# MAC Address Fix for XG-040G-MD
# ==========================================
log_section "Setting up MAC address fix for XG-040G-MD"

# Ensure uci-defaults directory exists
mkdir -p ../files/etc/uci-defaults

# Write uci-defaults script to fix MAC address on first boot
cat > ../files/etc/uci-defaults/99-fix-mac-address << 'FIXMAC_EOF'
#!/bin/sh
# Fix MAC address randomization on Bell XG-040G-MD
# This script runs once on first boot and then auto-deletes
# SAFETY: This script only reads factory data, never writes to U-Boot or hardware

. /lib/functions.sh
. /lib/functions/system.sh

log() {
    logger -t "mac-fix" "$*"
    echo "[mac-fix] $*"
}

# Only run on XG-040G-MD (nokia naming for ImmortalWrt)
BOARD=$(board_name)
if [ "$BOARD" != "nokia,xg-040g-md" ]; then
    exit 0
fi

log "Starting MAC address fix for $BOARD"

# ==========================================
# Helper: Check if MAC address is valid
# ==========================================
is_valid_mac() {
    local mac="$1"
    # Must be 6 colon-separated hex bytes
    if ! echo "$mac" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
        return 1
    fi
    # Must not be all zeros
    if [ "$mac" = "00:00:00:00:00:00" ]; then
        return 1
    fi
    # Must not be broadcast/multicast (LSB of first byte is 0 for unicast)
    local first_byte
    first_byte=$(echo "$mac" | cut -d: -f1)
    if [ $((0x$first_byte & 1)) -eq 1 ]; then
        return 1
    fi
    return 0
}

# ==========================================
# Helper: Generate stable random MAC from machine-id
# ==========================================
generate_stable_mac() {
    local seed=""

    # Try to get unique identifier from machine-id
    if [ -f /etc/machine-id ]; then
        seed=$(cat /etc/machine-id)
    fi

    # Fallback: use kernel command line or other sources
    if [ -z "$seed" ]; then
        seed=$(cat /proc/cmdline | md5sum | cut -d' ' -f1)
    fi

    if [ -z "$seed" ]; then
        # Last resort: truly random (will be different each boot, but saved to config)
        seed=$(head -c 16 /dev/urandom | hexdump -n 16 -e '4/4 "%08x"' | head -n1)
    fi

    # Generate MAC from seed (use Airoha OUI prefix: 00:0C:43 or similar)
    # We'll use a locally administered address (bit 1 of first byte = 1)
    # to avoid conflicts with real OUI
    local mac
    mac=$(echo "$seed" | md5sum | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*/\1:\2:\3:\4:\5:\6/')

    # Set locally administered bit and clear multicast bit
    # First byte: xx | 0x02 (locally admin) & 0xFE (not multicast)
    local first_byte
    first_byte=$(echo "$mac" | cut -d: -f1)
    first_byte=$(printf '%02x' $(( (0x$first_byte | 0x02) & 0xfe )))
    mac="${first_byte}:$(echo "$mac" | cut -d: -f2-)"

    echo "$mac"
}

# ==========================================
# Step 1: Try to read factory MAC from various sources
# ==========================================
WAN_MAC=""
LAN_MAC=""

# Method 1: Try fw_printenv (if available and working)
if command -v fw_printenv >/dev/null 2>&1; then
    log "Trying fw_printenv..."
    WAN_MAC=$(fw_printenv -n ethaddr 2>/dev/null)
    WAN_MAC=$(macaddr_canonicalize "$WAN_MAC")
    if [ -n "$WAN_MAC" ] && is_valid_mac "$WAN_MAC"; then
        log "Found MAC via fw_printenv: $WAN_MAC"
    else
        WAN_MAC=""
    fi
fi

# Method 2: Try reading directly from "env" MTD partition
if [ -z "$WAN_MAC" ]; then
    log "Trying direct MTD read from env partition..."
    ENV_IDX=$(find_mtd_index env 2>/dev/null || true)
    if [ -n "$ENV_IDX" ] && [ -b "/dev/mtdblock$ENV_IDX" ]; then
        WAN_MAC=$(strings "/dev/mtdblock$ENV_IDX" 2>/dev/null | sed -n 's/^ethaddr=//p' | head -n1)
        WAN_MAC=$(macaddr_canonicalize "$WAN_MAC")
        if [ -n "$WAN_MAC" ] && is_valid_mac "$WAN_MAC"; then
            log "Found MAC via MTD env partition: $WAN_MAC"
        else
            WAN_MAC=""
        fi
    fi
fi

# Method 3: Try reading from "factory" partition (common on many devices)
if [ -z "$WAN_MAC" ]; then
    log "Trying factory partition..."
    FACTORY_IDX=$(find_mtd_index factory 2>/dev/null || true)
    if [ -n "$FACTORY_IDX" ] && [ -b "/dev/mtdblock$FACTORY_IDX" ]; then
        # Try to find MAC in factory data (common patterns)
        WAN_MAC=$(hexdump -C "/dev/mtdblock$FACTORY_IDX" 2>/dev/null | grep -oE '([0-9a-fA-F]{2} ){5}[0-9a-fA-F]{2}' | head -n1 | tr ' ' ':')
        WAN_MAC=$(macaddr_canonicalize "$WAN_MAC")
        if [ -n "$WAN_MAC" ] && is_valid_mac "$WAN_MAC"; then
            log "Found MAC via factory partition: $WAN_MAC"
        else
            WAN_MAC=""
        fi
    fi
fi

# ==========================================
# Step 2: If no factory MAC found, generate stable one
# ==========================================
if [ -z "$WAN_MAC" ] || ! is_valid_mac "$WAN_MAC"; then
    log "No factory MAC found, generating stable MAC..."
    WAN_MAC=$(generate_stable_mac)
    log "Generated stable WAN MAC: $WAN_MAC"
fi

# ==========================================
# Step 3: Derive LAN MAC (WAN + 1)
# ==========================================
if is_valid_mac "$WAN_MAC"; then
    LAN_MAC=$(macaddr_add "$WAN_MAC" 1)
    log "Derived LAN MAC: $LAN_MAC"
fi

# ==========================================
# Step 4: Check if current config already has valid MACs
# ==========================================
CURRENT_WAN_MAC=""
CURRENT_LAN_MAC=""

# Get current WAN MAC from config
if uci get network.wan.macaddr >/dev/null 2>&1; then
    CURRENT_WAN_MAC=$(uci get network.wan.macaddr)
fi

# Get current LAN bridge MAC
if uci get network.@device[0].macaddr >/dev/null 2>&1; then
    CURRENT_LAN_MAC=$(uci get network.@device[0].macaddr 2>/dev/null || true)
fi

# Check if we need to update
NEED_UPDATE=false

if [ -n "$WAN_MAC" ] && is_valid_mac "$WAN_MAC"; then
    if [ "$CURRENT_WAN_MAC" != "$WAN_MAC" ]; then
        NEED_UPDATE=true
    fi
fi

if [ -n "$LAN_MAC" ] && is_valid_mac "$LAN_MAC"; then
    if [ "$CURRENT_LAN_MAC" != "$LAN_MAC" ]; then
        NEED_UPDATE=true
    fi
fi

if [ "$NEED_UPDATE" = false ]; then
    log "MAC addresses already configured correctly, no changes needed"
    exit 0
fi

# ==========================================
# Step 5: Apply MAC addresses to network config
# ==========================================
log "Applying MAC addresses to network configuration..."

# Set WAN MAC
if [ -n "$WAN_MAC" ] && is_valid_mac "$WAN_MAC"; then
    uci set network.wan.macaddr="$WAN_MAC"
    log "  WAN MAC set to: $WAN_MAC"
fi

# Set LAN MAC on the bridge device
# Find the br-lan device section
if [ -n "$LAN_MAC" ] && is_valid_mac "$LAN_MAC"; then
    # Try to find existing device section for br-lan
    DEVICE_IDX=""
    for i in $(seq 0 9); do
        DEV_NAME=$(uci get network.@device[$i].name 2>/dev/null || true)
        if [ "$DEV_NAME" = "br-lan" ]; then
            DEVICE_IDX=$i
            break
        fi
    done

    if [ -n "$DEVICE_IDX" ]; then
        uci set network.@device[$DEVICE_IDX].macaddr="$LAN_MAC"
        log "  LAN MAC set on br-lan device[$DEVICE_IDX]: $LAN_MAC"
    else
        # Create new device section for br-lan
        uci add network device
        uci set network.@device[-1].name="br-lan"
        uci set network.@device[-1].macaddr="$LAN_MAC"
        log "  Created br-lan device section with MAC: $LAN_MAC"
    fi
fi

# Commit changes
uci commit network
log "MAC address configuration saved"

log "MAC address fix completed successfully"

exit 0
FIXMAC_EOF

chmod +x ../files/etc/uci-defaults/99-fix-mac-address
log_info "MAC address fix configured"
log_info "  - Script: /etc/uci-defaults/99-fix-mac-address"
log_info "  - Runs once on first boot, then auto-deletes"
log_info "  - SAFETY: Only reads factory data, never modifies U-Boot or hardware"
log_info "  - Features: Multiple MAC detection methods + stable fallback"

# ==========================================
# NPU Support for Airoha AN7581
# ==========================================
log_section "Setting up NPU support for Airoha AN7581"

# Fixed DTS paths for ImmortalWrt nokia_xg-040g-md
DTS_FILE="../target/linux/airoha/dts/an7581.dtsi"
DTS_DEVICE_FILE="../target/linux/airoha/dts/an7581-nokia_xg-040g-md.dts"
log_info "Using DTS include: an7581.dtsi (ImmortalWrt)"
log_info "Using device DTS: an7581-nokia_xg-040g-md.dts (ImmortalWrt)"

# 1. Install luci-app-airoha-npu (LuCI NPU status page)
log_info "Installing luci-app-airoha-npu..."
UPDATE_PACKAGE "luci-app-airoha-npu" "oyk470p/luci-app-airoha-npu" "main"

# Fix LuCI makefile path (package is in package/, not feeds/luci/)
NPU_MAKEFILE="./luci-app-airoha-npu/Makefile"
if [ -f "$NPU_MAKEFILE" ]; then
    sed -i 's|include ../../luci.mk|include $(TOPDIR)/feeds/luci/luci.mk|' "$NPU_MAKEFILE"
    log_info "Fixed luci.mk path in luci-app-airoha-npu Makefile"
else
    log_warn "luci-app-airoha-npu Makefile not found, skipping path fix"
fi

# 2. Patch device tree to enable NPU and add missing memory regions
log_info "Patching device tree for NPU support..."

if [ -n "$DTS_FILE" ] && [ -f "$DTS_FILE" ]; then
    # Check if npu_ba is already present
    if grep -q "npu_ba\|npu-ba" "$DTS_FILE"; then
        log_info "npu_ba memory region already exists, skipping"
    else
        log_info "Adding npu_ba memory region to device tree..."

        # Add npu_ba memory region after npu_txbufid
        # Use sed to insert after the npu_txbufid node
        sed -i '/^\t\tnpu_txbufid: npu-txbufid@8c000000 {/,/^\t\t};/ {
            /^\t\t};/a\
\
\t\tnpu_ba: npu-ba@90c06800 {\
\t\t\tno-map;\
\t\t\treg = <0x0 0x90c06800 0x0 0x200000>;\
\t\t};
        }' "$DTS_FILE"

        log_info "npu_ba memory region added"
    fi

    # Update NPU node to include npu_ba memory region
    if grep -q "npu_ba" "$DTS_FILE"; then
        # Check if NPU memory-region already includes npu_ba
        if grep -A2 "memory-region.*npu_binary" "$DTS_FILE" | grep -q "npu_ba"; then
            log_info "NPU memory-region already includes npu_ba, skipping"
        else
            log_info "Adding npu_ba to NPU memory-region..."

            # Replace memory-region lines to add npu_ba
            # First, find the NPU node's memory-region and update it
            # Note: Use 5 tabs for indentation (matches actual DTS file format)
            sed -i '/npu@1e900000 {/,/^[[:space:]]*};/ {
                s/memory-region = <&npu_binary>, <&npu_pkt>, <&npu_txpkt>,/memory-region = <\&npu_binary>, <\&npu_pkt>, <\&npu_txpkt>,/
                s/\t\t\t\t\t<&npu_txbufid>;/\t\t\t\t\t<\&npu_txbufid>, <\&npu_ba>;/
                s/memory-region-names = "binary", "pkt", "tx-pkt",/memory-region-names = "binary", "pkt", "tx-pkt",/
                s/\t\t\t\t\t      "tx-bufid";/\t\t\t\t\t      "tx-bufid", "ba";/
            }' "$DTS_FILE"

            # Verify the patch was applied successfully
            if grep -A5 "memory-region.*npu_binary" "$DTS_FILE" | grep -q "npu_ba"; then
                log_info "NPU memory-region updated to include npu_ba"
            else
                log_warn "NPU memory-region patch may not have been applied correctly"
            fi
        fi
    fi

    # Ensure NPU node has status = "okay"
    # Check if NPU node already has any status property
    if grep -A30 "npu@1e900000" "$DTS_FILE" | grep -q "status\s*="; then
        log_info "NPU node already has status property, skipping"
    else
        log_info "Enabling NPU node in device tree..."

        # Add status = "okay" to NPU node (after the last memory-region-names line)
        # Note: memory-region-names spans two lines, "tx-bufid" is only on the second line
        sed -i '/npu@1e900000 {/,/^[[:space:]]*};/ {
            /"tx-bufid"/a\
\t\t\tstatus = "okay";
        }' "$DTS_FILE"

        # Verify the patch was applied
        if grep -A30 "npu@1e900000" "$DTS_FILE" | grep -q "status.*okay"; then
            log_info "NPU node enabled (status = okay)"
        else
            log_warn "NPU status patch may not have been applied correctly"
        fi
    fi

    log_info "Device tree NPU patching completed"
else
    log_warn "Device tree file not found: $DTS_FILE"
    log_warn "Skipping NPU device tree patching"
fi

# 3. Also enable NPU in device-level DTS (explicit override)
if [ -f "$DTS_DEVICE_FILE" ]; then
    # Check if &npu is already in device DTS
    if grep -q "&npu" "$DTS_DEVICE_FILE"; then
        log_info "Device-level NPU config already exists, skipping"
    else
        log_info "Adding device-level NPU enable override..."

        # Add &npu { status = "okay"; } before the end of file
        # Insert before &afe or &crypto or at the end
        if grep -q "&afe" "$DTS_DEVICE_FILE"; then
            sed -i '/^&afe/i\
&npu {\
\tstatus = "okay";\
};\
' "$DTS_DEVICE_FILE"
        else
            # Append before the last line
            sed -i '$i\
&npu {\
\tstatus = "okay";\
};\
' "$DTS_DEVICE_FILE"
        fi

        log_info "Device-level NPU enable override added"
    fi
else
    log_warn "Device DTS file not found: $DTS_DEVICE_FILE"
fi

log_info "NPU support setup completed"
log_info "  - luci-app-airoha-npu installed"
log_info "  - Device tree patched with npu_ba memory region"
log_info "  - NPU node explicitly enabled"

# ==========================================
# CPUFreq Fix for Airoha AN7581
# ==========================================
log_section "Fixing CPUFreq support for Airoha AN7581"

# Add reg properties to cpufreq node so the driver can use fallback mode
# (direct PLL register programming) when ATF SMC is not available.
# This fixes "CPU frequency: N/A" in luci-app-airoha-npu.
log_info "Patching device tree for cpufreq fallback mode..."

if [ -f "$DTS_FILE" ]; then
    # Step 1: Rename cpufreq node to include address (required for platform device creation)
    # Some kernels only create platform devices for nodes with addresses
    if grep -q "cpufreq: cpufreq@" "$DTS_FILE"; then
        log_info "cpufreq node already has address, skipping rename"
    else
        log_info "Adding address to cpufreq node name..."
        sed -i 's/cpufreq: cpufreq {/cpufreq: cpufreq@1fa20000 {/' "$DTS_FILE"
        
        if grep -q "cpufreq: cpufreq@" "$DTS_FILE"; then
            log_info "cpufreq node renamed successfully"
        else
            log_warn "cpufreq node rename may not have been applied correctly"
        fi
    fi

    # Step 2: Add reg properties for fallback mode
    # Check if cpufreq reg properties already exist
    if grep -A10 "cpufreq: cpufreq" "$DTS_FILE" | grep -q "chip-scu\|reg-names"; then
        log_info "cpufreq reg properties already exist, skipping"
    else
        log_info "Adding reg properties to cpufreq node..."

        # Insert reg and reg-names before the compatible line
        # This allows the driver to fall back to direct PLL register access
        # when ATF SMC is not available (e.g. older U-Boot versions)
        sed -i '/cpufreq: cpufreq.*{/,/compatible = "airoha,en7581-cpufreq"/ {
            /compatible = "airoha,en7581-cpufreq"/i\
\t\treg = <0x0 0x1fa20000 0x0 0x2c0>, <0x0 0x1efbe000 0x0 0x800>;\
\t\treg-names = "chip-scu", "mcucfg";
        }' "$DTS_FILE"

        # Verify the patch was applied
        if grep -A10 "cpufreq: cpufreq" "$DTS_FILE" | grep -q "chip-scu"; then
            log_info "cpufreq reg properties added successfully"
        else
            log_warn "cpufreq reg patch may not have been applied correctly"
        fi
    fi

    log_info "CPUFreq device tree patching completed"
else
    log_warn "Device tree file not found: $DTS_FILE"
    log_warn "Skipping CPUFreq device tree patching"
fi

log_info "CPUFreq fix setup completed"
log_info "  - Added address to cpufreq node name (cpufreq@1fa20000)"
log_info "  - Added chip-scu and mcucfg register addresses to cpufreq node"
log_info "  - Enables fallback mode when ATF SMC is not available"
log_info "  - Fixes CPU frequency display in NPU plugin"

# ==========================================

# ==========================================
# Login Page Title Banner for Argon Theme
# ==========================================
log_section "Adding login page title banner"

# Detect distribution version and build title text
log_info "Detecting distribution version..."

VERSION_TITLE=""
VERSION_FILE="../include/version.mk"

if [ -f "$VERSION_FILE" ]; then
    # Extract distribution ID
    DIST_ID=$(grep -E "^DISTRO_ID|^DISTRIB_ID" "$VERSION_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ' | tr -d '"' || true)
    DIST_RELEASE=$(grep -E "^DISTRO_RELEASE|^DISTRIB_RELEASE" "$VERSION_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ' | tr -d '"' || true)
    
    # Also check for immortalwrt specific files
    if [ -f "../package/base-files/files/etc/immortalwrt_release" ] || [ "$DIST_ID" = "ImmortalWrt" ]; then
        VERSION_TITLE="ImmortalWrt - XG-040G-MD"
        log_info "Detected: ImmortalWrt"
    elif echo "$DIST_RELEASE" | grep -q "25\."; then
        VERSION_TITLE="OpenWrt 25.12 - XG-040G-MD"
        log_info "Detected: OpenWrt 25.12 stable"
    else
        VERSION_TITLE="OpenWrt SNAPSHOT - XG-040G-MD"
        log_info "Detected: OpenWrt SNAPSHOT / main"
    fi
else
    # Fallback: check directory structure
    if [ -d "../package/feeds/immortalwrt" ] || grep -q "immortalwrt" ../Makefile 2>/dev/null; then
        VERSION_TITLE="ImmortalWrt - XG-040G-MD"
        log_info "Detected: ImmortalWrt (fallback detection)"
    else
        VERSION_TITLE="OpenWrt - XG-040G-MD"
        log_info "Detected: OpenWrt (fallback detection)"
    fi
fi

log_info "Version title: $VERSION_TITLE"

# Find Argon theme CSS file
ARGON_CSS=""
CSS_CANDIDATES=(
    "../feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css"
    "../package/feeds/luci/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css"
    "../feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/css/argon.css"
    "../package/feeds/luci/luci-theme-argon/htdocs/luci-static/argon/css/argon.css"
)

for css_path in "${CSS_CANDIDATES[@]}"; do
    if [ -f "$css_path" ]; then
        ARGON_CSS="$css_path"
        break
    fi
done

if [ -z "$ARGON_CSS" ]; then
    log_warn "Argon theme CSS file not found"
    log_warn "Skipping login page title injection"
else
    log_info "Found Argon CSS: $ARGON_CSS"
    log_info "Injecting login page title banner CSS..."
    
    # Escape title for CSS content
    ESCAPED_TITLE=$(echo "$VERSION_TITLE" | sed 's/"/\\"/g')
    
    # Append CSS to the file - targets login page only
    cat >> "$ARGON_CSS" << CSS_EOF

/* Login Page Title Banner - XG-040G-MD Custom */
.login-page .login-container::before {
    content: "$ESCAPED_TITLE";
    display: block;
    background: linear-gradient(135deg, #1e3a5f 0%, #2c5282 100%);
    color: #ffffff;
    text-align: center;
    padding: 14px 20px;
    font-size: 15px;
    font-weight: 500;
    border-radius: 12px 12px 0 0;
    margin: -24px -24px 20px -24px;
    letter-spacing:
