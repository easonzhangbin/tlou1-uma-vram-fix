# Optional rendering-menu diagnostics / 可选完整渲染菜单

Experimental inspection module, separate from the v2 VRAM fix. **No demonstrated FPS benefit.** Only the exact v2 `tlou-i.exe` below is supported; `tlou-i-l.exe` is not modified. Install the main hardware-guarded v2 patch first. The main patcher deliberately rejects a menu-unlocked image: restore this module before using the main patcher's Diagnose/Install/Restore.

## Use

Close the game. Use 64-bit Windows PowerShell 5.1 or PowerShell 7, with write permission to the game directory:

```powershell
.\optional\RenderMenu.ps1 -Action Diagnose -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
.\optional\RenderMenu.ps1 -Action Install -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
.\optional\RenderMenu.ps1 -Action Restore -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
```

Default action is read-only Diagnose. Install/Restore hold an exclusive lock, verify all input/output SHA-256 hashes and six sites, and save a verified full backup under `tlou-render-menu-backups`. Caught write failures attempt rollback while the lock remains held; power loss or forced termination can interrupt recovery. Unknown, updated and partially modified images are refused. Restore returns to **v2**, not to the original unpatched game. Main Restore can then restore the original.

This exposes Rendering entries after an existing developer-menu entry point is enabled. It does not independently enable developer mode or provide a hotkey/injector. No third-party trainer is bundled or downloaded. In the inspected session, Up/Down, Enter and Backspace navigated menus; mouse selection was unreliable. Restart the game after installation.

中文：本模块仅用于检查，默认不随主补丁安装。先安装主补丁，再关闭游戏安装本模块。它只扩展已有开发菜单中的 Rendering 项，仍需自行启用开发菜单入口。还原时先撤回本模块，再使用主补丁还原；未测试的调试选项可能改变画面或导致崩溃，不应当作一键优化。

## Exact images and changes

| State | SHA-256 |
|---|---|
| Base v2 | `1d65b6c8319d2c713f18fe605e1cd30ffd539f07d1bcb071ccbcb72adc665bc7` |
| Rendering menu unlocked | `f1c474f05ef998b122968b68a540704c0a513bab284cbfad3ad859af95a73942` |

Two local branches in CreateRenderingMenu hide the full menu. Bypassing those alone caused a menu allocation assertion: allocator 0x10 existed without initialized backing storage. The module initializes a **4 MiB CPU Debug DMENU pool** through an existing CPU category and balances the two categories' unaccounted entries. Category totals stay unchanged. It does not remove a global developer-capability check, activate all development resources, or reduce texture/PSO/GPU heap budgets.

| File offset | Base bytes | Unlocked bytes |
|---|---|---|
| `0x5d5b5b` | `0f84e8010000` | `909090909090` |
| `0x5d5dab` | `0f84040b0000` | `909090909090` |
| `0x2c55d74` | `0a000000` | `05000000` |
| `0x2c55d78` | `0000000300000000` | `0000400000000000` |
| `0x2c556b8` | `0050830000000000` | `0050430000000000` |
| `0x2c55ef8` | `0010d21800000000` | `0010d21b00000000` |

Game boot, save loading, the full Rendering menu and Render Graph navigation were checked on one Radeon 8060S machine. Not all menu actions, large debug workloads or long gameplay were tested; 4 MiB is not a guarantee for every developer feature.

## Findings, not optimization presets

The inspected Render Graph used async-grouped scheduling, zero ordinary compute queues and one high-priority compute queue; zero ordinary queues alone does not establish that async compute is disabled. Resource aliasing, aliased-resource caching, multithreaded allocations, descriptor caching and resource-table caching were enabled. Forced exclusive passes, randomized scheduling and releasing all resources each frame were disabled. These observations are machine/session-specific.

Validate Schedule was enabled and described as checking validity each frame, but its full execution path and cost were not traced or A/B tested. Merge Downsample Depth plus Upscale Info had a UI binding without a confirmed effective consumer in this PC build. Both remain unchanged. Run SSAO On Compute explicitly mentioned disabling normals, so it was excluded from changes intended to preserve quality. No synchronization protection, queue count, driver option or quality setting is changed.

## Tests

```powershell
.\tests\RenderMenu.Tests.ps1
# Optional integration input: your own exact base-v2 image, never upload it.
.\tests\RenderMenu.Tests.ps1 -BaseV2File 'D:\PrivateBackup\tlou-i.exe'
```

Tests work on temporary copies, checking unknown/partial-image rejection, locking, backup integrity, exact unlocked output, idempotence and byte-exact restoration. CI has no game binaries and runs source-only rejection tests. Integration sources are left untouched.
