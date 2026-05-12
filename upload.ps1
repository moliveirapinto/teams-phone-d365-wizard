[CmdletBinding()]
param(
  # Target Dataverse environment URL. Defaults to $env:DATAVERSE_URL so the script
  # is reusable across tenants. Pass -OrgUrl https://contoso.crm.dynamics.com to override.
  [string]$OrgUrl = $env:DATAVERSE_URL
)
$ErrorActionPreference = 'Stop'
if (-not $OrgUrl) { throw "Provide -OrgUrl https://<org>.crm.dynamics.com or set `$env:DATAVERSE_URL." }
$base = $OrgUrl.TrimEnd('/')
$tok  = az account get-access-token --resource $base --query accessToken -o tsv
if (-not $tok) { throw "az account get-access-token failed. Run 'az login --tenant <tenant>' first." }
$h = @{
  Authorization     = "Bearer $tok"
  Accept            = 'application/json'
  'Content-Type'    = 'application/json'
  'OData-Version'   = '4.0'
  'OData-MaxVersion'= '4.0'
}
$api = "$base/api/data/v9.2"

function Publish-WebResource {
  param([string]$Name, [string]$File, [int]$Type, [string]$DisplayName, [string]$Description)
  $bytes = [IO.File]::ReadAllBytes($File)
  $b64   = [Convert]::ToBase64String($bytes)
  $existing = Invoke-RestMethod -Headers $script:h -Uri "$script:api/webresourceset?`$select=webresourceid,name&`$filter=name eq '$Name'"
  $body = @{
    name            = $Name
    displayname     = $DisplayName
    description     = $Description
    webresourcetype = $Type
    content         = $b64
  } | ConvertTo-Json -Depth 5

  if ($existing.value.Count -gt 0) {
    $id = $existing.value[0].webresourceid
    Write-Host "Updating $Name ($id)..." -ForegroundColor Cyan
    Invoke-RestMethod -Method PATCH -Headers $script:h -Uri "$script:api/webresourceset($id)" -Body $body | Out-Null
  } else {
    Write-Host "Creating $Name..." -ForegroundColor Cyan
    $resp = Invoke-WebRequest -Method POST -Headers $script:h -Uri "$script:api/webresourceset" -Body $body
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([^)]+)\)') { $id = $matches[1] } else { throw "No location header" }
    Write-Host "Created $Name. id=$id" -ForegroundColor Green
  }
  return $id
}

$ids = @()
$ids += Publish-WebResource -Name 'mau_teamsphone_example.png' -File (Join-Path $PSScriptRoot 'webresource\mau_teamsphone_example.png') -Type 5 -DisplayName 'Teams Phone setup - example screenshot' -Description 'Screenshot of Admin Center > Channels > Phone numbers > Advanced > Teams phone system tab'
$ids += Publish-WebResource -Name 'mau_TeamsPhoneSetup.html' -File (Join-Path $PSScriptRoot 'webresource\mau_TeamsPhoneSetup.html') -Type 1 -DisplayName 'Teams Phone for D365 Contact Center' -Description 'Guided UI to onboard a Teams Phone number into the D365 Contact Center voice channel'

# Publish
Write-Host "Publishing..." -ForegroundColor Cyan
$wrXml = ($ids | ForEach-Object { "<webresource>{$_}</webresource>" }) -join ''
$pubBody = @{ ParameterXml = "<importexportxml><webresources>$wrXml</webresources></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Method POST -Headers $h -Uri "$api/PublishXml" -Body $pubBody | Out-Null
Write-Host "Published." -ForegroundColor Green

$url = "$base/WebResources/mau_TeamsPhoneSetup.html"
Write-Host ""
Write-Host "Web resource URL:" -ForegroundColor Magenta
Write-Host "  $url"
$url | Set-Clipboard
Write-Host "(URL copied to clipboard)" -ForegroundColor DarkGray
