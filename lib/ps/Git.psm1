function Get-GitCommitName {
    param(
        [string]$Path = '.',
        [string]$Fallback = '0'
    )

    $name = git -C $Path describe --always --dirty 2>$null

    if ($LASTEXITCODE -eq 0 -and $name) {
        return $name.Trim()
    }
    else {
        return $Fallback
    }
}

Export-ModuleMember -Function Get-GitCommitName
