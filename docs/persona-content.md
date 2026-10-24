# Persona content

<!-- Generated from Design/NotificationCharacter/persona-content.json by render_character.py --assets. Do not edit by hand: edit the JSON and re-run. -->

The copy library used by the on-device persona planner. The JSON file is the source of truth; the app data set, character portraits, and this page are generated from it. To change copy or art, edit `Design/NotificationCharacter/persona-content.json` and run `make notification-character`.

- 15 content entries, 81 authored strings.

## Tokens

| Token | Sample | Meaning |
|---|---|---|
| `{exercise}` | Rows | Exercise name, such as "Rows". |
| `{value}` | 20 lb | A weight with its unit, such as "20 lb", or "bodyweight". |
| `{count}` | 5 | A count from the evidence: workouts, reps, weeks in a row, or skips. |
| `{weekday}` | Sunday | A weekday name, such as "Sunday". |
| `{routine}` | Shoulder Day | A saved routine's name. |
| `{days}` | 16 | Calendar days, such as the gap before a comeback. |
| `{weeks}` | 3 | Weeks, such as how long a routine has gone untouched. |
| `{measurement}` | shoulder line | A posture measurement's short name, such as "shoulder line". |
| `{suggestion}` | Quick Upper · about 8 min | A gentler routine or exercise to try, such as "Quick Upper · about 8 min". |
| `{time}` | 7 AM | A time of day, such as "7 AM". |
| `{name}` | — | Reserved for the user's name in a later version. Not allowed in v1 copy. |

## Tone art

| Tone | Image |
|---|---|
| `proud` | `delighted-hoodie-portrait` |
| `pleased` | `smile2-hoodie-portrait` |
| `relieved` | `smile2-hoodie-close` |
| `annoyed` | `annoyed-hoodie-close` |
| `disappointed` | `sad-hoodie-close` |
| `smug` | `smug-hoodie-portrait` |
| `competitive` | `smug-pe-uniform-portrait` |
| `concerned` | `normal-hoodie-close` |
| `warm` | `smile-hoodie-portrait` |

## Content

### `achievement.pr.weight`

- **Family:** `achievement`
- **Default tone:** `pleased`
- **Tokens:** `exercise`, `value`
- **Art overrides:** `competitive` → `shocked-hoodie-close`

**Title variants**
- `New high on {exercise}` — tones: all tones; minimum familiarity: `new`
- `{exercise}, record breaker` — tones: `proud`, `pleased`, `smug`, `competitive`; minimum familiarity: `familiar`

**Body variants**
- `{value}. Your highest yet.` — tones: `proud`, `pleased`; minimum familiarity: `new`
- `{value}. That’s a first.` — tones: `proud`, `pleased`; minimum familiarity: `new`
- `{value}. I’m proud of that.` — tones: `proud`; minimum familiarity: `familiar`
- `{value}. That’s worth a little celebration.` — tones: `proud`, `pleased`; minimum familiarity: `familiar`
- `{value}. Okay, show-off.` — tones: `smug`; minimum familiarity: `established`
- `{value}. The old record had a good run.` — tones: `smug`; minimum familiarity: `established`
- `Wait. {value}?! Since when?` — tones: `competitive`; minimum familiarity: `established`

### `achievement.pr.reps`

- **Family:** `achievement`
- **Default tone:** `pleased`
- **Tokens:** `exercise`, `count`, `value`
- **Art overrides:** none

**Title variants**
- `New rep record on {exercise}` — tones: all tones; minimum familiarity: `new`
- `{exercise}: new territory` — tones: `proud`, `pleased`, `smug`, `competitive`; minimum familiarity: `familiar`

**Body variants**
- `{count} reps at {value}. Best so far.` — tones: all tones; minimum familiarity: `new`
- `{count} reps at {value}. Stronger than last time.` — tones: `proud`, `pleased`; minimum familiarity: `new`
- `{count} reps. Your best yet at {value}.` — tones: all tones; minimum familiarity: `new`
- `{count} reps at {value}. Proud of you.` — tones: `proud`; minimum familiarity: `familiar`
- `{count} reps at {value}. Look at you.` — tones: `smug`, `competitive`; minimum familiarity: `established`
- `{count} reps at {value}. Old record: retired.` — tones: `smug`, `competitive`; minimum familiarity: `established`

### `achievement.milestone`

- **Family:** `achievement`
- **Default tone:** `proud`
- **Tokens:** `count`
- **Art overrides:** `proud` → `laugh-sundress-portrait`; `pleased` → `delighted-sundress-portrait`

**Title variants**
- `A milestone` — tones: all tones; minimum familiarity: `new`
- `{count}. Yes, you.` — tones: `proud`, `pleased`, `warm`; minimum familiarity: `familiar`

**Body variants**
- `{count} workouts logged. That’s a lot of showing up.` — tones: all tones; minimum familiarity: `new`
- `{count} workouts. That’s real.` — tones: all tones; minimum familiarity: `new`
- `{count} workouts. Each one counts.` — tones: `proud`, `warm`; minimum familiarity: `new`
- `{count} workouts. You built that.` — tones: `proud`, `pleased`, `warm`; minimum familiarity: `familiar`
- `{count} workouts. I’m proud of you.` — tones: `proud`; minimum familiarity: `familiar`
- `{count} workouts! That deserves a moment.` — tones: `proud`, `pleased`; minimum familiarity: `familiar`

### `pattern.weekday`

- **Family:** `pattern`
- **Default tone:** `pleased`
- **Tokens:** `weekday`, `count`
- **Art overrides:** none

**Title variants**
- `{weekday} again` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{count} {weekday}s in a row. A pattern’s forming.` — tones: `pleased`, `warm`; minimum familiarity: `new`
- `{count} {weekday}s in a row. I’m keeping count.` — tones: `pleased`, `warm`; minimum familiarity: `familiar`
- `{count} {weekday}s in a row. I see the pattern.` — tones: `smug`, `pleased`; minimum familiarity: `established`

### `pattern.weekday.established`

- **Family:** `pattern`
- **Default tone:** `smug`
- **Tokens:** `weekday`, `count`
- **Art overrides:** none

**Title variants**
- `A {weekday} person` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{count} {weekday}s in a row. This is a thing now.` — tones: all tones; minimum familiarity: `new`
- `{count} {weekday}s. You have a {weekday} thing.` — tones: `pleased`, `warm`; minimum familiarity: `familiar`
- `{count} {weekday}s running. It’s practically your day.` — tones: `smug`, `pleased`; minimum familiarity: `established`

### `pattern.weekday.upcoming`

- **Family:** `pattern`
- **Default tone:** `pleased`
- **Tokens:** `weekday`, `count`
- **Art overrides:** none

**Title variants**
- `Your {weekday} pattern` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `It’s {weekday}. Make it {count} in a row?` — tones: all tones; minimum familiarity: `new`
- `{weekday} again. One more would make {count} in a row.` — tones: `pleased`, `warm`; minimum familiarity: `familiar`
- `{weekday}. Shall we make it {count} in a row?` — tones: `smug`, `pleased`; minimum familiarity: `established`

### `pattern.routineRepeat`

- **Family:** `pattern`
- **Default tone:** `pleased`
- **Tokens:** `routine`, `count`
- **Art overrides:** none

**Title variants**
- `{routine} again` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{routine}, {count} sessions running. There’s a rhythm.` — tones: all tones; minimum familiarity: `new`
- `{routine}, {count} in a row. An encore, then.` — tones: `pleased`, `smug`; minimum familiarity: `familiar`

### `pattern.timeOfDay`

- **Family:** `pattern`
- **Default tone:** `pleased`
- **Tokens:** `time`
- **Art overrides:** none

**Title variants**
- `Your usual time` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `Around {time} again. Clockwork.` — tones: all tones; minimum familiarity: `new`
- `Around {time} again. Your signature time.` — tones: `pleased`, `warm`, `smug`; minimum familiarity: `familiar`

### `lapse.skippedExercise`

- **Family:** `lapse`
- **Default tone:** `concerned`
- **Tokens:** `exercise`, `count`
- **Art overrides:** none

**Title variants**
- `{exercise}: a skip pattern` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{exercise} skipped {count} times in a row.` — tones: all tones; minimum familiarity: `new`
- `{count} skips in a row on {exercise}. That keeps coming up.` — tones: `concerned`, `warm`; minimum familiarity: `familiar`
- `{count} skips on {exercise}. A pattern, apparently.` — tones: `annoyed`, `smug`; minimum familiarity: `established`

### `lapse.skippedExercise.escalated`

- **Family:** `lapse`
- **Default tone:** `concerned`
- **Tokens:** `exercise`, `count`
- **Art overrides:** none

**Title variants**
- `{exercise}, skipped again` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{count} consecutive skips on {exercise} now.` — tones: all tones; minimum familiarity: `new`
- `{exercise}: {count} skips running. The pattern’s continuing.` — tones: `concerned`, `warm`; minimum familiarity: `familiar`
- `{count} skips in a row. {exercise}: officially your nemesis.` — tones: `annoyed`; minimum familiarity: `established`
- `{count} skips on {exercise}. An entire subplot.` — tones: `smug`; minimum familiarity: `established`

### `lapse.neglectedRoutine`

- **Family:** `lapse`
- **Default tone:** `concerned`
- **Tokens:** `routine`, `weeks`
- **Art overrides:** none

**Title variants**
- `Remember {routine}?` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `{routine} hasn’t come up in {weeks} weeks.` — tones: `concerned`; minimum familiarity: `new`
- `{weeks} weeks since {routine}. Want to revisit it?` — tones: `concerned`; minimum familiarity: `new`
- `{routine}, untouched for {weeks} weeks. Quite the hiatus.` — tones: `annoyed`; minimum familiarity: `established`
- `{weeks} weeks without {routine}. That’s a long gap.` — tones: `disappointed`; minimum familiarity: `established`

### `lapse.decliningWeeks`

- **Family:** `lapse`
- **Default tone:** `concerned`
- **Tokens:** `suggestion`
- **Art overrides:** none

**Title variants**
- `Fewer sessions lately` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `The pace has changed over the last few weeks.` — tones: `concerned`; minimum familiarity: `new`
- `If you want a lighter one: {suggestion}.` — tones: `concerned`; minimum familiarity: `new`
- `Three weeks, each quieter than the last.` — tones: `disappointed`; minimum familiarity: `longTerm`

### `lapse.comeback`

- **Family:** `lapse`
- **Default tone:** `warm`
- **Tokens:** `days`
- **Art overrides:** `relieved` → `smile2-hoodie-portrait`

**Title variants**
- `Welcome back` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `First workout in {days} days. A fresh start.` — tones: `warm`; minimum familiarity: `new`
- `{days} days, then a workout. Good to see you back.` — tones: `warm`, `relieved`; minimum familiarity: `familiar`
- `{days} days. You came back. That’s the good part.` — tones: `warm`, `relieved`; minimum familiarity: `familiar`
- `{days} days, and you’re back. Just glad.` — tones: `warm`, `relieved`; minimum familiarity: `familiar`

### `posture.returned`

- **Family:** `posture`
- **Default tone:** `pleased`
- **Tokens:** `days`
- **Art overrides:** none

**Title variants**
- `Back for a posture check` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `First check in {days} days. Good timing.` — tones: all tones; minimum familiarity: `new`
- `{days} days, then a check. Glad you came back to it.` — tones: `pleased`, `warm`; minimum familiarity: `familiar`

### `posture.improved`

- **Family:** `posture`
- **Default tone:** `pleased`
- **Tokens:** `measurement`
- **Art overrides:** none

**Title variants**
- `A measurable shift` — tones: all tones; minimum familiarity: `new`

**Body variants**
- `Your {measurement} trend is moving the right way.` — tones: all tones; minimum familiarity: `new`
- `Less deviation in {measurement} on two checks. Nice.` — tones: all tones; minimum familiarity: `new`

## Fragments

### Openers

- `Oh.` — tones: `smug`, `competitive`; minimum familiarity: `established`
- `Well, look.` — tones: `proud`, `pleased`; minimum familiarity: `familiar`
- `Well, then.` — tones: `smug`, `annoyed`, `competitive`; minimum familiarity: `established`

### Closers

- `Noted.` — tones: `smug`, `competitive`, `annoyed`; minimum familiarity: `established`
- `I saw that.` — tones: `proud`, `pleased`, `smug`, `competitive`; minimum familiarity: `familiar`
- `Worth a mention.` — tones: `proud`, `pleased`, `warm`, `relieved`, `concerned`; minimum familiarity: `familiar`

### Intro

- `I notice things.` — tones: all tones; minimum familiarity: `new`
- `I’m noticing now.` — tones: all tones; minimum familiarity: `new`
- `I notice more now.` — tones: all tones; minimum familiarity: `new`

## Persona images

12 distinct persona images, included in the shared notification character asset catalog:

- `annoyed-hoodie-close` — tones: `annoyed`
- `delighted-hoodie-portrait` — tones: `proud`
- `delighted-sundress-portrait` — content: `achievement.milestone (pleased)`
- `laugh-sundress-portrait` — content: `achievement.milestone (proud)`
- `normal-hoodie-close` — tones: `concerned`
- `sad-hoodie-close` — tones: `disappointed`
- `shocked-hoodie-close` — content: `achievement.pr.weight (competitive)`
- `smile-hoodie-portrait` — tones: `warm`
- `smile2-hoodie-close` — tones: `relieved`
- `smile2-hoodie-portrait` — tones: `pleased`; content: `lapse.comeback (relieved)`
- `smug-hoodie-portrait` — tones: `smug`
- `smug-pe-uniform-portrait` — tones: `competitive`
