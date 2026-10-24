# The notification character's voice

One character, two registers. This guide is the reference for anyone writing or reviewing copy in
`notification-scenarios.json` (reminders and acknowledgments) or `persona-content.json` (Extra Personable).

## Who she is

A teammate who becomes a familiar companion over time. She is invested in the user's training and has
dramatic flair: big reactions, short sentences, real feelings about what the user did. She lives in the
notification and the app. She has no persistent life off-screen.

## Stakes register: reminders and acknowledgments

Source: `notification-scenarios.json`.

She has a loud, comedic stake in **today's session** and the **shared streak**. The stake ends with the day.

- Theatrical guilt about today is allowed: "{streak} days and you're really going to leave me hanging?"
- One-shot situational fiction is allowed: pajamas, "I was going to sleep, you know."
- Relief and celebration after a close call are allowed: "Okay. That was way too close."
- Escalation stays rare and comedic, never hostile.

## Observer register: Extra Personable

Source: `persona-content.json`.

She notices **history** unprompted: records, habits, skipped exercises, comebacks, posture trends. She is an
invested companion with dramatic flair, pointed at what the user actually did.

- Her feelings are reactions to history: proud, pleased, smug, competitive, relieved, warm, annoyed at an
  undeniable skip pattern, concerned about a decline.
- She never appeals to what the user owes her. She never mentions waiting for the user, being hurt by an
  absence, or a persona message being ignored.
- Be specific and short. Lead with the fact, then the reaction: "20 lb. New high." beats a dashboard of numbers.
- One observation per message. Do not combine unrelated facts.

### Humor follows emotion

| Tone | How it sounds | Example |
|---|---|---|
| proud | sincere, little or no joke | "25 workouts. That's real." |
| pleased | warm, lightly playful | "Sunday again. I like this." |
| relieved | affectionate, playful | "There you are. Rows missed you." |
| warm | soft and sweet | "Welcome back. No speech. Just glad." |
| smug | earned show-off, playful | "20 lb. Okay, show-off." |
| competitive | smug and playful about records | "New high. The old one never stood a chance." |
| annoyed | medium tease, never mean | "Three skips in a row. Rows are officially your nemesis." |
| disappointed | rare, earned, brief | "Shoulder Day has been gathering dust." |
| concerned | straightforward, minimal humor | "Fewer sessions lately. Want a lighter one?" |

### Teasing scales with familiarity

- **new**: neutral observation only. No teasing, no negative tones.
- **familiar**: light teasing: "Rows again? Noted."
- **established** and **longTerm**: medium teasing is allowed. Annoyed and disappointed tones become available.
- When consistency is declining, concern replaces teasing.

### Persuasion she may use

- **Identity labels**: "This is definitely a thing now." / "You're a Sunday person."
- **Goal-gradient nudges**: "One more and that's five Sundays."
- **A gentler option** on a lapse: "Quick Upper is 8 minutes." Never a weight or rep prescription.
- **Softness and sweetness**, especially on comebacks.

Not in v1: challenges or bets.

## Rules for both registers

- No persistent off-screen life. Never "I was thinking about you while I was out."
- No dependency. She can care; the user is never responsible for her feelings about history.
- Counts, not motives: "Three skips in a row", never "You avoid exercises you're bad at."
- No medical, diagnostic, appearance, or body-image language. Posture copy is about measurable trends only.
- No quotas, scores, or implementation mechanics in user-facing copy.
- No names yet. `{name}` is reserved and rejected by validation.

## Reserved for later

- An `occasion` family for US holidays and occasions, voiced in the observer register.
- Anniversaries, such as a year since the first workout.
- The user's name.
- HealthKit-derived facts.

## Length and composition

- Titles: 36 characters at most. Bodies: 70 characters at most. Fragments: 18 characters at most, so a body with
  an opener and a closer stays within 110 characters.
- Persona copy is composed: a title, a body, and sometimes an opener ("Okay."), a closer ("Noted."), or, on the
  first persona message, an intro line. Write bodies that read well alone and with a fragment.
- Typography: curly apostrophes (’), no exclamation marks except for genuine celebration, no emoji.
