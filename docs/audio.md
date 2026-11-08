# Audio architecture

## Current ownership

`WorkoutAudioSession` is the only workout component that calls `AVAudioSession`. It conforms to
`AudioSessionControlling` and owns category changes, activation, ducking, interruption handling, and restoration.
`WorkoutVoiceController` owns microphone listening and coordinates half-duplex transitions with `SpeechCoach`.

## Current speech path

`WorkoutSession` emits value-only `Utterance` effects. `WorkoutCoachModel` sends those lines to `SpeechCoach`, which
keeps at most two pending lines, remembers the last instruction, and stops listening before ducking other audio.
When playback drains, the coach asks the same `WorkoutAudioSession` owner to restore other audio and resume listening
when needed. Queue, interruption, repeat, watchdog, activity, ducking, and restoration order are pinned by
`SpeechCoachQueueTests` using a fake synthesizer with the real `SpeechCoach`.

`SpeechSynthesizing` is the narrow speech backend seam. `SystemSpeechSynthesizer` forwards speech, stop, speaking
state, and start/finish/cancel callbacks to `AVSpeechSynthesizer`. `SpeechCoach` uses it by default. The injected
watchdog scheduler is test-only in purpose and defaults to the existing Foundation timer behavior.

## Dormant phase-2 contracts

`WorkoutAudioCoordinator` delegates every `AudioSessionControlling` method and event to its supplied owner. It is not
wired into production. `WorkoutAudioSession` remains the sole system session owner.

`SoundCueID` names future semantic events with stable values. `AudioPriority` orders speech above sound effects above
background music. Its policy labels say that recognition pauses music and sound effects, and speech ducks lower
priority playback. `BackgroundMusicPlaying` and `SoundEffectPlaying` are contracts only; this phase adds no players,
callers, mixing changes, or sounds.

## Future prerecorded speech

Issue #129 owns the prerecorded coach-clip catalog, cue resolution, assets, and playback durations. Its player can
adapt to `SpeechSynthesizing` where it can preserve `SpeechCoach`'s queue, interrupt, repeat, and completion contract,
or use a sibling speech backend protocol for catalog cues. It must use the shared audio-session owner rather than
creating a second `AVAudioSession` owner. Replacing synthesis with clips is intentional #129 work; no live TTS fallback
is added to that future player here. The current production speech backend remains system text-to-speech.
