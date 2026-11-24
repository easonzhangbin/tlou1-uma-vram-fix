param(
 [ValidateSet('Diagnose','Install','Restore')][string]$Action='Diagnose',
 [Parameter(Mandatory=$true)][string]$GameDirectory
)
$ErrorActionPreference='Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
if (-not ('TlouDiagnostics.RenderMenu' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'RenderMenu.cs') }
if ($Action -eq 'Diagnose') {
 [TlouDiagnostics.RenderMenu]::Diagnose($GameDirectory)
} else {
 [TlouDiagnostics.RenderMenu]::Apply($GameDirectory,($Action -eq 'Restore'))
}
