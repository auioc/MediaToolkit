[CmdletBinding()]
param(
    [string]$InputPath = '.',
    [string]$OutputPath = '',
    [string[]]$IncludeExtensions = @('mp4', 'mkv', 'flv', 'webm', 'mov', 'avi', 'wmv', 'rm', 'rmvb'),
    [switch]$Recurse,
    [int]$Depth = -1,
    [switch]$DryRun,
    [switch]$NoOutput,
    [switch]$NoOverwrite
)

# Set-Location -Path $PSScriptRoot
# Set-Location -LiteralPath 'R:\'

Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\lib\ps\MediaInfo.psm1')) -Force
Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\lib\ps\FFmpeg.psm1')) -Force
Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\lib\ps\Utils.psm1')) -Force
Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\lib\ps\Git.psm1')) -Force

$INCLUDE_FILES = @('mp4', 'mkv', 'flv', 'webm', 'mov', 'avi', 'wmv', 'rm', 'rmvb')

$GRID_ROWS_LANDSPACE = 6
$GRID_COLS_LANDSPACE = 5
$GRID_ROWS_PORTRAIT = 3
$GRID_COLS_PORTRAIT = 10
$GRID_CELL_HEIGHT_LANDSPACE = 320
$GRID_CELL_HEIGHT_PORTRAIT = 540
$GRID_GAP = 2
$PORTRAIT_RATIO = 0.8
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
$PROJECT_VERSION = '?'
$FFMPEG_VERSION = '?'

function FormatBitRate ($track) {
    $rate = [int]$track.BitRate
    $mode = "$(if($track.BitRate_Mode){" $($track.BitRate_Mode)"}else{''})"
    if ($rate -le 0) {
        if ($mode -ne '') {
            return '? kb/s' + $mode
        }
        return ''
    }
    return "$(Format-DataSize $rate)b/s" + $mode
}

function JoinInfoText($array) {
    return ($array | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join ', '
}

function EscapeDrawText () {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    return ([string]$InputObject).Replace(':', '\:').Replace("'", "'\\\''")
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
    $mediaInfo = mediainfo --Output=JSON "$($inputFile.FullName)" | ConvertFrom-Json
    $tracks = ($mediaInfo).media.track

    $general = $tracks | Where-Object { $_.'@type' -eq 'General' } | Select-Object -First 1
    $video = $tracks | Where-Object { $_.'@type' -eq 'Video' } | Select-Object -First 1
    $audio = $tracks | Where-Object { $_.'@type' -eq 'Audio' } | Select-Object -First 1

    $fileInfo = 'File Name: ' + "$($inputFile.Name)"

    $generalInfo = '' + (
        (
            "File Size: $(Format-DataSize ([int64]$general.FileSize))B",
            "Duration: $([TimeSpan]::FromSeconds([double]$general.Duration).ToString('g'))",
            "Format: $($general.Format)"
        ) -join ', ')

    $fileHash = 'File Hash: ' + "$($HASH_ALGORITHM.ToLower()) " + (
        (Get-FileHash -LiteralPath $inputFile.FullName -Algorithm $HASH_ALGORITHM).Hash.ToLower()
    )

    $videoInfo = 'Video: N/A'
    if ($null -ne $video) {
        $videoInfo = 'Video: ' + (JoinInfoText @(
                "$($video.Format)$(if($video.Format_Profile){" $($video.Format_Profile)"})$(if($video.Format_Level){"@L$($video.Format_Level)"})$(if($video.Format_Tier){"@$($video.Format_Tier)"}) ($($video.CodecID))",
                "$($video.Width)x$($video.Height) $(([double]$video.FrameRate).ToString('0.###')) FPS$(if($video.FrameRate_Mode -eq 'VFR'){' VFR'})",
                "$(if($video.ColorSpace){"$($video.ColorSpace)"})$(if($video.ChromaSubsampling){" $($video.ChromaSubsampling)"})$(if($video.BitDepth){" $($video.BitDepth) bits"})",
                "$(FormatBitRate $video)"
            ))
    }

    $audioInfo = 'Audio: N/A'
    if ($null -ne $audio) {
        $audioInfo = 'Audio: ' + (JoinInfoText @(
                "$($audio.Format)$(if($audio.Format_AdditionalFeatures){" $($audio.Format_AdditionalFeatures)"})$(if($audio.Format_Profile){" $($audio.Format_Profile)"}) ($($audio.CodecID))",
                "$($audio.Compression_Mode)",
                "$($audio.Channels) ch",
                "$(([int]$audio.SamplingRate/1000).ToString('0.###')) kHz$(if($audio.BitDepth){" $($audio.BitDepth) bit"})",
                "$(FormatBitRate $audio)"
            ))
    }

    Write-Host $fileInfo
    Write-Host $generalInfo
    Write-Host $fileHash
    Write-Host $videoInfo
    Write-Host $audioInfo

    $gridCols = $GRID_COLS_LANDSPACE
    $gridRows = $GRID_ROWS_LANDSPACE
    $gridCellHeight = $GRID_CELL_HEIGHT_LANDSPACE
    if (([double]$video.DisplayAspectRatio) -lt $PORTRAIT_RATIO) {
        # 竖屏视频 (高>宽)
        $gridCols = $GRID_COLS_PORTRAIT
        $gridRows = $GRID_ROWS_PORTRAIT
        $gridCellHeight = $GRID_CELL_HEIGHT_PORTRAIT
    }
    $frameInterval = [math]::Floor($video.FrameCount / ($gridCols * $gridRows))
    # 计算缩略图网格的整体宽度
    $gridWidth = ([int]$video.Width * ($gridCellHeight / [int]$video.Height)) * $gridCols + $GRID_GAP * ($gridRows - 1)
    # $gridHeight = $gridCellHeight * $gridRows + $GRID_GAP * ($gridRows - 1)

    $filter_thumbs = (
        "select=not(mod(n\,$($frameInterval)))",
        "scale=-1:$gridCellHeight",
        # 每个缩略图添加时间标记
        ('drawtext=' + ((
                "text='%{pts\:gmtime\:0\:%H\\\:%M\\\:%S}'",
                "fontcolor=$($COLOR_BG_FG[1])",
                "fontsize=$TIME_FONTSIZE",
                "fontfile='$DRAWTEXT_FONT'",
                'box=1:boxborderw=5|4',
                "boxcolor=$($COLOR_BG_FG[0])@0.5",
                'x=w-text_w-5',
                'y=h-text_h-4'
            ) -join ':'))
    ) -join ','

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
            ) -join ':')
        $infoY += $INFO_FONTSIZE + $INFO_LINE_GAP
    }
    $headerYb = $infoY + $INFO_HEADER_Y - $INFO_LINE_GAP - $GRID_GAP

    $footerText = '' + (
        (
            "Generated by $SCRIPT_NAME $PROJECT_VERSION",
            "$($mediaInfo.creatingLibrary.name) $($mediaInfo.creatingLibrary.version)",
            "FFmpeg $FFMPEG_VERSION",
            "$(Get-Date -Format 'yyyy/MM/ddTHH:mm:ssK' | EscapeDrawText)"
        ) -join ' // ')
    $footerFontsize = $FOOTER_HEIGHT - $FOOTER_LINE_GAP
    $infoDraw += 'drawtext=' + ((
            "text='$footerText'",
            "fontcolor=$($COLOR_BG_FG[1])",
            "fontsize=$footerFontsize",
            "fontfile='$DRAWTEXT_FONT'",
            "x=w-$($INFO_X)-text_w",
            "y=h-$($FOOTER_LINE_GAP)-text_h"
        ) -join ':')

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
        ($infoDraw -join ',')
    ) -join ''

    Write-Verbose $filter

    if (-not $NoOutput) {
        ffmpeg `
            -y `
            -v error `
            -hide_banner `
            -i "$($inputFile.FullName)" `
            -an `
            -frames 1 `
            -filter_complex "$filter" `
            "$outputFile"
    }

}

function Main {
    param(
        [Parameter(Mandatory = $false)]
        [string]$InputPath = '.',

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = '',

        [Parameter(Mandatory = $false)]
        [string[]]$IncludeExtensions = $INCLUDE_FILES,

        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $false,

        [Parameter(Mandatory = $false)]
        [int]$Depth = -1,

        [Parameter(Mandatory = $false)]
        [bool]$DryRun = $false,

        [Parameter(Mandatory = $false)]
        [bool]$NoOutput = $false,

        [Parameter(Mandatory = $false)]
        [bool]$NoOverwrite = $false
    )

    if (-not (Test-Path $InputPath)) {
        throw "InputPath NotFound: $InputPath"
    }
    $InputPath = Resolve-Path $InputPath

    # 未指定输出目录即为输入目录
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $OutputPath = $InputPath
    }
    else {
        $OutputPath = Resolve-OptionalPath $OutputPath
    }

    $Script:PROJECT_VERSION = Get-GitCommitName -Path $PSScriptRoot

    Write-Host
    Write-Host "  $SCRIPT_NAME $PROJECT_VERSION - Grid Thumbnail  "
    Write-Host

    Write-Host 'Input     ' $InputPath
    Write-Host 'Output    ' "$(if($NoOutput){'(Disabled)'}else{"$OutputPath $(if($NoOverwrite){'(NoOverwrite)'})"})"
    Write-Host 'Include   ' $IncludeExtensions
    Write-Host 'Recurse   ' $Recurse
    if ($Recurse -and ($Depth -ge 0)) { Write-Host 'Depth     ' $Depth }

    $mediainfo = Get-MediaInfo -ErrorAction Stop
    Write-Host "MediaInfo  $($mediainfo.Path) v$($mediainfo.Version)"

    $ffmpeg = Get-FFmpeg -ErrorAction Stop
    Write-Host "FFmpeg     $($ffmpeg.Path) v$($ffmpeg.Version)"
    $Script:FFMPEG_VERSION = $ffmpeg.Version

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

    if (-not ($DryRun -or $NoOutput)) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            Write-Warning "Create output dir $OutputPath"
            Write-Host
        }
    }

    if (-not $Recurse) {
        $Depth = 0
    }

    $files
    if ($Depth -ge 0) {
        $files = Get-ChildItem -LiteralPath $InputPath -File -Depth $Depth
    }
    else {
        $files = Get-ChildItem -LiteralPath $InputPath -File -Recurse
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
        $outputFileName = "$($_.BaseName)$($_.Extension).jpg"
        $outputFile = Join-Path $outputDir $outputFileName

        if ($NoOverwrite -and (Test-Path -LiteralPath $outputFile)) {
            Write-Verbose "[$i/$fileCount] Skip $($_.FullName)"
            return
        }
        Write-Host "[$i/$fileCount] $($_.FullName)" "$(if(-not $NoOutput){"-> $outputFile"})"

        if (-not ($DryRun -or $NoOutput)) {
            if (-not (Test-Path -LiteralPath $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                Write-Warning "Create output dir $outputDir"
            }
        }
        if (-not $DryRun) {
            ProcessSingle $_ $outputFile $NoOutput
        }

        Write-Host
    }
}

Main $InputPath $OutputPath $IncludeExtensions $Recurse $Depth $DryRun $NoOutput $NoOverwrite
