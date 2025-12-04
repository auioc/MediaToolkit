function Get-MediaInfo {
    if (Get-Command 'mediainfo' -ErrorAction SilentlyContinue) {
        $path = (Get-Command 'mediainfo').Source
        $ver = ((mediainfo --Version) -split '\n')[1] | `
            Select-String -Pattern 'v(\d+\.\d+(\.\d)?)' | `
            ForEach-Object { $_.Matches.Groups[1].value }
        return @{ Path = $path; Version = $ver }
    }
    else {
        throw 'MediaInfo not found'
    }
}

Export-ModuleMember -Function Get-MediaInfo
