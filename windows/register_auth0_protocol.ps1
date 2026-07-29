<#!
.SYNOPSIS
Registers Harmony Music's Windows Auth0 callback protocol for a local build.

.DESCRIPTION
The installer registers this automatically. Run this only when testing a
Flutter Windows build directly, for example after `flutter build windows`.
#>
[CmdletBinding()]
param(
  [string]$ExecutablePath = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\harmonymusic.exe')
)

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath -ErrorAction Stop).Path
$protocolKey = 'HKCU:\Software\Classes\harmonymusic'

New-Item -Path $protocolKey -Force | Out-Null
Set-Item -Path $protocolKey -Value 'URL:Harmony Music Protocol'
New-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
$commandKey = Join-Path $protocolKey 'shell\open\command'
New-Item -Path $commandKey -Force | Out-Null
Set-Item -Path $commandKey -Value ('"{0}" "%1"' -f $resolvedExecutable)

Write-Host "Registered harmonymusic:// for $resolvedExecutable"
