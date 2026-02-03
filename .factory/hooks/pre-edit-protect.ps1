$projectDir = $env:FACTORY_PROJECT_DIR
$path = $args[0]
if ($path -match "\.env|secrets|id_rsa|\.git") {
    Write-Error "Blocked sensitive file edit"
    exit 2
}
Write-Host "Pre-edit protection passed"
exit 0
