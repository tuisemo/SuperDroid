$projectDir = $env:FACTORY_PROJECT_DIR
Get-ChildItem -Path $projectDir -Recurse -Include *.py | ForEach { python -m black $_ }
Get-ChildItem -Path $projectDir -Recurse -Include *.js,*.ts,*.tsx,*.json | ForEach { npx prettier --write $_ }
git add -u
Write-Host "Auto-format completed"
