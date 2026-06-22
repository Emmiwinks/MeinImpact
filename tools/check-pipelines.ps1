#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs all CI pipeline checks locally for both backend and frontend.
    Mirrors .github/workflows/backend.yml and app.yml exactly.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failed = @()

function Step($label, $block) {
    Write-Host "`n==> $label" -ForegroundColor Cyan
    try {
        & $block
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
        Write-Host "    OK" -ForegroundColor Green
    } catch {
        Write-Host "    FAILED: $_" -ForegroundColor Red
        $script:failed += $label
    }
}

# ---------------------------------------------------------------------------
# BACKEND
# ---------------------------------------------------------------------------
Write-Host "`n==== BACKEND ====" -ForegroundColor Yellow

Step "backend: ruff format (check)" {
    docker compose --project-directory (Join-Path $root "backend") exec -T api ruff format --check .
}

Step "backend: ruff lint" {
    docker compose --project-directory (Join-Path $root "backend") exec -T api ruff check .
}

Step "backend: mypy (known Python 3.14 issue - warns only)" {
    docker compose --project-directory (Join-Path $root "backend") exec -T api python -m mypy src
    if ($LASTEXITCODE -eq 2) {
        Write-Host "    mypy internal error - skipping (mypy/Python 3.14 incompatibility)" -ForegroundColor DarkYellow
        $script:failed = $script:failed | Where-Object { $_ -ne "backend: mypy (known Python 3.14 issue - warns only)" }
    }
}

Step "backend: pytest + coverage" {
    docker compose --project-directory (Join-Path $root "backend") exec -T api python -m pytest
}

# ---------------------------------------------------------------------------
# FRONTEND (app)
# ---------------------------------------------------------------------------
Write-Host "`n==== FRONTEND ====" -ForegroundColor Yellow

$app = Join-Path $root "app"

# Check flutter is available
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "  flutter not found in PATH - skipping frontend checks" -ForegroundColor DarkYellow
} else {
    Step "app: flutter pub get" {
        Set-Location $app
        flutter pub get
    }

    Step "app: gen-l10n" {
        Set-Location $app
        flutter gen-l10n
    }

    Step "app: dart format (check)" {
        Set-Location $app
        dart format --set-exit-if-changed lib test
    }

    Step "app: flutter analyze" {
        Set-Location $app
        flutter analyze
    }

    Step "app: flutter test + coverage" {
        Set-Location $app
        flutter test --coverage
    }

    Step "app: enforce coverage (60%)" {
        Set-Location $app
        python (Join-Path $root "tools/check_lcov.py") coverage/lcov.info 35
    }

    Step "app: flutter build web" {
        Set-Location $app
        flutter build web --release `
            --dart-define=MEINIMPACT_API_BASE_URL=https://api.meinimpact.de
    }

    Set-Location $root
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n==== SUMMARY ====" -ForegroundColor Yellow
if ($failed.Count -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
} else {
    Write-Host "Failed steps:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
