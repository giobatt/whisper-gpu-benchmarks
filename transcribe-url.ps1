# Transcribe audio/video from a URL or local file using whisper.cpp
# Usage:
#   .\transcribe-url.ps1 "https://youtube.com/watch?v=..."
#   .\transcribe-url.ps1 "C:\Downloads\lecture.mp4"
#   .\transcribe-url.ps1 ".\samples\jfk.wav" -Model ggml-large-v3-q5_0.bin -Language en -Threads 8

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Source,

    [string]$Model = "ggml-medium.bin",
    [string]$Language = "",
    [int]$Threads = 4,
    [switch]$Srt
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-Dependency {
    param(
        [string]$Name,
        [string]$CheckCmd,
        [scriptblock]$Install
    )

    if (Test-Command $CheckCmd) {
        Write-Host "  $Name found." -ForegroundColor Green
        return
    }

    Write-Host "  $Name not found. Installing..." -ForegroundColor Yellow
    try {
        & $Install
    }
    catch {
        Write-Host "  Failed to install $Name : $_" -ForegroundColor Red
        Write-Host "  Please install $Name manually and re-run this script." -ForegroundColor Red
        exit 1
    }

    # Re-check
    if (-not (Test-Command $CheckCmd)) {
        Write-Host "  $Name installation succeeded but command still not on PATH." -ForegroundColor Red
        Write-Host "  You may need to restart your terminal." -ForegroundColor Red
        exit 1
    }
    Write-Host "  $Name installed successfully." -ForegroundColor Green
}

function ConvertTo-SafeFilename {
    param([string]$Name)
    $Name -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_'
}

# ---------------------------------------------------------------------------
# 1. Detect input type
# ---------------------------------------------------------------------------

$IsLocalFile = Test-Path -LiteralPath $Source -PathType Leaf

# Clean URL: strip playlist params that confuse yt-dlp
if (-not $IsLocalFile -and $Source -match '\?') {
    $BaseUrl = $Source.Split('?')[0]
    $QueryParams = ($Source.Split('?')[1]) -split '&' | Where-Object { $_ -notmatch '^(list|index|start_radio)=' }
    if ($QueryParams) {
        $Source = $BaseUrl + '?' + ($QueryParams -join '&')
    } else {
        $Source = $BaseUrl
    }
}

# YouTube: extract video ID to avoid playlist & param issues
if (-not $IsLocalFile -and $Source -match '(youtube\.com/watch\?.*v=|youtu\.be/)([a-zA-Z0-9_-]{11})') {
    $Source = 'https://www.youtube.com/watch?v=' + $Matches[2]
}

# ---------------------------------------------------------------------------
# 2. Check / install dependencies
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Whisper.cpp Transcriber" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host ""
if ($IsLocalFile) {
    Write-Host "Input: local file  $Source" -ForegroundColor DarkGray
} else {
    Write-Host "Input: URL  $Source" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "Checking dependencies..." -ForegroundColor Cyan

# Add local tools to PATH if they exist
$LocalFfmpeg = Join-Path $ScriptDir "tools\ffmpeg\ffmpeg.exe"
if (Test-Path $LocalFfmpeg) {
    $env:PATH = "$(Split-Path $LocalFfmpeg);$env:PATH"
}

# Add Python Scripts to PATH for yt-dlp
$AppData = [System.Environment]::GetFolderPath('ApplicationData')
$PythonScriptsDir = Get-ChildItem -Path (Join-Path $AppData "Python") -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "Scripts" } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if ($PythonScriptsDir) {
    $env:PATH = "$PythonScriptsDir;$env:PATH"
}

if (-not $IsLocalFile) {
    Assert-Dependency -Name "yt-dlp" -CheckCmd "yt-dlp" -Install {
        pip install yt-dlp
    }
}

Assert-Dependency -Name "ffmpeg" -CheckCmd "ffmpeg" -Install {
    $ToolsDir = Join-Path $ScriptDir "tools"
    $FfmpegDir = Join-Path $ToolsDir "ffmpeg"
    if (-not (Test-Path $FfmpegDir)) {
        New-Item -ItemType Directory -Path $FfmpegDir -Force | Out-Null
    }
    $ZipPath = Join-Path $ToolsDir "ffmpeg.zip"
    Write-Host "  Downloading ffmpeg..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" -OutFile $ZipPath -UseBasicParsing
    Write-Host "  Extracting..." -ForegroundColor Yellow
    Expand-Archive -Path $ZipPath -DestinationPath $ToolsDir -Force
    $ExtractedDir = Get-ChildItem -Path $ToolsDir -Directory | Where-Object { $_.Name -like "ffmpeg-*" } | Select-Object -First 1
    if ($ExtractedDir) {
        $BinDir = Join-Path $ExtractedDir.FullName "bin"
        Copy-Item -Path (Join-Path $BinDir "ffmpeg.exe") -Destination $FfmpegDir -Force
        Copy-Item -Path (Join-Path $BinDir "ffprobe.exe") -Destination $FfmpegDir -Force
        Remove-Item -Path $ExtractedDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
    $env:PATH = "$FfmpegDir;$env:PATH"
}

$WhisperCli = Join-Path $ScriptDir "build-vulkan\bin\Release\whisper-cli.exe"
if (-not (Test-Path $WhisperCli)) {
    Write-Host "  whisper-cli.exe not found at $WhisperCli" -ForegroundColor Red
    Write-Host "  Build whisper.cpp with Vulkan support first (see README.md)." -ForegroundColor Red
    exit 1
}
Write-Host "  whisper-cli found." -ForegroundColor Green

$ModelPath = Join-Path $ScriptDir $Model
if (-not (Test-Path $ModelPath)) {
    Write-Host "  Model '$Model' not found at $ModelPath" -ForegroundColor Red
    Write-Host "  Run .\download-models.ps1 or download from https://huggingface.co/ggerganov/whisper.cpp" -ForegroundColor Red
    exit 1
}
Write-Host "  Model: $Model" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Prepare audio (download or convert)
# ---------------------------------------------------------------------------

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "whisper_url_$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    if ($IsLocalFile) {
        # -------------------------------------------------------------------
        # Local file: convert directly with ffmpeg
        # -------------------------------------------------------------------

        Write-Host ""
        Write-Host "Converting audio..." -ForegroundColor Cyan

        $ConvertedWav = Join-Path $TempDir "audio_16k.wav"
        $FfmpegArgs = @(
            "-i", (Resolve-Path -LiteralPath $Source).Path,
            "-ar", "16000",
            "-ac", "1",
            "-y",
            $ConvertedWav
        )
        Write-Host "  Running: ffmpeg $($FfmpegArgs -join ' ')" -ForegroundColor DarkGray
        $FfmpegProc = Start-Process -FilePath "ffmpeg" -ArgumentList $FfmpegArgs -NoNewWindow -PassThru -Wait -RedirectStandardError "$TempDir\ffmpeg_err.txt"
        $FfmpegErrors = Get-Content "$TempDir\ffmpeg_err.txt" -ErrorAction SilentlyContinue
        if ($FfmpegProc.ExitCode -ne 0) {
            Write-Host "  ffmpeg conversion failed with exit code $($FfmpegProc.ExitCode)" -ForegroundColor Red
            $FfmpegErrors | Where-Object { $_ -match "error|Error|ERROR" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            exit 1
        }
        Write-Host "  Converted to 16kHz mono WAV." -ForegroundColor Green

        # Output name from input filename
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Source)
        $SafeTitle = ConvertTo-SafeFilename -Name $BaseName
    }
    else {
        # -------------------------------------------------------------------
        # URL: download with yt-dlp, then convert
        # -------------------------------------------------------------------

        Write-Host ""
        Write-Host "Downloading audio..." -ForegroundColor Cyan

        $TempAudio = Join-Path $TempDir "audio"
        $DlpArgs = @(
            "-x",
            "--audio-format", "wav",
            "--no-playlist",
            "--restrict-filenames",
            "--ffmpeg-location", (Split-Path $LocalFfmpeg),
            "-o", ($TempAudio + ".%(ext)s"),
            $Source
        )
        Write-Host "  Running: yt-dlp $($DlpArgs -join ' ')" -ForegroundColor DarkGray
        & yt-dlp @DlpArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  yt-dlp failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }

        # Find the downloaded file
        $DownloadedFile = Get-ChildItem -Path $TempDir -Filter "audio.*" | Select-Object -First 1
        if (-not $DownloadedFile) {
            Write-Host "  yt-dlp did not produce an audio file." -ForegroundColor Red
            exit 1
        }
        Write-Host "  Downloaded: $($DownloadedFile.Name)" -ForegroundColor Green

        Write-Host ""
        Write-Host "Converting audio..." -ForegroundColor Cyan

        $ConvertedWav = Join-Path $TempDir "audio_16k.wav"
        $FfmpegArgs = @(
            "-i", $DownloadedFile.FullName,
            "-ar", "16000",
            "-ac", "1",
            "-y",
            $ConvertedWav
        )
        Write-Host "  Running: ffmpeg $($FfmpegArgs -join ' ')" -ForegroundColor DarkGray
        $FfmpegProc = Start-Process -FilePath "ffmpeg" -ArgumentList $FfmpegArgs -NoNewWindow -PassThru -Wait -RedirectStandardError "$TempDir\ffmpeg_err.txt"
        $FfmpegErrors = Get-Content "$TempDir\ffmpeg_err.txt" -ErrorAction SilentlyContinue
        if ($FfmpegProc.ExitCode -ne 0) {
            Write-Host "  ffmpeg conversion failed with exit code $($FfmpegProc.ExitCode)" -ForegroundColor Red
            $FfmpegErrors | Where-Object { $_ -match "error|Error|ERROR" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            exit 1
        }
        Write-Host "  Converted to 16kHz mono WAV." -ForegroundColor Green

        # Output name from video title
        $TitleArgs = @("--print", "title", "--no-playlist", $Source)
        $VideoTitle = & yt-dlp @TitleArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($VideoTitle)) {
            $VideoTitle = "transcription"
        }
        $SafeTitle = ConvertTo-SafeFilename -Name $VideoTitle
    }

    if ($SafeTitle.Length -gt 80) {
        $SafeTitle = $SafeTitle.Substring(0, 80)
    }

    # -----------------------------------------------------------------------
    # 4. Transcribe with whisper-cli
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "Transcribing..." -ForegroundColor Cyan

    $OutputTxt = Join-Path $ScriptDir "$SafeTitle.txt"

    $WhisperArgs = @(
        "-m", $ModelPath,
        "-t", $Threads.ToString(),
        "-f", $ConvertedWav,
        "--output-txt"
    )
    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $WhisperArgs += "--language"
        $WhisperArgs += $Language
    }
    if ($Srt) {
        $WhisperArgs += "--output-srt"
    }

    Write-Host "  Model: $Model | Threads: $Threads | Language: $(if ($Language) { $Language } else { 'auto-detect' })" -ForegroundColor DarkGray
    & $WhisperCli @WhisperArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  whisper-cli failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }

    # whisper-cli writes output next to the input wav — move it to project root
    $WhisperOutput = Join-Path $TempDir "audio_16k.wav.txt"
    if (Test-Path $WhisperOutput) {
        Move-Item -Path $WhisperOutput -Destination $OutputTxt -Force
    }
    else {
        Write-Host "  Warning: whisper output file not found at $WhisperOutput" -ForegroundColor Yellow
    }

    if ($Srt) {
        $SrtOutput = Join-Path $TempDir "audio_16k.wav.srt"
        $SrtDest = Join-Path $ScriptDir "$SafeTitle.srt"
        if (Test-Path $SrtOutput) {
            Move-Item -Path $SrtOutput -Destination $SrtDest -Force
        }
    }

    Write-Host ""
    Write-Host "Done!" -ForegroundColor Green
    Write-Host "  Transcript saved to: $OutputTxt" -ForegroundColor Cyan
    if ($Srt) {
        Write-Host "  SRT saved to: $SafeTitle.srt" -ForegroundColor Cyan
    }
}
finally {
    # -----------------------------------------------------------------------
    # 5. Clean up temp files
    # -----------------------------------------------------------------------
    if (Test-Path $TempDir) {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
