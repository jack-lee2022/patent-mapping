# install.ps1 — patent-mapping 一鍵安裝腳本 (Windows)
# 用法：在 PowerShell 中執行  .\install.ps1
# 需求：Python 3.9+, pip, winget (Windows 11 內建)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  patent-mapping  Installation Script"                 -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# ─── 0. Git submodule init ────────────────────────────────────────────────
Write-Host "[0/4] Initializing git submodules (scripts/ → patent-shared)..." -ForegroundColor Yellow
git -C $ScriptDir submodule update --init --recursive
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] git submodule update failed. Make sure you cloned with --recurse-submodules." -ForegroundColor Red
    Write-Host "  Run: git submodule update --init --recursive" -ForegroundColor DarkYellow
} else {
    Write-Host "  OK — scripts/ submodule ready." -ForegroundColor Green
}
Write-Host ""

# ─── 1. Python packages ────────────────────────────────────────────────────
Write-Host "[1/4] Installing Python packages..." -ForegroundColor Yellow
pip install -r "$ScriptDir\requirements.txt"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] pip install failed. Ensure Python 3.9+ is installed." -ForegroundColor Red
    exit 1
}
Write-Host "  OK — Python packages installed." -ForegroundColor Green

# ─── 2. Playwright browser ────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Installing Playwright Chromium browser..." -ForegroundColor Yellow
playwright install chromium
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] playwright install failed. Browser fallback won't work." -ForegroundColor DarkYellow
} else {
    Write-Host "  OK — Chromium installed." -ForegroundColor Green
}

# ─── 3. Tor ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Setting up Tor..." -ForegroundColor Yellow

$TorDir    = "$ScriptDir\tor"
$TorExe    = "$TorDir\tor.exe"
$TorrcFile = "$TorDir\torrc"

if (Test-Path $TorExe) {
    Write-Host "  OK — tor.exe already present at $TorExe" -ForegroundColor Green
} else {
    Write-Host "  Trying winget to install Tor Expert Bundle..." -ForegroundColor Gray
    $wingetAvail = $null
    try { $wingetAvail = (Get-Command winget -ErrorAction Stop).Source } catch {}

    $TorBrowserPath = $null
    if ($wingetAvail) {
        try {
            winget install TorProject.TorBrowser --accept-package-agreements --accept-source-agreements --silent
            $candidates = @(
                "$env:LOCALAPPDATA\Tor Browser\Browser\TorBrowser\Tor\tor.exe",
                "$env:ProgramFiles\Tor Browser\Browser\TorBrowser\Tor\tor.exe",
                "$env:USERPROFILE\Desktop\Tor Browser\Browser\TorBrowser\Tor\tor.exe"
            )
            foreach ($c in $candidates) {
                if (Test-Path $c) { $TorBrowserPath = $c; break }
            }
        } catch {
            Write-Host "  winget install failed: $_" -ForegroundColor DarkYellow
        }
    }

    if ($TorBrowserPath) {
        New-Item -ItemType Directory -Force -Path $TorDir | Out-Null
        $TorSrcDir = Split-Path $TorBrowserPath
        Copy-Item "$TorSrcDir\tor.exe" $TorDir -Force
        Copy-Item "$TorSrcDir\*.dll"   $TorDir -Force -ErrorAction SilentlyContinue
        Copy-Item "$TorSrcDir\*.so"    $TorDir -Force -ErrorAction SilentlyContinue
        Write-Host "  OK — tor.exe copied from Tor Browser to $TorDir" -ForegroundColor Green
    } else {
        Write-Host "  winget path not found. Downloading Tor Expert Bundle..." -ForegroundColor Gray
        New-Item -ItemType Directory -Force -Path $TorDir | Out-Null

        try {
            $distJson = Invoke-RestMethod "https://aus1.torproject.org/torbrowser/update_3/release/downloads.json" -TimeoutSec 30
            $ebUrl = $distJson.downloads.win64."tor-expert-bundle"
            if (-not $ebUrl) { throw "Could not parse expert bundle URL" }
        } catch {
            $ebUrl = "https://archive.torproject.org/tor-package-archive/torbrowser/14.0.9/tor-expert-bundle-windows-x86_64-14.0.3.tar.gz"
            Write-Host "  Using fallback URL: $ebUrl" -ForegroundColor DarkYellow
        }

        $TgzPath = "$env:TEMP\tor-expert-bundle.tar.gz"
        try {
            Invoke-WebRequest $ebUrl -OutFile $TgzPath -TimeoutSec 120
            tar -xzf $TgzPath -C $TorDir --strip-components=1
            Write-Host "  OK — Tor Expert Bundle extracted to $TorDir" -ForegroundColor Green
            Remove-Item $TgzPath -Force
        } catch {
            Write-Host ""
            Write-Host "[WARN] Automatic Tor download failed: $_" -ForegroundColor DarkYellow
            Write-Host "  Manual steps:" -ForegroundColor DarkYellow
            Write-Host "  1. Download Expert Bundle from https://www.torproject.org/download/tor/" -ForegroundColor DarkYellow
            Write-Host "  2. Extract tor.exe and all DLLs into: $TorDir" -ForegroundColor DarkYellow
        }
    }
}

# Write torrc — CookieAuthentication 1 is required for stem NEWNYM auto-rotation
if (Test-Path $TorExe) {
    if (-not (Test-Path $TorrcFile)) {
        @"
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
DataDirectory $TorDir\data
Log notice stdout
"@ | Out-File -FilePath $TorrcFile -Encoding utf8
        New-Item -ItemType Directory -Force -Path "$TorDir\data" | Out-Null
        Write-Host "  torrc written to $TorrcFile (CookieAuthentication enabled)" -ForegroundColor Green
    } else {
        $torrcContent = Get-Content $TorrcFile -Raw
        if ($torrcContent -notmatch "CookieAuthentication") {
            Add-Content $TorrcFile "`nCookieAuthentication 1"
            Write-Host "  torrc updated — added CookieAuthentication 1" -ForegroundColor Green
        } else {
            Write-Host "  torrc already exists with CookieAuthentication — skipping." -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  [WARN] tor.exe not found. Add tor.exe manually to: $TorDir" -ForegroundColor DarkYellow
}

# ─── 4. Environment check ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Verifying environment..." -ForegroundColor Yellow

$checks = @(
    @{ name = "requests";        cmd = "python -c `"import requests; print(requests.__version__)`"" },
    @{ name = "beautifulsoup4";  cmd = "python -c `"import bs4; print(bs4.__version__)`"" },
    @{ name = "playwright";      cmd = "python -c `"import playwright; print('ok')`"" },
    @{ name = "stem (Tor ctrl)"; cmd = "python -c `"import stem; print(stem.__version__)`"" },
    @{ name = "pandas";          cmd = "python -c `"import pandas; print(pandas.__version__)`"" },
    @{ name = "seaborn";         cmd = "python -c `"import seaborn; print(seaborn.__version__)`"" },
    @{ name = "matplotlib";      cmd = "python -c `"import matplotlib; print(matplotlib.__version__)`"" },
    @{ name = "langdetect";      cmd = "python -c `"import langdetect; print(langdetect.__version__)`"" },
    @{ name = "tor.exe";         cmd = "Test-Path '$TorExe'" }
)

foreach ($c in $checks) {
    try {
        if ($c.name -eq "tor.exe") {
            $ok    = Test-Path $TorExe
            $val   = if ($ok) { "found" } else { "MISSING" }
            $color = if ($ok) { "Green" } else { "DarkYellow" }
        } else {
            $val   = Invoke-Expression $c.cmd 2>$null
            $color = "Green"
        }
        Write-Host "  [OK] $($c.name): $val" -ForegroundColor $color
    } catch {
        Write-Host "  [WARN] $($c.name): not available" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Installation complete!"                               -ForegroundColor Cyan
Write-Host ""
Write-Host "  Quick start:"
Write-Host "  - Collect:   python scripts/google_patents_collector.py --ipc A61M11/00 --max 200"
Write-Host "  - Enrich:    python scripts/advanced/abstract_enricher.py --csv raw.csv --out enriched.csv"
Write-Host "  - Visualize: python scripts/advanced/visualizer.py --csv enriched.csv --outdir ./output"
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
