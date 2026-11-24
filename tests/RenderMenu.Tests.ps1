param([string]$BaseV2File)
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\optional\RenderMenu.cs')
$script:checks=0
function Assert($condition,[string]$message) { if (-not $condition) { throw $message }; $script:checks++ }
function Reject([scriptblock]$operation) { $caught=$false; try { & $operation | Out-Null } catch { $caught=$true }; Assert $caught 'Expected rejection' }
$root=Join-Path ([IO.Path]::GetTempPath()) ('tlou-menu-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$target=Join-Path $root 'tlou-i.exe'
[IO.File]::WriteAllBytes($target,[byte[]](0x4d,0x5a,0,0))
$unknown=[IO.File]::ReadAllBytes($target)
Reject { [TlouDiagnostics.RenderMenu]::Apply($root,$false) }
Reject { [TlouDiagnostics.RenderMenu]::Apply($root,$true) }
Assert ([TlouDiagnostics.RenderMenu]::Hash([IO.File]::ReadAllBytes($target)) -eq [TlouDiagnostics.RenderMenu]::Hash($unknown)) 'Rejected input changed'
Assert (-not (Test-Path -LiteralPath (Join-Path $root 'tlou-render-menu-backups'))) 'Rejected input created backup'
if ($BaseV2File) {
 $sourceHash=(Get-FileHash -LiteralPath $BaseV2File -Algorithm SHA256).Hash.ToLowerInvariant()
 Assert ($sourceHash -eq [TlouDiagnostics.RenderMenu]::BaseHash) 'Integration input must be the exact base v2 image'
 Copy-Item -LiteralPath $BaseV2File -Destination $target -Force
 $locked=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try { Reject { [TlouDiagnostics.RenderMenu]::Apply($root,$false) } } finally { $locked.Dispose() }
 Assert ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $sourceHash) 'Lock failure changed input'
 Assert (-not (Test-Path -LiteralPath (Join-Path $root 'tlou-render-menu-backups'))) 'Lock failure created backup'
 Assert ([TlouDiagnostics.RenderMenu]::Diagnose($root) -eq 'BaseV2') 'Base diagnosis failed'
 [TlouDiagnostics.RenderMenu]::Apply($root,$false) | Write-Output
 Assert ([TlouDiagnostics.RenderMenu]::Diagnose($root) -eq 'RenderMenuUnlocked') 'Unlock diagnosis failed'
 Assert ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq [TlouDiagnostics.RenderMenu]::UnlockedHash) 'Unlocked hash differs from the gameplay-checked image'
 $backups=@(Get-ChildItem -LiteralPath (Join-Path $root 'tlou-render-menu-backups') -Directory)
 Assert ($backups.Count -eq 1) 'Expected one backup'
 Assert ((Get-FileHash -LiteralPath (Join-Path $backups[0].FullName 'tlou-i.exe')).Hash.ToLowerInvariant() -eq $sourceHash) 'Backup is not byte-exact'
 Assert ([TlouDiagnostics.RenderMenu]::Apply($root,$false) -like 'Already*') 'Repeat install changed file'
 [TlouDiagnostics.RenderMenu]::Apply($root,$true) | Write-Output
 Assert ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -eq $sourceHash) 'Restore is not byte-exact'
 Assert ([TlouDiagnostics.RenderMenu]::Apply($root,$true) -like 'Already*') 'Repeat restore changed file'
 $data=[IO.File]::ReadAllBytes($target); $data[0x5d5b5b]=0x90; [IO.File]::WriteAllBytes($target,$data)
 $tampered=(Get-FileHash -LiteralPath $target).Hash
 Reject { [TlouDiagnostics.RenderMenu]::Apply($root,$false) }
 Reject { [TlouDiagnostics.RenderMenu]::Apply($root,$true) }
 Assert ((Get-FileHash -LiteralPath $target).Hash -eq $tampered) 'Partial patch rejection changed input'
 Assert ((Get-FileHash -LiteralPath $BaseV2File).Hash.ToLowerInvariant() -eq $sourceHash) 'Private integration source changed'
}
Write-Output "PASS: $script:checks rendering-menu checks. Temporary copies retained at $root"
