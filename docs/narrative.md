Dormant and internal: not linked into the app; no user sees or hears any of this.

# Narrative foundation

## Purpose

`Packages/Narrative/` is a Foundation-only package for future authored scenes and companion callouts. It has no app routes, UI, persistence, bundled assets, or audio playback. Loading or running a script does not change installed app behavior.

## Model

Scripts contain a format version, stable string IDs, characters and their allowed semantic expressions, declared flags, and scenes. Each scene has an entry node and an ordered node list. Lines and control nodes move through that list; choices and branches target nodes in the current scene, while jumps name a scene and node.

Conditions can inspect flags or read-only integer facts supplied by the host. Scripts cannot write fitness facts. The standard known fact is `workouts_this_week`; hosts can supply their own known fact IDs during validation and execution.

## Validation

`NarrativeScriptLoader` decodes JSON and returns every problem as a typed issue with a code, path, message, and severity. Malformed JSON yields a `decoding` issue at `$`. A runtime accepts only a `NarrativeValidatedScript` produced when there are no errors.

Error codes are `unsupportedVersion`, `invalidIDSyntax`, `duplicateID`, `unknownSpeaker`, `disallowedExpression`, `missingScene`, `missingNode`, `missingBranchTarget`, `choiceHasNoOptions`, `duplicateOptionID`, `optionMissingTarget`, and `undeclaredFlag`.

Warnings are `unknownFact`, `unreachableNode`, and, when a manifest is provided, `missingPortraitAsset`, `missingExpressionAsset`, and `missingAudioAsset`. Unknown facts evaluate false. Unreachable nodes and missing assets do not prevent runtime construction; asset fallbacks are applied when needed. Callout validation also rejects `blockingCallout` and invalid automatic dismissal durations.

## Runtime semantics

`NarrativeRuntime` is a pure value type. `start(scene:)`, `advance(from:)`, and `choose(_:from:)` take explicit input and return a `NarrativeRuntimeResult` containing the `NarrativeStep`, optional new state, and optional checkpoint. Choices show only options whose conditions evaluate true. Selecting a hidden or unknown option returns `failed` and preserves the input state. Lines advance in scene order; branches, choices, and jumps select their declared targets. Automatic control flow is bounded by a configurable step limit.

Conditions treat absent flags as false. A fact is compared only if the host marks its ID as known and supplies an integer value; otherwise the condition evaluates false. Unknown fact names are reported by validation as warnings.

Crossing a checkpoint node returns an in-memory `NarrativeCheckpoint` containing its ID, scene, node, and current flags. `restore(_:)` checks that the scene and node exist, that the node declares the same checkpoint ID, and that all flags are declared. The restored state points at the checkpoint node; call `advance(from:)` to resume after it.

## Asset fallbacks

When a line's expression asset is unavailable, the runtime returns the character's default semantic expression and its available asset. When an audio asset is unavailable in the supplied manifest, the runtime omits its audio reference. Both decisions are recorded in that step's `fallbacks`.

## Companion presentation contract

**Dormant and internal:** `CompanionPresentation` is the value contract for scene lines and future coaching callouts. It carries a character, semantic expression, optional text and audio reference, kind, blocking behavior, and dismissal policy. Callouts must be non-blocking. `CompanionCallout.make(character:expression:cueID:text:)` creates a non-blocking value from the character, expression, cue ID, and text without app-specific types or playback behavior.

## Memory scopes

`.player` flags are reserved for host-managed player/meta-history, and `.loop` flags represent loop-local companion memory that a host may clear on a weekly reset. The package itself persists neither scope. `NarrativeState.resettingLoopMemory(in:)` is an in-memory helper that preserves player flags and removes loop flags. A future story reset must not touch workout history, adaptive training data, or notifications.

## Tests and activation

Run the Mac package tests with `swift test --package-path Packages/Narrative`. `PackageBoundaryTests` also verifies Foundation-only source imports and that the app project does not reference this package.

A future issue must explicitly authorize activation, choose the app integration and asset/audio ownership, link the package through the app composition root, and add the required behavior and privacy coverage. Until that work is reviewed and merged, the package stays dormant and the installed app does not use it.
