#!/bin/bash
#
# patch-cpufreq-dts.sh
# 向 an7581.dtsi 追加 cpufreq / thermal 相关节点，修复 CPU 频率显示 NA 问题
# 基于 470 作者 (oyk470p) 的实现
# 幂等设计：重复执行不会重复插入
#

set -e

# 目标 dtsi 路径（相对于 openwrt 源码根目录）
DTSI_REL="target/linux/airoha/dts/an7581.dtsi"

# 定位 openwrt 源码目录
if [ -d "openwrt" ]; then
    OPENWRT_DIR="./openwrt"
elif [ -f "$DTSI_REL" ]; then
    OPENWRT_DIR="."
else
    echo "ERROR: 无法定位 openwrt 源码目录和 an7581.dtsi"
    exit 1
fi

DTSI_FILE="${OPENWRT_DIR}/${DTSI_REL}"

if [ ! -f "$DTSI_FILE" ]; then
    echo "ERROR: 找不到文件: $DTSI_FILE"
    exit 1
fi

echo "==> 目标文件: $DTSI_FILE"

# ========== 幂等性检查 ==========
if grep -q "airoha,en7581-cpufreq" "$DTSI_FILE"; then
    echo "==> cpufreq 节点已存在，跳过补丁（幂等）"
    exit 0
fi

echo "==> 应用 cpufreq / thermal dts 补丁..."

# ========== 1. 为四个 CPU 节点追加属性 ==========
# 使用 awk 在每个 enable-method 行后插入属性
awk '
/^\t\t\tenable-method = "psci";/ {
    print
    print "\t\toperating-points-v2 = <&cpu_opp_table>;"
    print "\t\tclocks = <&cpufreq>;"
    print "\t\tclock-names = \"cpu\";"
    print "\t\tpower-domains = <&cpufreq>;"
    print "\t\tpower-domain-names = \"perf\";"
    print "\t\t#cooling-cells = <2>;"
    next
}
{ print }
' "$DTSI_FILE" > "${DTSI_FILE}.tmp" && mv "${DTSI_FILE}.tmp" "$DTSI_FILE"

echo "    -> CPU 节点属性已追加"

# ========== 2. 在 timer 节点之前插入 cpufreq + opp_table 节点 ==========
awk '
/^\ttimer \{/ {
    print ""
    print "\tcpufreq: cpufreq {"
    print "\t\treg = <0x0 0x1fa20000 0x0 0x2c0>, <0x0 0x1efbe000 0x0 0x800>;"
    print "\t\treg-names = \"chip-scu\", \"mcucfg\";"
    print "\t\tcompatible = \"airoha,en7581-cpufreq\";"
    print "\t\toperating-points-v2 = <&cpu_smcc_opp_table>;"
    print "\t\t#power-domain-cells = <0>;"
    print "\t\t#clock-cells = <0>;"
    print "\t};"
    print ""
    print "\tcpu_opp_table: opp-table {"
    print "\t\tcompatible = \"operating-points-v2\";"
    print "\t\topp-shared;"
    print ""
    print "\t\topp-500000000 {"
    print "\t\t\topp-hz = /bits/ 64 <500000000>;"
    print "\t\t\trequired-opps = <&smcc_opp0>;"
    print "\t\t};"
    print "\t\topp-550000000 {"
    print "\t\t\topp-hz = /bits/ 64 <550000000>;"
    print "\t\t\trequired-opps = <&smcc_opp1>;"
    print "\t\t};"
    print "\t\topp-600000000 {"
    print "\t\t\topp-hz = /bits/ 64 <600000000>;"
    print "\t\t\trequired-opps = <&smcc_opp2>;"
    print "\t\t};"
    print "\t\topp-650000000 {"
    print "\t\t\topp-hz = /bits/ 64 <650000000>;"
    print "\t\t\trequired-opps = <&smcc_opp3>;"
    print "\t\t};"
    print "\t\topp-700000000 {"
    print "\t\t\topp-hz = /bits/ 64 <700000000>;"
    print "\t\t\trequired-opps = <&smcc_opp4>;"
    print "\t\t};"
    print "\t\topp-750000000 {"
    print "\t\t\topp-hz = /bits/ 64 <750000000>;"
    print "\t\t\trequired-opps = <&smcc_opp5>;"
    print "\t\t};"
    print "\t\topp-800000000 {"
    print "\t\t\topp-hz = /bits/ 64 <800000000>;"
    print "\t\t\trequired-opps = <&smcc_opp6>;"
    print "\t\t};"
    print "\t\topp-850000000 {"
    print "\t\t\topp-hz = /bits/ 64 <850000000>;"
    print "\t\t\trequired-opps = <&smcc_opp7>;"
    print "\t\t};"
    print "\t\topp-900000000 {"
    print "\t\t\topp-hz = /bits/ 64 <900000000>;"
    print "\t\t\trequired-opps = <&smcc_opp8>;"
    print "\t\t};"
    print "\t\topp-950000000 {"
    print "\t\t\topp-hz = /bits/ 64 <950000000>;"
    print "\t\t\trequired-opps = <&smcc_opp9>;"
    print "\t\t};"
    print "\t\topp-1000000000 {"
    print "\t\t\topp-hz = /bits/ 64 <1000000000>;"
    print "\t\t\trequired-opps = <&smcc_opp10>;"
    print "\t\t};"
    print "\t\topp-1050000000 {"
    print "\t\t\topp-hz = /bits/ 64 <1050000000>;"
    print "\t\t\trequired-opps = <&smcc_opp11>;"
    print "\t\t};"
    print "\t\topp-1100000000 {"
    print "\t\t\topp-hz = /bits/ 64 <1100000000>;"
    print "\t\t\trequired-opps = <&smcc_opp12>;"
    print "\t\t};"
    print "\t\topp-1150000000 {"
    print "\t\t\topp-hz = /bits/ 64 <1150000000>;"
    print "\t\t\trequired-opps = <&smcc_opp13>;"
    print "\t\t};"
    print "\t\topp-1200000000 {"
    print "\t\t\topp-hz = /bits/ 64 <1200000000>;"
    print "\t\t\trequired-opps = <&smcc_opp14>;"
    print "\t\t};"
    print "\t};"
    print ""
    print "\tcpu_smcc_opp_table: opp-table-cpu-smcc {"
    print "\t\tcompatible = \"operating-points-v2\";"
    print ""
    print "\t\tsmcc_opp0: opp0 {"
    print "\t\t\topp-level = <0>;"
    print "\t\t};"
    print "\t\tsmcc_opp1: opp1 {"
    print "\t\t\topp-level = <1>;"
    print "\t\t};"
    print "\t\tsmcc_opp2: opp2 {"
    print "\t\t\topp-level = <2>;"
    print "\t\t};"
    print "\t\tsmcc_opp3: opp3 {"
    print "\t\t\topp-level = <3>;"
    print "\t\t};"
    print "\t\tsmcc_opp4: opp4 {"
    print "\t\t\topp-level = <4>;"
    print "\t\t};"
    print "\t\tsmcc_opp5: opp5 {"
    print "\t\t\topp-level = <5>;"
    print "\t\t};"
    print "\t\tsmcc_opp6: opp6 {"
    print "\t\t\topp-level = <6>;"
    print "\t\t};"
    print "\t\tsmcc_opp7: opp7 {"
    print "\t\t\topp-level = <7>;"
    print "\t\t};"
    print "\t\tsmcc_opp8: opp8 {"
    print "\t\t\topp-level = <8>;"
    print "\t\t};"
    print "\t\tsmcc_opp9: opp9 {"
    print "\t\t\topp-level = <9>;"
    print "\t\t};"
    print "\t\tsmcc_opp10: opp10 {"
    print "\t\t\topp-level = <10>;"
    print "\t\t};"
    print "\t\tsmcc_opp11: opp11 {"
    print "\t\t\topp-level = <11>;"
    print "\t\t};"
    print "\t\tsmcc_opp12: opp12 {"
    print "\t\t\topp-level = <12>;"
    print "\t\t};"
    print "\t\tsmcc_opp13: opp13 {"
    print "\t\t\topp-level = <13>;"
    print "\t\t};"
    print "\t\tsmcc_opp14: opp14 {"
    print "\t\t\topp-level = <14>;"
    print "\t\t};"
    print "\t};"
    print ""
    print
    next
}
{ print }
' "$DTSI_FILE" > "${DTSI_FILE}.tmp" && mv "${DTSI_FILE}.tmp" "$DTSI_FILE"

echo "    -> cpufreq / opp_table 节点已插入（timer 节点前）"

# ========== 3. thermal-zones 节点检查与插入 ==========
if grep -q "thermal-zones" "$DTSI_FILE"; then
    echo "    -> thermal-zones 节点已存在，跳过"
else
    echo "    -> 追加 thermal-zones 节点..."

    awk '
/^\tclk25m:/ {
    print ""
    print "\tthermal-zones {"
    print "\t\tcpu_thermal: cpu-thermal {"
    print "\t\t\tpolling-delay-passive = <0>;"
    print "\t\t\tpolling-delay = <0>;"
    print "\t\t\tthermal-sensors = <&thermal 0>;"
    print ""
    print "\t\t\ttrips {"
    print "\t\t\t\tcpu_hot: cpu-hot {"
    print "\t\t\t\t\ttemperature = <95000>;"
    print "\t\t\t\t\thysteresis = <1000>;"
    print "\t\t\t\t\ttype = \"hot\";"
    print "\t\t\t\t};"
    print "\t\t\t\tcpu-critical {"
    print "\t\t\t\t\ttemperature = <110000>;"
    print "\t\t\t\t\thysteresis = <1000>;"
    print "\t\t\t\t\ttype = \"critical\";"
    print "\t\t\t\t};"
    print "\t\t\t};"
    print ""
    print "\t\t\tcooling-maps {"
    print "\t\t\t\tmap0 {"
    print "\t\t\t\t\ttrip = <&cpu_hot>;"
    print "\t\t\t\t\tcooling-device = <&cpu0 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>,"
    print "\t\t\t\t\t\t\t <&cpu1 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>,"
    print "\t\t\t\t\t\t\t <&cpu2 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>,"
    print "\t\t\t\t\t\t\t <&cpu3 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;"
    print "\t\t\t\t};"
    print "\t\t\t};"
    print "\t\t};"
    print "\t};"
    print ""
    print
    next
}
{ print }
' "$DTSI_FILE" > "${DTSI_FILE}.tmp" && mv "${DTSI_FILE}.tmp" "$DTSI_FILE"

    echo "    -> thermal-zones 节点已插入"
fi

# ========== 4. 验证 ==========
echo ""
echo "==> 验证补丁结果："

if grep -q "airoha,en7581-cpufreq" "$DTSI_FILE"; then
    echo "    [OK] cpufreq 控制器节点存在"
else
    echo "    [FAIL] cpufreq 控制器节点缺失"
    exit 1
fi

if grep -q "cpu_opp_table:" "$DTSI_FILE"; then
    echo "    [OK] cpu_opp_table 节点存在"
else
    echo "    [FAIL] cpu_opp_table 节点缺失"
    exit 1
fi

if grep -q "cpu_smcc_opp_table:" "$DTSI_FILE"; then
    echo "    [OK] cpu_smcc_opp_table 节点存在"
else
    echo "    [FAIL] cpu_smcc_opp_table 节点缺失"
    exit 1
fi

# 检查四个 CPU 的 operating-points-v2
CPU_OP_COUNT=$(grep -c "operating-points-v2 = <&cpu_opp_table>" "$DTSI_FILE")
if [ "$CPU_OP_COUNT" -ge 4 ]; then
    echo "    [OK] 4个CPU节点均已配置 operating-points-v2 ($CPU_OP_COUNT 处)"
else
    echo "    [FAIL] CPU operating-points-v2 配置不足，实际: $CPU_OP_COUNT"
    exit 1
fi

# 检查 cooling-cells
COOL_COUNT=$(grep -c "#cooling-cells = <2>" "$DTSI_FILE")
if [ "$COOL_COUNT" -ge 4 ]; then
    echo "    [OK] 4个CPU节点均已配置 #cooling-cells ($COOL_COUNT 处)"
else
    echo "    [FAIL] CPU #cooling-cells 配置不足，实际: $COOL_COUNT"
    exit 1
fi

echo ""
echo "==> cpufreq / thermal dts 补丁应用成功！"
exit 0
