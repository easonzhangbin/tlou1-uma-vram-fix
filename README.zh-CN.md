# 最后生还者 Part I：UMA 显存与纹理预算修正

非官方开源补丁，适用于经过精确哈希核验的《The Last of Us Part I／最后生还者 Part I》PC 构建。面向具有较大预分配显存的 UMA 核显，包含自动硬件检测、原文件校验、备份及还原。MIT 许可证仅覆盖本项目源码和文档。

## 修正内容与限制

- **容量读取**：修正 UMA 回退路径使用共享内存一半、忽略更大预分配显存的情况。本机 Radeon 8060S 游戏菜单从 4,005 MiB 变为 16,206 MiB。
- **纹理预算**：绕过 APU 分支固定的 1648 MiB 预算，使用游戏原有的质量及流送预算计算。在已检查的质量参数下为 4608 MiB，并非把所有显存分配给纹理。
- **可选诊断**：独立提供完整 Rendering 开发菜单解锁，不默认安装，不宣称具有已验证的帧率收益。

这不是适用于所有版本、所有核显的通用强制补丁。支持菜单版本 1.1.5.0、EXE 资源版本 1.1.4.0 的已核验文件；最终以 [README 中的 SHA-256](README.md#supported-images) 为准。未知版本、混合文件或无法核验的硬件一律拒绝修改。

安装要求：Windows x64、64 位 PowerShell 5.1 或 7；D3D12 确认 UMA，预分配显存至少 8 GiB，显著大于共享内存一半，并通过当前 DXGI 预算检查。多显卡电脑必须显式选择显卡。除上述 8060S 外，其他符合条件的硬件尚未完成实机游戏测试。

## 下载与使用

在仓库首页选择 **Code → Download ZIP**，解压全部文件，先退出游戏。

1. 运行 `Diagnose.cmd` 查看文件与硬件是否受支持。
2. 运行 `Install.cmd` 安装容量和纹理预算两项修正。
3. 需要撤回时退出游戏，运行 `Restore.cmd`。

若游戏位于 Program Files 且提示拒绝访问，可右键以管理员身份运行。脚本不会自动提权，不访问网络。Steam 自动发现失败时，在 PowerShell 显式指定路径：

```powershell
.\Patch.ps1 -Action Diagnose -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
.\Patch.ps1 -Action Install -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I' -AdapterIndex 0
.\Patch.ps1 -Action Restore -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
```

两个 EXE 在修改期间保持独占锁，原文件备份到游戏目录下 `tlou-vram-backups`，修改前后均验证完整哈希。捕获到写入错误时尝试回滚；断电或进程被强制终止可能中断回滚，应保留备份。游戏更新后不要覆盖旧文件，重新 Diagnose；未知新版应等待重新核验。

如果安装过 [完整渲染菜单诊断模块](optional/README.md)，必须先运行该模块的 Restore，再使用主补丁。它的 Restore 保留 v2 显存修正，主补丁 Restore 才恢复原始 EXE。

## 检查结果与反馈

本项目不降低分辨率、纹理、阴影、反射或光照设置，不修改驱动、BIOS、页面文件或存档。v2 的预算计算已做隔离验证，尚未通过可重复场景测试证明帧率或贴图延迟改善，也没有覆盖长期游戏稳定性。显存显示正常后仍可能受解压、内存带宽或磁盘 I/O 影响；不能保证消除全部流送延迟。

开发菜单中已观察到资源别名、资源缓存、描述符缓存和多线程资源分配开启。调度校验等候选尚无完整调用路径和 A/B 测试，保持原值；没有禁用资源同步或强行增加异步队列。

提交 Issue 时提供 GPU 型号、游戏版本、EXE SHA-256 和去除个人路径的 Diagnose 输出即可。请勿上传游戏 EXE、存档、私人完整日志或跟踪文件。本仓库只分发补丁源码，不包含修改器或游戏程序。详细原理参见 [AUDIT.md](AUDIT.md)。
