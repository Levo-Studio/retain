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

## 4. Design, which is not decoration here

`docs/design/` **is** the design, and it is read-only. Every colour, size,
radius, padding, weight, line-height and timing is in it as a concrete value.
Take them exactly: no rounding to a 4- or 8-point grid, no "close enough", no
improving a ladder that is not a ladder. CSS pixels transfer 1:1 to SwiftUI
points. Where the HTML and the README disagree, **the HTML wins**, because it is
what was drawn. The export is dark-only; there is no light appearance, because
none was drawn, and inventing one is not a decision to make here.

**If a value you need is not in the export, that is a question for the owner —
not a gap to fill with taste.** In practice several values now exist that the
export does not draw (a reading line for the chapter rail, the room above a
title bar, the tick in a selected row). Every one of them carries a comment
saying it is not drawn and what it was derived from. That is the bar: a number
nobody can trace is worse than a number that is slightly wrong.

Three rules that come out of this and get broken by accident:

- **No numeric or colour literal in a feature file.** No `.padding(17)`, no
  `Color(hex:)`, no hand-rolled curve. A missing value goes into the design
  layer, not into the call site.
- **One component, not four copies.** When two screens draw the same thing, it
  is one view in `Core/Design/`. Two `AnnotationCard` types once ended up in one
  target and disagreed only about the measure — which was the one thing the
  boards genuinely drew differently.
- **Departures from the export are deliberate and written down.** Three exist:
  the annotation card is no longer drawn (annotations go to the model instead),
  the chapters rail has no footer ("exam relevant" was never true), and the
  window's name sits in the title bar rather than beside the traffic lights.
  Each is commented where it happens. Anything else that differs from the export
  is a bug.

## 5. The traps, each of which has already cost a day

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

## 6. What this session changed

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

## 7. The owner, and how work is delivered to them

This section is the part that cannot be reconstructed from the code. It is
long on purpose: nearly every rule in it was learned by getting it wrong first.

### Who they are

Julius Grimm, Levo Studio. A student who uses this app in lessons and also
writes it, on a Mac with 24 GB of memory running LM Studio locally. High
technical knowledge — skip beginner explanations, name trade-offs, and say what
you would do rather than listing options. Once a decision is made, stop arguing
and build it.

The company name is **Levo Studio**, both words, always. Never "Levo" alone,
anywhere: not in code, comments, commits, docs, UI copy or service names.

### How they report

In German, fast, typed on the run — spelling and word boundaries suffer and
that is not a signal about anything. Reports come as screenshots with a
sentence, usually while the app is open in front of them. They test every build
themselves; nobody else does.

**They mean something more specific than the words carry.** Two rounds of this
session were spent building the wrong thing because *"die Leiste"* (the bar) was
read as *"die Liste"* (the list), and another two because "the name should be
in the bar with the model, fully left" sounds impossible — macOS owns the
top-left of a title bar — until you realise the answer is to keep room clear
above the row so the buttons sit in it.

The rule that came out of that: **when a request could mean two materially
different things and the screenshot does not settle it, build the reading you
believe and say in one sentence which one you built.** They correct in four
words. Guessing twice costs a round each time; asking a blocking question
mid-flow annoys them more than a wrong build they can redirect.

They interrupt mid-turn with corrections and additions. Take them as they
arrive, fold them into what is already running, and do not restart.

### Their standards, in their own words

- *"mache hardcode nicht bist du deppert? warum hadocodest du da was"* — do not
  guess structure in code. When a shape is needed, **ask the model for it**
  rather than reverse-engineering it from strings. This killed a version of the
  notes that recovered sections by string-matching Markdown and searching the
  transcript for bold terms; the replacement has the model say where each
  section starts.
- *"das muss alles instant da sein kommt ja direkt vom pc"* — content that is
  already in memory appears with **no transition**. Cross-fades between panes
  were built and rejected. Motion is for work that is actually happening: the
  processing steps, the typing dots, the rail folding, a scroll. Nothing else.
- *"die ui wie sie gerade ist ist perfekt ändere daran nichts"* — when adding
  something, add **only** that. Padding, alignment, edges and everything not
  named stay exactly as they are.
- *"mache das alles einheitlich"* — **consistency is a requirement, not a
  preference.** Four title bars that are 38 points in three windows and 52 in
  the fourth is a bug to them. When a value is shared, it goes in the design
  layer *inside* the component so a window cannot be given it and the others
  forgotten. They notice a four-point difference across two windows open side
  by side.
- *"aber das model ist super und die prompts"* — praise is rare and specific.
  Take it as a marker of what not to touch.

### Accuracy, which is the product

Retain's value is that a student can trust the notes without re-listening —
and the audio is deleted, so there is no re-listening. Everything follows from
that:

- **Invent nothing.** The prompts say it three times over. A single made-up
  sentence makes the whole page worthless, because the reader cannot tell which
  one it is.
- **Every number survives.** Dates, percentages, page numbers, deadlines — the
  one thing a reader cannot reconstruct.
- **Never lose audio on the way to the model.** A missing word is
  unrecoverable; a stray one is visible and ignorable. That asymmetry decided
  the whole voice-activity design.
- **Never lose data.** Deleting anything asks first and the dialog states what
  is lost, counted before it opens. A merge keeps the earliest recording's id so
  nothing pointing at it breaks.
- **Nothing may lag the machine during a lecture.** No model loaded into RAM,
  nothing sent to it, no polling. This is why the live pipeline looks the way it
  does, and it is also the reason given for several other decisions — expect it
  to be the answer to "why not just…".

### The process rules, as given

Quoted because the wording matters, and because each one followed something
going wrong.

- *"teste die app nicht … mache einfach nur code änderung und schau das das
  syntax mäßig passt und wenn ich sage jetzt dann erst in apps folder aber nie
  testen oder bauen in debugger"* — **never run the app from a debugger.** Build,
  type-check, and when it is finished, install it.
- *"mach nicht diese komischen sachen mit debugger oder so einfach direkt als app
  installieren und sage mir bescheid was du genau gemacht hast"* — install by
  replacing `/Applications/Retain.app`, then report precisely what was done.
- *"lasse keine apps im debug folder bevor du immer fertig bist und mache immer
  die neuste version in apps rein"* — **exactly one `Retain.app` on the
  machine**, in `/Applications`. Delete
  `DerivedData/Retain-*/Build/Products/Debug/Retain.app` *and* the copy under
  `Index.noindex/`. They have twice found two Retains and it reads as a broken
  app.
- *"aber schaue das du nicht daten löschst oder so und keine pakete und auch das
  meine api keys da bleiben"* — never touch the database, the Swift packages or
  the Keychain item while installing.
- *"ich will nicht jedes mal nach pw gefragt werden wenn ich die app öffne"* —
  no Keychain prompt on launch. `LanguageModelKey.value()` does not touch the
  Keychain at all when no key has been stored.
- *"mache eigene commits"* — **one commit per logical change**, even when four
  corrections arrive in one message. Splitting afterwards with a soft reset is
  the price of having batched them; do it rather than shipping a mixed commit.
- No AI attribution anywhere — commits, PR bodies, code comments, branch names,
  this file.
- Never push to `main` without being told. They say so explicitly when they want
  it.

### What to do at the end of a piece of work

In this order, every time:

1. Build clean.
2. Type-check the test target without running anything.
3. Run the suites the change touches. **Run them for real when the change writes
   to or deletes user data** — the merge SQL had two wrong column names and only
   a real run found them.
4. Commit, one logical change at a time.
5. Release build, frameworks re-signed inside out, then the app; `ditto` into
   `/Applications`; verify `AudioHardwarePowerHint` with `plutil -p`; relaunch.
6. Delete every build bundle. Confirm exactly one `Retain.app` and one process.
7. Report in German, plainly: what changed, **why it was broken**, and anything
   you found on the way that they did not ask about. They read the reasoning and
   respond to it.

### Tone

Write back in German, direct, no hedging and no apologising. Say what was wrong
and why, not that you are sorry. When they are angry — and they will be, in
capitals — the useful reply is the fix and one sentence naming what you actually
got wrong, not an apology.

## 8. How to work in this repository

**Build** (`xcode-select` points at CommandLineTools on this machine, so the
prefix is required):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Retain.xcodeproj -scheme Retain \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

**Type-check the tests without running anything**: `build-for-testing` with a
`-derivedDataPath` in a scratch directory, deleted afterwards. **Run** a suite
with `xcodebuild test -only-testing:RetainTests/<Suite>`; tests are ad-hoc signed
on purpose (see `CLAUDE.md`), and `xcodebuild test` launches a host app — which
is why the bundle cleanup afterwards is not optional.

**Install:**

```bash
for f in Retain.app/Contents/Frameworks/*.framework; do
    codesign --force --sign - --timestamp=none "$f"
done
codesign --force --sign - --timestamp=none Retain.app
```

Inside out, because dyld refuses a framework whose Team ID differs from the
process's and the app then dies at launch before any Retain code runs.

## 9. What is not done

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
