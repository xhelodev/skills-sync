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
  if (-not $match) { Write-Host "· $name → omitido (solo para: $($tags -join ','))"; return }

  foreach ($tool in $Targets.Keys) {
    if ($wanted -notcontains $tool) { continue }
    $root = $Targets[$tool]
    if (-not (Test-Path $root)) { Write-Host "· $name → $tool no instalado, salto"; continue }
    $target = Join-Path $root $name
    if (Test-Path $target) {
      if ((Get-Item $target -Force).LinkType) { Remove-Item $target -Force }
      else {
        # Fuera del árbol de skills: al lado del enlace la herramienta lo detecta
        # como un skill duplicado con nombre "nombre.bak-<fecha>".
        $bakDir = Join-Path $HOME ".skillsync\backups\$tool"
        New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
        $bak = Join-Path $bakDir "$name-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Move-Item $target $bak
        Write-Host "  · backup: $name → $bak"
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
  $servers = @($cfg.servers)
  if ($servers.Count -eq 0) {
    Write-Host "MCP: 0 servidores en servers.json — nada que aplicar"
  } elseif (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "MCP: claude no está en PATH — $($servers.Count) servidor(es) sin aplicar"
  } else {
    foreach ($s in $servers) {
      # '$VAR' se resuelve del entorno local; si falta, se omite el servidor.
      $envFlags = @()
      $missing = @()
      if ($s.env) {
        foreach ($p in $s.env.PSObject.Properties) {
          $val = [string]$p.Value
          if ($val.StartsWith('$')) {
            $resolved = [Environment]::GetEnvironmentVariable($val.Substring(1))
            if ([string]::IsNullOrEmpty($resolved)) { $missing += $p.Name; continue }
          } else { $resolved = $val }
          $envFlags += @("-e", "$($p.Name)=$resolved")
        }
      }
      # headers: expansión de $VAR en cualquier posición (ej: "Bearer $TOKEN")
      $headerFlags = @()
      $missingH = @()
      if ($s.headers) {
        foreach ($h in $s.headers.PSObject.Properties) {
          $out = [string]$h.Value
          foreach ($m in [regex]::Matches($out, '\$([A-Za-z_][A-Za-z0-9_]*)')) {
            $varName = $m.Groups[1].Value
            $varValue = [Environment]::GetEnvironmentVariable($varName)
            if ([string]::IsNullOrEmpty($varValue)) { $missingH += "$($h.Name)=`$$varName"; continue }
            $out = $out.Replace($m.Value, $varValue)
          }
          $headerFlags += @("-H", "$($h.Name): $out")
        }
      }
      if ($missing.Count -gt 0 -or $missingH.Count -gt 0) {
        $allMissing = @($missing) + @($missingH)
        Write-Host "MCP ! $($s.name): faltan variables $($allMissing -join ', ') — expórtalas y re-ejecuta"
        continue
      }

      & claude mcp remove -s user $s.name 2>$null | Out-Null
      # Orden importa: `-e` es variádico y va después del nombre, antes de `--`.
      if ($s.transport -eq "http") {
        $addArgs = @("mcp", "add", "-s", "user", "--transport", "http", $s.name, $s.url) + $headerFlags
      } else {
        $addArgs = @("mcp", "add", "-s", "user", $s.name) + $envFlags + @("--", $s.command) + @($s.args)
      }
      & claude @addArgs
      if ($LASTEXITCODE -eq 0) { Write-Host "MCP OK claude: $($s.name)" }
      else { Write-Host "MCP X claude: $($s.name)" }
      Write-Host "     · OpenCode/Hermes: paso manual (ver README)"
    }
  }
}
