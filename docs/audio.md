# Audio architecture

## Current ownership

`WorkoutAudioSession` is the only workout component that calls `AVAudioSession`. It owns category changes, activation, ducking, interruption handling, and restoration. `WorkoutVoiceController` owns microphone listening and coordinates half-duplex transitions with `SpeechCoach`.

## Session worker and categories

The main-actor owner queues every operation and starts the next only after the previous request completes. Its private `WorkoutAudioSessionWorker` actor performs the `AVAudioSession` operations off the main actor, in request order.

With voice listening enabled, the base category is `.playAndRecord` and the session stays active between utterances; it uses `.mixWithOthers`, `.defaultToSpeaker`, and `.allowBluetoothA2DP`. A2DP preserves high-quality Bluetooth headphone playback while the built-in microphone listens. With listening disabled, the base is `.playback` with `.mixWithOthers`.

Ducking requires activation: the worker deactivates an already-active listening session, applies the base category plus `.duckOthers`, then activates before speech starts. When speech ends, it deactivates with `.notifyOthersOnDeactivation`, restores the base category, and reactivates only if listening should continue. Restoration is idempotent and safe on completion, error, and teardown paths; a busy deactivation retries every 0.25 seconds, up to four attempts.

## Speech path

`WorkoutSession` emits value-only `Utterance` effects. `WorkoutCoachModel` sends them to `SpeechCoach`, which keeps at most two pending lines and remembers the last instruction. Before ducking audio, it marks speech active so listening stops; after the queue drains, it restores audio through the shared session owner, then marks speech inactive so listening can resume.

`SpeechCoach` uses `SystemSpeechSynthesizer` by default. The wrapper forwards speak, stop, speaking state, and start/finish/cancel callbacks to `AVSpeechSynthesizer`; callbacks arrive asynchronously on the main queue. Its watchdog is `max(1, words / 2.5) + 5` seconds and is rearmed when playback starts. If deactivation reports busy, `WorkoutAudioSession` retries restoration every 0.25 seconds, up to four attempts. `SpeechCoachQueueTests` covers queueing, interruption, repeat, watchdog, activity, ducking, restoration order, and wrapper callback timing through the real coach and a fake synthesizer. The injected watchdog scheduler is for tests; production uses a Foundation timer.

## Dormant and internal contracts

**Dormant and internal:** `AudioCoordinating` and `WorkoutAudioCoordinator` forward calls and events to a supplied `AudioSessionControlling` owner. They are not wired into production.

**Dormant and internal:** `SoundCueID`, `AudioPriority`, `BackgroundMusicPlaying`, and `SoundEffectPlaying` define vocabulary and contracts only. There are no players or production callers. The policy labels describe speech above effects above music, with recognition pausing effects and music and speech ducking lower-priority audio.

Any future audio-coordinator wiring must stay behind a feature switch that is off by default and preserve current behavior.

## Prerecorded speech

The production backend remains system text-to-speech. [Issue #129](https://github.com/nintendom1/fix-my-posture/issues/129) tracks replacing it with prerecorded clips and no live text-to-speech fallback; scope includes the clip catalog, cue resolution, assets, and playback durations. Any backend must stay behind a feature switch that is off by default, preserve `SpeechCoach` queue, interruption, repeat, and completion behavior, and use the shared audio-session owner. It may need a sibling protocol because `SpeechSynthesizing` accepts `AVSpeechUtterance`.
