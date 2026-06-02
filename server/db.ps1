$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$DataDir = Join-Path $RepoRoot "data"
$DbConfigPath = Join-Path $DataDir "db.env.ps1"
$SchemaPath = Join-Path $PSScriptRoot "sql\schema.sql"

function Load-DbConfig {
    if (Test-Path $DbConfigPath) {
        . $DbConfigPath
    }
    if (-not $env:PGHOST) { $env:PGHOST = "localhost" }
    if (-not $env:PGPORT) { $env:PGPORT = "5432" }
    if (-not $env:PGDATABASE) { $env:PGDATABASE = "forhome" }
    if (-not $env:PGUSER) { $env:PGUSER = "postgres" }
    $env:PGCLIENTENCODING = "UTF8"
}

function Assert-Psql {
    $cmd = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "PostgreSQL client psql was not found. Install PostgreSQL and add its bin directory to PATH."
    }
    return $cmd.Source
}

function Sql-Literal($Value) {
    if ($null -eq $Value) { return "NULL" }
    if ($Value -is [bool]) { if ($Value) { return "TRUE" } else { return "FALSE" } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return [string]$Value }
    $s = [string]$Value
    return "'" + $s.Replace("'", "''") + "'"
}

function Sql-Ident($Value) {
    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function Sql-Bool($Value) {
    if ($Value -eq $true) { return "TRUE" }
    return "FALSE"
}

function Sql-Int($Value, $Default = 0) {
    if ($null -eq $Value -or $Value -eq "") { return [string]$Default }
    return [string][int]$Value
}

function Sql-Long($Value) {
    if ($null -eq $Value -or $Value -eq "") { return "NULL" }
    return [string][int64]$Value
}

function Sql-TimestampExpr($Milliseconds) {
    if ($null -eq $Milliseconds -or $Milliseconds -eq "") { return "now()" }
    $value = ([double]$Milliseconds).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    return "to_timestamp(($value) / 1000.0)"
}

function Invoke-PsqlText($Sql, $Database = $env:PGDATABASE) {
    Load-DbConfig
    $psql = Assert-Psql
    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, $Sql, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $output = & $psql -X -v ON_ERROR_STOP=1 -q -d $Database -f $tmp 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join "`n")
        }
        return $output
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PsqlScalar($Sql, $Database = $env:PGDATABASE) {
    Load-DbConfig
    $psql = Assert-Psql
    $output = & $psql -X -q -t -A -v ON_ERROR_STOP=1 -d $Database -c $Sql 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join "`n")
    }
    return (($output -join "`n").Trim())
}

function Invoke-PsqlCsv($Query) {
    Load-DbConfig
    $psql = Assert-Psql
    $outFile = [System.IO.Path]::GetTempFileName()
    $copy = "\copy ($Query) TO STDOUT WITH CSV HEADER"
    try {
        $output = & $psql -X -q -v ON_ERROR_STOP=1 -P footer=off -d $env:PGDATABASE -c $copy -o $outFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ($output -join "`n")
        }
        $content = Get-Content -Raw -Encoding UTF8 $outFile
        if ([string]::IsNullOrWhiteSpace($content)) { return @() }
        return @($content | ConvertFrom-Csv)
    } finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-PostgresDatabase {
    Load-DbConfig
    $psql = Assert-Psql
    $dbName = $env:PGDATABASE
    $test = & $psql -X -q -t -A -d $dbName -c "SELECT 1" 2>&1
    if ($LASTEXITCODE -eq 0 -and (($test -join "").Trim()) -eq "1") { return }

    $exists = & $psql -X -q -t -A -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$($dbName.Replace("'", "''"))'" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot connect to PostgreSQL. Check data\db.env.ps1 and PostgreSQL service status. $($exists -join "`n")"
    }
    if ((($exists -join "").Trim()) -ne "1") {
        $create = "CREATE DATABASE $(Sql-Ident $dbName) ENCODING 'UTF8';"
        Invoke-PsqlText $create "postgres" | Out-Null
    }
}

function Initialize-Database {
    Load-DbConfig
    Ensure-PostgresDatabase
    if (-not (Test-Path $SchemaPath)) { throw "Schema file not found: $SchemaPath" }
    Invoke-PsqlText (Get-Content -Raw -Encoding UTF8 $SchemaPath) | Out-Null
}

function Convert-CsvBool($Value) {
    return @("t", "true", "1", "TRUE", "True") -contains [string]$Value
}

function Convert-CsvInt($Value) {
    if ($null -eq $Value -or $Value -eq "") { return 0 }
    return [int]$Value
}

function Convert-CsvLong($Value) {
    if ($null -eq $Value -or $Value -eq "") { return 0 }
    return [int64]$Value
}

function Get-DbState {
    $meta = Invoke-PsqlCsv "SELECT version, updated_at FROM app_version WHERE singleton = TRUE"
    $settingsRows = Invoke-PsqlCsv "SELECT vacation_threshold, week_starts_on FROM settings WHERE singleton = TRUE"
    $memberRows = Invoke-PsqlCsv "SELECT id, name, emoji, restricted, color, xp, total_fatigue, completed_tasks, stickers, on_vacation FROM members ORDER BY sort_order, created_at, id"
    $accountRows = Invoke-PsqlCsv "SELECT id, password, member_id, is_admin FROM accounts ORDER BY id"
    $choreRows = Invoke-PsqlCsv "SELECT id, name, emoji, fatigue, xp, category FROM chores ORDER BY sort_order, created_at, id"
    $historyRows = Invoke-PsqlCsv "SELECT id, member_id, chore_id, chore_name, chore_emoji, category, fatigue_added, xp_earned, completed_at_ms FROM history ORDER BY completed_at_ms, id"
    $messageRows = Invoke-PsqlCsv "SELECT id, from_member_id, to_member_id, text, sent_at_ms FROM messages ORDER BY sent_at_ms, id"
    $badgeRows = Invoke-PsqlCsv "SELECT id, member_id, badge_id, name, emoji, earned_at_ms FROM badge_history ORDER BY earned_at_ms, id"
    $memberBadgeRows = Invoke-PsqlCsv "SELECT member_id, badge_id FROM member_badges ORDER BY earned_at_ms, badge_id"

    $earnedByMember = @{}
    foreach ($row in $memberBadgeRows) {
        if (-not $earnedByMember.ContainsKey($row.member_id)) { $earnedByMember[$row.member_id] = @() }
        $earnedByMember[$row.member_id] += $row.badge_id
    }

    $settings = if ($settingsRows.Count) {
        @{
            vacationThreshold = Convert-CsvInt $settingsRows[0].vacation_threshold
            weekStartsOn = Convert-CsvInt $settingsRows[0].week_starts_on
        }
    } else {
        @{ vacationThreshold = 25; weekStartsOn = 1 }
    }

    [pscustomobject]@{
        version = if ($meta.Count) { Convert-CsvLong $meta[0].version } else { 0 }
        updatedAt = if ($meta.Count) { $meta[0].updated_at } else { [DateTime]::UtcNow.ToString("o") }
        settings = $settings
        members = @($memberRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                name = $_.name
                emoji = $_.emoji
                restricted = Convert-CsvBool $_.restricted
                color = $_.color
                xp = Convert-CsvInt $_.xp
                totalFatigue = Convert-CsvInt $_.total_fatigue
                completedTasks = Convert-CsvInt $_.completed_tasks
                stickers = Convert-CsvInt $_.stickers
                onVacation = Convert-CsvBool $_.on_vacation
                earnedBadges = if ($earnedByMember.ContainsKey($_.id)) { @($earnedByMember[$_.id]) } else { @() }
            }
        })
        accounts = @($accountRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                password = $_.password
                memberId = if ($_.member_id) { $_.member_id } else { $null }
                isAdmin = Convert-CsvBool $_.is_admin
            }
        })
        chores = @($choreRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                name = $_.name
                emoji = $_.emoji
                fatigue = Convert-CsvInt $_.fatigue
                xp = Convert-CsvInt $_.xp
                category = $_.category
            }
        })
        history = @($historyRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                memberId = $_.member_id
                choreId = $_.chore_id
                choreName = $_.chore_name
                choreEmoji = $_.chore_emoji
                category = $_.category
                fatigueAdded = Convert-CsvInt $_.fatigue_added
                xpEarned = Convert-CsvInt $_.xp_earned
                timestamp = Convert-CsvLong $_.completed_at_ms
            }
        })
        messages = @($messageRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                fromId = $_.from_member_id
                toId = if ($_.to_member_id) { $_.to_member_id } else { $null }
                text = $_.text
                timestamp = Convert-CsvLong $_.sent_at_ms
            }
        })
        badgeHistory = @($badgeRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                memberId = $_.member_id
                badgeId = $_.badge_id
                name = $_.name
                emoji = $_.emoji
                timestamp = Convert-CsvLong $_.earned_at_ms
            }
        })
    }
}

function Set-DbState($JsonBody) {
    $state = $JsonBody | ConvertFrom-Json
    $settings = $state.settings
    $sql = New-Object System.Text.StringBuilder
    [void]$sql.AppendLine("BEGIN;")
    [void]$sql.AppendLine("DELETE FROM member_badges;")
    [void]$sql.AppendLine("DELETE FROM badge_history;")
    [void]$sql.AppendLine("DELETE FROM messages;")
    [void]$sql.AppendLine("DELETE FROM history;")
    [void]$sql.AppendLine("DELETE FROM accounts;")
    [void]$sql.AppendLine("DELETE FROM chores;")
    [void]$sql.AppendLine("DELETE FROM members;")
    [void]$sql.AppendLine("DELETE FROM settings;")
    [void]$sql.AppendLine("INSERT INTO settings (singleton, vacation_threshold, week_starts_on) VALUES (TRUE, $(Sql-Int $settings.vacationThreshold 25), $(Sql-Int $settings.weekStartsOn 1));")

    $sort = 0
    foreach ($m in @($state.members)) {
        $sort += 1
        [void]$sql.AppendLine("INSERT INTO members (id, name, emoji, restricted, color, xp, total_fatigue, completed_tasks, stickers, on_vacation, sort_order) VALUES ($(Sql-Literal $m.id), $(Sql-Literal $m.name), $(Sql-Literal $m.emoji), $(Sql-Bool $m.restricted), $(Sql-Literal $m.color), $(Sql-Int $m.xp), $(Sql-Int $m.totalFatigue), $(Sql-Int $m.completedTasks), $(Sql-Int $m.stickers), $(Sql-Bool $m.onVacation), $sort);")
        foreach ($badgeId in @($m.earnedBadges)) {
            [void]$sql.AppendLine("INSERT INTO member_badges (member_id, badge_id, earned_at_ms, earned_at) VALUES ($(Sql-Literal $m.id), $(Sql-Literal $badgeId), NULL, now()) ON CONFLICT DO NOTHING;")
        }
    }

    foreach ($a in @($state.accounts)) {
        [void]$sql.AppendLine("INSERT INTO accounts (id, password, member_id, is_admin) VALUES ($(Sql-Literal $a.id), $(Sql-Literal $a.password), $(Sql-Literal $a.memberId), $(Sql-Bool $a.isAdmin));")
    }

    $sort = 0
    foreach ($c in @($state.chores)) {
        $sort += 1
        [void]$sql.AppendLine("INSERT INTO chores (id, name, emoji, fatigue, xp, category, sort_order) VALUES ($(Sql-Literal $c.id), $(Sql-Literal $c.name), $(Sql-Literal $c.emoji), $(Sql-Int $c.fatigue), $(Sql-Int $c.xp), $(Sql-Literal $c.category), $sort);")
    }

    foreach ($h in @($state.history)) {
        $ms = Sql-Long $h.timestamp
        [void]$sql.AppendLine("INSERT INTO history (id, member_id, chore_id, chore_name, chore_emoji, category, fatigue_added, xp_earned, completed_at_ms, completed_at) VALUES ($(Sql-Literal $h.id), $(Sql-Literal $h.memberId), $(Sql-Literal $h.choreId), $(Sql-Literal $h.choreName), $(Sql-Literal $h.choreEmoji), $(Sql-Literal $h.category), $(Sql-Int $h.fatigueAdded), $(Sql-Int $h.xpEarned), $ms, $(Sql-TimestampExpr $h.timestamp));")
    }

    foreach ($msg in @($state.messages)) {
        $ms = Sql-Long $msg.timestamp
        [void]$sql.AppendLine("INSERT INTO messages (id, from_member_id, to_member_id, text, sent_at_ms, sent_at) VALUES ($(Sql-Literal $msg.id), $(Sql-Literal $msg.fromId), $(Sql-Literal $msg.toId), $(Sql-Literal $msg.text), $ms, $(Sql-TimestampExpr $msg.timestamp));")
    }

    foreach ($b in @($state.badgeHistory)) {
        $ms = Sql-Long $b.timestamp
        [void]$sql.AppendLine("INSERT INTO badge_history (id, member_id, badge_id, name, emoji, earned_at_ms, earned_at) VALUES ($(Sql-Literal $b.id), $(Sql-Literal $b.memberId), $(Sql-Literal $b.badgeId), $(Sql-Literal $b.name), $(Sql-Literal $b.emoji), $ms, $(Sql-TimestampExpr $b.timestamp));")
    }

    [void]$sql.AppendLine("INSERT INTO app_version (singleton, version, updated_at) VALUES (TRUE, 1, now()) ON CONFLICT (singleton) DO UPDATE SET version = app_version.version + 1, updated_at = now();")
    [void]$sql.AppendLine("COMMIT;")
    Invoke-PsqlText $sql.ToString() | Out-Null
    return Get-DbState
}
