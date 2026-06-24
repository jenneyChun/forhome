param(
    [int[]]$Ports = @(8080, 8081, 8082, 8083, 8084, 8085)
)

function Stop-ProcessTree {
    param([int]$ProcessId)

    if (-not $ProcessId -or $ProcessId -eq $PID) { return }
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-ProcessTree -ProcessId $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    cmd /c "taskkill /PID $ProcessId /F /T >nul 2>nul"
}

function Stop-PortOwner {
    param([int]$OwnerPid)

    if (-not $OwnerPid -or $OwnerPid -eq $PID) { return $false }
    $proc = Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Output "BUSY:$OwnerPid|$($proc.ProcessName)"
        Stop-ProcessTree -ProcessId $OwnerPid
        return $true
    }

    Write-Output "ZOMBIE:$OwnerPid"
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$OwnerPid" -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Output "CHILD:$($_.ProcessId)|$($_.Name)"
            Stop-ProcessTree -ProcessId $_.ProcessId
        }
    cmd /c "taskkill /PID $OwnerPid /F /T >nul 2>nul"
    return $true
}

foreach ($port in $Ports) {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $listen = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if (-not $listen) {
            Write-Output "FREE:$port"
            exit 0
        }

        $ownerPids = @($listen | Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -and $_ -ne $PID })
        foreach ($ownerPid in $ownerPids) {
            Stop-PortOwner -OwnerPid $ownerPid | Out-Null
        }
        Start-Sleep -Milliseconds (250 * $attempt)
    }
}

Write-Output "NONE_FREE"
