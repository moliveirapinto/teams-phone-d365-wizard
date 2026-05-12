[CmdletBinding()]
param(
  # Target Dataverse environment URL.
  [string]$OrgUrl = $env:DATAVERSE_URL,

  # Solution + publisher metadata. Override on the command line if you want
  # different names/prefixes — nothing here is tied to a specific tenant.
  [string]$SolutionUniqueName = 'mauTeamsPhoneSetup',
  [string]$SolutionFriendlyName = 'Teams Phone for D365 Contact Center',
  [string]$SolutionVersion = '1.0.0.0',
  [string]$SolutionDescription = 'Self-serve wizard that brings a Teams Phone number into the D365 Contact Center voice channel. Generates an idempotent PowerShell onboarding script (Teams + Microsoft Graph) and links to the relevant admin portals.',

  [string]$PublisherUniqueName = 'mauPublisher',
  [string]$PublisherFriendlyName = 'mau',
  [string]$CustomizationPrefix  = 'mau',
  [int]   $CustomizationOptionValuePrefix = 10000,

  # Web resources to add (must already be published via upload.ps1).
  [string[]]$WebResourceNames = @('mau_TeamsPhoneSetup.html','mau_teamsphone_example.png'),

  # If set, also export the managed + unmanaged solution zips into ./dist.
  [switch]$Export
)

$ErrorActionPreference = 'Stop'
if (-not $OrgUrl) { throw "Provide -OrgUrl https://<org>.crm.dynamics.com or set `$env:DATAVERSE_URL." }
$base = $OrgUrl.TrimEnd('/')
$tok  = az account get-access-token --resource $base --query accessToken -o tsv
if (-not $tok) { throw "az account get-access-token failed. Run 'az login --tenant <tenant>' first." }
$h = @{
  Authorization      = "Bearer $tok"
  Accept             = 'application/json'
  'Content-Type'     = 'application/json; charset=utf-8'
  'OData-Version'    = '4.0'
  'OData-MaxVersion' = '4.0'
  Prefer             = 'return=representation'
}
$api = "$base/api/data/v9.2"

function Invoke-Dv { param($Method,$Path,$Body=$null)
  $u = if ($Path.StartsWith('http')) { $Path } else { "$api/$Path" }
  if ($null -ne $Body) {
    $json = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 8 -Compress) }
    return Invoke-RestMethod -Method $Method -Headers $h -Uri $u -Body $json
  }
  return Invoke-RestMethod -Method $Method -Headers $h -Uri $u
}

# 1) Publisher (idempotent)
Write-Host "Ensuring publisher '$PublisherUniqueName' (prefix '$CustomizationPrefix')..." -ForegroundColor Cyan
$pubResp = Invoke-Dv GET "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq '$PublisherUniqueName'"
if ($pubResp.value.Count -gt 0) {
  $publisherId = $pubResp.value[0].publisherid
  if ($pubResp.value[0].customizationprefix -ne $CustomizationPrefix) {
    Write-Host "  WARNING: existing publisher prefix is '$($pubResp.value[0].customizationprefix)', not '$CustomizationPrefix'. Reusing it as-is." -ForegroundColor Yellow
  }
  Write-Host "  Reusing publisher $publisherId" -ForegroundColor DarkGray
} else {
  $pubBody = @{
    uniquename                    = $PublisherUniqueName
    friendlyname                  = $PublisherFriendlyName
    customizationprefix           = $CustomizationPrefix
    customizationoptionvalueprefix= $CustomizationOptionValuePrefix
    description                   = "Publisher for $SolutionFriendlyName"
  }
  $created = Invoke-Dv POST 'publishers' $pubBody
  $publisherId = $created.publisherid
  Write-Host "  Created publisher $publisherId" -ForegroundColor Green
}

# 2) Solution (idempotent)
Write-Host "Ensuring solution '$SolutionUniqueName'..." -ForegroundColor Cyan
$solResp = Invoke-Dv GET "solutions?`$select=solutionid,uniquename,version&`$filter=uniquename eq '$SolutionUniqueName'"
if ($solResp.value.Count -gt 0) {
  $solutionId = $solResp.value[0].solutionid
  Write-Host "  Reusing solution $solutionId (version $($solResp.value[0].version))" -ForegroundColor DarkGray
} else {
  $solBody = @{
    uniquename                              = $SolutionUniqueName
    friendlyname                            = $SolutionFriendlyName
    version                                 = $SolutionVersion
    description                             = $SolutionDescription
    'publisherid@odata.bind'                = "/publishers($publisherId)"
  }
  $created = Invoke-Dv POST 'solutions' $solBody
  $solutionId = $created.solutionid
  Write-Host "  Created solution $solutionId" -ForegroundColor Green
}

# 3) Add web resources to the solution (component type 61 = Web Resource)
foreach ($name in $WebResourceNames) {
  $wr = Invoke-Dv GET "webresourceset?`$select=webresourceid,name&`$filter=name eq '$name'"
  if ($wr.value.Count -eq 0) {
    Write-Host "  Skipping '$name' — not found. Run upload.ps1 first." -ForegroundColor Yellow
    continue
  }
  $wrId = $wr.value[0].webresourceid
  Write-Host "Adding '$name' ($wrId) to solution..." -ForegroundColor Cyan
  $addBody = @{
    ComponentId      = $wrId
    ComponentType    = 61
    SolutionUniqueName = $SolutionUniqueName
    AddRequiredComponents = $false
    DoNotIncludeSubcomponents = $false
  }
  try {
    Invoke-Dv POST 'AddSolutionComponent' $addBody | Out-Null
    Write-Host "  Added." -ForegroundColor Green
  } catch {
    # AddSolutionComponent is idempotent in practice but the server may 400
    # if the component is already there with the same root scope. Treat
    # 'already exists / invalid' as a no-op.
    $msg = $_.ErrorDetails.Message
    if ($msg -match 'already' -or $msg -match 'present in solution') {
      Write-Host "  Already in solution." -ForegroundColor DarkGray
    } else {
      throw
    }
  }
}

# 4) Publish (so the components show up everywhere)
Write-Host "Publishing all customizations..." -ForegroundColor Cyan
Invoke-Dv POST 'PublishAllXml' @{} | Out-Null
Write-Host "Published." -ForegroundColor Green

# 5) Export (optional)
if ($Export) {
  $dist = Join-Path $PSScriptRoot 'dist'
  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  foreach ($managed in @($false, $true)) {
    if ($managed) { $label = 'managed' } else { $label = 'unmanaged' }
    Write-Host "Exporting $label solution..." -ForegroundColor Cyan
    $body = @{
      SolutionName = $SolutionUniqueName
      Managed      = $managed
    }
    $resp = Invoke-Dv POST 'ExportSolution' $body
    $bytes = [Convert]::FromBase64String($resp.ExportSolutionFile)
    if ($managed) { $suffix = '_managed.zip' } else { $suffix = '.zip' }
    $verSafe = $SolutionVersion -replace '\.','_'
    $fileName = $SolutionUniqueName + '_' + $verSafe + $suffix
    $out = Join-Path $dist $fileName
    [IO.File]::WriteAllBytes($out, $bytes)
    $kb = [math]::Round($bytes.Length / 1024, 1)
    Write-Host "  Wrote $out - $kb KB" -ForegroundColor Green
  }
  Write-Host ""
  Write-Host "Distribute the *_managed.zip to other tenants. Install via:" -ForegroundColor Magenta
  Write-Host "  Power Apps maker portal -> Solutions -> Import solution"
  Write-Host "  or:  pac solution import --path .\dist\<file>_managed.zip"
}

Write-Host ""
Write-Host "Solution '$SolutionUniqueName' ready in $OrgUrl" -ForegroundColor Magenta
