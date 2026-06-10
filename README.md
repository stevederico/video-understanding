# video-understanding

Your agent's movie critic. Turns any video into something an AI agent can fully
understand: timestamped frames + an SRT transcript, then the agent reviews the
frames against the captions and writes a complete `understanding.md`.

Two stages:
1. **`video-understanding.sh`** — mechanical extraction (ffmpeg + local whisper.cpp STT). No AI.
2. **The agent** — reads the frames (filenames are timestamps) and `transcript.srt`,
   correlates picture↔speech, and writes `understanding.md`. Instructions land in
   `AGENT.md` inside the output folder.

## Install

```sh
git clone https://github.com/stevederico/video-understanding.git && cd video-understanding
```

You need **ffmpeg** and the **whisper.cpp CLI** (`whisper-cli`) on your `PATH`, plus a
GGML model. Full setup on a fresh machine:

### 1. ffmpeg

- macOS: `brew install ffmpeg`
- Linux: `sudo apt install ffmpeg` (or `dnf`/`pacman`)
- Windows: [ffmpeg.org](https://ffmpeg.org/download.html)

### 2. Build whisper.cpp and put the CLI on PATH

Builds from the official upstream repo ([ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)).
Needs `git` + `cmake` (and `SDL2` only if you want the realtime `whisper-stream`
mic example). On Apple Silicon the build is Metal-accelerated automatically.

```sh
# clone into a tool location (not a projects dir)
git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/opt/whisper.cpp
cd ~/.local/opt/whisper.cpp

# build (drop -DWHISPER_SDL2=ON if you don't need the mic streamer)
cmake -B build -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j --config Release

# expose the CLIs on PATH (symlink into a dir already on $PATH)
mkdir -p ~/.local/bin
for b in whisper-cli whisper-stream whisper-server; do
  ln -sf ~/.local/opt/whisper.cpp/build/bin/$b ~/.local/bin/$b
done
```

Make sure `~/.local/bin` is on your `PATH` (`echo $PATH | tr ':' '\n' | grep .local/bin`).
The symlinks point into `build/bin`, where the dylibs live — **don't move the
build dir afterward**, or rebuild in place if you do (rpaths are absolute).

### 3. Download a model

```sh
cd ~/.local/opt/whisper.cpp
bash models/download-ggml-model.sh large-v3-turbo   # ~1.5G, the default
```

This lands at `~/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin`, which is
exactly where the script looks by default. Override with `$WHISPER_MODEL` if you
keep models elsewhere.

Verify the whole chain:

```sh
whisper-cli -m ~/.local/opt/whisper.cpp/models/ggml-large-v3-turbo.bin \
  -f ~/.local/opt/whisper.cpp/samples/jfk.wav -otxt -of /tmp/jfk && cat /tmp/jfk.txt
```

## Use

```sh
./video-understanding.sh <video> [interval_seconds] [output_dir]
# e.g.
./video-understanding.sh ~/Movies/demo.mov 5
```

Then tell your agent: *"read `demo_understand/AGENT.md` and do it."*

## Output (in `<video>_understand/`)

| file | what |
|---|---|
| `frames/tNNmNNs.jpg` | one frame per interval; **filename = exact timestamp** |
| `transcript.srt` | timestamped captions |
| `transcript.txt` / `.json` | same transcript, other formats |
| `manifest.json` | duration, fps, interval, frame→time map |
| `AGENT.md` | stage-2 instructions for the agent |

## STT engine

Local **whisper.cpp** (`whisper-cli`) — GPU-accelerated (Metal on Apple Silicon),
running the `large-v3-turbo` model set up above. For a different model size,
download the matching `ggml-<size>.bin` (step 3) and pass `VU_MODEL`.

| var | default | note |
|---|---|---|
| `VU_MODEL` | `large-v3-turbo` | needs matching `ggml-<model>.bin` (`tiny`…`large-v3`) |
| `WHISPER_MODEL` | `~/.local/opt/whisper.cpp/models/ggml-<VU_MODEL>.bin` | explicit model path |
| `VU_LANG` | auto-detect | set e.g. `en` to skip detection |
| `FRAME_QUALITY` | `3` | ffmpeg `-q:v`, 2 best … 31 worst |

```sh
VU_MODEL=base ./video-understanding.sh demo.mov            # smaller/faster, lower accuracy
WHISPER_MODEL=/path/ggml-large-v3.bin ./video-understanding.sh demo.mov
```

## Bonus: `x-transcribe`

A standalone X-post video transcriber (also whisper.cpp-based) lives alongside as
`./x-transcribe`. Downloads an X video, extracts audio, chunks at 2 min, and writes
a markdown transcript. Same `$WHISPER_MODEL` setup as above. See the header of the
script for usage.

## Notes

- Frames are extracted by **seeking to each exact timestamp** (`ffmpeg -ss`), so
  the filename never drifts from the real frame time — unlike the `fps=1/N` filter.
- Fixed-interval sampling: smaller interval for fast-cut content, larger for
  talking-head/screencast.
- All local. No cloud, no API key. Whisper `large-v3-turbo` is the current
  best general model — there's no newer Whisper architecture to switch to.
