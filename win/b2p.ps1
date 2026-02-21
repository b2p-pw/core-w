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

# 1. Importar Motor (Local ou Web)
$B2P_BASE_URL = "https://raw.githubusercontent.com/b2p-pw/b2p/main/win"
$W_REPO_URL   = "https://raw.githubusercontent.com/b2p-pw/w/main"
$API_W_URL    = "https://api.github.com/repos/b2p-pw/w/contents"

if (Test-Path "$env:USERPROFILE\.b2p\bin\core.ps1") { . "$env:USERPROFILE\.b2p\bin\core.ps1" }
else { . { $(irm "$B2P_BASE_URL/core.ps1") } }

# --- FUNÇÕES DE INTERFACE ---

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
        $apps = $items | Where-Object { $_.type -eq "dir" -and $_.name -like "*$filter*" } | Select-Object -ExpandProperty name

        Write-Host "`nDisponíveis para instalação:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $apps.Count; $i++) {
            " [{0,2}] {1}" -f ($i + 1), $apps[$i]
        }
        Write-Host " [ Q] Voltar" -ForegroundColor Yellow

        $choice = Read-Host "`nSelecione um número para instalar"
        if ($choice -eq "Q") { return }
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -le $apps.Count) {
            $selected = $apps[$idx - 1]
            iex "& { $(irm "$W_REPO_URL/$selected/i.s") } -v latest"
            Pause
        }
    } catch {
        Write-Host "Erro ao acessar o catálogo." -ForegroundColor Red
        Pause
    }
}

function Manage-Installed {
    Show-Header
    $installedApps = Get-ChildItem $B2P_APPS -Directory
    if (-not $installedApps) {
        Write-Host "Nenhum aplicativo instalado via b2p." -ForegroundColor Yellow
        Pause; return
    }

    Write-Host "`nAplicativos Instalados:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $installedApps.Count; $i++) {
        $name = $installedApps[$i].Name
        " [{0,2}] {1}" -f ($i + 1), $name
    }
    Write-Host " [ Q] Voltar" -ForegroundColor Yellow

    $choice = Read-Host "`nSelecione um app para gerenciar"
    if ($choice -eq "Q") { return }
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -le $installedApps.Count) {
        $app = $installedApps[$idx - 1].Name
        $versions = Get-ChildItem (Join-Path $B2P_APPS $app) -Directory | Select-Object -ExpandProperty Name
        
        Show-Header
        Write-Host "Gerenciando: $app" -ForegroundColor Cyan
        Write-Host "Versões: $($versions -join ', ')" -ForegroundColor Gray
        Write-Host "`n [1] Definir Versão Padrão (Default)"
        Write-Host " [2] Upgrade (Última versão)"
        Write-Host " [3] Uninstall (Remover versão/tudo)"
        Write-Host " [4] Criar Shim Customizado"
        Write-Host " [Q] Voltar"

        switch (Read-Host "`nOpção") {
            "1" {
                $ver = Read-Host "Digite a versão para tornar padrão"
                if ($versions -contains $ver) { 
                    $source = Join-Path $B2P_TELEPORTS "$app-v$ver.bat"
                    Copy-Item $source (Join-Path $B2P_TELEPORTS "$app.bat") -Force
                    Write-Host "Sucesso!" -ForegroundColor Green
                }
            }
            "2" { iex "& { $(irm "$W_REPO_URL/$app/up.s") }" }
            "3" { 
                $ver = Read-Host "Versão específica ou 'all' para tudo"
                iex "& { $(irm "$W_REPO_URL/$app/un.s") } -v $ver"
            }
            "4" {
                $alias = Read-Host "Nome do comando (ex: clang)"
                $exe = Read-Host "Nome do executável (ex: bin\clang.exe)"
                $target = Join-Path $B2P_APPS "$app\latest\$exe"
                Create-B2PShim -BinaryPath $target -Alias $alias
            }
        }
        Pause
    }
}

function Setup-B2P-Self {
    Show-Header
    Write-Host "Instalando B2P CLI no sistema..." -ForegroundColor Cyan
    $b2pBat = Join-Path $B2P_SHIMS "b2p.bat"
    
    if (Test-Path $b2pBat) { Set-ItemProperty $b2pBat -Name IsReadOnly -Value $false }
    
    Invoke-WebRequest "$B2P_BASE_URL/core.ps1" -OutFile (Join-Path $B2P_BIN "core.ps1")
    Invoke-WebRequest "$B2P_BASE_URL/b2p.ps1" -OutFile (Join-Path $B2P_BIN "b2p.ps1")
    
    "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$B2P_BIN\b2p.ps1`" %*" | Out-File $b2pBat -Encoding ASCII
    Set-ItemProperty $b2pBat -Name IsReadOnly -Value $true
    
    # Adicionar pastas ao PATH se necessário
    $uPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $toAdd = @($B2P_SHIMS, $B2P_TELEPORTS)
    $newPaths = $uPath.Split(';') | Where-Object { $_ -ne "" }
    foreach($p in $toAdd) { if ($newPaths -notcontains $p) { $newPaths += $p } }
    [Environment]::SetEnvironmentVariable("Path", ($newPaths -join ';'), "User")

    Write-Host "`nB2P instalado com sucesso! Reinicie o terminal." -ForegroundColor Green
    Pause
}

# --- ROTEAMENTO ---

# Se houver parâmetros, executa CLI
if ($install) { 
    if ($install -eq "b2p") { Setup-B2P-Self } 
    else { iex "& { $(irm "$W_REPO_URL/$install/i.s") } -v $v -s:$s" }
    return
}
if ($uninstall) { iex "& { $(irm "$W_REPO_URL/$uninstall/un.s") } -v $v"; return }
if ($upgrade) { iex "& { $(irm "$W_REPO_URL/$upgrade/up.s") }"; return }
if ($default) { 
    $source = Join-Path $B2P_TELEPORTS "$install-$default.bat" # Aqui 'install' vira o nome do app via CLI positional
    Copy-Item $source (Join-Path $B2P_TELEPORTS "$install.bat") -Force; return 
}

# Caso contrário, Menu Interativo
while ($true) {
    Show-Header
    Write-Host " [1] Explorar Catálogo (Instalar Apps)"
    Write-Host " [2] Pesquisar App"
    Write-Host " [3] Gerenciar Instalados (Upgrade/Uninstall/Default)"
    Write-Host " [4] Instalar/Reparar B2P CLI"
    Write-Host " [0] Sair"
    
    switch (Read-Host "`nEscolha uma opção") {
        "1" { Show-Catalog }
        "2" { $q = Read-Host "Termo de busca"; Show-Catalog -filter $q }
        "3" { Manage-Installed }
        "4" { Setup-B2P-Self }
        "0" { exit }
    }
}