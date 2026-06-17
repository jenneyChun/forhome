$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$DataDir = Join-Path $RepoRoot "data"
$DbConfigPath = Join-Path $DataDir "db.env.ps1"
$SchemaPath = Join-Path $PSScriptRoot "sql\schema.sql"
$DefaultHouseholdId = "home"
$SessionCookieName = "forhome_session"
$PasswordIterations = 120000

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
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]$Value)
    }
    $s = [string]$Value
    return "'" + $s.Replace("'", "''") + "'"
}

function Sql-Jsonb($Value) {
    if ($null -eq $Value) { return "NULL" }
    return "$(Sql-Literal ($Value | ConvertTo-Json -Depth 30 -Compress))::jsonb"
}

function Sql-Ident($Value) {
    return '"' + ([string]$Value).Replace('"', '""') + '"'
}

function Sql-Bool($Value) {
    if ($Value -eq $true) { return "TRUE" }
    return "FALSE"
}

function Coalesce-Value($Value, $Default) {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $Default }
    return $Value
}

function Fill-RandomBytes([byte[]]$Bytes) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($Bytes)
    } finally {
        $rng.Dispose()
    }
}

function Test-FixedTimeEquals([byte[]]$Left, [byte[]]$Right) {
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if ($Left.Length -ne $Right.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $Left.Length; $i++) {
        $diff = $diff -bor ($Left[$i] -bxor $Right[$i])
    }
    return ($diff -eq 0)
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
        Invoke-PsqlText "CREATE DATABASE $(Sql-Ident $dbName) ENCODING 'UTF8';" "postgres" | Out-Null
    }
}

function Initialize-Database {
    Load-DbConfig
    Ensure-PostgresDatabase
    if (-not (Test-Path $SchemaPath)) { throw "Schema file not found: $SchemaPath" }
    Invoke-PsqlText (Get-Content -Raw -Encoding UTF8 $SchemaPath) | Out-Null
    Ensure-DefaultUsers
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

function Convert-CsvNullableLong($Value) {
    if ($null -eq $Value -or $Value -eq "") { return $null }
    return [int64]$Value
}

function Convert-CsvJson($Value) {
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    return $Value | ConvertFrom-Json
}

function New-DbId($Prefix) {
    $bytes = New-Object byte[] 12
    Fill-RandomBytes $bytes
    $token = [Convert]::ToBase64String($bytes).Replace("+", "").Replace("/", "").Replace("=", "")
    return "$Prefix$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString("x"))$token"
}

function New-RandomToken($Bytes = 32) {
    $data = New-Object byte[] $Bytes
    Fill-RandomBytes $data
    return [Convert]::ToBase64String($data).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Get-Sha256Hex($Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function New-PasswordHash($Password) {
    if ([string]::IsNullOrWhiteSpace([string]$Password)) { throw "Password is required." }
    $salt = New-Object byte[] 16
    Fill-RandomBytes $salt
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new([string]$Password, $salt, $PasswordIterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $hash = $derive.GetBytes(32)
    } finally {
        $derive.Dispose()
    }
    $saltText = [Convert]::ToBase64String($salt)
    $hashText = [Convert]::ToBase64String($hash)
    return ('pbkdf2_sha256${0}${1}${2}' -f $PasswordIterations, $saltText, $hashText)
}

function Test-PasswordHash($Password, $StoredHash) {
    $parts = ([string]$StoredHash).Split('$')
    if ($parts.Length -ne 4 -or $parts[0] -ne "pbkdf2_sha256") { return $false }
    $iterations = [int]$parts[1]
    $salt = [Convert]::FromBase64String($parts[2])
    $expected = [Convert]::FromBase64String($parts[3])
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new([string]$Password, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $actual = $derive.GetBytes($expected.Length)
    } finally {
        $derive.Dispose()
    }
    return Test-FixedTimeEquals $actual $expected
}

function Normalize-Role($Role) {
    $value = ([string]$Role).Trim().ToLowerInvariant()
    switch ($value) {
        "owner" { return "owner" }
        "admin" { return "owner" }
        "hero" { return "hero" }
        "adult" { return "hero" }
        "parent" { return "hero" }
        "guardian" { return "hero" }
        "care_member" { return "care_member" }
        "child" { return "care_member" }
        default { return "care_member" }
    }
}

function Get-UserIdForAccount($AccountId) {
    $clean = ([string]$AccountId).ToLowerInvariant() -replace '[^a-z0-9_-]', '_'
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "user" }
    return "usr_$clean"
}

function Ensure-DefaultUsers {
    $defaults = @(
        @{ accountId = "admin"; password = "admin1234"; name = "Admin"; memberId = $null; isAdmin = $true; role = "owner" },
        @{ accountId = "mom"; password = "mom1234"; name = "Mom"; memberId = "mom"; isAdmin = $false; role = "hero" },
        @{ accountId = "dad"; password = "dad1234"; name = "Dad"; memberId = "dad"; isAdmin = $false; role = "hero" },
        @{ accountId = "son"; password = "son1234"; name = "Son"; memberId = "son"; isAdmin = $false; role = "care_member" }
    )
    $sql = New-Object System.Text.StringBuilder
    [void]$sql.AppendLine("BEGIN;")
    foreach ($d in $defaults) {
        $uid = Get-UserIdForAccount $d.accountId
        $hash = New-PasswordHash $d.password
        [void]$sql.AppendLine("INSERT INTO users (id, account_id, email, password_hash, display_name, is_admin, active) VALUES ($(Sql-Literal $uid), $(Sql-Literal $d.accountId), $(Sql-Literal "$($d.accountId)@forhome.local"), $(Sql-Literal $hash), $(Sql-Literal $d.name), $(Sql-Bool $d.isAdmin), TRUE) ON CONFLICT (account_id) DO NOTHING;")
        if ($d.memberId) {
            [void]$sql.AppendLine("UPDATE household_members SET user_id = $(Sql-Literal $uid), role = $(Sql-Literal $d.role) WHERE household_id = $(Sql-Literal $DefaultHouseholdId) AND id = $(Sql-Literal $d.memberId);")
        } elseif ($d.isAdmin) {
            [void]$sql.AppendLine("UPDATE households SET owner_user_id = COALESCE(owner_user_id, $(Sql-Literal $uid)) WHERE id = $(Sql-Literal $DefaultHouseholdId);")
        }
    }
    [void]$sql.AppendLine("COMMIT;")
    Invoke-PsqlText $sql.ToString() | Out-Null
}

function Get-DbHealth {
    try {
        Initialize-Database
        [pscustomobject]@{ ok = $true; storage = "postgresql"; mode = "api"; database = $env:PGDATABASE }
    } catch {
        [pscustomobject]@{ ok = $false; storage = "postgresql"; mode = "api"; error = "$_" }
    }
}

function Get-DbState($HouseholdId = $DefaultHouseholdId) {
    Initialize-Database
    $hid = Sql-Literal $HouseholdId
    $meta = Invoke-PsqlCsv "SELECT version, updated_at FROM app_version WHERE singleton = TRUE"
    $settingsRows = Invoke-PsqlCsv "SELECT vacation_threshold, week_starts_on FROM settings WHERE household_id = $hid"
    $memberRows = Invoke-PsqlCsv "SELECT id, name, emoji, restricted, role, color, xp, total_fatigue, completed_tasks, stickers, on_vacation FROM household_members WHERE household_id = $hid ORDER BY sort_order, created_at, id"
    $accountRows = Invoke-PsqlCsv "SELECT u.account_id, u.display_name, u.is_admin, hm.id AS member_id FROM users u LEFT JOIN household_members hm ON hm.user_id = u.id AND hm.household_id = $hid WHERE u.active = TRUE ORDER BY u.account_id"
    $choreRows = Invoke-PsqlCsv "SELECT id, name, emoji, fatigue, xp, category FROM chores WHERE household_id = $hid ORDER BY sort_order, created_at, id"
    $historyRows = Invoke-PsqlCsv "SELECT id, member_id, chore_id, chore_name, chore_emoji, category, fatigue_added, xp_earned, verification_status, proof_image, proof_caption, proof_analysis, review_note, completed_at_ms FROM task_entries WHERE household_id = $hid ORDER BY completed_at_ms, id"
    $approvalRows = Invoke-PsqlCsv "SELECT entry_id, reviewer_id, status, reviewed_at_ms, review_note FROM task_approvals WHERE household_id = $hid ORDER BY entry_id, reviewer_id"
    $recipientRows = Invoke-PsqlCsv "SELECT entry_id, member_id FROM task_point_recipients WHERE household_id = $hid ORDER BY entry_id, member_id"
    $messageRows = Invoke-PsqlCsv "SELECT id, from_member_id, to_member_id, text, sent_at_ms FROM messages WHERE household_id = $hid ORDER BY sent_at_ms, id"
    $badgeRows = Invoke-PsqlCsv "SELECT id, member_id, badge_id, name, emoji, earned_at_ms FROM badge_history WHERE household_id = $hid ORDER BY earned_at_ms, id"
    $memberBadgeRows = Invoke-PsqlCsv "SELECT member_id, badge_id FROM member_badges WHERE household_id = $hid ORDER BY earned_at_ms, badge_id"
    $careItemRows = Invoke-PsqlCsv "SELECT id, name, emoji, points, xp, locked FROM care_items WHERE household_id = $hid ORDER BY sort_order, created_at, id"
    $assignmentRows = Invoke-PsqlCsv "SELECT date_key, morning_id, evening_id, updated_at_ms FROM care_assignments WHERE household_id = $hid ORDER BY date_key"
    $careRows = Invoke-PsqlCsv "SELECT id, date_key, member_id, care_item_id, child_member_id, points, xp_earned, start_time, end_time, minutes, note, created_at_ms FROM care_sessions WHERE household_id = $hid ORDER BY date_key, start_time, id"
    $careRecipientRows = Invoke-PsqlCsv "SELECT session_id, member_id FROM care_session_point_recipients WHERE household_id = $hid ORDER BY session_id, member_id"
    $planRows = Invoke-PsqlCsv "SELECT id, from_member_id, to_member_id, chore_id, title, target_date, note, status, request_status, decline_reason, responded_at_ms, created_at_ms FROM tomorrow_plans WHERE household_id = $hid ORDER BY created_at_ms, id"
    $changeRows = Invoke-PsqlCsv "SELECT id, type, before_json::text AS before_json, after_json::text AS after_json, requested_by, requested_at_ms, status, reviewed_at_ms, review_note, applied_at_ms FROM change_requests WHERE household_id = $hid ORDER BY requested_at_ms, id"
    $changeApprovalRows = Invoke-PsqlCsv "SELECT request_id, reviewer_id, status, reviewed_at_ms, review_note FROM change_request_approvals WHERE household_id = $hid ORDER BY request_id, reviewer_id"

    $earnedByMember = @{}
    foreach ($row in $memberBadgeRows) {
        if (-not $earnedByMember.ContainsKey($row.member_id)) { $earnedByMember[$row.member_id] = @() }
        $earnedByMember[$row.member_id] += $row.badge_id
    }

    $approvalsByEntry = @{}
    foreach ($row in $approvalRows) {
        if (-not $approvalsByEntry.ContainsKey($row.entry_id)) { $approvalsByEntry[$row.entry_id] = @() }
        $approvalsByEntry[$row.entry_id] += [pscustomobject]@{
            reviewerId = $row.reviewer_id
            status = $row.status
            reviewedAt = Convert-CsvNullableLong $row.reviewed_at_ms
            reviewNote = $row.review_note
        }
    }

    $recipientsByEntry = @{}
    foreach ($row in $recipientRows) {
        if (-not $recipientsByEntry.ContainsKey($row.entry_id)) { $recipientsByEntry[$row.entry_id] = @() }
        $recipientsByEntry[$row.entry_id] += $row.member_id
    }

    $careRecipientsBySession = @{}
    foreach ($row in $careRecipientRows) {
        if (-not $careRecipientsBySession.ContainsKey($row.session_id)) { $careRecipientsBySession[$row.session_id] = @() }
        $careRecipientsBySession[$row.session_id] += $row.member_id
    }

    $approvalsByChange = @{}
    foreach ($row in $changeApprovalRows) {
        if (-not $approvalsByChange.ContainsKey($row.request_id)) { $approvalsByChange[$row.request_id] = @() }
        $approvalsByChange[$row.request_id] += [pscustomobject]@{
            reviewerId = $row.reviewer_id
            status = $row.status
            reviewedAt = Convert-CsvNullableLong $row.reviewed_at_ms
            reviewNote = $row.review_note
        }
    }

    $settings = if ($settingsRows.Count) {
        @{ vacationThreshold = Convert-CsvInt $settingsRows[0].vacation_threshold; weekStartsOn = Convert-CsvInt $settingsRows[0].week_starts_on }
    } else {
        @{ vacationThreshold = 25; weekStartsOn = 1 }
    }

    [pscustomobject]@{
        version = if ($meta.Count) { Convert-CsvLong $meta[0].version } else { 0 }
        updatedAt = if ($meta.Count) { $meta[0].updated_at } else { [DateTime]::UtcNow.ToString("o") }
        settings = $settings
        members = @($memberRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; name = $_.name; emoji = $_.emoji; restricted = Convert-CsvBool $_.restricted; role = $_.role; color = $_.color
                xp = Convert-CsvInt $_.xp; totalFatigue = Convert-CsvInt $_.total_fatigue; completedTasks = Convert-CsvInt $_.completed_tasks
                stickers = Convert-CsvInt $_.stickers; onVacation = Convert-CsvBool $_.on_vacation
                earnedBadges = if ($earnedByMember.ContainsKey($_.id)) { @($earnedByMember[$_.id]) } else { @() }
            }
        })
        accounts = @($accountRows | ForEach-Object {
            [pscustomobject]@{ id = $_.account_id; password = "********"; memberId = if ($_.member_id) { $_.member_id } else { $null }; isAdmin = Convert-CsvBool $_.is_admin }
        })
        chores = @($choreRows | ForEach-Object {
            [pscustomobject]@{ id = $_.id; name = $_.name; emoji = $_.emoji; fatigue = Convert-CsvInt $_.fatigue; xp = Convert-CsvInt $_.xp; category = $_.category }
        })
        history = @($historyRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; memberId = $_.member_id; choreId = $_.chore_id; choreName = $_.chore_name; choreEmoji = $_.chore_emoji; category = $_.category
                fatigueAdded = Convert-CsvInt $_.fatigue_added; xpEarned = Convert-CsvInt $_.xp_earned; verificationStatus = $_.verification_status
                proofImage = $_.proof_image; proofCaption = $_.proof_caption; proofAnalysis = $_.proof_analysis; reviewNote = $_.review_note
                approvalRequests = if ($approvalsByEntry.ContainsKey($_.id)) { @($approvalsByEntry[$_.id]) } else { @() }
                pointRecipients = if ($recipientsByEntry.ContainsKey($_.id)) { @($recipientsByEntry[$_.id]) } else { @($_.member_id) }
                timestamp = Convert-CsvLong $_.completed_at_ms
            }
        })
        messages = @($messageRows | ForEach-Object {
            [pscustomobject]@{ id = $_.id; fromId = $_.from_member_id; toId = if ($_.to_member_id) { $_.to_member_id } else { $null }; text = $_.text; timestamp = Convert-CsvLong $_.sent_at_ms }
        })
        badgeHistory = @($badgeRows | ForEach-Object {
            [pscustomobject]@{ id = $_.id; memberId = $_.member_id; badgeId = $_.badge_id; name = $_.name; emoji = $_.emoji; timestamp = Convert-CsvLong $_.earned_at_ms }
        })
        careItems = @($careItemRows | ForEach-Object {
            [pscustomobject]@{ id = $_.id; name = $_.name; emoji = $_.emoji; points = Convert-CsvInt $_.points; xp = Convert-CsvInt $_.xp; locked = Convert-CsvBool $_.locked }
        })
        careAssignments = @($assignmentRows | ForEach-Object {
            [pscustomobject]@{ date = $_.date_key; morningId = $_.morning_id; eveningId = $_.evening_id; updatedAt = Convert-CsvNullableLong $_.updated_at_ms }
        })
        careSessions = @($careRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; date = $_.date_key; memberId = $_.member_id; careItemId = $_.care_item_id; childMemberId = $_.child_member_id
                pointRecipients = if ($careRecipientsBySession.ContainsKey($_.id)) { @($careRecipientsBySession[$_.id]) } else { @($_.member_id) }
                points = Convert-CsvInt $_.points; xpEarned = Convert-CsvInt $_.xp_earned; startTime = $_.start_time; endTime = $_.end_time
                minutes = Convert-CsvInt $_.minutes; note = $_.note; createdAt = Convert-CsvLong $_.created_at_ms
            }
        })
        tomorrowPlans = @($planRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; fromId = $_.from_member_id; toId = $_.to_member_id; choreId = $_.chore_id; title = $_.title; targetDate = $_.target_date
                note = $_.note; status = $_.status; requestStatus = $_.request_status; declineReason = $_.decline_reason
                respondedAt = Convert-CsvNullableLong $_.responded_at_ms; createdAt = Convert-CsvLong $_.created_at_ms
            }
        })
        changeRequests = @($changeRows | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; type = $_.type; before = Convert-CsvJson $_.before_json; after = Convert-CsvJson $_.after_json; requestedBy = $_.requested_by
                requestedAt = Convert-CsvLong $_.requested_at_ms; status = $_.status; reviewedAt = Convert-CsvNullableLong $_.reviewed_at_ms
                reviewNote = $_.review_note; appliedAt = Convert-CsvNullableLong $_.applied_at_ms
                approvalRequests = if ($approvalsByChange.ContainsKey($_.id)) { @($approvalsByChange[$_.id]) } else { @() }
            }
        })
    }
}

function Set-DbState($JsonBody, $HouseholdId = $DefaultHouseholdId) {
    Initialize-Database
    $state = if ($JsonBody -is [string]) { $JsonBody | ConvertFrom-Json } else { $JsonBody }
    $hid = Sql-Literal $HouseholdId
    $settings = $state.settings
    $sql = New-Object System.Text.StringBuilder
    [void]$sql.AppendLine("BEGIN;")
    [void]$sql.AppendLine("INSERT INTO households (id, name) VALUES ($hid, 'ForHome') ON CONFLICT (id) DO NOTHING;")
    [void]$sql.AppendLine("DELETE FROM change_request_approvals WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM change_requests WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM tomorrow_plans WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM care_session_point_recipients WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM care_sessions WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM care_assignments WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM care_items WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM member_badges WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM badge_history WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM messages WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM task_point_recipients WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM task_approvals WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM task_entries WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM chores WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM household_members WHERE household_id = $hid;")
    [void]$sql.AppendLine("DELETE FROM settings WHERE household_id = $hid;")
    [void]$sql.AppendLine("INSERT INTO settings (household_id, vacation_threshold, week_starts_on) VALUES ($hid, $(Sql-Int $settings.vacationThreshold 25), $(Sql-Int $settings.weekStartsOn 1));")

    $sort = 0
    foreach ($m in @($state.members)) {
        $sort += 1
        [void]$sql.AppendLine("INSERT INTO household_members (household_id, id, name, emoji, restricted, role, color, xp, total_fatigue, completed_tasks, stickers, on_vacation, sort_order) VALUES ($hid, $(Sql-Literal $m.id), $(Sql-Literal $m.name), $(Sql-Literal $m.emoji), $(Sql-Bool $m.restricted), $(Sql-Literal (Normalize-Role $m.role)), $(Sql-Literal $m.color), $(Sql-Int $m.xp), $(Sql-Int $m.totalFatigue), $(Sql-Int $m.completedTasks), $(Sql-Int $m.stickers), $(Sql-Bool $m.onVacation), $sort);")
        foreach ($badgeId in @($m.earnedBadges)) {
            [void]$sql.AppendLine("INSERT INTO member_badges (household_id, member_id, badge_id, earned_at_ms, earned_at) VALUES ($hid, $(Sql-Literal $m.id), $(Sql-Literal $badgeId), NULL, now()) ON CONFLICT DO NOTHING;")
        }
    }

    foreach ($a in @($state.accounts)) {
        if (-not $a.id) { continue }
        $userId = Get-UserIdForAccount $a.id
        $passwordHash = "__KEEP__"
        if ($a.password -and $a.password -ne "********") { $passwordHash = New-PasswordHash $a.password }
        $displayName = if ($a.memberId) { (@($state.members) | Where-Object { $_.id -eq $a.memberId } | Select-Object -First 1).name } else { $a.id }
        if (-not $displayName) { $displayName = $a.id }
        [void]$sql.AppendLine("INSERT INTO users (id, account_id, email, password_hash, display_name, is_admin, active) VALUES ($(Sql-Literal $userId), $(Sql-Literal $a.id), $(Sql-Literal "$($a.id)@forhome.local"), $(Sql-Literal $passwordHash), $(Sql-Literal $displayName), $(Sql-Bool $a.isAdmin), TRUE) ON CONFLICT (account_id) DO UPDATE SET display_name = EXCLUDED.display_name, email = EXCLUDED.email, is_admin = EXCLUDED.is_admin, active = TRUE, password_hash = CASE WHEN EXCLUDED.password_hash = '__KEEP__' THEN users.password_hash ELSE EXCLUDED.password_hash END, updated_at = now();")
        if ($a.memberId) {
            [void]$sql.AppendLine("UPDATE household_members SET user_id = (SELECT id FROM users WHERE account_id = $(Sql-Literal $a.id)) WHERE household_id = $hid AND id = $(Sql-Literal $a.memberId);")
        }
        if ($a.isAdmin) {
            [void]$sql.AppendLine("UPDATE households SET owner_user_id = (SELECT id FROM users WHERE account_id = $(Sql-Literal $a.id)) WHERE id = $hid;")
        }
    }
    $sort = 0
    foreach ($c in @($state.chores)) {
        $sort += 1
        [void]$sql.AppendLine("INSERT INTO chores (household_id, id, name, emoji, fatigue, xp, category, sort_order) VALUES ($hid, $(Sql-Literal $c.id), $(Sql-Literal $c.name), $(Sql-Literal $c.emoji), $(Sql-Int $c.fatigue), $(Sql-Int $c.xp), $(Sql-Literal $c.category), $sort);")
    }

    foreach ($h in @($state.history)) {
        $ms = Sql-Long $h.timestamp
        [void]$sql.AppendLine("INSERT INTO task_entries (household_id, id, member_id, chore_id, chore_name, chore_emoji, category, fatigue_added, xp_earned, verification_status, proof_image, proof_caption, proof_analysis, review_note, completed_at_ms, created_at) VALUES ($hid, $(Sql-Literal $h.id), $(Sql-Literal $h.memberId), $(Sql-Literal $h.choreId), $(Sql-Literal $h.choreName), $(Sql-Literal $h.choreEmoji), $(Sql-Literal $h.category), $(Sql-Int $h.fatigueAdded), $(Sql-Int $h.xpEarned), $(Sql-Literal (Coalesce-Value $h.verificationStatus 'approved')), $(Sql-Literal $h.proofImage), $(Sql-Literal $h.proofCaption), $(Sql-Literal $h.proofAnalysis), $(Sql-Literal $h.reviewNote), $ms, $(Sql-TimestampExpr $h.timestamp));")
        foreach ($r in @($h.approvalRequests)) {
            [void]$sql.AppendLine("INSERT INTO task_approvals (household_id, entry_id, reviewer_id, status, reviewed_at_ms, review_note) VALUES ($hid, $(Sql-Literal $h.id), $(Sql-Literal $r.reviewerId), $(Sql-Literal (Coalesce-Value $r.status 'pending')), $(Sql-Long $r.reviewedAt), $(Sql-Literal $r.reviewNote));")
        }
        $recipients = if ($h.pointRecipients) { @($h.pointRecipients) } else { @($h.memberId) }
        foreach ($memberId in $recipients) {
            if ($memberId) { [void]$sql.AppendLine("INSERT INTO task_point_recipients (household_id, entry_id, member_id) VALUES ($hid, $(Sql-Literal $h.id), $(Sql-Literal $memberId)) ON CONFLICT DO NOTHING;") }
        }
    }

    foreach ($msg in @($state.messages)) {
        $ms = Sql-Long $msg.timestamp
        [void]$sql.AppendLine("INSERT INTO messages (household_id, id, from_member_id, to_member_id, text, sent_at_ms, sent_at) VALUES ($hid, $(Sql-Literal $msg.id), $(Sql-Literal $msg.fromId), $(Sql-Literal $msg.toId), $(Sql-Literal $msg.text), $ms, $(Sql-TimestampExpr $msg.timestamp));")
    }

    foreach ($b in @($state.badgeHistory)) {
        $ms = Sql-Long $b.timestamp
        [void]$sql.AppendLine("INSERT INTO badge_history (household_id, id, member_id, badge_id, name, emoji, earned_at_ms, earned_at) VALUES ($hid, $(Sql-Literal $b.id), $(Sql-Literal $b.memberId), $(Sql-Literal $b.badgeId), $(Sql-Literal $b.name), $(Sql-Literal $b.emoji), $ms, $(Sql-TimestampExpr $b.timestamp));")
    }

    $sort = 0
    foreach ($item in @($state.careItems)) {
        $sort += 1
        [void]$sql.AppendLine("INSERT INTO care_items (household_id, id, name, emoji, points, xp, locked, sort_order) VALUES ($hid, $(Sql-Literal $item.id), $(Sql-Literal $item.name), $(Sql-Literal $item.emoji), $(Sql-Int $item.points), $(Sql-Int $item.xp), $(Sql-Bool ($item.locked -or $item.id -eq 'edu')), $sort);")
    }

    foreach ($a in @($state.careAssignments)) {
        [void]$sql.AppendLine("INSERT INTO care_assignments (household_id, date_key, morning_id, evening_id, updated_at_ms, updated_at) VALUES ($hid, $(Sql-Literal $a.date), $(Sql-Literal $a.morningId), $(Sql-Literal $a.eveningId), $(Sql-Long $a.updatedAt), $(Sql-TimestampExpr $a.updatedAt));")
    }

    foreach ($s in @($state.careSessions)) {
        $created = Sql-Long $s.createdAt
        [void]$sql.AppendLine("INSERT INTO care_sessions (household_id, id, date_key, member_id, care_item_id, child_member_id, points, xp_earned, start_time, end_time, minutes, note, created_at_ms, created_at) VALUES ($hid, $(Sql-Literal $s.id), $(Sql-Literal $s.date), $(Sql-Literal $s.memberId), $(Sql-Literal $s.careItemId), $(Sql-Literal $s.childMemberId), $(Sql-Int $s.points), $(Sql-Int $s.xpEarned), $(Sql-Literal $s.startTime), $(Sql-Literal $s.endTime), $(Sql-Int $s.minutes), $(Sql-Literal $s.note), $created, $(Sql-TimestampExpr $s.createdAt));")
        $recipients = if ($s.pointRecipients) { @($s.pointRecipients) } else { @($s.memberId) }
        foreach ($memberId in $recipients) {
            if ($memberId) { [void]$sql.AppendLine("INSERT INTO care_session_point_recipients (household_id, session_id, member_id) VALUES ($hid, $(Sql-Literal $s.id), $(Sql-Literal $memberId)) ON CONFLICT DO NOTHING;") }
        }
    }

    foreach ($p in @($state.tomorrowPlans)) {
        [void]$sql.AppendLine("INSERT INTO tomorrow_plans (household_id, id, from_member_id, to_member_id, chore_id, title, target_date, note, status, request_status, decline_reason, responded_at_ms, created_at_ms, updated_at) VALUES ($hid, $(Sql-Literal $p.id), $(Sql-Literal $p.fromId), $(Sql-Literal $p.toId), $(Sql-Literal $p.choreId), $(Sql-Literal $p.title), $(Sql-Literal $p.targetDate), $(Sql-Literal $p.note), $(Sql-Literal (Coalesce-Value $p.status 'open')), $(Sql-Literal (Coalesce-Value $p.requestStatus 'pending')), $(Sql-Literal $p.declineReason), $(Sql-Long $p.respondedAt), $(Sql-Long $p.createdAt), now());")
    }

    foreach ($r in @($state.changeRequests)) {
        [void]$sql.AppendLine("INSERT INTO change_requests (household_id, id, type, before_json, after_json, requested_by, requested_at_ms, status, reviewed_at_ms, review_note, applied_at_ms) VALUES ($hid, $(Sql-Literal $r.id), $(Sql-Literal $r.type), $(Sql-Jsonb $r.before), $(Sql-Jsonb $r.after), $(Sql-Literal $r.requestedBy), $(Sql-Long $r.requestedAt), $(Sql-Literal (Coalesce-Value $r.status 'pending')), $(Sql-Long $r.reviewedAt), $(Sql-Literal $r.reviewNote), $(Sql-Long $r.appliedAt));")
        foreach ($a in @($r.approvalRequests)) {
            [void]$sql.AppendLine("INSERT INTO change_request_approvals (household_id, request_id, reviewer_id, status, reviewed_at_ms, review_note) VALUES ($hid, $(Sql-Literal $r.id), $(Sql-Literal $a.reviewerId), $(Sql-Literal (Coalesce-Value $a.status 'pending')), $(Sql-Long $a.reviewedAt), $(Sql-Literal $a.reviewNote));")
        }
    }

    [void]$sql.AppendLine("INSERT INTO app_version (singleton, version, updated_at) VALUES (TRUE, 1, now()) ON CONFLICT (singleton) DO UPDATE SET version = app_version.version + 1, updated_at = now();")
    [void]$sql.AppendLine("COMMIT;")
    Invoke-PsqlText $sql.ToString() | Out-Null
    return Get-DbState $HouseholdId
}

function Get-UserByAccountId($AccountId) {
    $rows = Invoke-PsqlCsv "SELECT id, account_id, email, password_hash, display_name, is_admin, active FROM users WHERE account_id = $(Sql-Literal $AccountId) LIMIT 1"
    if ($rows.Count -eq 0) { return $null }
    return $rows[0]
}

function New-DbSession($UserId, $HouseholdId = $DefaultHouseholdId) {
    $rawToken = New-RandomToken 32
    $tokenHash = Get-Sha256Hex $rawToken
    $memberRows = Invoke-PsqlCsv "SELECT id FROM household_members WHERE household_id = $(Sql-Literal $HouseholdId) AND user_id = $(Sql-Literal $UserId) LIMIT 1"
    $userRows = Invoke-PsqlCsv "SELECT account_id, is_admin FROM users WHERE id = $(Sql-Literal $UserId) LIMIT 1"
    if ($userRows.Count -eq 0) { throw "User not found." }
    $memberId = if ($memberRows.Count) { $memberRows[0].id } else { $null }
    $isAdmin = Convert-CsvBool $userRows[0].is_admin
    Invoke-PsqlText "INSERT INTO sessions (token_hash, user_id, household_id, member_id, is_admin, expires_at) VALUES ($(Sql-Literal $tokenHash), $(Sql-Literal $UserId), $(Sql-Literal $HouseholdId), $(Sql-Literal $memberId), $(Sql-Bool $isAdmin), now() + interval '30 days'); UPDATE users SET last_login_at = now() WHERE id = $(Sql-Literal $UserId);" | Out-Null
    [pscustomobject]@{
        token = $rawToken
        session = [pscustomobject]@{
            accountId = $userRows[0].account_id
            userId = $UserId
            householdId = $HouseholdId
            memberId = $memberId
            isAdmin = $isAdmin
        }
    }
}

function Login-DbUser($AccountId, $Password) {
    Initialize-Database
    $user = Get-UserByAccountId $AccountId
    if (-not $user -or -not (Convert-CsvBool $user.active) -or -not (Test-PasswordHash $Password $user.password_hash)) {
        throw "Check your account ID and password."
    }
    return New-DbSession $user.id $DefaultHouseholdId
}

function Get-DbSession($Token) {
    if ([string]::IsNullOrWhiteSpace([string]$Token)) { return $null }
    Initialize-Database
    $hash = Get-Sha256Hex $Token
    $rows = Invoke-PsqlCsv "SELECT s.user_id, s.household_id, s.member_id, s.is_admin, u.account_id FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = $(Sql-Literal $hash) AND s.expires_at > now() LIMIT 1"
    if ($rows.Count -eq 0) { return $null }
    Invoke-PsqlText "UPDATE sessions SET last_seen_at = now() WHERE token_hash = $(Sql-Literal $hash)" | Out-Null
    [pscustomobject]@{
        accountId = $rows[0].account_id
        userId = $rows[0].user_id
        householdId = $rows[0].household_id
        memberId = if ($rows[0].member_id) { $rows[0].member_id } else { $null }
        isAdmin = Convert-CsvBool $rows[0].is_admin
    }
}

function Clear-DbSession($Token) {
    if ([string]::IsNullOrWhiteSpace([string]$Token)) { return }
    Initialize-Database
    Invoke-PsqlText "DELETE FROM sessions WHERE token_hash = $(Sql-Literal (Get-Sha256Hex $Token))" | Out-Null
}

function Register-Owner($Body) {
    Initialize-Database
    $accountId = [string]$Body.accountId
    if (-not $accountId) { $accountId = [string]$Body.email }
    if (-not $accountId) { throw "accountId is required." }
    $passwordHash = New-PasswordHash $Body.password
    $userId = Get-UserIdForAccount $accountId
    $householdId = if ($Body.householdId) { [string]$Body.householdId } else { New-DbId "home_" }
    $householdName = if ($Body.householdName) { [string]$Body.householdName } else { "ForHome" }
    $displayName = if ($Body.displayName) { [string]$Body.displayName } else { $accountId }
    $profileMark = if ($Body.profileMark) { [string]$Body.profileMark } else { $displayName.Substring(0, [Math]::Min(2, $displayName.Length)) }
    $sql = @"
BEGIN;
INSERT INTO users (id, account_id, email, password_hash, display_name, is_admin, active)
VALUES ($(Sql-Literal $userId), $(Sql-Literal $accountId), $(Sql-Literal $Body.email), $(Sql-Literal $passwordHash), $(Sql-Literal $displayName), TRUE, TRUE);
INSERT INTO households (id, name, owner_user_id)
VALUES ($(Sql-Literal $householdId), $(Sql-Literal $householdName), $(Sql-Literal $userId));
INSERT INTO settings (household_id, vacation_threshold, week_starts_on)
VALUES ($(Sql-Literal $householdId), 25, 1);
INSERT INTO household_members (household_id, id, user_id, name, emoji, restricted, role, color, sort_order)
VALUES ($(Sql-Literal $householdId), 'owner', $(Sql-Literal $userId), $(Sql-Literal $displayName), $(Sql-Literal $profileMark), TRUE, 'owner', '#d97706', 1);
COMMIT;
"@
    Invoke-PsqlText $sql | Out-Null
    return New-DbSession $userId $householdId
}

function New-InviteHash($HouseholdId, $InviteId, $Secret) {
    return Get-Sha256Hex "forhome-invite-v1:$HouseholdId`:$InviteId`:$Secret"
}

function New-ShortInviteCode {
    $digits = ""
    $bytes = New-Object byte[] 6
    Fill-RandomBytes $bytes
    for ($i = 0; $i -lt 6; $i++) {
        if ($i -eq 3) { $digits += "-" }
        $digits += [string]($bytes[$i] % 10)
    }
    return $digits
}

function New-DbInvitation($Session, $Body) {
    Initialize-Database
    if (-not $Session) { throw "Login is required." }
    $membership = Invoke-PsqlCsv "SELECT role FROM household_members WHERE household_id = $(Sql-Literal $Session.householdId) AND user_id = $(Sql-Literal $Session.userId) LIMIT 1"
    $canInvite = $Session.isAdmin -or ($membership.Count -and @("owner", "hero") -contains $membership[0].role)
    if (-not $canInvite) { throw "Invite permission is required." }
    $inviteId = New-DbId "inv_"
    $token = New-RandomToken 32
    $shortCode = New-ShortInviteCode
    $roleHint = Normalize-Role $Body.roleHint
    if ($roleHint -eq "owner") { $roleHint = "hero" }
    $ttlHours = if ($Body.ttlHours) { [int]$Body.ttlHours } else { 24 }
    $maxUses = if ($Body.maxUses) { [int]$Body.maxUses } else { 1 }
    $sql = "INSERT INTO invitations (household_id, id, token_hash, code_hash, role_hint, role_locked, display_name_hint, max_uses, expires_at, created_by_user_id) VALUES ($(Sql-Literal $Session.householdId), $(Sql-Literal $inviteId), $(Sql-Literal (New-InviteHash $Session.householdId $inviteId $token)), $(Sql-Literal (New-InviteHash $Session.householdId $inviteId $shortCode)), $(Sql-Literal $roleHint), $(Sql-Bool $Body.roleLocked), $(Sql-Literal $Body.displayNameHint), $(Sql-Int $maxUses 1), now() + interval '$ttlHours hours', $(Sql-Literal $Session.userId));"
    Invoke-PsqlText $sql | Out-Null
    $baseUrl = if ($Body.baseUrl) { [string]$Body.baseUrl } else { "" }
    $mobileBaseUrl = if ($Body.mobileBaseUrl) { [string]$Body.mobileBaseUrl } else { $baseUrl }
    $webUrl = if ($baseUrl) { "$($baseUrl.TrimEnd('/'))/invite/$inviteId?token=$token" } else { "/invite/$inviteId?token=$token" }
    $mobileUrl = if ($mobileBaseUrl) { "$($mobileBaseUrl.TrimEnd('/'))/invite/$inviteId?token=$token" } else { $webUrl }
    [pscustomobject]@{
        invite = [pscustomobject]@{ inviteId = $inviteId; householdId = $Session.householdId; roleHint = $roleHint; roleLocked = [bool]$Body.roleLocked; maxUses = $maxUses }
        rawToken = $token
        rawCode = $shortCode
        share = [pscustomobject]@{
            webUrl = $webUrl
            mobileUrl = $mobileUrl
            qrPayload = $mobileUrl
            shortCode = $shortCode
            message = "ForHome invitation`nInvite URL: $mobileUrl`nInvite code: $shortCode"
        }
    }
}

function Get-InvitationById($InviteId) {
    $rows = Invoke-PsqlCsv "SELECT household_id, id, token_hash, code_hash, role_hint, role_locked, display_name_hint, max_uses, used_count, expires_at, revoked_at FROM invitations WHERE id = $(Sql-Literal $InviteId) LIMIT 1"
    if ($rows.Count -eq 0) { return $null }
    return $rows[0]
}

function Get-DbInvitationPreview($InviteId) {
    Initialize-Database
    $invite = Get-InvitationById $InviteId
    if (-not $invite) { throw "Invitation was not found." }
    [pscustomobject]@{
        inviteId = $invite.id
        householdId = $invite.household_id
        roleHint = $invite.role_hint
        roleLocked = Convert-CsvBool $invite.role_locked
        displayNameHint = $invite.display_name_hint
        usable = (-not $invite.revoked_at) -and ([int]$invite.used_count -lt [int]$invite.max_uses) -and ([DateTime]$invite.expires_at -gt [DateTime]::UtcNow)
    }
}

function Accept-DbInvitation($InviteId, $Body) {
    Initialize-Database
    $invite = Get-InvitationById $InviteId
    if (-not $invite) { throw "Invitation was not found." }
    if ($invite.revoked_at) { throw "Invitation has been revoked." }
    if ([int]$invite.used_count -ge [int]$invite.max_uses) { throw "Invitation has already been used." }
    if ([DateTime]$invite.expires_at -le [DateTime]::UtcNow) { throw "Invitation has expired." }
    if (-not $Body.token -and -not $Body.shortCode) { throw "Invite token or code is required." }
    if ($Body.token -and (New-InviteHash $invite.household_id $invite.id $Body.token) -ne $invite.token_hash) { throw "Invite token is invalid." }
    if ($Body.shortCode -and (New-InviteHash $invite.household_id $invite.id $Body.shortCode) -ne $invite.code_hash) { throw "Invite code is invalid." }
    $accountId = if ($Body.accountId) { [string]$Body.accountId } else { [string]$Body.email }
    if (-not $accountId) { throw "accountId is required." }
    $displayName = if ($Body.displayName) { [string]$Body.displayName } elseif ($invite.display_name_hint) { $invite.display_name_hint } else { $accountId }
    $role = if (Convert-CsvBool $invite.role_locked) { $invite.role_hint } else { Normalize-Role $Body.selectedRole }
    if ($role -eq "owner") { $role = "hero" }
    $userId = Get-UserIdForAccount $accountId
    $memberId = New-DbId "mem_"
    $passwordHash = New-PasswordHash $Body.password
    $mark = $displayName.Substring(0, [Math]::Min(2, $displayName.Length))
    $sql = @"
BEGIN;
INSERT INTO users (id, account_id, email, password_hash, display_name, is_admin, active)
VALUES ($(Sql-Literal $userId), $(Sql-Literal $accountId), $(Sql-Literal $Body.email), $(Sql-Literal $passwordHash), $(Sql-Literal $displayName), FALSE, TRUE);
INSERT INTO household_members (household_id, id, user_id, name, emoji, restricted, role, color, sort_order)
VALUES ($(Sql-Literal $invite.household_id), $(Sql-Literal $memberId), $(Sql-Literal $userId), $(Sql-Literal $displayName), $(Sql-Literal $mark), $(Sql-Bool ($role -ne 'care_member')), $(Sql-Literal $role), '#2563eb', 999);
UPDATE invitations SET used_count = used_count + 1, last_used_at = now() WHERE household_id = $(Sql-Literal $invite.household_id) AND id = $(Sql-Literal $invite.id);
COMMIT;
"@
    Invoke-PsqlText $sql | Out-Null
    return New-DbSession $userId $invite.household_id
}
