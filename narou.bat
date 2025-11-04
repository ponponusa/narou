@echo off
REM -*- mode: ruby -*-
echo narou コマンドは narou-mod に名称変更されました。narou-mod.bat をご利用ください。
@if exist "narou-mod.bat" (
	call narou-mod.bat %*
) else (
	ruby -e "warn 'narou-mod.bat が見つかりません'; exit 1"
	exit /b 1
)
