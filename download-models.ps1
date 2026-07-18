# Download whisper.cpp models from Hugging Face
# Run from the project root directory

$baseUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
$models = @(
    @{ Name = "ggml-base.bin"; Size = "147 MB" },
    @{ Name = "ggml-medium.bin"; Size = "1.5 GB" },
    @{ Name = "ggml-large-v3-q5_0.bin"; Size = "1 GB" }
)

Write-Host "Whisper.cpp Model Downloader" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

foreach ($model in $models) {
    if (Test-Path $model.Name) {
        Write-Host "$($model.Name) already exists, skipping." -ForegroundColor Green
        continue
    }

    Write-Host "Downloading $($model.Name) ($($model.Size))..." -ForegroundColor Yellow
    $url = "$baseUrl/$($model.Name)"

    try {
        # Use BitsTransfer for resume support
        Start-BitsTransfer -Source $url -Destination "." -ErrorAction Stop
        Write-Host "Done!" -ForegroundColor Green
    }
    catch {
        Write-Host "BitsTransfer failed, trying WebClient..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        (New-Object System.Net.WebClient).DownloadFile($url, $model.Name)
        Write-Host "Done!" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "All models downloaded!" -ForegroundColor Green
Write-Host "Run transcription with:" -ForegroundColor Cyan
Write-Host '  .\build-vulkan\bin\Release\whisper-cli.exe -m ggml-medium.bin -t 4 -f your_audio.wav'
