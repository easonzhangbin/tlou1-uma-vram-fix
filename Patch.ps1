[CmdletBinding()]
param(
 [ValidateSet('Diagnose','Install','Restore')][string]$Action = 'Diagnose',
 [string]$GameDirectory,
 [int]$AdapterIndex = -1
)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell or PowerShell 7.' }
if (-not ('TlouVram.Fix' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'src\Native.cs') }
if ([TlouVram.Fix]::Version -ne '2.0.0') { throw 'An older patcher is loaded in this PowerShell session. Open a fresh 64-bit PowerShell window.' }
Write-Output 'TLOU UMA VRAM Fix 2.0.0: capacity + texture-budget correction'
if (-not $GameDirectory) {
 $candidates = @($PSScriptRoot, (Get-Location).Path)
 $steamRoots = @("${env:ProgramFiles(x86)}\Steam")
 foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
  try { if (Test-Path -LiteralPath $key) { $s = Get-ItemProperty -LiteralPath $key -ErrorAction Stop; if ($s.SteamPath) { $steamRoots += $s.SteamPath }; if ($s.InstallPath) { $steamRoots += $s.InstallPath } } } catch { Write-Verbose "Skipping unreadable Steam registry location: $key" }
 }
 foreach ($steam in @($steamRoots | Select-Object -Unique)) {
  $candidates += Join-Path $steam 'steamapps\common\The Last of Us Part I'
  $libraries = Join-Path $steam 'steamapps\libraryfolders.vdf'
  if (Test-Path -LiteralPath $libraries) {
   foreach ($m in [regex]::Matches((Get-Content -LiteralPath $libraries -Raw), '"path"\s*"([^"]+)"')) { $candidates += Join-Path ($m.Groups[1].Value.Replace('\\','\')) 'steamapps\common\The Last of Us Part I' }
  }
 }
 $found = @($candidates | Where-Object { (Test-Path -LiteralPath (Join-Path $_ 'tlou-i.exe')) -and (Test-Path -LiteralPath (Join-Path $_ 'tlou-i-l.exe')) } | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique)
 if ($found.Count -ne 1) { throw 'Cannot uniquely find game. Specify -GameDirectory with the installation folder.' }
 $GameDirectory = $found[0]
}
$GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
Write-Output "Game: $GameDirectory"
# Validate BOTH binaries before hardware eligibility or any write.
foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) {
 $plan = [TlouVram.Fix]::Inspect($name, [IO.File]::ReadAllBytes((Join-Path $GameDirectory $name)), ($Action -eq 'Restore'))
 Write-Output "$name : $($plan.State); SHA256 $($plan.BeforeHash)"
}
if ($Action -eq 'Restore') { Write-Output ([TlouVram.Fix]::Apply($GameDirectory,$true)); return }
$adapters = @([TlouVram.Hardware]::Probe())
foreach ($gpu in $adapters) {
 Write-Output ('GPU {0}: {1}; UMA={2}; dedicated={3:N2} MiB; shared/2={4:N2} MiB; OS budget={5:N2} MiB; {6}' -f $gpu.Index,$gpu.Name,$gpu.Uma,($gpu.Dedicated/1MB),($gpu.Shared/2/1MB),($gpu.LocalBudget/1MB),[TlouVram.Fix]::Eligibility($gpu))
}
if ($Action -eq 'Diagnose') { Write-Output 'Read-only diagnosis complete. No files changed.'; return }
if ($AdapterIndex -ge 0) { $selected = @($adapters | Where-Object Index -eq $AdapterIndex) } else {
 # Do not guess the active adapter on multi-GPU systems.
 if ($adapters.Count -ne 1) { throw 'Multiple/no GPUs detected. Select the GPU used by the game with -AdapterIndex; check the game display menu first.' }
 $selected = @($adapters[0])
}
if ($selected.Count -ne 1) { throw 'Adapter selection is not unique.' }
$eligibility = [TlouVram.Fix]::Eligibility($selected[0])
if ($eligibility -ne 'ELIGIBLE') { throw $eligibility }
Write-Output ([TlouVram.Fix]::Apply($GameDirectory,$false))
