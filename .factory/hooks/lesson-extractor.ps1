$lessonsFile = "$env:FACTORY_PROJECT_DIR\.factory\lessons.md"
$logTail = Get-Content "$env:FACTORY_PROJECT_DIR\.factory\logs\failure.log" -Tail 15
Add-Content -Path $lessonsFile -Value "`n### Lesson $(Get-Date)`n$logTail`n---"
Write-Host "Lesson extracted"
