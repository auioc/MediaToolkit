function Get-FFmpeg {
    if (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue) {
        $path = (Get-Command 'ffmpeg').Source
        $ver = ((ffmpeg -v error -hide_banner -version) -split '\n')[0] | `
            Select-String -Pattern '^ffmpeg version (\d+\.\d+(\.\d)?)' | `
            ForEach-Object { $_.Matches.Groups[1].value }
        return @{ Path = $path; Version = $ver }
    }
    else {
        throw 'FFmpeg not found'
    }
}

Export-ModuleMember -Function Get-FFmpeg
