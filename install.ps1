# skillsync para Windows — junctions (no requieren admin)
# Uso: .\install.ps1   (o $env:SKILLSYNC_MACHINE="vps"; .\install.ps1)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Machine = if ($env:SKILLSYNC_MACHINE) { $env:SKILLSYNC_MACHINE } else { $env:COMPUTERNAME.ToLower() }

$Targets = [ordered]@{
  "hermes"   = Join-Path $HOME ".hermes\skills"
  "opencode" = Join-Path $HOME ".config\opencode\skills"
  "claude"   = Join-Path $HOME ".claude\skills"
}

Write-Host "skillsync · máquina='$Machine' · repo='$Repo'"

$installed = 0
Get-ChildItem -Directory (Join-Path $Repo "skills") | ForEach-Object {
  $name = $_.Name
  $machinesFile = Join-Path $_.FullName ".machines"
  $targetsFile  = Join-Path $_.FullName ".targets"
  $tags   = if (Test-Path $machinesFile) { (Get-Content $machinesFile -Raw).Split(",") } else { @("*") }
  $wanted = if (Test-Path $targetsFile)  { (Get-Content $targetsFile -Raw).Split(",") } else { @("hermes","opencode","claude") }

  $match = $false
  foreach ($t in $tags) { $tt = $t.Trim(); if ($tt -eq "*" -or $tt -eq $Machine) { $match = $true } }
  if (-not $match) { Write-Host "· $name → omitido (solo para: $machines)"; return }

  foreach ($tool in $Targets.Keys) {
    if ($wanted -notcontains $tool) { continue }
    $root = $Targets[$tool]
    if (-not (Test-Path $root)) { Write-Host "· $name → $tool no instalado, salto"; continue }
    $target = Join-Path $root $name
    if (Test-Path $target) {
      if ((Get-Item $target -Force).LinkType) { Remove-Item $target -Force }
      else {
        $bak = "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Move-Item $target $bak
        Write-Host "  · backup: $name → $(Split-Path -Leaf $bak)"
      }
    }
    New-Item -ItemType Junction -Path $target -Value $_.FullName | Out-Null
    Write-Host "OK $name → $target"
    $installed++
  }
}
Write-Host "Skills enlazados: $installed"

# MCP — igual que en Linux: fuente mcp/servers.json sin secretos, auto para Claude Code
$serversFile = Join-Path $Repo "mcp\servers.json"
if (Test-Path $serversFile) {
  $cfg = Get-Content $serversFile -Raw | ConvertFrom-Json
  if ($cfg.servers.Count -eq 0) { Write-Host "MCP: 0 servidores en servers.json — nada que aplicar" }
  foreach ($s in $cfg.servers) {
    if ($s.transport -eq "http") {
      claude mcp add --transport http $s.name $s.url
    } else {
      & claude mcp add $s.name -- $s.command @($s.args)
    }
    Write-Host "     · OpenCode/Hermes: paso manual (ver README)"
  }
}
