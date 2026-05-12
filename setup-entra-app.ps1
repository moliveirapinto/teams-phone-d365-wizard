$ErrorActionPreference = 'Stop'

$displayName = 'D365 Contact Center - Teams Phone Sync'
$existing = az ad app list --display-name $displayName --query "[?displayName=='$displayName']|[0]" -o json | ConvertFrom-Json
if (-not $existing) {
    Write-Host "Creating Entra app '$displayName'..." -ForegroundColor Cyan
    $app = az ad app create --display-name $displayName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
} else {
    Write-Host "Reusing existing app $($existing.appId)" -ForegroundColor Yellow
    $app = $existing
}
$appId = $app.appId
Write-Host "AppId = $appId"

$graphId = '00000003-0000-0000-c000-000000000000'
$graphSp = az ad sp show --id $graphId -o json | ConvertFrom-Json
$perm = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq 'TeamsResourceAccount.Read.All' }
if (-not $perm) { throw "TeamsResourceAccount.Read.All scope not found on Graph SP" }
Write-Host "Permission id = $($perm.id)" -ForegroundColor DarkGray

az ad app permission add --id $appId --api $graphId --api-permissions "$($perm.id)=Scope" 2>$null
Write-Host "Permission added." -ForegroundColor Green

$sp = az ad sp list --filter "appId eq '$appId'" -o json | ConvertFrom-Json
if (-not $sp -or $sp.Count -eq 0) {
    Write-Host "Creating service principal..." -ForegroundColor Cyan
    az ad sp create --id $appId | Out-Null
}

Write-Host "Granting admin consent..." -ForegroundColor Cyan
az ad app permission admin-consent --id $appId
Write-Host ""
Write-Host "AppId = $appId" -ForegroundColor Green
