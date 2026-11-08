# Thin wrapper for Windows PowerShell: forwards all arguments to the Python installer.
# Example: .\scripts\install\install.ps1 --target C:\Games\MyGame --dry-run
$ErrorActionPreference = "Stop"
$py = (Get-Command py -ErrorAction SilentlyContinue)
if ($py) { & py -3 "$PSScriptRoot\install.py" @args } else { & python "$PSScriptRoot\install.py" @args }
exit $LASTEXITCODE
