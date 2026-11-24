# v2 review — 2026-11-12

Scope: the two allowlisted Steam programs, their shared texture-budget helper, direct callers of Display::IsCurrentAdapterAPU and the inspected saved settings. This is not an audit of every engine subsystem.

## Confirmed code and callers

Preferred-image-base addresses for tlou-i.exe:

- `Display::IsCurrentAdapterAPU`: `0x141f2d594`. The inspected Radeon 8060S log has Dedicated GPU = 0, selecting APU behavior.
- Budget helper: `0x1410dd690`. With debug Pseudo-VRAM disabled, `0x1410dd733` reaches normal calculations only for non-APU. Otherwise ECX becomes `0x670` (1648 MiB), then converts to bytes and aligns to 16 MiB.
- Quality fields `+0x1d0`, `+0x1d4`, `+0x1d8`, `+0x1dc` map to foreground, character, environment and FX texture settings; `+0x1e0` maps to TextureStreaming. The APU fixed-value branch skips their budget adjustments.
- `0x141ec152e` calls the helper. `0x141ec1541` passes output[0] to `TextureMgrPub::PerformTextureSwaps` (`0x14043aac0`, confirmed by embedded function/source strings).
- PerformTextureSwaps stores the budget at texture-manager `+0x84238` and a global budget slot.
- Frame-end resource update calls the helper at `0x1411ca754`.
- Texture-cache pressure code calls it at `0x14043ddf6`, comparing the budget with texture counters and a 10 MiB margin.
- Menu usage estimation calls it at `0x1420a4e9b`.

This value feeds real texture work, not just a menu. v1 left the helper unchanged. v2 changes only `74 0a` to `eb 0a`; it keeps normal quality/streaming calculation and cap/alignment. The earlier debug Pseudo-VRAM override branch remains untouched. The installer skips low-carve-out hardware.

The helper has 1339 bytes at file offsets `0x10dca90` and `0x10ddf20`. Only one texture-helper byte changes; the jump displacement stays identical.

## Independent execution

Copies of each helper were executed outside the game. RIP-relative float constants were relocated. The normal debug-disabled branch was selected, avoiding external game calls. Tests covered APU on/off × 4 texture quality values × 3 streaming values: 24 original and 24 v2 cases per executable, **96 total**. In every v2 case, APU output matched the corresponding original normal-path calculation.

All four texture qualities=3:

| Streaming value | Original APU MiB | v2 APU / original non-APU MiB |
|---|---:|---:|
| 0 | 1648 | 3344 |
| 1 | 1648 | 4608 |
| 2 | 1648 | 4608 |

Value 1 tests supplied a 4096 MiB baseline to the normal override field. Values 0 and 2 use their own normal-path base, so are independent of that supplied baseline. The inspected machine has qualities=3 and streaming=2. These are calculated targets, not measured GPU residency.

Patcher integration tests pass **30 assertions on Windows PowerShell 5.1 and 30 on PowerShell 7**, including v1 migration and exact restoration. Hardware diagnosis succeeds on the 8060S machine. No repeatable in-game scene comparison or long gameplay stability test has been performed for v2.

## Other settings reviewed

| Item | Finding/action |
|---|---|
| Total VRAM fallback | Retain v1 fix; v2 restore reverses both sites. |
| Swaps, frame-end updates, pressure checks, menu estimate | Share the patched helper; no separate edits needed in those callers. |
| Pseudo-VRAM debug settings | Default constructor disables override; preserve controls. |
| TextureStreaming=2 | Maximum exposed enumeration; v2 restores its normal budget path. No configuration change. |
| Texture qualities=3 | Valid highest-quality choices; preserve preferences. |
| Other direct APU-check callers | Render-option UI conditions and resource-layout choices; no matching demonstrated budget defect. Preserve them. |
| ScalingMode=0, RenderScale=1 | Valid native rendering settings, not a texture-budget error. |
| UncappedFramerate=1 | Valid preference, possible added rendering pressure. No automatic cap without a measured comparison. |
| RAM/UMA allocation | 32 GiB installed, about 16 GiB carved out, about 15.65 GiB visible to Windows. System-memory pressure remains a separate possibility. No BIOS/pagefile edit. |
| Shaders | User confirms complete. Preserve cache and completed work. |
| Game assets/SSD | Not all assets were hashed, and no problem-scene disk measurement was captured. No corruption claim. |

The restriction's deterministic behavior is confirmed. Its exact contribution to a specific random delay is not established without gameplay comparison. Extra budget can reduce eviction pressure but cannot increase storage, decompression or memory-bandwidth performance.
