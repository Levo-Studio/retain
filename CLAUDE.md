# CLAUDE.md — Working instructions for Retain

This file describes **Retain** and nothing else. No infrastructure, no servers,
no deployment, no other projects. What is written here applies to work in this
repository.

It is the first file every agent reads. If you have read only this file and
`docs/design/`, you know enough not to get anything badly wrong.

**Read `CONTEXT.md` second.** This file says how to work here; that one says
where the work actually stands — what the current pipeline is, which traps have
already cost a day, what changed recently and why, and what is left. It exists
so a session can be closed at any point without the next one starting from
nothing.

## What Retain is

Retain is a **menu-bar app for macOS**. It records the lesson through the
microphone, transcribes it live on the Neural Engine, and has a language model
running on the same Mac turn the transcript into notes.

**Everything is local.** No account, no cloud, no backend, no telemetry, and no
network code at all beyond a connection to `localhost`. That is not a roadmap
item that has not happened yet. It is the product.

**The audio is not kept.** The recording is working material: it is transcribed
in batch, diarized, and then deleted. Retain has no playback and no archive of
recordings — what survives a lesson is the transcript, the notes, the
annotations and the highlights. See `TransientAudio`.

The audience is students with an open laptop in the room.

What it does:

- **While the lesson runs** — live transcript (finished lines plus the line
  currently forming), note blocks that close every few minutes, speaker
  separation between the person teaching and a question from the room, course,
  lesson number, elapsed time, a `⌘⇧M` annotation that goes to the model, a
  speech/silence indicator, and a model size that follows battery versus mains.
- **Menu-bar popover** — recent lessons with their state, start and stop.
- **Lesson detail** — written-out notes, the full transcript with timestamps,
  a chapter rail and a chat that cites its sources; clicking a chapter or a
  citation brings that part of the lesson into view.
- **Library** — courses and terms, full-text search over every lesson in a term.
- **Settings** — LM Studio connection (base URL, optional API key, model picked
  from `/v1/models`), a connection test, the one-time speech-model download with
  progress, microphone selection, level meter, permission state.

## Design

**`docs/design/` is the design. Read `docs/design/README.md` before the first
line of UI work, and check against it before calling UI work done.** Not after
building something and comparing. Before.

- The folder is **read-only**. It is never edited to match the code. If the code
  and the design disagree, the code is wrong. If you think the design is wrong,
  that is a question for the owner.
- `docs/design/README.md` carries every colour, size, radius, padding, grid,
  weight, line-height and timing as a **concrete value**. Take them exactly. No
  rounding to a 4- or 8-point grid, no "close enough", no improving a ladder
  that is not a ladder. CSS pixels transfer 1:1 to AppKit/SwiftUI points.
- `Retain - Alle Screens.dc.html` is the file with the pixels in it, and where
  the HTML and the README disagree the **HTML wins**, because it is what was
  drawn. `screens/*.png` are renders of the same HTML for quick reference.
- `support.js` is the generic dc-runtime. It contains no design information. Do
  not spend a token on it.
- **If a value you need is not in the export, that is a question for the owner**,
  not a gap you fill with taste.
- The export is dark-only. **There is no light appearance**, because none is
  drawn. Do not invent one.
- The bottom of `docs/design/README.md` lists ten places where the export and
  the written brief disagree. They are open questions, not licence to pick. The
  design wins for anything that is drawn.

Do not start UI work with your own sketch. Start in `docs/design/`.

## Language

**Everything in this repository is English.** Interface, string catalog, code,
comments, commit messages, branch names, documentation, issues, pull requests.

The design export is German. **The labels are translated** — the table is at the
bottom of `docs/design/README.md`. Only the words change. Geometry, weight,
letter-spacing, casing, opacity and colour do not.

## Locked technical decisions

These were researched and settled. **Do not renegotiate them.** If you hit a
concrete reason while building that disproves one, say so and wait — do not
change it on your own.

| | |
|---|---|
| Deployment target | macOS 15.0, **Apple Silicon only** |
| Language | Swift 6, SwiftUI, strict concurrency |
| Audio | `AVAudioEngine` `inputNode.installTap`, 16 kHz mono Int16 → CAF. **No Core Audio process taps** — Retain records the microphone and nothing else. |
| Live speech-to-text | FluidAudio, `StreamingNemotronMultilingualAsrManager`, `languageCode "de-DE"`, `chunkMs 1120` |
| Final speech-to-text | FluidAudio, Parakeet TDT v3, batch, after the lesson |
| Voice activity | FluidAudio `VadManager`, **segmenting** the live transcript, not gating it. It gated the ASR until a lecturer across a classroom — audible on the recording — never cleared the bar at any threshold and never reached the screen. Every chunk now goes to the streaming model; the VAD only says where the lines break. See `LiveGate`. |
| Diarization | FluidAudio, offline, after the lesson |
| Language model | LM Studio over **`/api/v0/chat/completions`**, not `/v1/` — `/api/v0/` returns `stop_reason` and `loaded_context_length`, which are needed |
| Persistence | **GRDB.swift with FTS5.** Not SwiftData — it has no full-text search. The database is a plain SQLite file at `~/Library/Application Support/Retain/Retain.sqlite`. |
| UI shell | **`NSStatusItem` + `NSPanel`.** Not `MenuBarExtra` — it still cannot be opened programmatically, so it cannot have a hotkey. |
| Distribution | Developer ID and notarization. No sandbox, no App Store. |

Swift package dependencies, pinned:

| Package | Version | Licence |
|---|---|---|
| FluidAudio | from `0.15.7` | Apache 2.0 |
| GRDB.swift | 7.x | |
| KeyboardShortcuts | 3.0.1 | |
| Defaults | 9.0.9 | |
| Sparkle | 2.9.6 | |

**FluidAudio's documentation is wrong.** The README still says 0.12.4 and
`Documentation/API.md` contradicts the source in several places — wrong chunk
enums, wrong method names. **Read `Sources/FluidAudio/`, not the docs.**
Specifically: `StreamingAsrManager` does not exist, and `process(samples:)`
always returns `""` — partial results arrive through `setPartialCallback`.

## The architecture in one paragraph

While the lesson runs: microphone → 16 kHz mono → in parallel raw to disk **and**
through the streaming model → partial into the UI. The VAD runs alongside and
says where the lines break: a line closes three seconds after it reports the
speech stopped, or after twenty seconds regardless, and the model is reset
there. Nothing is dropped on the way to the model — a line the VAD never opened
is read off on the same timer, and what decoded to nothing is discarded. Every ~3 minutes of
speech, or on the annotation hotkey, a block closes: a small model (3–8B)
summarises **only that block**, and the card appears in the UI. After the
lesson: batch re-transcription of the raw file with Parakeet for the
authoritative transcript, then diarization, then a reduce over all block
summaries with a larger model into the final notes.

**The live transcript is feedback, not truth.** Streaming sits around 10 % WER
on German, batch around 5.9 %. The final notes always come from the batch
transcript.

## Hard rules — a violation is a bug

Battery is a hard constraint. Retain runs for a whole school day.

1. **`AudioHardwarePowerHint = "Favor Saving Power"` in `Info.plist`.** Verify
   with `plutil -p` on the built bundle that the key is actually in there. It
   turns 512-frame buffers into 4096 — eight times fewer wakeups.
2. **Never hold a display-sleep assertion.** On the first recording test, check
   `pmset -g assertions`. A display assertion attributable to our audio context
   is a P0 bug ahead of everything else.
3. **Never poll Core Audio properties.** Always
   `AudioObjectAddPropertyListenerBlock`. Polling drove `coreaudiod` to 65 % CPU
   in another app and leaked thousands of audio contexts.
4. **Do not configure the ANE away.** Every FluidAudio manager defaults to
   `.cpuAndNeuralEngine`. Hand it your own `MLModelConfiguration` with `.all`
   and CoreML routes the int8 ops to the GPU, running roughly ten times slower
   at several times the power.
5. **In the audio callback: `memcpy` and a timestamp, nothing else.** No
   `malloc`, no lock, no logging, no UI, no encoder. Ring buffer to a consumer
   at `.utility` QoS.
6. **Move batch work to mains power where possible.** `pmset -g batt` or
   `IOPSCopyPowerSourcesInfo`. Respect
   `ProcessInfo.processInfo.isLowPowerModeEnabled`.
7. **The large model runs on mains only.** On battery, the small one.
8. **Never set `.idleDisplaySleepDisabled`.**

And in general:

9. **No network code except `localhost`.** No analytics, no crash reporter, no
   telemetry. A dependency that brings any of that along gets dropped.
10. **The API key lives in the Keychain, never in `UserDefaults`** — even for
    localhost.
11. **No force-unwrap outside tests.**
12. **LM Studio: `json_schema` with a three-step fallback ladder** — strict →
    `json_object` → free text with tolerant extraction — and always validate
    through `Codable`. A 3–8B model does not hold a schema contract reliably.
13. **`contextOverflowPolicy` is `stopAtLimit`, and `stop_reason` is checked.**
    `truncateMiddle` would silently summarise half a lesson.

## Toolchain and commands

- **Xcode 26**, target **macOS 15.0**, **Swift 6** with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are on the main actor
  unless they say otherwise. Anything that should not be — the audio consumer,
  the pipeline, anything a test runs without a UI — is explicitly `nonisolated`.
- Bundle ID `apps.levo-studio.Retain`, matching its siblings.
- No linter, no formatter, no `.editorconfig`. Four spaces, no tabs,
  `// MARK: -` for structure, otherwise match the file you are editing.
- Synchronized folders: new files under `Retain/` join the target on their own.
  **`Retain.xcodeproj/project.pbxproj` is not touched for that.**

`xcode-select` points at the CommandLineTools on many machines, and those cannot
build this project. Prefix `DEVELOPER_DIR`:

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

Tests are ad-hoc signed on purpose: an unsigned process has no keychain access
group, so every `Security` call returns `errSecMissingEntitlement` (-34018)
before it reaches any Retain code, and the keychain tests would pass by never
running. Do not "simplify" this back to `CODE_SIGNING_ALLOWED=NO`.

**An app built without a real signing identity has to have its embedded
frameworks re-signed too.** Sparkle ships signed by its own team, and a dyld
that finds a framework whose Team ID differs from the process's refuses to map
it — the app then dies at launch with `Library not loaded`, before any of our
code runs. Sign inside out:

```bash
for f in Retain.app/Contents/Frameworks/*.framework; do
    codesign --force --sign - --timestamp=none "$f"
done
codesign --force --sign - --timestamp=none Retain.app
```

Phase 7 replaces the `-` with the Developer ID, in that order.

`DEVELOPMENT_TEAM` is not stored in the project. It goes in `Local.xcconfig`,
which is gitignored; `Base.xcconfig` includes it optionally so a clone without
it still builds.

## Architecture rules — not negotiable

```
Retain/
  Core/Design/     RetainPalette, RetainTypography, RetainMetrics, RetainMotion
  Core/Audio/      the engine, the tap, the ring buffer, device listeners
  Core/Speech/     FluidAudio wrappers: streaming, batch, VAD, diarization
  Core/LLM/        SummarizationBackend and the LM Studio conformer
  Core/Data/       the GRDB store, migrations, FTS5
  Core/Keychain/   the API-key wrapper
  Core/Power/      power source, low-power mode, the model-size decision
  Models/          plain Sendable record types
  Pipeline/        pure logic: block boundaries, map/reduce, transcript merging
  Features/        Shell, plus one folder per screen area
  Resources/       fonts, Localizable.xcstrings
RetainTests/       Swift Testing
docs/design/       the design export — read-only, never edited to match the code
```

**The pipeline knows no database.** `Retain/Pipeline/` works on plain `Sendable`
values, not on store rows. Block boundaries, the map/reduce over summaries and
the merge of live and batch transcripts are pure functions over pure values,
which is what lets their tests run in milliseconds without a database and
without audio hardware. Nothing from GRDB travels deeper than the hand-off type.

**The pipeline knows no view either.** No `@Observable`, no `Color`, no
`import SwiftUI`.

**Colour, size and motion come only from the design layer.** `RetainPalette`,
`RetainTypography`, `RetainMetrics`, `RetainMotion`, all filled from
`docs/design/`. No numeric or colour literals in feature files: no
`.padding(17)`, no `Color(hex:)`, no hand-rolled timing curve. If a value is
missing it goes into the design layer, not into the call site. *Reduce Motion*
is handled centrally in `RetainMotion` — at a hundred call sites it would be
forgotten at ninety of them.

**Everything the user can see is a string catalog key.**
`Retain/Resources/Localizable.xcstrings`, maintained by hand
(`extractionState: manual`). No visible string sits as a literal in a view. The
interface is English-only — do not add a second language.

Reach the catalog through `String(localized:comment:)`, not through a generated
symbol: `STRING_CATALOG_GENERATE_SYMBOLS` is **off**. It was on, and it made
two keys that differ only by punctuation a build error — "Settings" and
"Settings…" collide, and both are required, because macOS puts an ellipsis on a
menu item that opens a window and not on the button or the window's own title.
Nothing in Retain used a generated symbol, so the setting only ever cost
correct copy.

**There is no network code outside `Core/LLM/`**, and what is there talks to
`localhost`. If a view is building a `URLRequest`, the design of that feature is
wrong.

**Audio-thread code lives in `Core/Audio/` and is reviewed as real-time code.**
See hard rule 5. A `print` in there is a bug, not a style problem.

## Code style

- **Four spaces**, no tabs.
- `// MARK: -` in any file with more than one type or a handful of functions.
- **No numeric or colour literals in feature files.** See above.
- **Nothing enforces style** — no SwiftLint, no SwiftFormat. Match the file you
  are editing.
- Never change formatting in the same commit as logic.
- No `print`, no `debugPrint`, no commented-out code, no `TODO` without a name
  and a reason beside it. Preferably no `TODO` at all.

## Comments

Comments explain the **why**, not the what. A comment describing what the line
below it does is wasted. One explaining why it is not the obvious approach saves
the next person half a day. Whole paragraphs above a single constant are
deliberate here.

**A comment that promises something the code does not do is worse than no
comment.** If you change behaviour, pull the comments above it along — including
the ones in neighbouring files repeating the same promise. Every hard rule above
that shows up as a constant in the code gets the reason written beside it.

## Tests

`RetainTests/`, **Swift Testing** (`@Test`, `@Suite`, `#expect`) — not XCTest. A
red run is not delivered; a genuinely wrong test is fixed in its own commit,
with a reason.

The pipeline is where the tests live, because it is pure and there is no excuse:
block boundaries, the map/reduce, the merge of live and batch transcripts, the
three-step JSON fallback ladder, `stop_reason` handling, the power-source
decision. LM Studio is tested against recorded response shapes, never a live
endpoint. Speech models are tested against a committed short WAV, never the
microphone.

Every fix ships with a test that fails **without** the fix. The counter-check is
mandatory: pull the fix, watch it go red, put it back, watch it go green. A
regression test nobody has seen fail is decoration.

## Keeping `CONTEXT.md` true

`CONTEXT.md` is the handover. Its promise is that somebody who reads it knows
what the last session knew, so it is **updated in the same commit as the change
it describes**, never in a sweep afterwards — a sweep is how it becomes a file
nobody trusts, and an untrusted handover is worse than none.

What belongs in it:

- a decision that changes how the app works, especially one that contradicts
  something written down elsewhere;
- a trap that cost real time, with the symptom it presents as — the symptom is
  the part that saves the next person;
- what is deliberately unfinished, and why;
- a standing instruction from the owner about how work is delivered.

What does not: a list of commits (git has one), anything the code already says
plainly, or a roadmap.

If a change makes a sentence in it wrong, fix the sentence. A handover that
describes a pipeline the app no longer has is the same bug as a comment that
promises what the code does not do.

## Commits

- Conventional Commits, description in **English**: `type(scope): description`.
  Scope optional but welcome.
- Types in use: `fix`, `feat`, `test`, `refactor`, `chore`, `design`, `docs`,
  `build`, `perf`, `security`, `revert`.
- The description says **what now holds**, not what was done.
- **One commit = one logical change.** No collection commits, no `WIP`, no
  "fix stuff", formatting never in the same commit as logic.
- **No tool trailers.** No `Co-Authored-By`, no "Generated with", no session
  IDs, no mention of AI tooling — not in commits, not in PR titles or bodies,
  not in code comments, not anywhere in the repo.

## Branches

**Never commit directly to `main`** unless the owner says so explicitly.

Before every new branch: `git fetch --all --prune`, and if the base is behind
its remote, pull before branching.

Prefixes: `feat/`, `fix/`, `hotfix/`, `security/`, `refactor/`, `perf/`,
`design/`, `feedback/`, `infra/`, `ci/`, `deps/`, `migration/`, `docs/`,
`test/`, `chore/`, `spike/`, `release/`, `revert/`. Lowercase, hyphens,
specific: `feat/streaming-asr-gate`, not `feat/speech`.

**No `claude/` prefix** and no other named after the tool that was used. The
branch is named after the work, not the hammer.

## README tone

Short, factual, no marketing. **Forbidden:** seamless, cutting-edge, leverage,
empower, robust, powerful, revolutionary, game-changing, exclamation marks and
emoji. Say what the app is, what it deliberately does not have, and how to get
it running. Match the tone of the READMEs of Fuel and Score.

The README carries one plain sentence telling users to check with the person
teaching, or their institution's rules, before recording. One sentence, not a
disclaimer paragraph.

## Conventions come from Fuel and Score

Retain follows the repository conventions of `levo-studio/fuel` and
`levo-studio/score`: `Base.xcconfig` plus a gitignored `Local.xcconfig` for the
development team, synchronized folders so `project.pbxproj` stays untouched,
`Core/` and `Features/` splitting the app, a design layer that owns every
number, a hand-maintained string catalog, Swift Testing, and Conventional
Commits. **Do not invent your own.** Where Fuel and Score disagree, Fuel is
newer and wins — which is why this repository is English throughout, as Fuel is,
and not German, as Score is.

Retain departs from them in one place: **the licence is PolyForm Noncommercial
1.0.0**, not the bespoke source-available licence Fuel and Score carry. Retain
is therefore source-available and **not open source** — do not describe it as
open source anywhere, and do not add it to a listing that filters on OSI
approval.

Two consequences worth holding on to, because both get asked:

- The licence binds licensees, not Levo Studio. Levo Studio holds the copyright
  and keeps every right in Retain, including selling it. Nothing in the
  repository may suggest Retain cannot be sold by its owner.
- A contribution ships in a release only because the contributor grants Levo
  Studio the rights for it. That grant is in `LICENSE`; do not remove it, and do
  not merge a contribution from someone who has refused it.

## None of this happens without asking

Ask first, then touch:

- **Anything in `docs/design/`.** The export is read-only. Refreshing it is the
  owner's job and lands as its own commit.
- **Any of the locked technical decisions above**, including swapping a
  dependency or its version.
- **Adding a dependency** beyond the five listed.
- **`DEVELOPMENT_TEAM` and the bundle identifier** in `Retain.xcodeproj`.
- **`Retain.xcodeproj/project.pbxproj`** for anything but a deliberate
  build-setting change.
- **Anything that would put a Retain request anywhere but `localhost`**, or an
  API key anywhere but the Keychain. There is no version of this that gets
  approved, but ask anyway so the answer is on the record.
- **Deleting user data paths** — anything that drops a table, throws a store
  away, or removes a recording from disk.
- **Editing a migration that has already shipped.** The migrator only compares
  identifiers, so an edited migration never runs again on a database that has
  recorded it — the install is left on the old schema for good, and every query
  against the new one throws behind a `try?`. That happened once, to
  `v1.library`; `v4.courses-across-terms` is the repair. Correct a mistake with
  the next migration, guarded on the shape it finds rather than on the
  identifier.
- **Push to `main`.**
