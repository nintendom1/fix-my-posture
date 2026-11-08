import Foundation
@testable import Narrative

enum NarrativeFixtures {
    static let twoSceneScript = #"""
    {
      "version": 1,
      "id": "morning_story",
      "characters": [{
        "id": "mika",
        "allowedExpressions": ["calm", "happy"],
        "defaultExpression": "calm",
        "portrait": "mika_portrait",
        "expressionAssets": [
          {"expression": "calm", "asset": "mika_calm"},
          {"expression": "happy", "asset": "mika_happy"}
        ]
      }],
      "flags": [
        {"id": "met_today", "scope": "player"},
        {"id": "loop_seen", "scope": "loop"}
      ],
      "scenes": [
        {
          "id": "opening",
          "entryNode": "intro",
          "nodes": [
            {"type": "line", "id": "intro", "speaker": "mika", "expression": "calm", "text": "Welcome back.", "audio": "hello"},
            {"type": "checkpoint", "id": "mark", "checkpointID": "after_intro"},
            {"type": "choice", "id": "question", "prompt": "What next?", "options": [{"id": "continue", "text": "Continue", "condition": {"type": "fact", "fact": "workouts_this_week", "comparison": "greaterThanOrEqual", "value": 3}, "target": "check"}, {"id": "skip", "text": "Skip ahead", "target": "skip_line"}]},
            {"type": "branch", "id": "check", "condition": {"type": "flagIsSet", "flag": "met_today"}, "thenTarget": "finish", "elseTarget": "set_done"},
            {"type": "setFlag", "id": "set_done", "flag": "met_today", "value": true},
            {"type": "line", "id": "finish", "speaker": "mika", "expression": "happy", "text": "Good work."},
            {"type": "jump", "id": "to_outro", "target": {"scene": "outro", "node": "outro_line"}},
            {"type": "line", "id": "skip_line", "speaker": "mika", "expression": "calm", "text": "We can pick this up later."},
            {"type": "end", "id": "opening_end"}
          ]
        },
        {
          "id": "outro",
          "entryNode": "outro_line",
          "nodes": [
            {"type": "line", "id": "outro_line", "speaker": "mika", "expression": "calm", "text": "See you soon."},
            {"type": "end", "id": "outro_end"}
          ]
        }
      ]
    }
    """#

    static func script(nodes: String, characters: String = "[]", flags: String = "[]", version: Int = 1) -> String {
        "{\"version\":\(version),\"id\":\"test_script\",\"characters\":\(characters),\"flags\":\(flags),\"scenes\":[{\"id\":\"scene\",\"entryNode\":\"entry\",\"nodes\":\(nodes)}]}"
    }

    static func load(_ json: String, manifest: NarrativeAssetManifest? = nil, knownFacts: Set<FactID> = NarrativeFacts.standardFactIDs) -> NarrativeLoadResult {
        NarrativeScriptLoader.load(Data(json.utf8), assetManifest: manifest, knownFactIDs: knownFacts)
    }
}
