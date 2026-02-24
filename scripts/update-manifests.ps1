$ErrorActionPreference = "Stop"

function Get-Release([string]$repo, [string]$version, [string]$token) {
  $headers = @{ Authorization = "Bearer $token" }
  if ([string]::IsNullOrWhiteSpace($version)) {
    return Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repo/releases/latest"
  }

  $trimmed = $version.TrimStart("v")
  return Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repo/releases/tags/v$trimmed"
}

function Get-AssetSha256([object]$release, [string]$assetName, [string]$token) {
  $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
  if ($null -eq $asset) {
    throw "Missing release asset: $assetName"
  }

  if (-not [string]::IsNullOrWhiteSpace($asset.digest)) {
    return ($asset.digest -replace '^sha256:', '')
  }

  $tmp = Join-Path $env:RUNNER_TEMP $assetName
  Invoke-WebRequest -Headers @{ Authorization = "Bearer $token" } -Uri $asset.browser_download_url -OutFile $tmp
  $hash = (Get-FileHash -Algorithm SHA256 -Path $tmp).Hash.ToLowerInvariant()
  Remove-Item -Path $tmp -Force
  return $hash
}

$projectsConfig = Get-Content "projects.json" -Raw | ConvertFrom-Json
$projects = @($projectsConfig.projects)

$inputProject = $env:INPUT_PROJECT
$inputVersion = $env:INPUT_VERSION
$eventName = $env:GITHUB_EVENT_NAME
$eventPath = $env:GITHUB_EVENT_PATH
$token = $env:GH_TOKEN

$dispatchRepo = $null
$dispatchTag = $null
if ($eventName -eq "repository_dispatch" -and (Test-Path $eventPath)) {
  $event = Get-Content $eventPath -Raw | ConvertFrom-Json
  $dispatchRepo = $event.client_payload.source_repo
  $dispatchTag = $event.client_payload.tag
}

$updated = @()

foreach ($project in $projects) {
  if (-not [string]::IsNullOrWhiteSpace($inputProject) -and $project.id -ne $inputProject) {
    continue
  }

  if (-not [string]::IsNullOrWhiteSpace($dispatchRepo) -and $project.sourceRepo -ne $dispatchRepo) {
    continue
  }

  $selectedVersion = $inputVersion
  if ([string]::IsNullOrWhiteSpace($selectedVersion) -and -not [string]::IsNullOrWhiteSpace($dispatchTag) -and $project.sourceRepo -eq $dispatchRepo) {
    $selectedVersion = $dispatchTag
  }

  $release = Get-Release -repo $project.sourceRepo -version $selectedVersion -token $token
  $version = $release.tag_name.TrimStart("v")

  $architecture = [ordered]@{}
  $autoArchitecture = [ordered]@{}

  foreach ($arch in $project.architectures) {
    $url = $arch.urlTemplate.Replace("{version}", $version)
    $hash = Get-AssetSha256 -release $release -assetName $arch.asset -token $token

    $architecture[$arch.name] = [ordered]@{
      url  = $url
      hash = $hash
    }

    $autoArchitecture[$arch.name] = [ordered]@{
      url = $arch.urlTemplate.Replace("{version}", '$version')
    }
  }

  $manifest = [ordered]@{
    version      = $version
    description  = $project.description
    homepage     = $project.homepage
    license      = $project.license
    architecture = $architecture
    bin          = @($project.bin)
    checkver     = [ordered]@{ github = $project.sourceRepo }
    autoupdate   = [ordered]@{ architecture = $autoArchitecture }
  }

  $manifestPath = [string]$project.manifest
  $dir = Split-Path -Path $manifestPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  $json = $manifest | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($manifestPath, "$json`n", [System.Text.UTF8Encoding]::new($false))

  $updated += "$($project.id):$version"
}

if ((git status --porcelain).Length -eq 0) {
  Write-Host "No manifest changes to commit."
  exit 0
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add bucket/*.json
git commit -m "chore(scoop): update manifests ($($updated -join ', '))"
git push