#!/bin/bash
#=================================================
# 自定义脚本：安装第三方插件和配置
# 适用于 ImmortalWrt master for Nokia XG-040G-MD
# 注意：ImmortalWrt官方已经完整支持XG-040G-MD硬件，NPU、闪存驱动等都已内置
# 仅补充cpufreq的reg属性，解决U-Boot不支持SMCC时CPU频率显示N/A的问题
# 执行时工作目录：openwrt/package
#=================================================
set -euo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
echo -e "${BLUE}===> 开始安装自定义插件...${NC}"
echo -e "${BLUE}---> 当前工作目录：$(pwd)${NC}"

# 带重试的git克隆函数
git_clone_with_retry() {
    local max_retries=3
    local retry_delay=5
    local attempt=1
    local target_dir="${@: -1}"
    while [ $attempt -le $max_retries ]; do
        echo -e "${YELLOW}---> 克隆尝试 $attempt/$max_retries${NC}"
        # 每次克隆前清理不完整目录，避免目录已存在导致克隆失败
        rm -rf "$target_dir"
        if git clone --depth 1 --single-branch "$@"; then
            echo -e "${GREEN}---> 克隆成功${NC}"
            return 0
        fi
        if [ $attempt -lt $max_retries ]; then
            echo -e "${YELLOW}---> 克隆失败，${retry_delay}秒后重试...${NC}"
            sleep $retry_delay
        fi
        attempt=$((attempt + 1))
    done
    echo -e "${RED}---> 克隆失败，已重试$max_retries次${NC}"
    return 1
}

# 第三方插件安装函数
UPDATE_PACKAGE() {
    local PKG_NAME=$1
    local PKG_REPO=$2
    local PKG_BRANCH=$3
    echo -e "${YELLOW}---> 安装插件：${PKG_NAME}${NC}"
    
    # 删除feeds中已存在的同名包，避免冲突
    local FOUND_DIRS
    FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$PKG_NAME*" 2>/dev/null || true)
    if [ -n "$FOUND_DIRS" ]; then
        while read -r DIR; do
            if [ -n "$DIR" ]; then
                rm -rf "$DIR"
                echo -e "${YELLOW}---> 删除feeds中已有的同名包：$DIR${NC}"
            fi
        done <<< "$FOUND_DIRS"
    fi
    
    # 删除本地已存在的目录
    if [ -d "$PKG_NAME" ]; then
        rm -rf "$PKG_NAME"
    fi
    
    # 克隆插件（当前目录是package/，直接克隆到这里）
    if ! git_clone_with_retry --branch "$PKG_BRANCH" "https://github.com/${PKG_REPO}.git" "$PKG_NAME"; then
        echo -e "${RED}---> ${PKG_NAME} 安装失败！${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}---> ${PKG_NAME} 安装成功${NC}"
}

#=================================================
# 1. 克隆第三方插件
#=================================================
# Argon 主题（最受欢迎的OpenWrt主题）
UPDATE_PACKAGE "luci-theme-argon" "jerrykuku/luci-theme-argon" "master"
# Argon 主题配置插件
UPDATE_PACKAGE "luci-app-argon-config" "jerrykuku/luci-app-argon-config" "master"
# NPU 图形化管理界面（官方NPU驱动已正常工作，此为管理界面）
UPDATE_PACKAGE "luci-app-airoha-npu" "oyk470p/luci-app-airoha-npu" "main"

#=================================================
# 2. 修复NPU插件Makefile路径问题
#=================================================
echo -e "${YELLOW}---> 修复NPU插件Makefile路径${NC}"
NPU_MAKEFILE="luci-app-airoha-npu/Makefile"
if [ -f "$NPU_MAKEFILE" ]; then
    # 插件默认写的../../luci.mk，但它在package/目录下，正确使用TOPDIR绝对路径
    sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' "$NPU_MAKEFILE"
    echo -e "${GREEN}---> NPU Makefile路径修复成功${NC}"
else
    echo -e "${RED}---> NPU Makefile不存在，跳过修复${NC}"
fi

#=================================================
# 3. 补充cpufreq的reg属性（安全补丁，不修改其他内容）
# 解决U-Boot不支持SMCC调用时，NPU插件CPU频率显示N/A的问题
#=================================================
echo -e "${YELLOW}---> 检查cpufreq节点配置${NC}"
CPUFREQ_DTS="../target/linux/airoha/dts/an7581.dtsi"
if [ -f "$CPUFREQ_DTS" ]; then
    # 先检查是否已经有reg属性，有就跳过（幂等）
    if ! grep -A5 "cpufreq: cpufreq" "$CPUFREQ_DTS" | grep -q "reg ="; then
        echo -e "${YELLOW}---> cpufreq节点缺少reg属性，安全添加reg和reg-names${NC}"
        # 安全补丁：精确匹配cpufreq节点内的compatible行，在后面插入
        # 只在cpufreq节点{}范围内匹配，不会影响其他内容
        sed -i '/cpufreq: cpufreq {/,/}/{
            /compatible = "airoha,en7581-cpufreq";/a\		reg = <0x10210000 0x1000>, <0x10220000 0x1000>;\
		reg-names = "chip-scu", "mcucfg";
        }' "$CPUFREQ_DTS"
        echo -e "${GREEN}---> cpufreq reg属性添加成功${NC}"
    else
        echo -e "${GREEN}---> cpufreq节点已有reg属性，跳过补丁${NC}"
    fi
else
    echo -e "${YELLOW}---> 未找到cpufreq设备树文件，跳过补丁${NC}"
fi

#=================================================
# 4. 设置Argon为默认主题
#=================================================
echo -e "${YELLOW}---> 设置Argon为默认主题${NC}"
# 修改LuCI默认主题（../feeds/是openwrt/feeds/）
COLLECTION_MAKEFILES=$(find ../feeds/luci/collections/ -type f -name "Makefile" 2>/dev/null || true)
if [ -n "$COLLECTION_MAKEFILES" ]; then
    sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $COLLECTION_MAKEFILES
    echo -e "${GREEN}---> 默认主题设置完成${NC}"
else
    echo -e "${YELLOW}---> 未找到LuCI集合Makefile，跳过默认主题设置${NC}"
fi

#=================================================
# 5. 登录页设备名称横幅
#=================================================
echo -e "${YELLOW}---> 配置登录页设备横幅${NC}"
# ../files/是openwrt/files/，编译时会自动复制到根文件系统
ARGON_CSS_DIR="../files/www/luci-static/argon/css"
mkdir -p "$ARGON_CSS_DIR"
ARGON_CSS="$ARGON_CSS_DIR/cascade.css"
# 写入CSS，只写一次，避免重复
if ! grep -q "Login Page Title Banner" "$ARGON_CSS" 2>/dev/null; then
    cat >> "$ARGON_CSS" << 'CSS_EOF'
/* Login Page Title Banner - XG-040G-MD Custom */
.login-page .login-container::before {
    content: "ImmortalWrt for Nokia XG-040G-MD";
    display: block;
    background: linear-gradient(135deg, #1e3a5f 0%, #2c5282 100%);
    color: #ffffff;
    text-align: center;
    padding: 14px 20px;
    font-size: 15px;
    font-weight: 500;
    border-radius: 12px 12px 0 0;
    margin: -24px -24px 20px -24px;
    letter-spacing: 0.5px;
}
CSS_EOF
    echo -e "${GREEN}---> 登录页横幅配置完成${NC}"
else
    echo -e "${YELLOW}---> 登录页横幅已存在，跳过${NC}"
fi

echo -e "${BLUE}===> 所有自定义插件安装完成！${NC}"
echo -e "${GREEN}===> 硬件驱动、NPU支持官方已内置，cpufreq补丁已安全添加${NC}"