function Join-Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Text,
        [Parameter(Mandatory = $false)]
        [string]$Splitter = ', ',
        [Parameter(Mandatory = $false)]
        [switch]$NoTrim,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeEmpty
    )
    begin {
        [Collections.ArrayList]$array = @()
    }
    process {
        if (-not $NoTrim) {
            $Text = $Text.Trim()
        }
        if ($IncludeEmpty -or ($Text -ne '')) {
            [void]$array.Add($Text)
        }
    }
    end {
        return $array -join $Splitter
    }
}

function Format-DataSize ($num) {
    switch ($num) {
        { $_ -lt 1KB } { $t = $_; $f = 'B'; break }
        { $_ -lt 1MB -and $_ -ge 1KB } { $t = $_ / 1KB; $f = 'K'; break }
        { $_ -lt 1GB -and $_ -ge 1MB } { $t = $_ / 1MB; $f = 'M'; break }
        { $_ -lt 1TB -and $_ -ge 1GB } { $t = $_ / 1GB; $f = 'G'; break }
    }
    ('{0:N2} {1}' -f $t, $f)
}

function Resolve-OptionalPath {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Path
    )
    $Path = Resolve-Path $Path -ErrorAction SilentlyContinue -ErrorVariable error
    if (-not($Path)) {
        $Path = $error[0].TargetObject
    }
    return $Path
}

Export-ModuleMember -Function Join-Text, Format-DataSize, Resolve-OptionalPath
