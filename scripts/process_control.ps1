#
# Copyright 2025 ponponusa
#
# narou-mod プロセス管理スクリプト (Windows版)
# Usage: .\scripts\process_control.ps1 [-List] [-Restart] [-Kill] [-Force]
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
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# バックエンドプロセスを取得
function Get-BackendProcesses {
    $processes = @()

    # Ruby narou-mod web プロセス
    $rubyProcesses = Get-Process -Name "ruby" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            $cmdLine -match "narou-mod.*web" -or $cmdLine -match "narou\.rb.*web" -or $cmdLine -match "puma"
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
    Write-Host ""

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
                Write-Host ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Backend", "5678", $cmdLine)
            } catch {
                Write-Host ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Backend", "5678", $proc.ProcessName)
            }
        }
        Write-Host ""
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
                Write-Host ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Frontend", "4321", $cmdLine)
            } catch {
                Write-Host ("  {0,-8} {1,-12} {2,-10} {3}" -f $proc.Id, "Frontend", "4321", $proc.ProcessName)
            }
        }
        Write-Host ""
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
            Write-Host ""
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
    Write-Host ""

    # 確認プロンプト
    if (-not $ForceKill) {
        Write-Host "以下のプロセスを終了します:"

        if ($backendProcesses.Count -gt 0) {
            Write-Host ""
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
            Write-Host ""
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

        Write-Host ""
        $response = Read-Host "これらのプロセスを終了しますか? (y/N)"

        if ($response -notmatch "^[Yy]$") {
            Write-ColorOutput "キャンセルしました。" -ForegroundColor Yellow
            return $false
        }
    }

    Write-Host "プロセスを終了中..."

    # バックエンドプロセス終了
    foreach ($proc in $backendProcesses) {
        try {
            Write-Host "  Backend PID $($proc.Id) を終了中..."
            # taskkill で子プロセスも含めて終了
            $null = & taskkill /PID $proc.Id /T /F 2>&1
        } catch {
            Write-Host "  Backend PID $($proc.Id) は既に終了しています"
        }
    }

    # フロントエンドプロセス終了
    foreach ($proc in $frontendProcesses) {
        try {
            Write-Host "  Frontend PID $($proc.Id) を終了中..."
            # taskkill で子プロセスも含めて終了
            $null = & taskkill /PID $proc.Id /T /F 2>&1
        } catch {
            Write-Host "  Frontend PID $($proc.Id) は既に終了しています"
        }
    }

    Start-Sleep -Seconds 1
    Write-ColorOutput "プロセス終了完了。" -ForegroundColor Green
    return $true
}

# サーバーを起動
function Start-NarouServers {
    Write-ColorOutput "=== サーバー起動 ===" -ForegroundColor Cyan
    Write-Host ""

    Push-Location $ProjectRoot

    try {
        # Bootsnap キャッシュをクリア
        Write-Host "Bootsnap キャッシュをクリア中..."
        $bootSnapCache = Join-Path $ProjectRoot "tmp\bootsnap-cache"
        if (Test-Path $bootSnapCache) {
            Remove-Item -Path "$bootSnapCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        # バックエンド起動
        Write-Host ""
        Write-ColorOutput "バックエンドサーバーを起動中..." -ForegroundColor Green

        $backendLogPath = Join-Path $ProjectRoot "backend.log"
        $backendErrorLogPath = Join-Path $ProjectRoot "backend.log.err"

        # Start-Process の -RedirectStandardOutput は bundle exec と相性が悪いので
        # cmd /c を使ってリダイレクトを行う
        $backendProcess = Start-Process -FilePath "cmd" `
            -ArgumentList "/c", "bundle exec ruby bin/narou-mod web --no-browser > `"$backendLogPath`" 2> `"$backendErrorLogPath`"" `
            -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden

        Write-Host "  PID: $($backendProcess.Id)"

        Write-Host "バックエンドの初期化を待機中..."
        Start-Sleep -Seconds 5

        # バックエンドが起動しているか確認 (cmd プロセスは終了するが ruby プロセスが残る)
        # Ruby プロセスを検索
        $rubyProcesses = Get-BackendProcesses
        if ($rubyProcesses.Count -eq 0) {
            Write-ColorOutput "❌ バックエンドサーバーの起動に失敗しました。" -ForegroundColor Red
            Write-Host "ログを確認してください: $backendLogPath"
            if (Test-Path $backendLogPath) {
                Get-Content $backendLogPath -Tail 20
            }
            if (Test-Path $backendErrorLogPath) {
                Write-Host ""
                Write-Host "エラーログ:"
                Get-Content $backendErrorLogPath -Tail 20
            }
            return $false
        }

        $backendPid = $rubyProcesses[0].Id

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
        Write-Host ""
        Write-ColorOutput "フロントエンドサーバーの起動を待機中..." -ForegroundColor Green
        Write-Host "  (バックエンドが自動的にフロントエンドを起動します)"
        Start-Sleep -Seconds 10

        # フロントエンドプロセスを検索
        $frontendProcesses = Get-FrontendProcesses

        # 起動確認
        Write-Host ""
        Write-ColorOutput "=== サーバー状態確認 ===" -ForegroundColor Cyan
        Write-Host ""

        $allOk = $true

        # バックエンド確認 (Ruby プロセスを再検索)
        $rubyProcesses = Get-BackendProcesses
        if ($rubyProcesses.Count -gt 0) {
            Write-ColorOutput "✅ Backend Server" -ForegroundColor Green
            Write-Host "   URL: http://localhost:$backendPort"
            Write-Host "   PID: $($rubyProcesses[0].Id)"
        } else {
            Write-ColorOutput "❌ Backend Server (起動失敗)" -ForegroundColor Red
            $allOk = $false
        }

        # フロントエンド確認
        if ($frontendProcesses.Count -gt 0) {
            Write-ColorOutput "✅ Frontend Server" -ForegroundColor Green
            Write-Host "   URL: http://localhost:4321"
            Write-Host "   PID: $($frontendProcesses[0].Id)"
        } else {
            Write-ColorOutput "❌ Frontend Server (起動失敗)" -ForegroundColor Red
            $allOk = $false
        }

        Write-ColorOutput "✅ WebSocket Server" -ForegroundColor Green
        Write-Host "   Port: $wsPort"

        Write-Host ""

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
    Write-Host ""

    # プロセスを終了
    $result = Stop-NarouProcesses -ForceKill:$ForceKill

    if (-not $result) {
        # ユーザーがキャンセルした場合
        return $false
    }

    Write-Host ""
    Start-Sleep -Seconds 2

    # サーバーを起動
    Start-NarouServers
}

# ヘルプ表示
function Show-Help {
    Write-ColorOutput "narou-mod プロセス管理スクリプト (Windows版)" -ForegroundColor Cyan
    Write-Host ""
    Write-ColorOutput "使い方:" -ForegroundColor Green
    Write-Host "  .\scripts\process_control.ps1 [オプション]"
    Write-Host ""
    Write-ColorOutput "オプション:" -ForegroundColor Green
    Write-Host "  -List      実行中のプロセス一覧と詳細を表示"
    Write-Host "  -Restart   すべてのプロセスを終了して再起動"
    Write-Host "  -Kill      すべてのプロセスを終了"
    Write-Host "  -Force     -Restart または -Kill 実行時に確認を省略"
    Write-Host "  -Help      このヘルプを表示"
    Write-Host ""
    Write-ColorOutput "使用例:" -ForegroundColor Green
    Write-Host "  .\scripts\process_control.ps1 -List               # プロセス一覧を表示"
    Write-Host "  .\scripts\process_control.ps1 -Restart            # 確認後に再起動"
    Write-Host "  .\scripts\process_control.ps1 -Restart -Force     # 確認なしで即座に再起動"
    Write-Host "  .\scripts\process_control.ps1 -Kill               # 確認後に全プロセス終了"
    Write-Host "  .\scripts\process_control.ps1 -Kill -Force        # 確認なしで即座に全プロセス終了"
    Write-Host ""
    Write-ColorOutput "プロセスの役割:" -ForegroundColor Green
    Write-Host "  Backend Server   - Ruby (Sinatra) API サーバー (ポート: 5678)"
    Write-Host "  Frontend Server  - Astro + Svelte 開発サーバー (ポート: 4321)"
    Write-Host "  WebSocket Server - リアルタイム更新通知 (ポート: 5679)"
    Write-Host ""
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
