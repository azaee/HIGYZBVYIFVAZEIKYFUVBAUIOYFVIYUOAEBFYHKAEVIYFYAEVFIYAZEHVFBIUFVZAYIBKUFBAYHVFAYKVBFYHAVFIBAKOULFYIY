if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n [+] Restart in Administrator" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

try {
    $mp = Get-MpPreference -ErrorAction Stop
    if ($mp.RealTimeProtectionEnabled -eq $true) {
        Write-Host "`n [+] Remove Windows Defender !" -ForegroundColor Red
        Start-Sleep -Seconds 5
        exit
    }
} catch {}

$port = 8080
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

try {
    $listener.Start()
    Start-Process 'http://localhost:8080'
} catch {
    Write-Host 'CRITICAL ERROR: Could not start listener.' -ForegroundColor Red
    pause
    exit
}

Write-Host '[+] Trinity Server is running...' -ForegroundColor Magenta

$shutdownTimer = $null

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.LocalPath

        if ($null -ne $shutdownTimer) {
            $shutdownTimer.Stop()
            $shutdownTimer.Dispose()
            $shutdownTimer = $null
        }
        
        if ($path -eq '/shutdown') {
            $response.StatusCode = 200
            $response.Close()
            $shutdownTimer = New-Object System.Timers.Timer(2000)
            $shutdownTimer.AutoReset = $false
            $action = { $listener.Stop() }
            Register-ObjectEvent -InputObject $shutdownTimer -EventName Elapsed -Action $action | Out-Null
            $shutdownTimer.Start()
            continue
        }

        if ($path -eq '/spoof/permanent') {
            $triggerPath = "$env:TEMP\trinity_spoof.flag"
            [System.IO.File]::WriteAllText($triggerPath, '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/tpm_driverless') {
            $triggerPath = "$env:TEMP\trinity_tpm.flag"
            [System.IO.File]::WriteAllText($triggerPath, '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/driverless') {
            $triggerPath = "$env:TEMP\trinity_dl.flag"
            [System.IO.File]::WriteAllText($triggerPath, '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($path -eq '/drives') {
            $drivesFile = "$env:TEMP\trinity_drives.json"
            $json = if (Test-Path $drivesFile) { [System.IO.File]::ReadAllText($drivesFile) } else { '[]' }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json'
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/locked') {
            $drive = $request.QueryString["drive"]
            if ($drive) {
                [System.IO.File]::WriteAllText("$env:TEMP\trinity_locked_drive.txt", $drive)
            }
            [System.IO.File]::WriteAllText("$env:TEMP\trinity_locked.flag", '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/temp') {
            $triggerPath = "$env:TEMP\trinity_temp.flag"
            [System.IO.File]::WriteAllText($triggerPath, '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/reset') {
            $triggerPath = "$env:TEMP\trinity_reset.flag"
            [System.IO.File]::WriteAllText($triggerPath, '1')
            $response.StatusCode = 200
            $response.Close()
            continue
        }



        if ($path -eq '/sysinfo') {
            $sysFile = "$env:TEMP\trinity_sys.json"
            $json = if (Test-Path $sysFile) { [System.IO.File]::ReadAllText($sysFile) } else { '{}' }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json'
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        if ($path -eq '/spoof/logs') {
            $logPath = "$env:TEMP\trinity_log.txt"
            $entries = @()
            try {
                if (Test-Path $logPath) {
                    # Use a stream reader with sharing enabled to avoid locks
                    $stream = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $lines = @()
                    while (($line = $reader.ReadLine()) -ne $null) { $lines += $line }
                    $reader.Close()
                    $stream.Close()

                    # Clear the log file safely if we read something
                    if ($lines.Count -gt 0) {
                        $clearStream = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Truncate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                        $clearStream.SetLength(0)
                        $clearStream.Close()
                    }

                    foreach ($line in $lines) {
                        $parts = $line.Split('|', 2)
                        if ($parts.Length -eq 2) {
                            $entries += [PSCustomObject]@{ type = $parts[0]; msg = $parts[1] }
                        }
                    }
                }
            } catch {
                # Log error to server console if needed
                Write-Host "[!] Error reading logs: $($_.Exception.Message)" -ForegroundColor Red
            }

            $json = if ($entries.Count -gt 0) { ConvertTo-Json $entries -Compress } else { '[]' }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = 'application/json'
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            continue
        }

        # Handling remote logging from browser to CMD
        if ($path -eq '/log') {
            $msg = $request.QueryString["msg"]
            $type = $request.QueryString["type"]
            $time = Get-Date -Format "HH:mm:ss"
            
            $cleanMsg = $msg -replace '<b>', '' -replace '</b>', '' -replace '<code>', '' -replace '</code>', ''
            
            if ($type -eq 'ok') {
                Write-Host "[$time] [+] $cleanMsg" -ForegroundColor Green
            } elseif ($type -eq 'warn') {
                Write-Host "[$time] [!] $cleanMsg" -ForegroundColor Yellow
            } else {
                Write-Host "[$time] [*] $cleanMsg" -ForegroundColor Cyan
            }
            
            $response.Close()
            continue
        }

        if ($path -eq '/') { $path = '/index.html' }
        $filePath = Join-Path $PSScriptRoot $path.TrimStart('/')
        
        if (Test-Path $filePath -PathType Leaf) {
            $content = [System.IO.File]::ReadAllBytes($filePath)

            $ext = [System.IO.Path]::GetExtension($filePath)
            if ($ext -eq '.html') { $response.ContentType = 'text/html' }
            if ($ext -eq '.css')  { $response.ContentType = 'text/css' }
            if ($ext -eq '.js')   { $response.ContentType = 'application/javascript' }

            $response.Headers.Add('Cache-Control', 'no-store, no-cache, must-revalidate')
            $response.Headers.Add('Pragma', 'no-cache')
            $response.ContentLength64 = $content.Length
            $response.OutputStream.Write($content, 0, $content.Length)
        } else {
            $response.StatusCode = 404
        }
    } catch {
        # Error during request processing
    } finally {
        if ($null -ne $response) {
            try { $response.Close() } catch {}
        }
    }
}
