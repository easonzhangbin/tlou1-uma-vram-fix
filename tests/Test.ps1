param([string]$OriginalGameFiles)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\src\Native.cs')
$script:checks = 0
function Assert($condition,[string]$message) { if (-not $condition) { throw $message }; $script:checks++ }
function Reject([scriptblock]$operation) { $caught=$false; try { & $operation | Out-Null } catch { $caught=$true }; Assert $caught 'Expected rejection' }
function Adapter([bool]$uma,[uint64]$dedicated,[uint64]$shared,[uint64]$budget) {
 $a=New-Object TlouVram.Adapter; $a.ArchitectureKnown=$true; $a.Uma=$uma; $a.Dedicated=$dedicated; $a.Shared=$shared; $a.LocalBudget=$budget; return $a
}
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 16GB 8GB 23GB)) -eq 'ELIGIBLE') 'High-carve-out UMA should be eligible'
Assert ([TlouVram.Fix]::Eligibility((Adapter $false 16GB 8GB 23GB)) -ne 'ELIGIBLE') 'Discrete GPU must be skipped'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 512MB 16GB 16GB)) -ne 'ELIGIBLE') 'Low-carve-out UMA must retain original fallback'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 4GB 8GB 8GB)) -ne 'ELIGIBLE') 'No-benefit patch must be skipped'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 6GB 4GB 12GB)) -ne 'ELIGIBLE') 'V2 must reject less than 8 GiB dedicated memory'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 8GB 8GB 12GB)) -eq 'ELIGIBLE') '8 GiB threshold failed'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 16GB 8GB 0)) -ne 'ELIGIBLE') 'Unknown budget must be skipped'
Assert ([TlouVram.Fix]::Eligibility((Adapter $true 16GB 8GB 8GB)) -ne 'ELIGIBLE') 'Insufficient OS budget must be skipped'
$unknown=Adapter $true 16GB 8GB 23GB; $unknown.ArchitectureKnown=$false
Assert ([TlouVram.Fix]::Eligibility($unknown) -ne 'ELIGIBLE') 'Unknown architecture must be skipped'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('tlou-vram-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { [IO.File]::WriteAllBytes((Join-Path $testRoot $name),[byte[]](0x4d,0x5a,0,0)) }
$before=[TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot 'tlou-i.exe')))
Reject { [TlouVram.Fix]::Apply($testRoot,$false) }
Assert ([TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot 'tlou-i.exe'))) -eq $before) 'Unknown files changed'
Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'tlou-vram-backups'))) 'Rejected operation created backup'
Reject { [TlouVram.Fix]::Inspect('other.exe',[byte[]](0),$false) }
if ($OriginalGameFiles) {
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { Copy-Item -LiteralPath (Join-Path $OriginalGameFiles $name) -Destination (Join-Path $testRoot $name) -Force }
 $original=@{}; foreach($name in @('tlou-i.exe','tlou-i-l.exe')) { $original[$name]=[TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot $name))) }
 $locked=New-Object IO.FileStream((Join-Path $testRoot 'tlou-i-l.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try { Reject { [TlouVram.Fix]::Apply($testRoot,$false) } } finally { $locked.Dispose() }
 Assert ([TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot 'tlou-i.exe'))) -eq $original['tlou-i.exe']) 'Lock failure changed first file'
 [TlouVram.Fix]::Apply($testRoot,$false) | Write-Output
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { $p=[TlouVram.Fix]::Inspect($name,[IO.File]::ReadAllBytes((Join-Path $testRoot $name)),$false); Assert ($p.State -eq 'PatchedV2') 'Installation failed'; Assert ($p.Sites.Length -eq 2) 'Expected two verified patch sites' }
 Assert ([TlouVram.Fix]::Apply($testRoot,$false) -like 'Already*') 'Repeated installation was not a no-op'
 [TlouVram.Fix]::Apply($testRoot,$true) | Write-Output
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { Assert ([TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot $name))) -eq $original[$name]) 'Restoration not byte-for-byte identical' }
 # Upgrade a capacity-only v1 installation, then restore exact originals.
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) {
  $path=Join-Path $testRoot $name; $data=[IO.File]::ReadAllBytes($path); $plan=[TlouVram.Fix]::Inspect($name,$data,$false)
  [Array]::Copy($plan.Sites[0].Bytes,0,$data,$plan.Sites[0].Offset,$plan.Sites[0].Bytes.Length); [IO.File]::WriteAllBytes($path,$data)
  Assert ([TlouVram.Fix]::Inspect($name,$data,$false).State -eq 'CapacityOnlyV1') 'V1 recognition failed'
 }
 [TlouVram.Fix]::Apply($testRoot,$false) | Write-Output
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { Assert ([TlouVram.Fix]::Inspect($name,[IO.File]::ReadAllBytes((Join-Path $testRoot $name)),$false).State -eq 'PatchedV2') 'V1 upgrade failed' }
 [TlouVram.Fix]::Apply($testRoot,$true) | Write-Output
 foreach ($name in @('tlou-i.exe','tlou-i-l.exe')) { Assert ([TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot $name))) -eq $original[$name]) 'V1 upgrade restore failed' }
 # A newer/tampered second image must prevent ANY modification of the first.
 $second=Join-Path $testRoot 'tlou-i-l.exe'; $data=[IO.File]::ReadAllBytes($second); $data[1024]=$data[1024] -bxor 1; [IO.File]::WriteAllBytes($second,$data)
 Reject { [TlouVram.Fix]::Apply($testRoot,$false) }
 Assert ([TlouVram.Fix]::Hash([IO.File]::ReadAllBytes((Join-Path $testRoot 'tlou-i.exe'))) -eq $original['tlou-i.exe']) 'Mixed-version rejection was not atomic'
}
Write-Output "PASS: $script:checks checks. Temporary test copies retained at $testRoot"
