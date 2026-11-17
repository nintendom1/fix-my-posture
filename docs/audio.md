# Audio architecture

## Current ownership

`WorkoutAudioSession` is the only workout component that calls `AVAudioSession`. It owns category changes, activation, ducking, interruption handling, and restoration. `WorkoutVoiceController` owns microphone listening and coordinates half-duplex transitions with `SpeechCoach`.

## Speech path

`WorkoutSession` emits value-only `Utterance` effects. `WorkoutCoachModel` sends them to `SpeechCoach`, which keeps at most two pending lines and remembers the last instruction. Before ducking audio, it marks speech active so listening stops; after the queue drains, it restores audio through the shared session owner, then marks speech inactive so listening can resume.

`SpeechCoach` uses `SystemSpeechSynthesizer` by default. The wrapper forwards speak, stop, speaking state, and start/finish/cancel callbacks to `AVSpeechSynthesizer`; callbacks arrive asynchronously on the main queue. `SpeechCoachQueueTests` covers queueing, interruption, repeat, watchdog, activity, ducking, restoration order, and wrapper callback timing through the real coach and a fake synthesizer. The injected watchdog scheduler is for tests; production uses a Foundation timer.

## Dormant and internal contracts

**Dormant and internal:** `AudioCoordinating` and `WorkoutAudioCoordinator` forward calls and events to a supplied `AudioSessionControlling` owner. They are not wired into production.

**Dormant and internal:** `SoundCueID`, `AudioPriority`, `BackgroundMusicPlaying`, and `SoundEffectPlaying` define vocabulary and contracts only. There are no players or production callers. The policy labels describe speech above effects above music, with recognition pausing effects and music and speech ducking lower-priority audio.

## Prerecorded speech

The production backend remains system text-to-speech. A future clip player must preserve `SpeechCoach` queue, interruption, repeat, and completion behavior, and use the shared audio-session owner. It may need a sibling protocol because `SpeechSynthesizing` accepts `AVSpeechUtterance`.
