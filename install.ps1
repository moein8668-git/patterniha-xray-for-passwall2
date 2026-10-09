# Push pattx.sh from Windows to the router and run it.
# Usage: .\install.ps1 [-Router 192.168.1.1] [-Action install] [-Arg v26.10.9]
# Special thanks to patterniha, creator of the core.
param([string]$Router = "192.168.1.1", [string]$Action = "install", [string]$Arg = "")
$ErrorActionPreference = "Stop"
$src = (Get-Content "$PSScriptRoot\pattx.sh" -Raw) -replace "`r`n", "`n"
[IO.File]::WriteAllText("$env:TEMP\pattx.sh", $src, (New-Object Text.UTF8Encoding $false))
scp -O -o StrictHostKeyChecking=no "$env:TEMP\pattx.sh" root@${Router}:/tmp/pattx.sh
ssh root@$Router "sh /tmp/pattx.sh $Action $Arg"
