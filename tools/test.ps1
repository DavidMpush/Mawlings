# Runs the complete automated MAWLINGS check and prints one compact line per test.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 [-Only smoke,boss] [-SkipPlaythrough]
param(
	[string[]]$Only = @(),
	[switch]$SkipPlaythrough
)
$ErrorActionPreference = 'Continue'
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$tests = @('smoke','run_model','hunt_flow','survival','evolution','arena','skitter','model_budget','boss','motion')
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })
if ($Only.Count -gt 0) { $tests = $tests | Where-Object { $Only -contains $_ } }

& $godotExe --headless --editor --import --path $projectDir --quit *> $null
$failed = @()
foreach ($testName in $tests) {
	$out = & $godotExe --headless --path $projectDir --script "res://tests/$testName.gd" 2>&1 | Out-String
	$code = $LASTEXITCODE
	$errors = ($out -split "`n" | Where-Object { $_ -match 'ERROR|SCRIPT ERROR|Parse Error' }) -join "`n"
	if ($code -ne 0 -or $errors) {
		$failed += $testName
		Write-Output "FAIL $testName (exit $code)"
		Write-Output ($out.Trim() -split "`n" | Select-Object -Last 15 | Out-String)
	} else {
		Write-Output ("ok   $testName :: " + (($out.Trim() -split "`n") | Select-Object -Last 1).Trim())
	}
}
if (-not $SkipPlaythrough -and $Only.Count -eq 0) {
	$out = & $godotExe --headless --fixed-fps 60 --path $projectDir --script 'res://tests/endless_playthrough.gd' 2>&1 | Out-String
	$code = $LASTEXITCODE
	if ($code -ne 0) {
		$failed += 'endless_playthrough'
		Write-Output "FAIL endless_playthrough (exit $code)"
		Write-Output ($out.Trim() -split "`n" | Select-Object -Last 15 | Out-String)
	} else {
		Write-Output ("ok   endless_playthrough :: " + (($out.Trim() -split "`n") | Where-Object { $_ -match 'PLAYTEST' } | Select-Object -Last 1))
	}
}
if ($failed.Count -gt 0) {
	Write-Output "RESULT: FAILED -> $($failed -join ', ')"
	exit 1
}
Write-Output 'RESULT: ALL PASS'
exit 0
