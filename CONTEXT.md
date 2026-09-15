# CONTEXT.md — where Retain stands, and how to pick it up

This file is for an agent or a person opening this repository with no memory of
what came before. Read it first, then read what it tells you to read. It is kept
current: **anything that changes what the next session needs to know is written
here in the same commit that changes it.**

It is not a design document, a changelog or a roadmap. It is the state of the
work, why the work is shaped the way it is, and the traps that have already cost
a day each.

---

## 1. Read these, in this order

| | |
|---|---|
| `CLAUDE.md` | The working instructions. Locked technical decisions, the hard rules, the architecture, the commit and branch conventions, and the list of things to ask about before touching. **It wins over anything in this file.** |
| `docs/design/README.md` | The design, as concrete values. Read before the first line of UI work, not after. The folder is read-only. |
| `docs/design/Retain - Alle Screens.dc.html` | The pixels. Where the HTML and the README disagree, the HTML wins. |
| `README.md` | What the app is, for somebody who is not going to work on it. |
| This file | What has actually happened, and what is unfinished. |

`docs/design/support.js` is a generic runtime with no design in it. Do not read
it.

---

## 2. The core idea, in one paragraph

Retain records a lesson through the microphone, transcribes it on the Neural
Engine, and has a language model running on the same Mac turn the transcript
into notes. **Everything is local** — no account, no cloud, no telemetry, and no
network code beyond `localhost`. **The audio is not kept**: it is working
material, transcribed in batch and then deleted. What survives a lesson is the
transcript, the notes, the annotations and the highlights. The audience is
students with an open laptop in the room. Battery is a hard constraint: the app
runs for a whole school day.

---

## 3. What actually happens during and after a lecture

This has changed twice and the old shape is still described in places. **This is
the current one.**

**While the lecture runs**, nothing is sent to the language model at all. The
microphone feeds 16 kHz mono float to the writer, which writes the file and
hands blocks to `LiveTranscriber`. Every chunk reaches the streaming speech
model; voice activity detection runs alongside and only decides where the lines
break. The window shows the transcript full-screen and nothing else.

**On Finish** — which now asks for confirmation — the file is re-transcribed in
batch, the speakers are separated, and then the model is given the **whole
transcript once** and writes the notes and the topic. An animated step display
covers all three. If the model is unreachable, the transcript is still stored,
the window opens normally, and the notes column says so and offers the button.

The model is never loaded into RAM during the lecture. `SummarizerFactory.make()`
builds a client and opens no connection; the first request is the one after the
lecture. This is deliberate — loading a 12B model mid-lesson makes the machine
unusable.

---

## 4. The traps, each of which has already cost a day

**Swift 6 actor isolation.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes
closure literals `@MainActor`. Passing one to a `@Sendable` parameter through a
`@preconcurrency` declaration compiles a **runtime isolation check** that traps.
It crashed recording twice — `DrainTimer` and `AudioTap` exist to turn that crash
into a build error. The compiler warns: *"main actor-isolated … can not be
referenced from a Sendable closure."* **That warning is a crash. Never silence
it**; make the thing `nonisolated`.

**Migrations are immutable.** GRDB's migrator compares identifiers only, so an
edited shipped migration never runs again on a database that recorded it. That
happened to `v1.library`; `v4.courses-across-terms` is the repair, guarded on the
shape it finds rather than on the identifier. Symptom: every feature looks like a
dead button and nothing logs an error, because the queries fail behind `try?`.

**FluidAudio's documentation is wrong.** Read `Sources/FluidAudio/`, not the
docs. `StreamingAsrManager` does not exist; `process(samples:)` always returns
`""` and partials arrive through `setPartialCallback`. In streaming mode the VAD
reads only `minSilenceDuration`, `speechPadding` and the negative threshold —
`minSpeechDuration` and `maxSpeechDuration` are batch-only, and tuning them is
tuning nothing.

**Local model sizing.** Weights plus KV cache must fit macOS's ~75 % GPU wired
limit. A 27B at 4-bit is 15.2 GB of weights plus 17.2 GB of KV at 64k — 32.4 GB
on a 24 GB machine. The owner runs `lmstudio-community/gemma-4-12B-it-MLX-4bit`
at 64k context with an 8-bit KV cache. Do not recommend from a model card's
"fits in 16 GB".

**Tests reach real services if you let them.** `ChatFactory` and
`LanguageModelPresence.refresh()` both opened live connections; one sent a real
question. Both no-op under `RetainApp.isTestHost`.

**Keychain ACLs.** An item records the creating binary's signature, and ad-hoc
builds differ every time, so the prompt comes back on every launch.
`SecACLSetContents(acl, nil, …)` means "any application"; an **empty** trusted-app
array means "trust nobody" and hangs. `LanguageModelKey.value()` returns nil
without touching the Keychain when `Defaults[.hasLanguageModelKey]` is false.

---

## 5. What this session changed

Twenty-two commits, all on `main`. Grouped by what they were about.

### Speech — the live transcript was losing words

- **A cough cost twenty seconds.** The VAD decided both where a line ends *and*
  whether the speech model heard anything; a transient closed it and everything
  after was discarded.
- **A voice across the room never arrived at all.** It is a genuinely faint
  signal — no threshold both admits it and still means anything.
- **The gate came off the audio path entirely.** Every chunk now reaches the
  model. The VAD only breaks lines: three seconds after it says speech stopped,
  or after twenty seconds regardless — and that second timer is what puts an
  unflagged voice into the transcript at all, because the audio was decoded
  either way. The decision lives in `LiveGate`, a pure value, tested against a
  written-down lesson. **This changed a locked decision in `CLAUDE.md`**, on the
  owner's instruction, and that row is updated.

### Notes — what the model is told

- The prompts now say the transcript is dirty: sentences may make no sense and
  words were never said. Use the surrounding lines where they settle it, leave
  it out where they do not, **invent nothing**, and a fragment that fits nowhere
  does not go in. Both note prompts and the chat prompt.
- **Annotations (`⌘⇧M`) reached the model nowhere at all** — they hung off the
  map step, and nothing is summarised during a lecture any more. They go into
  the reduce prompt last, each with its timestamp, with the rule that every one
  must reach the notes and none may be quoted. The blue-ruled card is no longer
  drawn; this is a deliberate departure from board 03.
- **The topic was never stored.** The reduce returns one and `writeNotes`
  dropped it, so a lecture the model had read still showed its date as its name
  everywhere. It is written now, only where there is no name yet — Retain cannot
  tell a typed name from a written one.

### The detail window

- The chapter rail follows the reader down the page (`NotesScroll`, 140-point
  reading line).
- The rail's "exam relevant" footer is gone — nothing decided it.
- The sidebar folds away from a button at the trailing end of the tab bar,
  animated, one flag for both tabs, folded by width so the scroll position and
  the chat survive.
- The topic is editable in place (text until clicked; Return, click-away and
  Escape all behave), and the course opens Retain's own dropdown and asks before
  moving. Both update live in every window — the detail window follows
  `LibraryChanges` now, as the library already did.

### Chrome, which took several rounds

The window's name is **in the title bar, on the left, in every window**. macOS
paints close/minimise/zoom over the top-left of the content view, so the bar
keeps `titleBarTopRoom` clear above its one row: the buttons sit in that, and
the row beneath begins on the same edge as the sidebar or the meta strip. Every
bar also has `titleBarBottomRoom` under it. All four windows resize between
`windowMinimumSize` and whatever the display allows, and the notes measure grows
with the window up to 96 characters.

### The library — selecting, deleting and merging

`Select` puts the table into selection mode: a tick grows in front of each row
and the title slides over. The bar's three usual controls are replaced by
**Merge / Delete / Cancel**, each outlined in a different colour; the bar's own
padding and edges do not move.

**Merging** joins several recordings of one lesson, in the order they happened.
The earliest survives — it keeps its id, so highlights, chapters and open
windows still point at something, and the lesson keeps the start time somebody
has in their head. Transcripts and annotations move onto one timeline; the new
`recordingPart` table (migration `v5.merged-recordings`) keeps each part's own
start, because the merged timeline is continuous where the afternoon was not.
The transcript draws `RECORDING 2 · 10:40` at the seam. The notes and the topic
are **dropped, not stitched** — the merged window opens immediately with the
model already writing both.

---

## 6. How to work in this repository

**Build** (`xcode-select` points at CommandLineTools on this machine, so the
prefix is required):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Retain.xcodeproj -scheme Retain \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

**Type-check the tests without running anything** — `build-for-testing` with a
`-derivedDataPath` in a scratch directory, deleted afterwards. **Run** a suite
with `xcodebuild test -only-testing:RetainTests/<Suite>`; tests are ad-hoc signed
on purpose (see `CLAUDE.md`).

### What the owner has asked for, repeatedly

- **Never leave a build bundle behind.** After installing, delete
  `DerivedData/Retain-*/Build/Products/Debug/Retain.app` *and* the copy under
  `Index.noindex/`. Exactly one `Retain.app`, in `/Applications`.
- **Install by replacing `/Applications/Retain.app`**, never by running from a
  debugger. Release build, frameworks re-signed inside out, then the app, then
  `ditto`, then relaunch. Verify `AudioHardwarePowerHint` with `plutil -p`.
- **Never delete data, packages or the API key.**
- **One commit per logical change**, even when four corrections arrive in one
  message. Splitting afterwards is the price of having batched them.
- **No AI attribution anywhere** — not in commits, PR bodies, code comments or
  this file.
- Say plainly what was done. If a test failed, say so with the output.

### A judgement call worth knowing

The owner reports in German, quickly, and often means something more specific
than the words carry. Two rounds were spent on the wrong reading of *"die Leiste"*
(the bar) as *"die Liste"* (the list). When a request could mean two materially
different things and the screenshot does not settle it, say which one you built
in one sentence rather than guessing twice.

---

## 7. What is not done

- **Phase 7: distribution.** Developer ID signing, notarization, Sparkle feed,
  Homebrew tap. The owner does the Apple ID steps themselves — never ask for or
  handle their Apple ID password.
- **Live speaker separation.** Diarization runs offline after the lecture using
  speaker embeddings. Doing it live per closed line — one embedding compared to
  the running centroids — was offered and not yet asked for.
- **A third batch action.** The owner wrote "move" and the merge behaviour was
  built, since that is what they described at length. Moving several recordings
  to another course at once does not exist; moving one does.
- **Two model sizes.** `SummarizerFactory` sends both passes to the one model
  Settings offers, because board 06 draws one picker. Hard rule 7 — the large
  model on mains only — is decided in `ModelSizeDecision` and has nowhere to
  land until there is a second field.
