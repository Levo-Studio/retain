<img src="retain-logo.png" alt="" width="72">

# Retain

Lecture transcription for macOS · SwiftUI · offline

[Building](#building) · [Architecture](#architecture) · [Design](#design) ·
[License](#license)

---

Retain sits in the menu bar, records the lecture through the microphone,
transcribes it on the Neural Engine while it runs, and has a language model on
the same Mac turn the transcript into notes.

Nothing leaves the machine. There is no account, no cloud, no backend, no
telemetry, and no network code beyond a connection to `localhost`.

> Recording a lecture is not always allowed. Check with the person teaching, or
> your institution's rules, before you start.

## Status

**Phase 1 of 7.** The project builds and runs, puts an item in the menu bar, and
does nothing else yet. Recording, transcription, summarization, storage and the
interface are the phases after this one.

## What it will do

| | |
|---|---|
| **While the lecture runs** | Live transcript, note blocks that close every few minutes, speaker separation between the lecturer and a question from the room, an annotation hotkey, elapsed time |
| **Afterwards** | The lecture re-transcribed in batch for an authoritative transcript, diarization, written-out notes with timestamps, chapters and a chat about the lesson |
| **Library** | Courses and terms, full-text search across a whole term |
| **Settings** | The LM Studio connection, the speech model, the microphone |

## What it deliberately does not have

- No account and no sign-in.
- No server. Retain talks to a language model you run yourself, on your own Mac,
  and to nothing else.
- No analytics, no crash reporter, no telemetry of any kind.
- No sync and no export to a service.
- No system-audio capture. Retain records the microphone. It does not tap other
  applications' audio.
- No archive of recordings. The audio is deleted once it has been transcribed,
  and there is no playback anywhere in the app. What Retain keeps is the
  transcript, the notes and what you marked.

## How it works

While the lecture runs, the microphone feeds 16 kHz mono audio to two places at
once: straight to disk, and through a voice-activity gate into a streaming
speech model, which pushes partial lines into the interface. Every few minutes
of speech a block closes and a small language model summarises that block alone,
so notes appear during the lecture rather than after it.

When the lecture ends, the raw recording is transcribed again in one batch pass,
which is roughly twice as accurate as the streaming pass, and the block
summaries are reduced into the final notes against that transcript. **The live
transcript is feedback, not the record.**

**The audio is not kept.** Once the batch pass and the speaker separation have
both read the file and the transcript has been written, the recording is
deleted. Ninety minutes of 16 kHz mono is about 173 MB, and a school year of it
is tens of gigabytes of files you cannot read. A recording whose transcription
failed keeps its audio, so nothing is lost because a model was.

Battery is treated as a constraint rather than an afterthought: the audio buffer
is sized for fewer wakeups, the speech models stay on the Neural Engine, batch
work waits for mains power where it can, and the large language model only runs
when the Mac is plugged in.

## Requirements

- macOS 15.0 or later, Apple Silicon
- [LM Studio](https://lmstudio.ai) running locally, with a model loaded
- Xcode 26 to build

## Building

`xcode-select` points at the CommandLineTools on many machines, and those cannot
build this project. Either switch it permanently
(`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) or prefix
each call:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Retain.xcodeproj -scheme Retain \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Retain.xcodeproj -scheme Retain \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```

Tests are ad-hoc signed on purpose. An unsigned process has no keychain access
group, so every `Security` call fails with `errSecMissingEntitlement` before it
reaches any Retain code, and the keychain tests would pass by never running.

`CODE_SIGNING_ALLOWED=NO` means **you do not need a developer team** to build
Retain. Signing a build for distribution does; copy `Local.xcconfig.example` to
`Local.xcconfig` and put your Team ID in. `Base.xcconfig` includes it optionally,
so a clone without it still builds, and `Local.xcconfig` is ignored by git.

**Do not set the team in Xcode's Signing & Capabilities editor.** Picking it
from that dropdown writes `DEVELOPMENT_TEAM` into `project.pbxproj`, which is
tracked and public. `Local.xcconfig` feeds the same setting in from outside the
project, and Xcode shows the team as selected either way. Run
`scripts/install-hooks.sh` once after cloning and a commit that would carry a
signing identity into the project is refused.

The project uses synchronized folders — new files under `Retain/` and
`RetainTests/` join the target on their own, and `project.pbxproj` does not have
to be touched for that.

## Architecture

```
Retain/
  Core/Design/     RetainPalette, RetainTypography, RetainMetrics, RetainMotion
  Core/Audio/      the engine, the tap, the ring buffer, device listeners
  Core/Speech/     FluidAudio wrappers: streaming, batch, voice activity, diarization
  Core/LLM/        SummarizationBackend and the LM Studio conformer
  Core/Data/       the GRDB store, migrations, full-text search
  Core/Keychain/   the API-key wrapper
  Core/Power/      power source, low-power mode, the model-size decision
  Models/          plain Sendable record types
  Pipeline/        pure logic: block boundaries, map and reduce, transcript merging
  Features/        Shell, plus one folder per screen area
  Resources/       fonts, Localizable.xcstrings
RetainTests/       Swift Testing
docs/design/       the design export — read-only, never edited to match the code
```

**The pipeline knows no database and no view.** `Retain/Pipeline/` works on plain
`Sendable` values, so block boundaries, the map and reduce over summaries and the
merge of live and batch transcripts are pure functions whose tests run in
milliseconds without a database and without audio hardware.

**Colour, size and motion come only from the design layer.** No `.padding(17)`
and no `Color(hex:)` in a feature file. A missing value goes into
`RetainMetrics`, `RetainPalette`, `RetainTypography` or `RetainMotion`, not into
the call site.

**There is no network code outside `Core/LLM/`**, and what is there talks to
`localhost`.

| Dependency | Version | License |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 0.15.7 | Apache-2.0 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.11.1 | MIT |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 3.0.1 | MIT |
| [Defaults](https://github.com/sindresorhus/Defaults) | 9.0.9 | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.6 | MIT |

All five are permissive, so Retain's own licence is free to be stricter. Their
notices ship with the app.

## Design

The interface is drawn before it is built. `docs/design/` holds the export —
seven boards, a render of each, and `docs/design/README.md` with every colour,
size, radius, padding and timing as a concrete value. The folder is read-only:
if the code and the design disagree, the code is wrong.

## App icon

`retain-icon.icon` at the repository root is an Icon Composer document, wired up
through `ASSETCATALOG_COMPILER_APPICON_NAME`. There is no `AppIcon` in the asset
catalog on purpose — Xcode uses the Icon Composer file instead of one and
generates the pre-Tahoe sizes from it at build time.

`retain-logo.png` is the same mark as a flat file, for this README and the
website. It is not the app icon.

## Credits

[Julius Grimm](https://github.com/justthatrandomcoder) — [Levo Studio](https://levo-studio.com)

## License

**Source-available, not open source.** PolyForm Noncommercial 1.0.0: read it,
build it, change it, run it, pass it on — for any purpose that is not
commercial. Private study, hobby projects, schools, universities, public
research and government bodies are covered by name. Making money from it is
what the licence rules out.

The licence binds you, not Levo Studio, which holds the copyright and keeps
every right in Retain including the right to sell it. Contributors keep
authorship of what they wrote, are named in the credits, and grant Levo Studio
the rights it needs to ship that contribution in a release.

The full text, with both points spelled out, is in [`LICENSE`](LICENSE).

© 2026 Levo Studio
