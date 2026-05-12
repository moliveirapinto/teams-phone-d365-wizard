[CmdletBinding()]
param(
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
$wrName = 'mau_TeamsPhoneSetup.html'
# Look up the web resource id by name so the script works in any tenant.
$lookup = Invoke-RestMethod -Headers $h -Uri "$api/webresourceset?`$select=webresourceid&`$filter=name eq '$wrName'"
if ($lookup.value.Count -eq 0) { throw "Web resource '$wrName' not found in $base. Run upload.ps1 first." }
$id = $lookup.value[0].webresourceid
$pubBody = '{"ParameterXml":"<importexportxml><webresources><webresource>{' + $id + '}</webresource></webresources></importexportxml>"}'
Write-Host "Publishing web resource $id..." -ForegroundColor Cyan
Invoke-RestMethod -Method POST -Headers $h -Uri "$api/PublishXml" -Body $pubBody -UseBasicParsing | Out-Null
Write-Host "Published OK." -ForegroundColor Green
$url = "$base/WebResources/mau_TeamsPhoneSetup.html"
Write-Host "URL: $url" -ForegroundColor Magenta
