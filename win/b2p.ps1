# b2p.ps1 - The CLI & Interactive Manager
param([String]$install, [String]$uninstall, [String]$upgrade, [String]$search, [String]$v = "latest", [Switch]$s = $false)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Configurações de URL (GitHub Raw para performance)
$RAW_B2P = "https://raw.githubusercontent.com/b2p-pw/b2p/main/win"
$RAW_W   = "https://raw.githubusercontent.com/b2p-pw/w/main"
$API_W   = "https://api.github.com/repos/b2p-pw/w/contents"

# 2. Carregar Core
$B2P_HOME = Join-Path $env:USERPROFILE ".b2p"
$localCore = Join-Path $B2P_HOME "bin\core.ps1"
if (Test-Path $localCore) { . $localCore } 
else { . { $(Invoke-RestMethod -Uri "$RAW_B2P/core.ps1") } }

# Garantia de caminhos (caso o core falhe)
if (-not $B2P_BIN) {
    $B2P_BIN = Join-Path $B2P_HOME "bin"; $B2P_SHIMS = Join-Path $B2P_HOME "shims"
    $B2P_APPS = Join-Path $B2P_HOME "apps"; $B2P_TELEPORTS = Join-Path $B2P_HOME "teleports"
}

function Show-Header {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "      Binary-2-Path (b2p) Manager       " -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Magenta
}

function Show-Catalog {
    param([String]$filter = "")
    Show-Header
    Write-Host "Buscando catálogo no repositório W..." -ForegroundColor Gray
    try {
        $items = Invoke-RestMethod -Uri $API_W -UserAgent "b2p"
        $apps = @($items | Where-Object { $_.type -eq "dir" -and $_.name -like "*$filter*" } | Select-Object -ExpandProperty name)

        if ($apps.Count -eq 0) { Write-Host "Nenhum app encontrado." -ForegroundColor Yellow }
        else {
            Write-Host "`nDisponíveis para instalação:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $apps.Count; $i++) { " [{0,2}] {1}" -f ($i + 1), $apps[$i] }
        }
        Write-Host " [ Q] Voltar" -ForegroundColor Yellow

        $choice = Read-Host "`nSelecione"
        if ($choice -eq "Q" -or [string]::IsNullOrWhiteSpace($choice)) { return }
        
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $apps.Count) {
            $selected = $apps[$idx - 1]
            iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$selected/i.s") } -v latest"
            Read-Host "`nPressione Enter para continuar..."
        }
    } catch { Write-Host "Erro: $_" -ForegroundColor Red; Pause }
}

function Manage-Installed {
    Show-Header
    if (-not (Test-Path $B2P_APPS)) { Write-Host "Nenhum app instalado." -ForegroundColor Yellow; Pause; return }
    $installedApps = @(Get-ChildItem $B2P_APPS -Directory)
    
    Write-Host "`nAplicativos Instalados:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $installedApps.Count; $i++) { " [{0,2}] {1}" -f ($i + 1), $installedApps[$i].Name }
    Write-Host " [ Q] Voltar" -ForegroundColor Yellow

    $choice = Read-Host "`nSelecione"
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $installedApps.Count) {
        $app = $installedApps[$idx - 1].Name
        Show-Header
        Write-Host "Gerenciando: $app" -ForegroundColor Cyan
        Write-Host "`n [1] Upgrade" -Write-Host " [2] Uninstall" -Write-Host " [Q] Voltar"
        switch (Read-Host "`nOpção") {
            "1" { iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$app/up.s") }" }
            "2" { $ver = Read-Host "Versão ou 'all'"; iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$app/un.s") } -v $ver" }
        }
        Read-Host "`nPressione Enter para continuar..."
    }
}

function Setup-B2P-Self {
    Show-Header
    Write-Host "Instalando B2P CLI..." -ForegroundColor Cyan
    @($B2P_BIN, $B2P_SHIMS, $B2P_TELEPORTS, $B2P_APPS) | ForEach-Object { if (-not (Test-Path $_)) { New-Item $_ -ItemType Directory -Force | Out-Null } }

    $b2pBat = Join-Path $B2P_SHIMS "b2p.bat"
    if (Test-Path $b2pBat) { Set-ItemProperty $b2pBat -Name IsReadOnly -Value $false }
    
    Invoke-WebRequest "$RAW_B2P/core.ps1" -OutFile (Join-Path $B2P_BIN "core.ps1")
    Invoke-WebRequest "$RAW_B2P/b2p.ps1" -OutFile (Join-Path $B2P_BIN "b2p.ps1")
    
    $content = "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$B2P_BIN\b2p.ps1`" %*"
    $content | Out-File $b2pBat -Encoding ASCII
    Set-ItemProperty $b2pBat -Name IsReadOnly -Value $true
    
    $uPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pSplit = $uPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    $modified = $false
    foreach($p in @($B2P_SHIMS, $B2P_TELEPORTS)) { if ($pSplit -notcontains $p) { $uPath = "$uPath;$p"; $modified = $true } }
    if ($modified) { [Environment]::SetEnvironmentVariable("Path", $uPath, "User") }
    Write-Host "`nB2P instalado! Reinicie o terminal." -ForegroundColor Green; Pause
}

# ROTEAMENTO
if ($install) { if ($install -eq "b2p") { Setup-B2P-Self } else { iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$install/i.s") } -v $v -s:$s" }; return }
if ($uninstall) { iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$uninstall/un.s") } -v $v"; return }
if ($upgrade) { iex "& { $(Invoke-RestMethod -Uri "$RAW_W/$upgrade/up.s") }"; return }

while ($true) {
    Show-Header
    Write-Host " [1] Explorar Catálogo" -Write-Host " [2] Pesquisar App" -Write-Host " [3] Gerenciar Instalados" -Write-Host " [4] Instalar B2P CLI" -Write-Host " [0] Sair"
    switch (Read-Host "`nEscolha") {
        "1" { Show-Catalog }
        "2" { $q = Read-Host "Busca"; Show-Catalog -filter $q }
        "3" { Manage-Installed }
        "4" { Setup-B2P-Self }
        "0" { exit }
    }
}