# Whisper.cpp GPU Acceleration on Intel Iris Xe

Benchmarking different GPU backends for [whisper.cpp](https://github.com/ggerganov/whisper.cpp) speech-to-text on an **Intel Iris Xe Graphics** (integrated, 1 GB shared VRAM).

## TL;DR

**Vulkan is the winner.** 3.3x faster than CPU on the medium model.

| Backend | JFK Base | JFK Medium | JFK Large-v3-q5_0 |
|---------|----------|------------|---------------------|
| **Vulkan GPU** | **1.15s** | **6.4s** | **12.7s** |
| CPU-only (AVX512) | 2.15s | 21.7s | 40.6s |

## System

- **CPU:** Intel (8 threads, AVX512)
- **GPU:** Intel Iris Xe Graphics (integrated, driver 30.0.101.1340)
- **OS:** Windows
- **whisper.cpp:** v1.9.1 (cloned from source)
- **Audio:** JFK sample (11 sec, 176000 samples)

## Backends Tested

### 1. CPU-only (baseline)

Built with OpenVINO compiled in but GPU disabled via `--no-gpu`. Uses ggml's native CPU backend with AVX512 SIMD.

```powershell
.\build\bin\Release\whisper-cli.exe -m ggml-base.bin -t 8 --no-gpu -f samples\jfk.wav
```

### 2. Vulkan GPU (winner)

Built with `-DGGML_VULKAN=ON`. Uses the Iris Xe GPU via Vulkan 1.2 compute shaders.

```powershell
.\build-vulkan\bin\Release\whisper-cli.exe -m ggml-base.bin -t 4 -f samples\jfk.wav
```

### 3. OpenVINO GPU (failed)

Built with `-DGGML_OPENVINO=ON`. Uses the Intel OpenVINO toolkit for GPU inference.

**Status: Crashes at runtime.**

The ggml scheduler has a bug: it pre-allocates tensors in the OPENVINO0 buffer, then when a CPY (copy) operation is needed for recurrent-state snapshots, the scheduler finds that the buffer can't run the operation and calls `GGML_ABORT`. The `supports_op` function correctly marks these CPY ops as unsupported, but the buffer allocation has already happened.

This is an **upstream bug** in `ggml-backend.cpp:898` — the scheduler forces views to inherit their source's backend buffer, then crashes when the op isn't supported.

### 4. OpenVINO CPU plugin (not available)

whisper.cpp only uses OpenVINO for GPU acceleration. There is no separate path to use OpenVINO's optimized CPU plugin. The `--no-gpu` flag disables OpenVINO entirely and falls back to ggml's native CPU backend.

### 5. SYCL (failed to install)

Intel's oneAPI DPC++/C++ Compiler provides native SYCL support for Intel GPUs. Requires the full Intel oneAPI toolkit (~5 GB download). The silent installer failed with error 1003 (needs GUI + admin elevation).

## Benchmark Results

### Base Model (147 MB)

| Backend | Threads | Encode | Total | Speedup |
|---------|---------|--------|-------|---------|
| **Vulkan GPU** | 1 | 284 ms | 1.18s | 1.8x |
| **Vulkan GPU** | 4 | 270 ms | **1.15s** | **1.9x** |
| **Vulkan GPU** | 8 | 288 ms | 1.16s | 1.9x |
| CPU-only | 1 | 3,943 ms | 5.78s | 0.4x |
| CPU-only | 2 | 2,482 ms | 3.72s | 0.6x |
| CPU-only | 4 | 1,599 ms | 2.55s | 0.8x |
| CPU-only | 8 | 1,245 ms | **2.15s** | 1x |

Key insight: Vulkan encode time is constant (~280 ms) regardless of CPU thread count, because the work runs on the GPU.

### Medium Model (1.5 GB)

| Backend | Threads | Encode | Total | Speedup |
|---------|---------|--------|-------|---------|
| **Vulkan GPU** | 4 | 2,725 ms | **6.4s** | **3.3x** |
| **Vulkan GPU** | 8 | 2,715 ms | 6.4s | 3.4x |
| CPU-only | 8 | 15,823 ms | 21.7s | 1x |

### Large-v3-q5_0 Model

| Backend | Threads | Encode | Total | Speedup |
|---------|---------|--------|-------|---------|
| **Vulkan GPU** | 4 | 4,313 ms | **12.7s** | **3.2x** |
| CPU-only | 8 | 31,761 ms | 40.6s | 1x |

## Transcription Quality

Both CPU and Vulkan produce **identical output** on the JFK sample:

```
[00:00:00.000 --> 00:00:10.500]   And so my fellow Americans ask not what your
country can do for you, ask what you can do for your country.
```

## Quick Start

The repo includes pre-built Vulkan GPU binaries. Just download models and run:

```powershell
# 1. Download models
.\download-models.ps1

# 2. Transcribe
.\build-vulkan\bin\Release\whisper-cli.exe -m ggml-medium.bin -t 4 -f samples\jfk.wav
```

### Available Models

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| `ggml-base.bin` | 147 MB | 1.15s | Quick testing |
| `ggml-medium.bin` | 1.5 GB | 6.4s | Good balance |
| `ggml-large-v3-q5_0.bin` | 1 GB | 12.7s | Best quality |

### CLI Options

```powershell
.\build-vulkan\bin\Release\whisper-cli.exe [options]
  -m <model>     Model path (required)
  -f <wav>       Audio file (required)
  -t <threads>   CPU threads (default: 4, doesn't affect GPU encode)
  --output-srt   Output SRT subtitles
  --output-txt   Output plain text
  --language <l> Force language (e.g. "en", "it")
  --translate    Translate to English
```

### Examples

```powershell
# English transcription with SRT output
.\build-vulkan\bin\Release\whisper-cli.exe -m ggml-medium.bin -t 4 --language en --output-srt -f samples\jfk.wav

# Translate Italian audio to English
.\build-vulkan\bin\Release\whisper-cli.exe -m ggml-medium.bin -t 4 --translate --output-txt -f italian_audio.wav

# Fast base model for testing
.\build-vulkan\bin\Release\whisper-cli.exe -m ggml-base.bin -t 4 -f samples\jfk.wav
```

## Building from Source

If you want to build yourself instead of using the pre-built binaries:

### Prerequisites

- Windows with Intel Iris Xe Graphics
- Visual Studio 2022 Build Tools (MSVC)
- [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) (LunarG)
- [CMake](https://cmake.org/download/) 3.21+

### Build

```powershell
# Clone whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git whisper-cpp-source
cd whisper-cpp-source

# Set Vulkan SDK path
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"

# Configure and build
cmake -B build-vulkan -G "Visual Studio 17 2022" -A x64 -DGGML_VULKAN=ON
cmake --build build-vulkan --config Release -j
```

## Why Vulkan is Fast on Iris Xe

The Intel Iris Xe is an integrated GPU with 96 execution units and shared memory. While it lacks the raw compute of a discrete GPU, it excels at the matrix operations that whisper.cpp's encoder/decoder need. The Vulkan compute shaders map well to the SIMD-like architecture of Intel's EU cores.

CPU-only inference with AVX512 is also fast, but the GPU's parallel execution units give a 2-3x advantage for the encode step, which is the bottleneck for speech-to-text.

## Files

- `build-vulkan/bin/Release/whisper-cli.exe` — Pre-built Vulkan GPU binary
- `build-vulkan/bin/Release/ggml-vulkan.dll` — Vulkan compute backend (46 MB)
- `build-vulkan/bin/Release/*.dll` — Required runtime DLLs
- `download-models.ps1` — Downloads models from Hugging Face
- `samples/jfk.wav` — JFK speech sample (11 sec)
- `README.md` — This file

Models are excluded from the repo (too large). Run `.\download-models.ps1` to fetch them.

## License

whisper.cpp is MIT licensed. Models are subject to their respective licenses.
