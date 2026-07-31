<#!
.SYNOPSIS
Registers Harmony Music Dev's Windows Auth0 callback protocol.

.DESCRIPTION
The Release installer owns harmonymusic://. This helper registers the separate
harmonymusic-dev:// callback used by a local Flutter Debug build.
#>
[CmdletBinding()]
param(
  [string]$ExecutablePath = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Debug\harmonymusic.exe')
)

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath -ErrorAction Stop).Path
$protocolKey = 'HKCU:\Software\Classes\harmonymusic-dev'

New-Item -Path $protocolKey -Force | Out-Null
Set-Item -Path $protocolKey -Value 'URL:Harmony Music Dev Protocol'
New-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
$commandKey = Join-Path $protocolKey 'shell\open\command'
New-Item -Path $commandKey -Force | Out-Null
Set-Item -Path $commandKey -Value ('"{0}" "%1"' -f $resolvedExecutable)

Write-Host "Registered harmonymusic-dev:// for $resolvedExecutable"
