[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('video', 'audio', 'image', IgnoreCase = $false)]
    [string]$PerceivedType,
    [Parameter(Mandatory = $false, ParameterSetName = 'List')]
    [switch]$List,
    [Parameter(Mandatory = $true, ParameterSetName = 'Register')]
    [switch]$Register,
    [Parameter(Mandatory = $true, ParameterSetName = 'Deregister')]
    [switch]$Deregister
)

$SHELL_KEY_PATH = 'HKCU:\SOFTWARE\Classes\SystemFileAssociations\{0}\shell\'
$SHELL_KEY_NAME = 'MediaInfo_MeTools'
$SHELL_DISPLAY_NAME = 'MediaInfo'
$SHELL_COMMAND_VALUE = 'cmd /c mediainfo "%1" & pause>nul'

function GetPerceivedType ([string]$type) {
    return Get-ChildItem -Path 'HKLM:\SOFTWARE\Classes\' | `
        Where-Object PSChildName -Like '.*' | `
        Where-Object { ((Get-ItemProperty $_.PSPath).PerceivedType) -eq $type } | `
        ForEach-Object { $_.PSChildName }
}


function RegisterMediainfo ([string]$ext) {
    $path = ($SHELL_KEY_PATH -f $ext) + $SHELL_KEY_NAME
    $pathCommand = $path + '\command'

    if (Test-Path $path) {
        Write-Warning "File $ext already has MediaInfo context menu"
        return
    }

    Write-Host "Register MediaInfo context menu for $ext"

    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name 'MUIVerb' -Value $SHELL_DISPLAY_NAME
    New-Item -Path $pathCommand | Out-Null
    Set-ItemProperty -Path $pathCommand -Name '(default)' -Value $SHELL_COMMAND_VALUE
}

function DeregisterMediainfo ([string]$ext) {
    $path = ($SHELL_KEY_PATH -f $ext) + $SHELL_KEY_NAME
    if (-not (Test-Path $path)) {
        Write-Warning "File $ext doesn't have MediaInfo context menu"
        return
    }
    Write-Host "Deregister MediaInfo context menu for $ext"
    Remove-Item -Path $path -Recurse | Out-Null
}

$ParamSet = $PSCmdlet.ParameterSetName
Write-Host 'Mode:' $ParamSet

if ($ParamSet -eq 'List') {
    $types = GetPerceivedType $PerceivedType
    Write-Host $types
}
elseif ($ParamSet -eq 'Register') {
    if (Get-Command 'mediainfo' -ErrorAction SilentlyContinue) {}
    else {
        throw 'MediaInfo not found'
    }
    GetPerceivedType $PerceivedType | ForEach-Object {
        RegisterMediainfo $_
    }
}
elseif ($ParamSet -eq 'Deregister') {
    GetPerceivedType $PerceivedType | ForEach-Object {
        DeregisterMediainfo $_
    }
}
