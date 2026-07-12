# ImmortalWrt for Nokia XG-040G-MD

基于ImmortalWrt官方master分支，为诺基亚贝尔XG-040G-MD万兆光猫定制的云编译固件。

## 特性
- ✅ 100%基于ImmortalWrt官方源码，官方完整支持设备，无需额外补丁
- ✅ 内核6.18，支持NPU硬件加速、2.5G电口、USB3.0
- ✅ 内置常用插件：网页终端、UPnP、SQM智能流控、iStore应用商店
- ✅ 内置OFA应用过滤（家长控制、上网行为管理）
- ✅ 内置AdGuard Home广告过滤
- ✅ 内置DDNSTO简单内网穿透
- ✅ 内置HomeProxy科学上网
- ✅ Argon精美主题，默认中文界面
- ✅ NPU图形化管理界面，显示CPU频率、硬件加速状态
- ✅ 内置dllkids第三方软件源，插件更新更快
- ✅ 成熟云编译方案，自动缓存、自动清理空间、自动发布固件

## 使用方法
1. 在GitHub新建仓库，将本仓库所有文件上传到仓库根目录
2. 进入仓库的Actions页面，启用Workflow
3. 手动触发"Build ImmortalWrt for XG-040G-MD"工作流
4. 等待约2-3小时编译完成，在Releases页面下载固件
5. 刷机：
   - 已在ImmortalWrt/OpenWrt系统：直接在系统升级页面刷入sysupgrade.bin，第一次刷不保留配置
   - 救砖/首次刷机：在U-Boot Web界面分别刷入factory-kernel.bin和factory-rootfs.bin

## 注意事项
- ❌ 绝对不要刷UBI版本固件，会变砖！本固件自动排除UBI版本
- 第一次刷机建议不保留配置，避免旧配置冲突
- 默认登录地址：192.168.1.1，用户名root，密码password