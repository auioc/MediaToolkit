param(
    [string]$InputPath = '.',
    [string]$OutputPath = '',
    [string[]]$IncludeExtensions = @('mp4', 'mkv', 'flv', 'webm', 'mov', 'avi', 'wmv', 'rm', 'rmvb'),
    [switch]$Recurse,
    [int]$Depth = -1,
    [switch]$DryRun,
    [switch]$NoOutput
)

# Set-Location -Path $PSScriptRoot
# Set-Location -LiteralPath 'R:\'

$INCLUDE_FILES = @('mp4', 'mkv', 'flv', 'webm', 'mov', 'avi', 'wmv', 'rm', 'rmvb')

$GRID_ROWS = 6
$GRID_COLS = 5
$GRID_CELL_HEIGHT = 320
$GRID_GAP = 2
$HASH_ALGORITHM = 'SHA1'
$DRAWTEXT_FONT = 'unifont.otf'
$FONT_WH_RATIO = 1 / 2
$COLOR_BG_FG = ('black', 'white')
$INFO_FONTSIZE = 32
$TIME_FONTSIZE = 24
$INFO_HEADER_Y = 20
$INFO_X = 20
$INFO_LINE_GAP = 2
$FOOTER_HEIGHT = 28
$FOOTER_LINE_GAP = 2
$SCRIPT_NAME = 'MeTools@PCC'
$FFMPEG_VERSION = '?'

function FormatDataSize ($num) {
    switch ($num) {
        { $_ -lt 1KB } { $t = $_; $f = 'B'; break }
        { $_ -lt 1MB -and $_ -ge 1KB } { $t = $_ / 1KB; $f = 'K'; break }
        { $_ -lt 1GB -and $_ -ge 1MB } { $t = $_ / 1MB; $f = 'M'; break }
        { $_ -lt 1TB -and $_ -ge 1GB } { $t = $_ / 1GB; $f = 'G'; break }
    }
    ('{0:N2} {1}' -f $t, $f)
}

function FormatBitRate ($track) {
    $rate = [int]$track.BitRate
    $mode = "$(if ($track.BitRate_Mode) { " $($track.BitRate_Mode)" }else { '' })"
    if ($rate -le 0) {
        return '? kb/s' + $mode
    }
    return "$(FormatDataSize $rate)b/s" + $mode
}

function EscapeDrawText () {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    return ([string]$InputObject).Replace(':', '\:')
}

function GetLongestLineWidth($lines, $fontSize, $fontRatio) {
    $lines | ForEach-Object {
        $s = [string]$_
        $fwCount = ($s | Select-String -Pattern '[^\x00-\x7F]' -AllMatches).Matches.Length
        $hwCount = $s.Length - $fwCount
        $_width = ($hwCount * $fontSize + $fwCount * 2 * $fontSize) * $fontRatio
        if ($_width -gt $width) {
            $width = $_width
        }
    }
    return $width
}

function ProcessSingle([System.IO.FileInfo]$inputFile, [string]$outputFile, [bool]$NoOutput) {
    $mediaInfo = mediainfo --Output=JSON "`"$($inputFile.FullName)`"" | ConvertFrom-Json
    $tracks = ($mediaInfo).media.track

    $general = $tracks | Where-Object { $_.'@type' -eq 'General' } | Select-Object -First 1
    $video = $tracks | Where-Object { $_.'@type' -eq 'Video' } | Select-Object -First 1
    $audio = $tracks | Where-Object { $_.'@type' -eq 'Audio' } | Select-Object -First 1

    $fileInfo = 'File Name: ' + "$($inputFile.Name)"

    $generalInfo = '' + (
        (
            "File Size: $(FormatDataSize ([int64]$general.FileSize))B",
            "Duration: $([TimeSpan]::FromSeconds([double]$general.Duration).ToString("g"))",
            "Format: $($general.Format)"
        ) -Join ', ')

    $fileHash = 'File Hash: ' + "$($HASH_ALGORITHM.ToLower()) " + (
        (Get-FileHash -LiteralPath $inputFile.FullName -Algorithm $HASH_ALGORITHM).Hash.ToLower()
    )

    $frameInterval = [math]::Floor($video.FrameCount / ($GRID_COLS * $GRID_ROWS))

    $frameRatio = [double]$video.DisplayAspectRatio
    $gridCols = $GRID_COLS
    $gridRows = $GRID_ROWS
    if ($frameRatio -lt 1) {
        # 竖屏视频（高>宽）交换行列数
        $gridCols = $GRID_ROWS
        $gridRows = $GRID_COLS
    }
    # 计算缩略图网格的整体宽度
    $gridWidth = ([int]$video.Width * ($GRID_CELL_HEIGHT / [int]$video.Height)) * $gridCols + $GRID_GAP * ($gridRows - 1)
    # $gridHeight = $GRID_CELL_HEIGHT * $gridRows + $GRID_GAP * ($gridRows - 1)

    $videoInfo = 'Video: N/A'
    if ($null -ne $video) {
        $videoInfo = 'Video: ' + (
            (
                "$($video.Format)$(if($video.Format_Profile){" $($video.Format_Profile)"}else{''})$(if($video.Format_Level){"@L$($video.Format_Level)"}else{''})$(if($video.Format_Tier){"@$($video.Format_Tier)"}else{''}) ($($video.CodecID))",
                "$($video.Width)x$($video.Height) $(([double]$video.FrameRate).ToString("0.###")) FPS$(if($video.FrameRate_Mode -eq 'VFR'){' (VFR)'}else{''})",
                "$($video.ColorSpace)$(if($video.ChromaSubsampling){" $($video.ChromaSubsampling)"}) $($video.BitDepth) bits",
                "$(FormatBitRate $video)"
            ) -Join ', ')
    }

    $audioInfo = 'Audio: N/A'
    if ($null -ne $audio) {
        $audioInfo = 'Audio: ' + (
            (
                "$($audio.Format)$(if($audio.Format_AdditionalFeatures){" $($audio.Format_AdditionalFeatures)"}else{''})$(if($audio.Format_Profile){" $($audio.Format_Profile)"}else{''}) ($($audio.CodecID))$(if($audio.Compression_Mode){", $($audio.Compression_Mode)"}else{''})",
                "$($audio.Channels) ch",
                "$(([int]$audio.SamplingRate/1000).ToString("0.###")) kHz$(if($audio.BitDepth){" $($audio.BitDepth) bit"}else{''})",
                "$(FormatBitRate $audio)"
            ) -Join ', ')
    }

    Write-Host $fileInfo
    Write-Host $generalInfo
    Write-Host $fileHash
    Write-Host $videoInfo
    Write-Host $audioInfo

    # 每个缩略图添加时间标记
    $filter_thumbs = (
        "select=not(mod(n\,$($frameInterval)))",
        "scale=-1:$GRID_CELL_HEIGHT",
        ('drawtext=' + ((
                "text='%{pts\:gmtime\:0\:%H\\\:%M\\\:%S}'",
                "fontcolor=$($COLOR_BG_FG[1])",
                "fontsize=$TIME_FONTSIZE",
                "fontfile='$DRAWTEXT_FONT'",
                'box=1:boxborderw=5|4',
                "boxcolor=$($COLOR_BG_FG[0])@0.5",
                'x=w-text_w-5',
                'y=h-text_h-4'
            ) -Join ":"))
    ) -Join ","

    $infoLines = ($fileInfo, $generalInfo, $fileHash, $videoInfo, $audioInfo)
    $infoDraw = @()
    $infoY = $INFO_HEADER_Y
    for ($i = 0; $i -lt $infoLines.Length; $i++) {
        $line = $infoLines[$i]
        if ([string]::IsNullOrEmpty($line)) {
            continue
        }
        $infoDraw += 'drawtext=' + ((
                "text='$(EscapeDrawText $infoLines[$i])'",
                "fontcolor=$($COLOR_BG_FG[1])",
                "fontsize=$INFO_FONTSIZE",
                "fontfile='$DRAWTEXT_FONT'",
                "x=$INFO_X",
                "y=$infoY"
            ) -Join ":")
        $infoY += $INFO_FONTSIZE + $INFO_LINE_GAP
    }
    $headerYb = $infoY + $INFO_HEADER_Y - $INFO_LINE_GAP - $GRID_GAP

    $footerText = '' + (
        (
            "Generated by $SCRIPT_NAME",
            "$($mediaInfo.creatingLibrary.name) $($mediaInfo.creatingLibrary.version)",
            "FFmpeg $FFMPEG_VERSION",
            "$(Get-Date -Format 'yyyy/MM/ddTHH:mm:ssK' | EscapeDrawText)"
        ) -Join ' // ')
    $footerFontsize = $FOOTER_HEIGHT - $FOOTER_LINE_GAP
    $infoDraw += 'drawtext=' + ((
            "text='$footerText'",
            "fontcolor=$($COLOR_BG_FG[1])",
            "fontsize=$footerFontsize",
            "fontfile='$DRAWTEXT_FONT'",
            "x=w-$($INFO_X)-text_w",
            "y=h-$($FOOTER_LINE_GAP)-text_h"
        ) -Join ":")

    # 计算最长的信息行和缩略图网格宽度的差值，以便调整输出图片的宽度
    $deltaWidth = [Math]::Max(
        [Math]::Max(
            (GetLongestLineWidth $infoLines $INFO_FONTSIZE $FONT_WH_RATIO),
            (GetLongestLineWidth $footerText $footerFontsize $FONT_WH_RATIO)
        ) - ($gridWidth + 4),
        0
    ) + $INFO_X * 2

    $filter = (
        '[0:v]',
        $filter_thumbs,
        '[tiled];[tiled]',
        "tile=$($gridCols)x$($gridRows):padding=$($GRID_GAP):color=$($COLOR_BG_FG[0])",
        '[grid];[grid]',
        "pad=iw+$($GRID_GAP+1+$deltaWidth):ih+$($headerYb+$FOOTER_HEIGHT):$($GRID_GAP+$deltaWidth/2):$($headerYb):$($COLOR_BG_FG[0])",
        '[padded];[padded]',
        ($infoDraw -Join ",")
    ) -Join ""

    Write-Debug $filter

    if (-not $NoOutput) {
        ffmpeg `
            -y `
            -v error `
            -hide_banner `
            -i "`"$($inputFile.FullName)`"" `
            -an `
            -frames 1 `
            -filter_complex "`"$filter`"" `
            "`"$outputFile`""
    }

}

function Main {
    param(
        [Parameter(Mandatory = $false)]
        [string]$InputPath = ".",

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "",

        [Parameter(Mandatory = $false)]
        [string[]]$IncludeExtensions = $INCLUDE_FILES,

        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $false,

        [Parameter(Mandatory = $false)]
        [int]$Depth = -1,

        [Parameter(Mandatory = $false)]
        [bool]$DryRun = $false,

        [Parameter(Mandatory = $false)]
        [bool]$NoOutput = $false
    )

    if (-not (Test-Path $InputPath)) {
        throw "NotFound: $InputPath"
    }

    # 未指定输出目录即为输入目录
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = (Resolve-Path $InputPath).Path
    }

    Write-Host 'Input     ' $InputPath
    Write-Host 'Output    ' $OutputPath "$(if((-not $DryRun) -and $NoOutput){'(Disabled)'})"
    Write-Host 'Include   ' $IncludeExtensions
    Write-Host 'Recurse   ' $Recurse
    if ($Recurse -and ($Depth -ge 0)) { Write-Host 'Depth     ' $Depth }

    if (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue) {
        $path = (Get-Command 'ffmpeg').Source
        $FFMPEG_VERSION = ((ffmpeg -v error -hide_banner -version) -split '\n')[0] | `
            Select-String -Pattern '^ffmpeg version (\d+\.\d+(\.\d)?)' | `
            ForEach-Object { $_.Matches.Groups[1].value }
        Write-Host "FFmpeg     $path v$FFMPEG_VERSION"
    }
    else {
        throw 'FFmpeg not found'
    }

    if (Get-Command 'mediainfo' -ErrorAction SilentlyContinue) {
        $path = (Get-Command 'mediainfo').Source
        $ver = ((mediainfo --Version) -split '\n')[1] | `
            Select-String -Pattern '(v\d+\.\d+(\.\d)?)' | `
            ForEach-Object { $_.Matches.Groups[1].value }
        Write-Host "MediaInfo  $path $ver"
    }
    else {
        throw 'MediaInfo not found'
    }

    $DRAWTEXT_FONT = (
        Get-ChildItem -Path "$($env:windir)\Fonts", "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" -File | `
            Where-Object Name -Match '^unifont-\d+\.\d+\.\d+\.otf' | `
            Select-Object -First 1
    ).FullName
    Write-Host 'Font      ' $DRAWTEXT_FONT
    $DRAWTEXT_FONT = $DRAWTEXT_FONT.Replace('\', '/') | EscapeDrawText

    if ($DryRun) {
        Write-Host
        Write-Host '*** Dry Run ***' -ForegroundColor DarkCyan
    }
    Write-Host

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    if (-not $Recurse) {
        $Depth = 0
    }

    $files
    if ($Depth -ge 0) {
        $files = Get-ChildItem -Path $InputPath -File -Depth $Depth
    }
    else {
        $files = Get-ChildItem -Path $InputPath -File -Recurse
    }

    $IncludeExtensions = $IncludeExtensions | ForEach-Object { '.' + $_ }
    # PS5 中 Get-ChildItem 的 -Include 导致 —Depth 失效，使用 Where-Object 过滤后缀名
    # https://github.com/PowerShell/PowerShell/issues/3726
    $files = @($files | Where-Object Extension -In -Value $IncludeExtensions)

    $fileCount = $files.Length

    $i = 0
    $files | ForEach-Object {
        $i++

        $relativePath = $_.FullName.Substring((Resolve-Path $InputPath).Path.Length).TrimStart('\', '/')
        $outputFile = Join-Path $OutputPath $relativePath
        $outputDir = [System.IO.Path]::GetDirectoryName($outputFile)
        $outputFileName = "$($_.BaseName).jpg"
        $outputFile = Join-Path $outputDir $outputFileName

        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        Write-Host "[$i/$fileCount] $($_.FullName) -> $outputFile"
        if (-not $DryRun) {
            ProcessSingle $_ $outputFile $NoOutput
        }

        Write-Host
    }
}

Main $InputPath $OutputPath $IncludeExtensions $Recurse $Depth $DryRun $NoOutput
