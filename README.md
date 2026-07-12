# ImmortalWrt for XG-040G-MD
基于你自己实际编译成功的workflow优化，编译稳定好用的ImmortalWrt固件。

## 说明
- 源码：ImmortalWrt 官方 master 分支
- 设备：Nokia XG-040G-MD（官方原生支持，无需任何补丁）
- 默认包含：中文界面、USB/存储支持、常用工具、zram内存优化、硬件加速
- 无多余第三方插件，需要什么自己加

## 使用方法
1. 将所有文件上传到GitHub仓库根目录
2. 进入Actions页面，启用Workflows
3. 选择 "Build ImmortalWrt for XG-040G-MD"，点击 "Run workflow" 即可开始编译
4. 编译完成后在Releases页面下载sysupgrade.bin刷入

## 怎么加第三方插件？
编辑 `scripts/custom.sh`，需要什么插件就取消对应的注释就行，不用改workflow：
- Argon主题：取消主题那几行的注释
- HomeProxy/PassWall/OpenClash代理：取消对应插件的注释
- 广告过滤：取消AdGuardHome的注释
- 其他插件：照着例子加一行`UPDATE_PACKAGE "插件名" "作者/仓库" "分支"`就行

脚本会自动处理依赖冲突，非常方便。

## 可选编译选项
- SSH：编译时勾选ssh选项，可以SSH连接到编译环境调试
- Clean build：全量清理后重新编译（一般不用，缓存会加速编译）
- Verbose log：默认开启详细编译日志，出问题方便排查
