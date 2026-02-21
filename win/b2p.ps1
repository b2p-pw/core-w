# b2p.ps1 - The CLI & Interactive Manager
param(
    [String]$install,
    [String]$uninstall,
    [String]$upgrade,
    [String]$default,
    [String]$search,
    [String]$v = "latest",
    [Switch]$s = $false
)

# 1. Configurações de URL
$B2P_BASE_URL = "https://raw.githubusercontent.com/b2p-pw/b2p/main/win"
$W_REPO_URL   = "https://raw.githubusercontent.com/b2p-pw/w/main"
$API_W_URL    = "https://api.github.com/repos/b2p-pw/w/contents"

# 2. Tentar carregar o Core e garantir variáveis de ambiente
$localCore = "$env:USERPROFILE\.b2p\bin\core.ps1"
if (Test-Path $localCore) { 
    . $localCore 
} else { 
    $coreCode = Invoke-RestMethod -Uri "$B2P_BASE_URL/core.ps1"
    Invoke-Expression $coreCode
}

# Garantia de emergência: se as variáveis do core não carregaram, define localmente
if (-not $B2P_BIN) {
    $B2P_HOME = Join-Path $env:USERPROFILE ".b2p"
    $B2P_BIN = Join-Path $B2P_HOME "bin"
    $B2P_SHIMS = Join-Path $B2P_HOME "shims"
    $B2P_APPS = Join-Path $B2P_HOME "apps"
    $B2P_TELEPORTS = Join-Path $B2P_HOME "teleports"
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
    Write-Host "Buscando catálogo em w.b2p.pw..." -ForegroundColor Gray
    try {
        $items = Invoke-RestMethod -Uri $API_W_URL -UserAgent "b2p"
        # @(...) Força o resultado a ser um Array, mesmo que venha apenas 1 item
        $apps = @($items | Where-Object { $_.type -eq "dir" -and $_.name -like "*$filter*" } | Select-Object -ExpandProperty name)

        if ($apps.Count -eq 0) {
            Write-Host "Nenhum app encontrado." -ForegroundColor Yellow
        } else {
            Write-Host "`nDisponíveis para instalação:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $apps.Count; $i++) {
                " [{0,2}] {1}" -f ($i + 1), $apps[$i]
            }
        }
        Write-Host " [ Q] Voltar" -ForegroundColor Yellow

        $choice = Read-Host "`nSelecione um número ou 'Q'"
        if ($choice -eq "Q" -or [string]::IsNullOrWhiteSpace($choice)) { return }
        
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -le $apps.Count) {
            $selected = $apps[$idx - 1]
            Write-Host "Iniciando instalador para $selected..." -ForegroundColor Cyan
            iex "& { $(irm "$W_REPO_URL/$selected/i.s") } -v latest"
            Read-Host "`nPressione Enter para continuar"
        }
    } catch {
        Write-Host "Erro ao acessar o catálogo: $_" -ForegroundColor Red
        Pause
    }
}

function Manage-Installed {
    Show-Header
    if (-not (Test-Path $B2P_APPS)) { 
        Write-Host "Nenhum app instalado." -ForegroundColor Yellow
        Pause; return 
    }
    
    $installedApps = @(Get-ChildItem $B2P_APPS -Directory)
    if ($installedApps.Count -eq 0) {
        Write-Host "Nenhum aplicativo instalado via b2p." -ForegroundColor Yellow
        Pause; return
    }

    Write-Host "`nAplicativos Instalados:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $installedApps.Count; $i++) {
        " [{0,2}] {1}" -f ($i + 1), $installedApps[$i].Name
    }
    Write-Host " [ Q] Voltar" -ForegroundColor Yellow

    $choice = Read-Host "`nSelecione um app"
    if ($choice -eq "Q") { return }
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -le $installedApps.Count) {
        $app = $installedApps[$idx - 1].Name
        $versions = @(Get-ChildItem (Join-Path $B2P_APPS $app) -Directory | Select-Object -ExpandProperty Name)
        
        Show-Header
        Write-Host "Gerenciando: $app" -ForegroundColor Cyan
        Write-Host "Versões: $($versions -join ', ')" -ForegroundColor Gray
        Write-Host "`n [1] Definir Versão Padrão (Default)"
        Write-Host " [2] Upgrade (Última versão)"
        Write-Host " [3] Uninstall (Remover)"
        Write-Host " [Q] Voltar"

        switch (Read-Host "`nOpção") {
            "1" {
                $ver = Read-Host "Versão para tornar padrão"
                if ($versions -contains $ver) { 
                    $source = Join-Path $B2P_TELEPORTS "$app-v$ver.bat"
                    Copy-Item $source (Join-Path $B2P_TELEPORTS "$app.bat") -Force
                    Write-Host "Sucesso!" -ForegroundColor Green
                }
            }
            "2" { iex "& { $(irm "$W_REPO_URL/$app/up.s") }" }
            "3" { 
                $ver = Read-Host "Versão específica ou 'all'"
                iex "& { $(irm "$W_REPO_URL/$app/un.s") } -v $ver"
            }
        }
        Pause
    }
}

function Setup-B2P-Self {
    Show-Header
    Write-Host "Instalando B2P CLI no sistema..." -ForegroundColor Cyan
    
    # Garantir pastas
    @($B2P_BIN, $B2P_SHIMS, $B2P_TELEPORTS, $B2P_APPS) | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item $_ -ItemType Directory -Force | Out-Null }
    }

    $b2pBat = Join-Path $B2P_SHIMS "b2p.bat"
    
    if (Test-Path $b2pBat) { Set-ItemProperty $b2pBat -Name IsReadOnly -Value $false }
    
    Write-Host "Baixando componentes..." -ForegroundColor Gray
    Invoke-WebRequest "$B2P_BASE_URL/core.ps1" -OutFile (Join-Path $B2P_BIN "core.ps1")
    Invoke-WebRequest "$B2P_BASE_URL/b2p.ps1" -OutFile (Join-Path $B2P_BIN "b2p.ps1")
    
    Write-Host "Criando atalhos..." -ForegroundColor Gray
    $batPath = Join-Path $B2P_BIN "b2p.ps1"
    $content = "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$batPath`" %*"
    $content | Out-File $b2pBat -Encoding ASCII
    Set-ItemProperty $b2pBat -Name IsReadOnly -Value $true
    
    # Atualizar PATH
    $uPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPaths = $uPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    $modified = $false
    foreach($p in @($B2P_SHIMS, $B2P_TELEPORTS)) {
        if ($newPaths -notcontains $p) {
            $uPath = "$uPath;$p"
            $modified = $true
        }
    }
    if ($modified) { [Environment]::SetEnvironmentVariable("Path", $uPath, "User") }

    Write-Host "`nB2P instalado com sucesso! Reinicie o terminal." -ForegroundColor Green
    Pause
}

# --- ROTEAMENTO ---
if ($install) { 
    if ($install -eq "b2p") { Setup-B2P-Self } 
    else { iex "& { $(irm "$W_REPO_URL/$install/i.s") } -v $v -s:$s" }
    return
}
if ($uninstall) { iex "& { $(irm "$W_REPO_URL/$uninstall/un.s") } -v $v"; return }
if ($upgrade) { iex "& { $(irm "$W_REPO_URL/$upgrade/up.s") }"; return }

# Menu Interativo
while ($true) {
    Show-Header
    Write-Host " [1] Explorar Catálogo (Instalar Apps)"
    Write-Host " [2] Pesquisar App"
    Write-Host " [3] Gerenciar Instalados"
    Write-Host " [4] Instalar/Reparar B2P CLI"
    Write-Host " [0] Sair"
    
    switch (Read-Host "`nEscolha") {
        "1" { Show-Catalog }
        "2" { $q = Read-Host "Busca"; Show-Catalog -filter $q }
        "3" { Manage-Installed }
        "4" { Setup-B2P-Self }
        "0" { exit }
    }
}