$logPath = "$env:FACTORY_PROJECT_DIR\.factory\logs\failure.log"
Add-Content -Path $logPath -Value "$(Get-Date): $(Get-Content -Raw $args[0] | ConvertFrom-Json | ConvertTo-Json -Compress)"
pwsh.exe -File "$env:FACTORY_PROJECT_DIR\.factory\hooks\lesson-extractor.ps1"
Write-Host "Failure logged"
