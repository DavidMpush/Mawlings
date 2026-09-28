# Runs the MAWLINGS balance matrix (tests/balance_sim.gd) in parallel and prints
# median/min/max survival per group plus the per-difficulty target check.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/balance.ps1
#          [-Strains glutmaw,sporling,...] [-Difficulties 0,1,2] [-Seeds 1,2,3,4,5]
#          [-Strategies greedy,attack_first] [-Limit 900] [-Parallel 6] [-Out balance.log]
param(
	# Etappe 21: all six strains and five seeds by default (spread <= 40 % per difficulty).
	[string[]]$Strains = @('glutmaw', 'sporling', 'knochenkiefer', 'flinkzahn', 'aetzmaul', 'nachtmaul'),
	[string[]]$Difficulties = @('0', '1', '2'),
	[string[]]$Seeds = @('1', '2', '3', '4', '5'),
	[string[]]$Strategies = @('greedy', 'attack_first'),
	[double]$Limit = 900,
	[int]$Parallel = 6,
	[string]$Out = ''
)
$ErrorActionPreference = 'Stop'
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$split = { param($list) @($list | ForEach-Object { "$_" -split ',' } | Where-Object { $_ }) }
$Strains = & $split $Strains
$Strategies = & $split $Strategies
$Difficulties = @(& $split $Difficulties | ForEach-Object { [int]$_ })
$Seeds = @(& $split $Seeds | ForEach-Object { [int]$_ })
# Targets from stages/08_flood_difficulty.md (median death in seconds): Wild 6:30-8:30
# (every run < 11 min), Brutal 5:00-6:30, Apex 3:30-4:30. Stage 09: with the lone start one
# overlooked ring can end a run early, so Wild allows at most 10 % of runs below 120 s
# (before: every run >= 120 s).
# Stage 09 (lone start) growth curve, Wild median: 1:00 -> 6-14, 2:00 -> 25-55,
# flood start -> 80-160 Mawlings.
$targets = @{ 0 = @(390, 510); 1 = @(300, 390); 2 = @(210, 270) }
$wildMaxSeconds = 660
$wildEarlyShare = 0.10
$wildGrowth = @{ pop60 = @(6, 14); pop120 = @(25, 55); popflood = @(80, 160) }
$maxSpread = 0.40

$jobs = New-Object System.Collections.Generic.List[object]
foreach ($d in $Difficulties) { foreach ($s in $Strains) { foreach ($st in $Strategies) { foreach ($seed in $Seeds) {
	$jobs.Add(@{ strain = $s; diff = $d; strategy = $st; seed = $seed })
} } } }

$started = Get-Date
$running = @()
$lines = New-Object System.Collections.Generic.List[string]
$queue = [System.Collections.Queue]::new($jobs)
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
	while ($running.Count -lt $Parallel -and $queue.Count -gt 0) {
		$job = $queue.Dequeue()
		$info = New-Object System.Diagnostics.ProcessStartInfo
		$info.FileName = $godotExe
		$info.Arguments = "--headless --audio-driver Dummy --fixed-fps 60 --path `"$projectDir`" --script res://tests/balance_sim.gd -- strain=$($job.strain) diff=$($job.diff) seed=$($job.seed) strategy=$($job.strategy) limit=$Limit"
		$info.UseShellExecute = $false
		$info.RedirectStandardOutput = $true
		$info.RedirectStandardError = $true
		$info.CreateNoWindow = $true
		$proc = [System.Diagnostics.Process]::Start($info)
		$running += @{ proc = $proc; out = $proc.StandardOutput.ReadToEndAsync(); err = $proc.StandardError.ReadToEndAsync(); job = $job }
	}
	Start-Sleep -Milliseconds 200
	$still = @()
	foreach ($r in $running) {
		if ($r.proc.HasExited) {
			$found = @($r.out.Result -split "`n" | Where-Object { $_ -match '^BALANCE ' })
			if ($found.Count -eq 0) {
				Write-Output "FAIL $($r.job.strain) diff=$($r.job.diff) seed=$($r.job.seed): no BALANCE line"
				Write-Output (($r.err.Result -split "`n" | Select-Object -Last 5) -join "`n")
			}
			foreach ($l in $found) { $lines.Add($l.Trim()); Write-Output $l.Trim() }
		} else { $still += $r }
	}
	$running = $still
}
if ($Out) { $lines | Set-Content -Encoding utf8 $Out }

function Parse($line) {
	$h = @{}
	foreach ($m in [regex]::Matches($line, '(\w+)=(\S+)')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
	$h.survived = [double]$h.survived; $h.diff = [int]$h.diff; $h.peak = [int]$h.peak; $h.kills = [int]$h.kills
	$h.pop120 = if ($h.ContainsKey('pop120')) { [int]$h.pop120 } else { -1 }
	$h.pop60 = if ($h.ContainsKey('pop60')) { [int]$h.pop60 } else { -1 }
	$h.popflood = if ($h.ContainsKey('popflood')) { [int]$h.popflood } else { -1 }
	$h.swaps = if ($h.ContainsKey('swaps')) { [int]$h.swaps } else { 0 }
	$h.flood = if ($h.ContainsKey('flood')) { [double]$h.flood } else { 0 }
	return [pscustomobject]$h
}
function Median($values) {
	$v = @($values | Sort-Object)
	if ($v.Count -eq 0) { return 0 }
	if ($v.Count % 2) { return $v[[int][math]::Floor($v.Count / 2)] }
	return ($v[$v.Count / 2 - 1] + $v[$v.Count / 2]) / 2
}
$rows = @($lines | ForEach-Object { Parse $_ })
function Summary($group, $label) {
	$t = @($group | ForEach-Object { $_.survived })
	$causes = ($group | Group-Object cause | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)$($_.Count)" }) -join ' '
	'{0,-34} n={1,2}  median={2,6:N0}s  min={3,5:N0}s  max={4,5:N0}s  peak~{5,3}  pop1:00~{6,3}  pop2:00~{7,3}  popFlut~{8,3}  swaps~{9,2}  flood~{10,4:N0}s  kills~{11,4}  {12}' -f $label, $t.Count, (Median $t), ($t | Measure-Object -Minimum).Minimum, ($t | Measure-Object -Maximum).Maximum, (Median @($group | ForEach-Object { $_.peak })), (Median @($group | ForEach-Object { $_.pop60 })), (Median @($group | ForEach-Object { $_.pop120 })), (Median @($group | ForEach-Object { $_.popflood })), (Median @($group | ForEach-Object { $_.swaps })), (Median @($group | ForEach-Object { $_.flood })), (Median @($group | ForEach-Object { $_.kills })), $causes
}
Write-Output ''
Write-Output '--- per strain / difficulty / strategy'
foreach ($g in ($rows | Group-Object diff, strain, strategy | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
Write-Output '--- per difficulty / strain'
foreach ($g in ($rows | Group-Object diff, strain | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
Write-Output '--- per difficulty / strategy'
foreach ($g in ($rows | Group-Object diff, strategy | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
Write-Output '--- per difficulty (target check)'
$ok = $true
foreach ($g in ($rows | Group-Object diff | Sort-Object Name)) {
	$d = [int]$g.Name
	$med = Median @($g.Group | ForEach-Object { $_.survived })
	$min = ($g.Group | Measure-Object survived -Minimum).Minimum
	$range = $targets[$d]
	$max = ($g.Group | Measure-Object survived -Maximum).Maximum
	$growthOk = $true
	$growthText = ''
	if ($d -eq 0) {
		foreach ($key in @('pop60', 'pop120', 'popflood')) {
			$value = Median @($g.Group | ForEach-Object { $_.$key })
			$band = $wildGrowth[$key]
			$inside = $value -ge $band[0] -and $value -le $band[1]
			if (-not $inside) { $growthOk = $false }
			$growthText += ('  {0}={1} ({2}-{3} {4})' -f $key, $value, $band[0], $band[1], $(if ($inside) { 'ok' } else { 'MISS' }))
		}
	}
	$early = @($g.Group | Where-Object { $_.survived -lt 120 }).Count / [math]::Max(1, $g.Count)
	if ($d -eq 0) { $growthText += ('  under2:00={0:P0} (max {1:P0})' -f $early, $wildEarlyShare) }
	# Etappe 21: the strain spread (max/min of the strain medians) is part of the target.
	$meds = @($g.Group | Group-Object strain | ForEach-Object { Median @($_.Group | ForEach-Object { $_.survived }) })
	$spread = 0
	if ($meds.Count -gt 1) { $spread = (($meds | Measure-Object -Maximum).Maximum / [math]::Max(1, ($meds | Measure-Object -Minimum).Minimum)) - 1 }
	$hit = $med -ge $range[0] -and $med -le $range[1] -and $spread -le $maxSpread -and ($d -ne 0 -or ($early -le $wildEarlyShare -and $max -lt $wildMaxSeconds -and $growthOk))
	if (-not $hit) { $ok = $false }
	Write-Output ((Summary $g.Group "diff=$d") + ("  target {0}-{1}s {2}" -f $range[0], $range[1], $(if ($hit) { 'OK' } else { 'MISS' })))
	if ($growthText) { Write-Output ('    growth' + $growthText) }
	if ($meds.Count -gt 1) { Write-Output ('    strain median spread {0:P0} (limit {1:P0})' -f $spread, $maxSpread) }
}
Write-Output ('{0} runs in {1:N0} s -> {2}' -f $rows.Count, ((Get-Date) - $started).TotalSeconds, $(if ($ok) { 'TARGETS MET' } else { 'TARGETS MISSED' }))
