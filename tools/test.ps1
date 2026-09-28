# Runs the complete automated MAWLINGS check and prints one compact line per test.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 [-Only smoke,boss] [-SkipPlaythrough] [-TimeoutSec 180]
# Each Godot run has its own timeout: a headless script with a runtime error can
# hang, and only that one process is killed (never other Godot instances).
param(
	[string[]]$Only = @(),
	[switch]$SkipPlaythrough,
	[int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Continue'
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$tests = @('encoding','smoke','joystick','run_model','hunt_flow','survival','evolution','arena','skitter','leaper','model_budget','boss','motion','per_unit_hits','leader','objectives','horde','flood','surge','eruptions','apex','apex_run','migration','apex_toad','toad_run','apex_sandworm','sandgrub','desert_run','telegraph_shapes','abilities','ability_run','minimap','onboarding','drama','meta','attack_forms','forms_extra','run_config','menu','sfx','sfx_hooks','music','corpse_visuals','loot_magnet','chronicle','map_bounds','map_layout','water','progression_stats','arsenal','chests','powerups','shrines','vfx')
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })
if ($Only.Count -gt 0) { $tests = $tests | Where-Object { $Only -contains $_ } }

function Invoke-Godot([string[]]$GodotArgs, [int]$Limit = 0) {
	if ($Limit -le 0) { $Limit = $TimeoutSec }
	$outFile = [IO.Path]::GetTempFileName()
	$errFile = [IO.Path]::GetTempFileName()
	$quoted = $GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
	$process = Start-Process -FilePath $godotExe -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
	$null = $process.Handle  # keeps ExitCode readable after exit
	$timedOut = -not $process.WaitForExit($Limit * 1000)
	if ($timedOut) {
		try { $process.Kill() } catch {}
		$process.WaitForExit()
	}
	$text = (Get-Content $outFile -Raw -Encoding UTF8) + "`n" + (Get-Content $errFile -Raw -Encoding UTF8)
	Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
	return @{ Code = $(if ($timedOut) { -1 } else { $process.ExitCode }); Out = $text; TimedOut = $timedOut }
}

function Report([string]$Name, $Run, [string]$Pattern) {
	$errors = ($Run.Out -split "`n" | Where-Object { $_ -cmatch '(^|\s)(SCRIPT )?ERROR:|Parse Error' }) -join "`n"
	if ($Run.TimedOut) {
		Write-Host "FAIL $Name (Zeitlimit $TimeoutSec s ueberschritten, Prozess beendet)"
		Write-Host (($Run.Out.Trim() -split "`n") | Select-Object -Last 12 | Out-String)
		return $false
	}
	if ($Run.Code -ne 0 -or $errors) {
		Write-Host "FAIL $Name (exit $($Run.Code))"
		Write-Host (($Run.Out.Trim() -split "`n") | Select-Object -Last 15 | Out-String)
		return $false
	}
	$lines = ($Run.Out.Trim() -split "`n") | Where-Object { $_.Trim() -ne '' }
	# Prefer a PASS line as summary; warnings on stderr may come last.
	$pass = $lines | Where-Object { $_ -match "PASS|passed|bestanden" } | Select-Object -Last 1
	$summary = if ($Pattern) { ($lines | Where-Object { $_ -match $Pattern }) -join ' | ' } elseif ($pass) { $pass } else { ($lines | Select-Object -Last 1) }
	Write-Host ("ok   $Name :: " + "$summary".Trim())
	return $true
}

& $godotExe --headless --editor --import --path $projectDir --quit *> $null
$failed = @()
foreach ($testName in $tests) {
	$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--path', $projectDir, '--script', "res://tests/$testName.gd")
	if (-not (Report $testName $run '')) { $failed += $testName }
}
if (-not $SkipPlaythrough -and $Only.Count -eq 0) {
	$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60', '--path', $projectDir, '--script', 'res://tests/endless_playthrough.gd')
	if (-not (Report 'endless_playthrough' $run 'PLAYTEST')) { $failed += 'endless_playthrough' }
	# Balance regression: 3 specs x 5 seeded bot runs against the difficulty target
	# curve (~3-4 min on the path map), so it gets three times the per-test limit.
	$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60', '--path', $projectDir, '--script', 'res://tests/balance_sim.gd', '--', 'regress') ($TimeoutSec * 3)
	if (-not (Report 'balance_regress' $run 'BALANCE|PASS')) { $failed += 'balance_regress' }
}
if ($failed.Count -gt 0) {
	Write-Output "RESULT: FAILED -> $($failed -join ', ')"
	exit 1
}
Write-Output 'RESULT: ALL PASS'
exit 0
