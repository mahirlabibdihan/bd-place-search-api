[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 5001,
    [ValidatePattern('^[\w .()-]+$')]
    [string]$InterfaceAlias
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Port $Port"
    if ($InterfaceAlias) { $arguments += " -InterfaceAlias `"$InterfaceAlias`"" }
    if ($WhatIfPreference) { $arguments += ' -WhatIf' }
    Write-Host 'Approve the Windows administrator prompt to configure LAN access.'
    $child = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $child.ExitCode
}

try {
    # Select a physical adapter with an IPv4 gateway; exclude WSL/virtual adapters.
    $adapters = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up')
    $connections = @(Get-NetIPConfiguration | Where-Object {
        $_.InterfaceIndex -in $adapters.ifIndex -and $_.IPv4DefaultGateway -and
        (-not $InterfaceAlias -or $_.InterfaceAlias -eq $InterfaceAlias)
    })
    if ($connections.Count -ne 1) {
        throw 'Specify one connected LAN adapter with -InterfaceAlias (see Get-NetIPConfiguration).'
    }
    $connection = $connections[0]
    $addresses = @($connection.IPv4Address | Where-Object {
        $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1'
    })
    if ($addresses.Count -ne 1) { throw 'The adapter must have exactly one usable IPv4 address.' }
    $lanAddress = $addresses[0].IPAddress
    $ruleName = "BPO-LAN-TCP-$Port"

    if (-not $PSCmdlet.ShouldProcess("${lanAddress}:$Port", 'Forward to localhost and allow local-subnet traffic')) {
        return
    }

    # Check the existing local service before changing Windows networking.
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $pending.Wait(3000) -or -not $client.Connected) {
            throw "Start the container on localhost:$Port first."
        }
    } finally { $client.Dispose() }

    # Remove stale IP bindings owned by this script (and the initial manual setup).
    $rules = @(Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
    $rules += @(Get-NetFirewallRule -DisplayName "BPO API $Port Wi-Fi LAN" -ErrorAction SilentlyContinue)
    foreach ($rule in $rules) {
        foreach ($oldAddress in @(($rule | Get-NetFirewallAddressFilter).LocalAddress)) {
            $parsedAddress = $null
            if ([Net.IPAddress]::TryParse($oldAddress, [ref]$parsedAddress) -and $oldAddress -ne $lanAddress) {
                netsh interface portproxy delete v4tov4 "listenaddress=$oldAddress" "listenport=$Port" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'Could not remove the previous LAN forwarding rule.' }
            }
        }
    }

    netsh interface portproxy add v4tov4 "listenaddress=$lanAddress" "listenport=$Port" connectaddress=127.0.0.1 "connectport=$Port" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not configure Windows port forwarding.' }

    foreach ($rule in $rules) { $rule | Remove-NetFirewallRule }
    New-NetFirewallRule -Name $ruleName -DisplayName "BPO API $Port LAN" `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
        -LocalAddress $lanAddress -RemoteAddress LocalSubnet `
        -InterfaceAlias $connection.InterfaceAlias -Profile Any | Out-Null

    Write-Host "LAN access enabled: http://${lanAddress}:$Port"
    Write-Host 'Forwarding persists across restarts. Rerun if your LAN IP changes.'
} catch {
    Write-Error $_
    exit 1
}
