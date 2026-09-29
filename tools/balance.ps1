# Runs the MAWLINGS balance matrix (tests/balance_sim.gd) in parallel and prints
# median/min/max survival per group plus the per-difficulty target check.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/balance.ps1
#          [-Strains glutmaw,sporling,...] [-Difficulties 0,1,2] [-Seeds 1,2,3]
#          [-Strategies smart,greedy,attack_first] [-Limit 1500] [-Parallel 6] [-Out balance.log]
#          [-From balance.log]  (re-evaluates a saved log without running Godot)
param(
	# Etappe 32: all six strains, seeds 1-3, the "smart" build bot, limit 25 min.
	[string[]]$Strains = @('glutmaw', 'sporling', 'knochenkiefer', 'flinkzahn', 'aetzmaul', 'nachtmaul'),
	[string[]]$Difficulties = @('0', '1', '2'),
	[string[]]$Seeds = @('1', '2', '3'),
	[string[]]$Strategies = @('smart'),
	[double]$Limit = 1500,
	[int]$Parallel = 6,
	[string]$Out = '',
	[string]$From = ''
)
$ErrorActionPreference = 'Stop'
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$split = { param($list) @($list | ForEach-Object { "$_" -split ',' } | Where-Object { $_ }) }
$Strains = & $split $Strains
$Strategies = & $split $Strategies
$Difficulties = @(& $split $Difficulties | ForEach-Object { [int]$_ })
$Seeds = @(& $split $Seeds | ForEach-Object { [int]$_ })
# Balance targets (stages/32_balance_worlds.md, world model since stage 26-31; median
# over 6 strains x 3 seeds, strategy smart, limit 25 min) per difficulty:
#   death median in s, median world reached (arrivals + 1), max share of runs that die
#   at the first endboss. Wild 11-17 min / world 3 / <= 25 %, Brutal 8-12 min /
#   world 2-3 / <= 30 %, Apex 5-9 min / world 2 / <= 35 %.
# Every difficulty: at most 1 run survives the limit, strain spread (max/min of the
# strain medians) <= 50 %, endboss fights (won, median) 45-90 s.
# The old stage 08/09/21 bands (Wild 390-510 s, growth 1:00/2:00/flood) belong to
# the pre-world model; growth and early deaths are still printed as information.
$targets = @{
	0 = @{ death = @(660, 1020); world = @(3, 3); firstApex = 0.25 }
	1 = @{ death = @(480, 720); world = @(2, 3); firstApex = 0.30 }
	2 = @{ death = @(300, 540); world = @(2, 2); firstApex = 0.35 }
}
$maxTimeouts = 1
$maxSpread = 0.50
$fightBand = @(45, 90)

$started = Get-Date
$lines = New-Object System.Collections.Generic.List[string]
if ($From) {
	foreach ($l in (Get-Content $From -Encoding utf8)) { if ($l -match '^BALANCE ') { $lines.Add($l.Trim()) } }
} else {
	$jobs = New-Object System.Collections.Generic.List[object]
	foreach ($d in $Difficulties) { foreach ($s in $Strains) { foreach ($st in $Strategies) { foreach ($seed in $Seeds) {
		$jobs.Add(@{ strain = $s; diff = $d; strategy = $st; seed = $seed })
	} } } }
	$running = @()
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
}

function Parse($line) {
	$h = @{}
	foreach ($m in [regex]::Matches($line, '(\w+)=(\S+)')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value }
	$h.survived = [double]$h.survived; $h.diff = [int]$h.diff; $h.peak = [int]$h.peak; $h.kills = [int]$h.kills
	$h.pop120 = if ($h.ContainsKey('pop120')) { [int]$h.pop120 } else { -1 }
	$h.pop60 = if ($h.ContainsKey('pop60')) { [int]$h.pop60 } else { -1 }
	$h.popflood = if ($h.ContainsKey('popflood')) { [int]$h.popflood } else { -1 }
	$h.swaps = if ($h.ContainsKey('swaps')) { [int]$h.swaps } else { 0 }
	$h.flood = if ($h.ContainsKey('flood')) { [double]$h.flood } else { 0 }
	# Etappe 32: world reached (arrivals + 1), death at the first endboss, endboss fights.
	$h.world = if ($h.ContainsKey('world')) { [int]$h.world } elseif ($h.ContainsKey('migrations')) { [int]$h.migrations + 1 } else { 1 }
	$h.firstapex = if ($h.ContainsKey('firstapex')) { [int]$h.firstapex } else { 0 }
	$h.timeout = $h.extinct -ne 'true'
	$won = @(); $open = @()
	if ($h.ContainsKey('fights') -and $h.fights -ne '-') {
		foreach ($f in ($h.fights -split ',')) {
			if ($f -match '^(moos|worm|toad):(\d+)(\+)?') {
				if ($Matches[3]) { $open += [double]$Matches[2] } else { $won += [double]$Matches[2] }
			}
		}
	}
	$h.apexWon = $won
	$h.apexOpen = $open
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
	$fights = @($group | ForEach-Object { $_.apexWon })
	'{0,-30} n={1,2}  median={2,5:N0}s  min={3,5:N0}s  max={4,5:N0}s  world~{5,3}  apex1={6,2}  peak~{7,4}  pop2:00~{8,3}  apexfight~{9,3}s({10})  kills~{11,5}  {12}' -f $label, $t.Count, (Median $t), ($t | Measure-Object -Minimum).Minimum, ($t | Measure-Object -Maximum).Maximum, (Median @($group | ForEach-Object { $_.world })), @($group | Where-Object { $_.firstapex -eq 1 }).Count, (Median @($group | ForEach-Object { $_.peak })), (Median @($group | ForEach-Object { $_.pop120 })), (Median $fights), $fights.Count, (Median @($group | ForEach-Object { $_.kills })), $causes
}
Write-Output ''
if (@($rows | Group-Object strategy).Count -gt 1) {
	Write-Output '--- per strain / difficulty / strategy'
	foreach ($g in ($rows | Group-Object diff, strain, strategy | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
	Write-Output '--- per difficulty / strategy'
	foreach ($g in ($rows | Group-Object diff, strategy | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
}
Write-Output '--- per difficulty / strain'
foreach ($g in ($rows | Group-Object diff, strain | Sort-Object Name)) { Write-Output (Summary $g.Group $g.Name) }
Write-Output '--- per difficulty (target check, stages/32_balance_worlds.md)'
$ok = $true
foreach ($g in ($rows | Group-Object diff | Sort-Object Name)) {
	$d = [int]$g.Name
	$tg = $targets[$d]
	$n = [math]::Max(1, $g.Count)
	$med = Median @($g.Group | ForEach-Object { $_.survived })
	$world = Median @($g.Group | ForEach-Object { $_.world })
	$apexShare = @($g.Group | Where-Object { $_.firstapex -eq 1 }).Count / $n
	$timeouts = @($g.Group | Where-Object { $_.timeout }).Count
	$meds = @($g.Group | Group-Object strain | ForEach-Object { Median @($_.Group | ForEach-Object { $_.survived }) })
	$spread = 0
	if ($meds.Count -gt 1) { $spread = (($meds | Measure-Object -Maximum).Maximum / [math]::Max(1, ($meds | Measure-Object -Minimum).Minimum)) - 1 }
	$fights = @($g.Group | ForEach-Object { $_.apexWon })
	$fightMed = Median $fights
	$firstFights = @($g.Group | Where-Object { $_.apexWon.Count -gt 0 } | ForEach-Object { $_.apexWon[0] })
	$checks = [ordered]@{
		('death {0:N0}s ({1}-{2})' -f $med, $tg.death[0], $tg.death[1]) = ($med -ge $tg.death[0] -and $med -le $tg.death[1])
		('world {0} ({1}-{2})' -f $world, $tg.world[0], $tg.world[1]) = ($world -ge $tg.world[0] -and $world -le $tg.world[1])
		('first-endboss deaths {0:P0} (max {1:P0})' -f $apexShare, $tg.firstApex) = ($apexShare -le $tg.firstApex + 0.0001)
		('timeouts {0} (max {1})' -f $timeouts, $maxTimeouts) = ($timeouts -le $maxTimeouts)
		('spread {0:P0} (max {1:P0})' -f $spread, $maxSpread) = ($spread -le $maxSpread)
		('endboss fight {0:N0}s n={1} ({2}-{3})' -f $fightMed, $fights.Count, $fightBand[0], $fightBand[1]) = ($fights.Count -gt 0 -and $fightMed -ge $fightBand[0] -and $fightMed -le $fightBand[1])
	}
	$hit = -not ($checks.Values -contains $false)
	if (-not $hit) { $ok = $false }
	Write-Output ((Summary $g.Group "diff=$d") + $(if ($hit) { '  OK' } else { '  MISS' }))
	Write-Output ('    ' + (($checks.Keys | ForEach-Object { '{0} {1}' -f $_, $(if ($checks[$_]) { 'ok' } else { 'MISS' }) }) -join ' | '))
	Write-Output ('    strain medians: ' + (($g.Group | Group-Object strain | ForEach-Object { '{0} {1:N0}s/w{2}' -f $_.Name, (Median @($_.Group | ForEach-Object { $_.survived })), (Median @($_.Group | ForEach-Object { $_.world })) }) -join ', '))
	# Information only (pre-world targets): growth, early deaths, first endboss fight.
	$early = @($g.Group | Where-Object { $_.survived -lt 120 }).Count / $n
	Write-Output ('    info: pop1:00~{0} pop2:00~{1} popFlut~{2} under2:00={3:P0} first-endboss fight (won) ~{4:N0}s n={5} worlds={6}' -f (Median @($g.Group | ForEach-Object { $_.pop60 })), (Median @($g.Group | ForEach-Object { $_.pop120 })), (Median @($g.Group | ForEach-Object { $_.popflood })), $early, (Median $firstFights), $firstFights.Count, (($g.Group | ForEach-Object { $_.world } | Sort-Object) -join ','))
}
Write-Output ('{0} runs in {1:N0} s -> {2}' -f $rows.Count, ((Get-Date) - $started).TotalSeconds, $(if ($ok) { 'TARGETS MET' } else { 'TARGETS MISSED' }))
