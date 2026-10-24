# Extra Personable

Extra Personable lets the notification character notice meaningful workout and posture history and say something
about it: a new record, a habit, a skipped exercise, a comeback, a posture trend. It is deterministic. Detectors read
saved history, a planner picks at most one observation per message, and copy comes from templates and fragments in
`Design/NotificationCharacter/persona-content.json`. There is no LLM and no network.

## Gating and settings

- Extra Personable is a sub-setting of Character-style workout reminders. It runs only when reminders are on, the style
  is Character, and the Extra Personable toggle is on (it is on by default). It reuses the reminders' notification
  permission and scheduler.
- Settings → Workout reminders shows the toggle with the explanation "She may occasionally notice progress, habits, and
  patterns from your workout and posture history." Turning it off removes pending persona notifications. History and
  derived state are untouched.
- **Reset Persona** (same page, with confirmation) sets `persona.resetDate` to now and clears the decision traces,
  engagement, and tone history. Workouts, assessments, and the toggle stay. History before the reset still counts for
  factual records such as an all-time PR, but not for familiarity, patterns, or lapses.
- A dismissible intro card on the Posture and Train tabs introduces the feature once, and the first persona message
  after install or reset carries a short intro line. The card shows only while Character reminders are on (reminders
  are off on a fresh install), and its Settings button opens Settings over the current tab.
- Reset Persona is also available on the Persona debug page.

## Data flow

```text
PersonaHistory (workouts, assessments, routine names and minutes, exercise names)
  + preferences (enabled, reset date) + PersonaTraceState (recent decisions, engagement)
    → PersonaContextBuilder.build      familiarity, trajectory, streak, relationship records, reminder slot times
    → PersonaDetectors.all              achievement · pattern · lapse · posture → [PersonaObservation]
    → PersonaPlanner.plan               one winner per event or day; salience, cap, quiet hours, cooling, tone, copy
    → PersonaPlan { immediate, scheduled, traces }
    → WorkoutReminderCoordinator        fold into the acknowledgment, add/replace persona requests, store traces
```

Everything under `PostureAnalysisApp/Notifications/Persona/` is Foundation-only and pure: detectors and the planner read
time only from the context, so the same history always produces the same decision.

## When she speaks

- **Workout saved**: the coordinator evaluates the saved workout. If the day's acknowledgment is firing, persona content
  rides on it: HIGH and MEDIUM replace its title, body, and art; LOW adds one line. Otherwise HIGH sends an Active
  notification and MEDIUM a Passive one, a second after the save. LOW alone is kept for the debug page only.
- **Reconciliation** (launch, activation, settings and routine changes, workout save): the planner projects today and the
  next 7 days, at most one notification per day at about 11:30, moved at least 90 minutes from any reminder slot.
  Projected requests use the identifier prefix `fixMyPosture.persona.plan.` and are all replaced on every reconciliation,
  so they always reflect current history. Immediate requests use `fixMyPosture.persona.now.` and are never replaced.
- **Daily cap**: at most 2 standalone persona notifications per calendar day, Active and Passive together. Folded content
  does not count. The cap is absolute; extra candidates are suppressed and rediscovered later from history.
- **Quiet hours**: 22:00–08:00 behind `QuietHoursProviding`. An immediate notification during quiet hours is deferred to
  the end of quiet hours unless the app is active. Projected slots never land in quiet hours. Nothing uses Time Sensitive.

## Observations

All thresholds live in `PersonaPolicy`. Keys are deterministic (`family.kind.subject.period`), so the same fact is never
announced twice and a pattern's copy can keep referring back while the detector keeps finding it.

| Kind | Evidence | Salience |
|---|---|---|
| `achievement.pr.weight` | Heaviest comparable weight (lb converted to kg; bands never compare) beats every earlier session, with at least 3 earlier sessions | HIGH at +10 %, else MEDIUM |
| `achievement.pr.reps` | More reps than ever at that weight or heavier, at least 3 earlier sessions; not when the same exercise set a weight PR | HIGH at +3 reps, else MEDIUM |
| `achievement.milestone` | Workout count 10, 25, 50, 100, then every 50 | HIGH from 50 |
| `pattern.weekday` | 3, 4, or 5+ consecutive weeks with a workout on this weekday (5+ uses identity copy) | LOW, MEDIUM, MEDIUM |
| `pattern.weekday.upcoming` | Projected: 3+ previous weeks on today's weekday and none yet today; a goal-gradient nudge | LOW at 3, else MEDIUM |
| `pattern.routineRepeat` | The same routine 3 or 5 times in a row within 21 days | LOW, MEDIUM |
| `pattern.timeOfDay` | The last 5 workouts ended within a 2-hour band | LOW |
| `lapse.skippedExercise` | An exercise skipped 3+ consecutive times it came up (escalated copy at 6) | MEDIUM |
| `lapse.neglectedRoutine` | Projected: a routine done 3+ times, untouched for 3+ weeks while 3+ other workouts happened | MEDIUM |
| `lapse.decliningWeeks` | Projected: three closed weeks strictly decreasing from at least 3 workouts; may suggest the shortest routine | MEDIUM |
| `lapse.comeback` | First workout after 14+ days | HIGH at 28+ days with 10+ earlier workouts, else MEDIUM |
| `posture.returned` | An assessment today after 21+ days without one | LOW, MEDIUM at 45+ days |
| `posture.improved` | The two latest assessments both 2°+ closer to zero than the baseline on the same measurement | MEDIUM |

Negative observations (lapses other than a comeback) need evidence strength 3 or more and never exceed MEDIUM. Lapse
copy can suggest a gentler routine through a tappable target; it never prescribes weight or reps.

## Familiarity, trajectory, tone

- **Familiarity** counts distinct workout days since the reset: new below 5, familiar 5–14, established 15–39, long-term
  at 40+ when the counted days span at least 8 weeks.
- **Trajectory** compares workouts in the last 14 days with the 14 before: ±2 is improving or declining; fewer than 4 in
  total is unknown.
- **Tone** comes from the observation kind, familiarity, and trajectory, then avoids repeating the most recent tone or
  using any tone more than once in the last five. Annoyed and disappointed need established familiarity.

## Engagement cooling

The persona category registers `customDismissAction`, so taps and dismissals of standalone persona notifications are
recorded (`persona.traceID` in `userInfo`). Two dismissals with no taps among the last five standalone messages is mild
cooling (MEDIUM becomes LOW). Three dismissals, or five unanswered messages older than a day, is strong cooling (only
HIGH achievements and comebacks get through). A tap on the newest message clears it; engagement older than 14 days is
ignored. Cooling changes frequency only. She never mentions being ignored.

## Copy and art

`Design/NotificationCharacter/persona-content.json` is the single hand-edited source of truth for persona wording and
art. Each content key has titles and bodies tagged with the tones they fit and a minimum familiarity; openers, closers,
and intro lines are composed around a body. Art is a tone default (`toneArt`) with optional per-key overrides, using the
same expression, outfit, and crop vocabulary as the scenarios. Edit the JSON, run `make notification-character`, and
commit the JSON with the regenerated data set, images, and `docs/persona-content.md`. The voice is described in
`Design/NotificationCharacter/VOICE.md` (observer register).

Length limits apply to the authored templates (title 36, body 70, fragment 18 characters), and the composer drops
fragments to keep a body within 110 characters. Token values are not limited, so a very long routine or exercise name
can still produce a longer line; iOS truncates it in the banner.

## Debug page

Settings → Developer diagnostics → Persona debug shows the live status (familiarity, trajectory, cooling, standalone count
today, quiet hours, pending requests), the last 10 sent and the recent suppressed decisions, a detail view of each stored
`PersonaDecisionTrace` with categorical dot meters and a "why this won" sentence, and a content preview that can send any
configured variant without waiting for a detector. Traces live in `persona-traces.json` in Application Support.

## Known limits (v1)

- **Travel**: persona notifications fire on local wall-clock time like reminders, but traces store absolute fire
  dates. After crossing time zones on a day with a projected message, one message can repeat or be counted as delivered
  a few hours early.
- **Count keys**: observations keyed by a count (`pattern.routineRepeat`, `lapse.skippedExercise`) are deduplicated
  only while they are among the newest ten fired traces, so the same count can come up again weeks later.
- **Ending a workout early** marks the remaining routine items as skipped, so the tail exercises of a long routine can
  build a skip run for someone who often runs out of time. The copy only states counts.
- **Comeback** reads all history, not just history since the reset, because a gap is a fact.
- **Passive messages and cooling**: a passive message left unanswered for a day counts toward strong cooling, the same
  as an Active one. People who never open Notification Center can see her go quiet for up to two weeks.
- The debug page's Send uses the developer preview scheduler, so a Passive variant previews with sound and the default
  interruption level.

## Extending

- A new observation family (for example `occasion` for US holidays, or anniversaries) is a new `PersonaDetecting` type,
  its content keys in the JSON, and one line in `PersonaDetectors.all`. The planner, tone selector, composer, trace, and
  debug page need no changes beyond tone preferences for the new kinds.
- New history sources (for example HealthKit facts) become fields on `PersonaHistory`.
- A real quiet-hours source replaces `FixedQuietHours` behind `QuietHoursProviding`.
- `{name}` is a reserved token for a later version; validation rejects it today.
