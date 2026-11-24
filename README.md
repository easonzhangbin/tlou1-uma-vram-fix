# TLOU Part I UMA VRAM Fix — v2.0.0

Unofficial, source-only Windows patcher for **The Last of Us Part I**. 自动检测 UMA 硬件，修复显存容量读取及独立纹理预算，支持校验、备份、v1 升级和还原。

[中文说明](README.zh-CN.md) · [Optional rendering-menu diagnostics](optional/README.md)

This repository distributes no game executables, saves, drivers or credentials. The separate personal replacement archive contains locally owned game files and must not be uploaded here.

## What v2 fixes

1. **Capacity:** the original UMA fallback uses SharedSystemMemory / 2 despite a larger dedicated carve-out. v1 redirects it to DedicatedVideoMemory. An 8060S game menu verified the change from 4,005 to 16,206 MiB.
2. **Texture budget:** another APU branch fixes the main texture budget at **1648 MiB**, skipping normal quality/streaming adjustments. v2 redirects eligible hardware through the game's original normal calculation: **4608 MiB** for texture qualities=3 and streaming=2.

The texture helper is shared by real texture swaps, cache-pressure checks, frame-end resource updates and the menu estimate. v2 changes their common helper, keeping the budget consistent. It retains normal quality adjustments, normal cap/alignment and debug overrides. It does not allocate all VRAM to textures, globally change GPU identity, or modify drivers, BIOS, pagefile, settings or caches.

## Usage / 使用方法

Windows 10/11 x64; **64-bit Windows PowerShell 5.1 or PowerShell 7**. Extract all files; close the game before Install/Restore.

- `Diagnose.cmd`: read-only diagnosis (default).
- `Install.cmd`: install both fixes, including upgrading a supported v1 installation.
- `Restore.cmd`: restore exact known-original game images, reversing both fixes.

If Program Files access is denied, run the CMD as administrator. No automatic elevation or network access occurs.

```powershell
.\Patch.ps1 -Action Diagnose
.\Patch.ps1 -Action Install
.\Patch.ps1 -Action Restore
# Explicit location when Steam discovery cannot identify exactly one game:
.\Patch.ps1 -Action Diagnose -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I'
# Multi-GPU: confirm the GPU selected in the game, then specify its reported index:
.\Patch.ps1 -Action Install -GameDirectory 'D:\SteamLibrary\steamapps\common\The Last of Us Part I' -AdapterIndex 0
```

Discovery checks Steam registry/libraries and skips unreadable registry entries. Use a fresh PowerShell session when upgrading a previously loaded patcher.

## Installation guards

- DirectX 12 ARCHITECTURE1 must positively identify UMA. Unknown/failed checks are rejected.
- At least **8 GiB dedicated UMA carve-out**, exceeding shared-memory/2 by at least 64 MiB. This conservative guard does not guarantee every qualifying machine can run Ultra smoothly.
- A successful DXGI local-budget query at least as large as the carve-out. This is a per-process snapshot, not a guarantee of the game's future budget.
- Multiple physical GPUs require explicit selection; the tool does not guess the game's adapter.
- Both EXEs must have allowlisted original, capacity-only v1 or v2 full SHA-256 hashes and exact patch-site bytes. **Unknown builds are refused; no force/fuzzy mode.**

Hardware classification is generic; game-build support is deliberately restricted. Only the 8060S configuration above has been verified in a game menu for v1. v2's calculations are tested in isolation, not by a repeatable in-game scene or long gameplay run. Other qualifying UMA GPUs are not gameplay-tested.

Eligibility is checked at installation, not every game launch. Re-diagnose after changing UMA allocation, GPU, driver or computer. Restore before moving to a nonqualifying configuration. An existing patch is not silently removed when eligibility changes: use Restore.

## Supported images

Observed Steam menu version **1.1.5.0**, EXE version resources **1.1.4.0**. Trust hashes, not labels.

| Image/state | SHA-256 |
|---|---|
| tlou-i.exe original | `088d37aff3b8e3f65715e7e325547c07e6c4d794966c0573cd0f7af5c6c3503a` |
| tlou-i.exe v1 | `245b1f569533ed709f42a9e4c82e4b1755bdb3d732fa53114617a0e1fcb39824` |
| tlou-i.exe v2 | `1d65b6c8319d2c713f18fe605e1cd30ffd539f07d1bcb071ccbcb72adc665bc7` |
| tlou-i-l.exe original | `3c9284ff5beddebbdec2d127ffb42ad3c488c8eea38c9a29718c32a09cdfbea3` |
| tlou-i-l.exe v1 | `405c145b1910ffabbac22ab5348dcc4656131c52d3f9dcad6793b221de98784d` |
| tlou-i-l.exe v2 | `c6fa70397e10700754d987aae008eb1b0e75fb946d7913886eb75ee892cd111d` |

| Site | tlou-i.exe offset | tlou-i-l.exe offset | Original → fixed |
|---|---|---|---|
| Capacity | `0x206c270` | `0x20679e0` | `488b431848d1e8` → `488b4310909090` |
| Texture branch | `0x10dcb33` | `0x10ddfc3` | `740a` → `eb0a` |

The texture change turns the short conditional jump into an unconditional jump to the existing normal calculation. Hash checks prevent applying these offsets to unknown images.

## Backup and recovery

Both EXEs stay exclusively locked during validation, verified full local backup, both-site writes and full-image output verification. Backups are under `tlou-vram-backups/<timestamp>-<id>/`. Caught failures trigger rollback of both files while locks remain held. Power loss/process termination can interrupt rollback; preserve backups.

Restore reconstructs byte-exact supported originals from v1/v2 and verifies their hashes. Unknown/newer files are never overwritten. Old v1-only restore scripts do not recognize v2: use **v2 Restore.cmd**. Steam updates/Verify integrity may overwrite the patch; never restore an older program over an updated game.

## Tests and review

```powershell
.\tests\Test.ps1
# Optional integration tests using your own known-original programs:
.\tests\Test.ps1 -OriginalGameFiles 'D:\MyPrivateBackup'
```

Integration tests use unique temporary copies and leave supplied originals untouched. They cover original→v2, v1→v2, repeat-install no-op, exact restoration, both sites, file locking and unknown/mixed versions. No game binaries are included in CI. Temporary copies remain at the printed path.

[AUDIT.md](AUDIT.md) records the call-chain review, isolated budget calculations and settings intentionally left unchanged. Short random loading delays can still involve decompression, bandwidth, system RAM or resource I/O; v2 targets the confirmed restrictive branch, not every possible bottleneck.

## Optional rendering-menu diagnostics

The separate [rendering-menu module](optional/README.md) exposes additional developer rendering menus on the exact audited **v2 tlou-i.exe** only. It is experimental and is **not installed by Install.cmd**. It provides inspection access, not a verified FPS improvement. Existing resource aliasing, caches and multithreaded allocations were already enabled on the inspected machine; no speculative rendering/synchronization changes are included.

**Restore the optional module first** before using the main patcher's Diagnose/Install/Restore, because the main patcher deliberately rejects its modified hash. Optional Restore returns to v2; main Restore then returns to the original game.

For another build, submit versions, SHA-256, GPU model and redacted Diagnose output. Do not attach game programs, saves or private full logs. New hashes/offsets need independent code/field verification and testing; do not remove guards.

References: [DXGI memory fields](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ns-dxgi-dxgi_adapter_desc1), [D3D12 UMA detection](https://learn.microsoft.com/en-us/windows/win32/api/d3d12/ns-d3d12-d3d12_feature_data_architecture1).

## License

MIT applies to patcher source/documentation only. Game files belong to their respective owners. No affiliation with Naughty Dog, Sony, Iron Galaxy or AMD is claimed.
