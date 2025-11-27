#
# Copyright 2025 ponponusa
#
# narou-mod プロセス管理スクリプト (Windows版)
# Usage: .\bin\process_control.ps1 [-List] [-Restart] [-Kill] [-Force]
#

param(
    [switch]$List,
    [switch]$Restart,
    [switch]$Kill,
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# 色定義用関数
function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $fc
}

# バックエンドプロセスを取得
function Get-BackendProcesses {
    $processes = @()

    # Ruby narou.rb web プロセス
    $rubyProcesses = Get-Process -Name "ruby" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -match "narou\.rb.*web" -or $cmdLine -match "puma"
        } catch {
            $false
        }
    }

    if ($rubyProcesses) {
        $processes += $rubyProcesses
    }

    return $processes
}

# フロントエンドプロセスを取得
function Get-FrontendProcesses {
    $processes = @()

    # Node.js プロセス (npm run dev, astro)
    $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -match "astro" -or $cmdLine -match "npm.*dev"
        } catch {
            $false
        }
    }

    if ($nodeProcesses) {
        $processes += $nodeProcesses
    }

    return $processes
}

# プロセス一覧を表示
function Show-ProcessList {
    Write-ColorOutput "=== narou-mod プロセス一覧 ===" -ForegroundColor Cyan
    Write-Output ""

    $backendProcesses = Get-BackendProcesses
    $frontendProcesses = Get-FrontendProcesses

    $hasProcesses = $false

    # バックエンドプロセス
    if ($backendProcesses.Count -gt 0) {
        Write-ColorOutput "Backend Server (Ruby/Sinatra API, Port: 5678)" -ForegroundColor Green
        Write-ColorOutput ("  {0,-8} {1,-12} {2,-10} {3}" -f "PID", "TYPE", "PORT", "COMMAND") -ForegroundColor Yellow

        foreach ($proc in $backendProcesses) {
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                if (-not $cmdLine) { $cmdLine = $proc.ProcessName }
                # コマンドラインを短縮
                if ($cmdLine.Length -gt 60) {
                    $cmdLine = $cmdLine.Substring(0, 57) + "..."
                }
                Write-Output ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Backend", "5678", $cmdLine)
            } catch {
                Write-Output ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Backend", "5678", $proc.ProcessName)
            }
        }
        Write-Output ""
        $hasProcesses = $true
    }

    # フロントエンドプロセス
    if ($frontendProcesses.Count -gt 0) {
        Write-ColorOutput "Frontend Server (Astro/Svelte, Port: 4321)" -ForegroundColor Green
        Write-ColorOutput ("  {0,-8} {1,-12} {2,-10} {3}" -f "PID", "TYPE", "PORT", "COMMAND") -ForegroundColor Yellow

        foreach ($proc in $frontendProcesses) {
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                if (-not $cmdLine) { $cmdLine = $proc.ProcessName }
                # コマンドラインを短縮
                if ($cmdLine.Length -gt 60) {
                    $cmdLine = $cmdLine.Substring(0, 57) + "..."
                }
                Write-Output ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Frontend", "4321", $cmdLine)
            } catch {
                Write-Output ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Frontend", "4321", $proc.ProcessName)
            }
        }
        Write-Output ""
        $hasProcesses = $true
    }

    if (-not $hasProcesses) {
        Write-ColorOutput "実行中のプロセスは見つかりませんでした。" -ForegroundColor Yellow
    } else {
        # WebSocketポート情報
        $envFile = Join-Path $ProjectRoot "frontend\.env"
        if (Test-Path $envFile) {
            $wsPort = "5679"
            $content = Get-Content $envFile -Raw
            if ($content -match "PUBLIC_PUSH_SERVER_PORT=(\d+)") {
                $wsPort = $Matches[1]
            }
            Write-ColorOutput "WebSocket Server (Port: $wsPort, バックエンドに含まれる)" -ForegroundColor Green
            Write-Output ""
        }
    }
}

# プロセスを終了
function Stop-NarouProcesses {
    param(
        [switch]$ForceKill
    )

    $backendProcesses = Get-BackendProcesses
    $frontendProcesses = Get-FrontendProcesses

    if ($backendProcesses.Count -eq 0 -and $frontendProcesses.Count -eq 0) {
        Write-ColorOutput "終了するプロセスが見つかりませんでした。" -ForegroundColor Yellow
        return $true
    }

    Write-ColorOutput "=== プロセス終了 ===" -ForegroundColor Cyan
    Write-Output ""

    # 確認プロンプト
    if (-not $ForceKill) {
        Write-Output "以下のプロセスを終了します:"

        if ($backendProcesses.Count -gt 0) {
            Write-Output ""
            Write-ColorOutput "Backend:" -ForegroundColor Green
            foreach ($proc in $backendProcesses) {
                try {
                    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                    if (-not $cmdLine) { $cmdLine = $proc.ProcessName }
                    Write-ColorOutput "  PID $($proc.Id): $cmdLine" -ForegroundColor Yellow
                } catch {
                    Write-ColorOutput "  PID $($proc.Id): $($proc.ProcessName)" -ForegroundColor Yellow
                }
            }
        }

        if ($frontendProcesses.Count -gt 0) {
            Write-Output ""
            Write-ColorOutput "Frontend:" -ForegroundColor Green
            foreach ($proc in $frontendProcesses) {
                try {
                    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
                    if (-not $cmdLine) { $cmdLine = $proc.ProcessName }
                    Write-ColorOutput "  PID $($proc.Id): $cmdLine" -ForegroundColor Yellow
                } catch {
                    Write-ColorOutput "  PID $($proc.Id): $($proc.ProcessName)" -ForegroundColor Yellow
                }
            }
        }

        Write-Output ""
        $response = Read-Host "これらのプロセスを終了しますか? (y/N)"

        if ($response -notmatch "^[Yy]$") {
            Write-ColorOutput "キャンセルしました。" -ForegroundColor Yellow
            return $false
        }
    }

    Write-Output "プロセスを終了中..."

    # バックエンドプロセス終了
    foreach ($proc in $backendProcesses) {
        try {
            Write-Output "  Backend PID $($proc.Id) を終了中..."
            # taskkill で子プロセスも含めて終了
            $null = & taskkill /PID $proc.Id /T /F 2>&1
        } catch {
            Write-Output "  Backend PID $($proc.Id) は既に終了しています"
        }
    }

    # フロントエンドプロセス終了
    foreach ($proc in $frontendProcesses) {
        try {
            Write-Output "  Frontend PID $($proc.Id) を終了中..."
            # taskkill で子プロセスも含めて終了
            $null = & taskkill /PID $proc.Id /T /F 2>&1
        } catch {
            Write-Output "  Frontend PID $($proc.Id) は既に終了しています"
        }
    }

    Start-Sleep -Seconds 1
    Write-ColorOutput "プロセス終了完了。" -ForegroundColor Green
    return $true
}

# サーバーを起動
function Start-NarouServers {
    Write-ColorOutput "=== サーバー起動 ===" -ForegroundColor Cyan
    Write-Output ""

    Push-Location $ProjectRoot

    try {
        # Bootsnap キャッシュをクリア
        Write-Output "Bootsnap キャッシュをクリア中..."
        $bootSnapCache = Join-Path $ProjectRoot "tmp\bootsnap-cache"
        if (Test-Path $bootSnapCache) {
            Remove-Item -Path "$bootSnapCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        # バックエンド起動
        Write-Output ""
        Write-ColorOutput "バックエンドサーバーを起動中..." -ForegroundColor Green

        $backendLogPath = Join-Path $ProjectRoot "backend.log"
        $backendProcess = Start-Process -FilePath "bundle" -ArgumentList "exec", "ruby", "bin/narou-mod", "web", "--no-browser" `
            -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $backendLogPath -RedirectStandardError "$backendLogPath.err"

        Write-Output "  PID: $($backendProcess.Id)"

        Write-Output "バックエンドの初期化を待機中..."
        Start-Sleep -Seconds 5

        # バックエンドが起動しているか確認
        if ($backendProcess.HasExited) {
            Write-ColorOutput "❌ バックエンドサーバーの起動に失敗しました。" -ForegroundColor Red
            Write-Output "ログを確認してください: $backendLogPath"
            if (Test-Path $backendLogPath) {
                Get-Content $backendLogPath -Tail 20
            }
            return $false
        }

        # ポート情報取得
        $backendPort = 5678
        $wsPort = 5679
        $envFile = Join-Path $ProjectRoot "frontend\.env"
        if (Test-Path $envFile) {
            $content = Get-Content $envFile -Raw
            if ($content -match "PUBLIC_PUSH_SERVER_PORT=(\d+)") {
                $wsPort = $Matches[1]
            }
        }

        # フロントエンドはバックエンドが自動起動するので待機のみ
        Write-Output ""
        Write-ColorOutput "フロントエンドサーバーの起動を待機中..." -ForegroundColor Green
        Write-Output "  (バックエンドが自動的にフロントエンドを起動します)"
        Start-Sleep -Seconds 10

        # フロントエンドプロセスを検索
        $frontendProcesses = Get-FrontendProcesses

        # 起動確認
        Write-Output ""
        Write-ColorOutput "=== サーバー状態確認 ===" -ForegroundColor Cyan
        Write-Output ""

        $allOk = $true

        # バックエンド確認
        $backendCheck = Get-Process -Id $backendProcess.Id -ErrorAction SilentlyContinue
        if ($backendCheck -and -not $backendCheck.HasExited) {
            Write-ColorOutput "✅ Backend Server" -ForegroundColor Green
            Write-Output "   URL: http://localhost:$backendPort"
            Write-Output "   PID: $($backendProcess.Id)"
        } else {
            Write-ColorOutput "❌ Backend Server (起動失敗)" -ForegroundColor Red
            $allOk = $false
        }

        # フロントエンド確認
        if ($frontendProcesses.Count -gt 0) {
            Write-ColorOutput "✅ Frontend Server" -ForegroundColor Green
            Write-Output "   URL: http://localhost:4321"
            Write-Output "   PID: $($frontendProcesses[0].Id)"
        } else {
            Write-ColorOutput "❌ Frontend Server (起動失敗)" -ForegroundColor Red
            $allOk = $false
        }

        Write-ColorOutput "✅ WebSocket Server" -ForegroundColor Green
        Write-Output "   Port: $wsPort"

        Write-Output ""

        if ($allOk) {
            Write-ColorOutput "✅ すべてのサーバーが正常に起動しました！" -ForegroundColor Green
            return $true
        } else {
            Write-ColorOutput "❌ 一部のサーバーの起動に失敗しました。ログを確認してください。" -ForegroundColor Red
            return $false
        }
    } finally {
        Pop-Location
    }
}

# 再起動
function Restart-NarouServers {
    param(
        [switch]$ForceKill
    )

    Write-ColorOutput "=== サーバー再起動 ===" -ForegroundColor Cyan
    Write-Output ""

    # プロセスを終了
    $result = Stop-NarouProcesses -ForceKill:$ForceKill

    if (-not $result) {
        # ユーザーがキャンセルした場合
        return $false
    }

    Write-Output ""
    Start-Sleep -Seconds 2

    # サーバーを起動
    Start-NarouServers
}

# ヘルプ表示
function Show-Help {
    Write-ColorOutput "narou-mod プロセス管理スクリプト (Windows版)" -ForegroundColor Cyan
    Write-Output ""
    Write-ColorOutput "使い方:" -ForegroundColor Green
    Write-Output "  .\bin\process_control.ps1 [オプション]"
    Write-Output ""
    Write-ColorOutput "オプション:" -ForegroundColor Green
    Write-Output "  -List      実行中のプロセス一覧と詳細を表示"
    Write-Output "  -Restart   すべてのプロセスを終了して再起動"
    Write-Output "  -Kill      すべてのプロセスを終了"
    Write-Output "  -Force     -Restart または -Kill 実行時に確認を省略"
    Write-Output "  -Help      このヘルプを表示"
    Write-Output ""
    Write-ColorOutput "使用例:" -ForegroundColor Green
    Write-Output "  .\bin\process_control.ps1 -List               # プロセス一覧を表示"
    Write-Output "  .\bin\process_control.ps1 -Restart            # 確認後に再起動"
    Write-Output "  .\bin\process_control.ps1 -Restart -Force     # 確認なしで即座に再起動"
    Write-Output "  .\bin\process_control.ps1 -Kill               # 確認後に全プロセス終了"
    Write-Output "  .\bin\process_control.ps1 -Kill -Force        # 確認なしで即座に全プロセス終了"
    Write-Output ""
    Write-ColorOutput "プロセスの役割:" -ForegroundColor Green
    Write-Output "  Backend Server   - Ruby (Sinatra) API サーバー (ポート: 5678)"
    Write-Output "  Frontend Server  - Astro + Svelte 開発サーバー (ポート: 4321)"
    Write-Output "  WebSocket Server - リアルタイム更新通知 (ポート: 5679)"
    Write-Output ""
}

# メイン処理
if ($Help) {
    Show-Help
    exit 0
}

if ($List) {
    Show-ProcessList
    exit 0
}

if ($Kill) {
    $result = Stop-NarouProcesses -ForceKill:$Force
    if ($result) { exit 0 } else { exit 1 }
}

if ($Restart) {
    $result = Restart-NarouServers -ForceKill:$Force
    if ($result) { exit 0 } else { exit 1 }
}

# アクションが指定されていない場合はヘルプを表示
Show-Help
exit 0
