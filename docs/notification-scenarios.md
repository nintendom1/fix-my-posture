# Notification scenarios

<!-- Generated from Design/NotificationCharacter/notification-scenarios.json by render_character.py --assets. Do not edit by hand: edit the JSON and re-run. -->

Every state the notification character can be in, with the art and copy it uses. The JSON file is the source of truth; the app loads it at runtime and this page, the portrait images and the app's data set are generated from it. To add or change a scenario, edit `Design/NotificationCharacter/notification-scenarios.json` and run `make notification-character`.

- **nudge**: scheduled ahead of time as a reminder.
- **acknowledgment**: sent a few seconds after a workout is saved.
- **crop**: `portrait` is head and shoulders. `close` is the tighter face crop used for heavier moments.
- **art**: the first entry is the primary image. Other entries are alternates, chosen by variant.
- 35 scenarios, 27 portrait images, 124 copy lines.

## Tokens

| Token | Meaning |
|---|---|
| `{suggestion}` | The routine or exercise being advertised, such as "Shoulder Day · about 12 min". |
| `{streak}` | The current streak in planned days. For streak-broken it is the length that just ended. |
| `{record}` | The longest streak before the current one. |
| `{remaining}` | Sessions still needed to beat the record. |
| `{days}` | Calendar days since the last saved workout. |

## Summary

| # | Scenario | Kind | Crop | Expression | Outfit |
|---|---|---|---|---|---|
| 1 | [Never established history](#1-never-established-history) | nudge | portrait | smile | hoodie |
| 2 | [First-ever notification](#2-first-ever-notification) | nudge | portrait | smile | hoodie |
| 3 | [Ordinary daily reminder](#3-ordinary-daily-reminder) | nudge | portrait | smile | hoodie |
| 4 | [Neutral check-in](#4-neutral-check-in) | nudge | portrait | normal | hoodie |
| 5 | [Early streak forming](#5-early-streak-forming) | nudge | portrait | smile / normal | hoodie |
| 6 | [Almost one week](#6-almost-one-week) | nudge | portrait | normal | hoodie |
| 7 | [One-week milestone](#7-one-week-milestone) | acknowledgment | portrait | delighted | hoodie |
| 8 | [Established streak reminder](#8-established-streak-reminder) | nudge | portrait | smile | hoodie |
| 9 | [Established streak at risk](#9-established-streak-at-risk) | nudge | close | sad | hoodie |
| 10 | [High-value streak at risk](#10-high-value-streak-at-risk) | nudge | close | sad | hoodie |
| 11 | [First ignored reminder](#11-first-ignored-reminder) | nudge | close | normal | hoodie |
| 12 | [Repeated ignored reminder](#12-repeated-ignored-reminder) | nudge | close | annoyed | hoodie |
| 13 | [Strong repeated-dismissal reminder](#13-strong-repeated-dismissal) | nudge | close | annoyed | hoodie |
| 14 | [Late-night reminder](#14-late-night-reminder) | nudge | portrait | sleepy | pajamas |
| 15 | [Late-night streak at risk](#15-late-night-streak-at-risk) | nudge | close | sleepy / sad | pajamas |
| 16 | [Final streak warning](#16-final-streak-warning) | nudge | close | sad | hoodie / pajamas |
| 17 | [Rare escalation](#17-rare-escalation) | nudge | close | angry | hoodie |
| 18 | [Session completed](#18-session-completed) | acknowledgment | portrait | smile2 | hoodie |
| 19 | [Session completed after reminders](#19-session-completed-after-reminders) | acknowledgment | portrait | smug / smile2 | hoodie |
| 20 | [Streak preserved at last minute](#20-streak-preserved-last-minute) | acknowledgment | portrait | delighted | hoodie |
| 21 | [Streak broken](#21-streak-broken) | nudge | close | sad | hoodie |
| 22 | [Immediate post-break](#22-immediate-post-break) | nudge | portrait | sad / normal | hoodie |
| 23 | [Restart after broken streak](#23-restart-after-broken-streak) | acknowledgment | portrait | smile2 | hoodie |
| 24 | [Second day after restart](#24-second-day-after-restart) | acknowledgment | portrait | smile | hoodie |
| 25 | [Long absence](#25-long-absence) | nudge | portrait | normal / sad | hoodie |
| 26 | [Comeback after long absence](#26-comeback-after-long-absence) | acknowledgment | portrait | smile2 | hoodie |
| 27 | [New personal-best streak](#27-new-personal-best-streak) | acknowledgment | portrait | smug | hoodie / pe-uniform |
| 28 | [Approaching personal best](#28-approaching-personal-best) | nudge | portrait | smug | hoodie |
| 29 | [Major streak milestone](#29-major-streak-milestone) | acknowledgment | portrait | laugh / delighted | hoodie / sundress |
| 30 | [Perfect week](#30-perfect-week) | acknowledgment | portrait | delighted / laugh | hoodie |
| 31 | [Weekly recovery](#31-weekly-recovery) | acknowledgment | portrait | smile2 | hoodie |
| 32 | [Morning reminder](#32-morning-reminder) | nudge | portrait | smile | hoodie / coat |
| 33 | [Weekend reminder](#33-weekend-reminder) | nudge | portrait | smile / normal | hoodie |
| 34 | [First completed session](#34-first-completed-session) | acknowledgment | portrait | delighted / smile2 | hoodie |
| 35 | [Notification after notification-free success](#35-notification-free-success) | acknowledgment | portrait | smile / smug | hoodie |

## Scenarios

### 1. never-established-history

**Never established history** · nudge

- **Trigger:** The user has never developed a meaningful streak or recurring habit.
- **Tone:** Inviting rather than guilt-driven. Establish the idea that this can become something shared.
- **Art:** `smile-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Hey. Want to start one with me?
  2. A streak starts with one day. Want it to be today?
  3. No pressure. Want to see how far we can take this?
  4. I’d like to do this with you. Ready when you are.

### 2. first-ever-notification

**First-ever notification** · nudge

- **Trigger:** The character is appearing to the user for the first time.
- **Tone:** Warm introduction. No guilt, because no relationship has been established yet.
- **Art:** `smile-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Hi. Want to do this together?
  2. Hi! I’ll check in now and then. Want to start with one today?
  3. Hello. I’m here whenever you want to get started.

### 3. ordinary-daily-reminder

**Ordinary daily reminder** · nudge

- **Trigger:** Today’s session is incomplete and there is no meaningful streak pressure.
- **Tone:** Friendly and low-pressure.
- **Art:** `smile-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Want to get today’s one in?
  2. Ready for today’s session?
  3. Got a few minutes for today’s one?
  4. Today’s session is waiting. Want to knock it out?
  5. No rush. Want to do today’s now?

### 4. neutral-check-in

**Neutral check-in** · nudge

- **Trigger:** Today’s session is incomplete and the user has recently been consistent.
- **Tone:** Quietly expectant.
- **Art:** `normal-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Still planning to do this today?
  2. Checking in. Today’s session is still open.
  3. Is today still on?
  4. Quiet one today. Still on for it?

### 5. early-streak-forming

**Early streak forming** · nudge

- **Trigger:** Roughly 2 to 4 consecutive planned days are complete.
- **Tone:** Reinforce momentum without overstating it.
- **Art:** `smile-hoodie-portrait`, `normal-hoodie-portrait`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 3
- **Copy:**
  1. We’re getting a streak going.
  2. {streak} in a row so far. Let’s keep it moving.
  3. Look at that. {streak} days. Don’t stop now.
  4. This is turning into something.

### 6. almost-one-week

**Almost one week** · nudge

- **Trigger:** One session away from a 7-day streak.
- **Tone:** Goal-gradient pressure.
- **Art:** `normal-hoodie-portrait`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 6
- **Copy:**
  1. One more and we make it a week.
  2. {streak} down. One more and it’s a full week.
  3. A week is one session away.
  4. So close to a week. Let’s finish it.

### 7. one-week-milestone

**One-week milestone** · acknowledgment

- **Trigger:** A 7-day streak was just achieved.
- **Tone:** Strong positive reinforcement.
- **Art:** `delighted-hoodie-portrait`
- **Title:** `A whole week`
- **Copy:**
  1. A whole week!
  2. Seven days. I knew we could do it.
  3. One full week together. That’s real.
  4. Week one: done. Look at us.

### 8. established-streak-reminder

**Established streak reminder** · nudge

- **Trigger:** A meaningful streak exists but is not yet in immediate danger.
- **Tone:** Make the streak feel shared.
- **Art:** `smile-hoodie-portrait`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 12
- **Copy:**
  1. Let’s keep this going.
  2. We’ve got something good going. Let’s keep it.
  3. Day after day. Ready for today’s?
  4. Our streak’s at {streak}. Let’s protect it.

### 9. established-streak-at-risk

**Established streak at risk** · nudge

- **Trigger:** A meaningful streak exists and the session is still incomplete later in the day.
- **Tone:** Relational guilt.
- **Art:** `sad-hoodie-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 26
- **Copy:**
  1. {streak} days and you’re really going to leave me hanging?
  2. We’re at {streak} days. Please don’t let it slip.
  3. I’ve been counting. {streak} days. Don’t stop now.
  4. It would be a shame to lose {streak} days over today.

### 10. high-value-streak-at-risk

**High-value streak at risk** · nudge

- **Trigger:** A long or personal-best-adjacent streak is at risk and the session is incomplete.
- **Tone:** Stronger concern.
- **Art:** `sad-hoodie-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 31
- **Copy:**
  1. Don’t make me watch {streak} days disappear.
  2. {streak} days. I’m not ready to lose that.
  3. We’re too far in to quit now. {streak} days.

### 11. first-ignored-reminder

**First ignored reminder** · nudge

- **Trigger:** An earlier reminder was dismissed or ignored and the task remains incomplete.
- **Tone:** Minimal, watchful follow-up.
- **Art:** `normal-hoodie-close`
- **Title:** `{suggestion}`
- **Copy:**
  1. …still here.
  2. Still waiting.
  3. Hey. Still here.
  4. Just a gentle second knock.

### 12. repeated-ignored-reminder

**Repeated ignored reminder** · nudge

- **Trigger:** Multiple reminders were ignored during the same relevant window.
- **Tone:** Mildly confrontational but playful.
- **Art:** `annoyed-hoodie-close`
- **Title:** `{suggestion}`
- **Copy:**
  1. Oh. We’re doing this again.
  2. That’s a few reminders now.
  3. I can do this all evening, you know.
  4. Ignoring me won’t make today’s session go away.

### 13. strong-repeated-dismissal

**Strong repeated-dismissal reminder** · nudge

- **Trigger:** An established streak plus repeated ignored reminders.
- **Tone:** Earned social pressure.
- **Art:** `annoyed-hoodie-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 26
- **Copy:**
  1. You know I’m going to keep asking, right?
  2. {streak} days of work, and you’re ignoring me?
  3. I’m not going anywhere. Neither is your streak, if you move.

### 14. late-night-reminder

**Late-night reminder** · nudge

- **Trigger:** The session is incomplete late in the evening.
- **Tone:** Contextual, low-key guilt.
- **Art:** `sleepy-pajamas-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. I was going to sleep, you know.
  2. It’s late. One quick session and we’re both done.
  3. Stayed up for this. Let’s make it quick.
  4. Almost bedtime. Want to squeeze today’s in?

### 15. late-night-streak-at-risk

**Late-night streak at risk** · nudge

- **Trigger:** A meaningful streak, late night, and the session is incomplete.
- **Tone:** Combine streak loss with the relationship.
- **Art:** `sleepy-pajamas-close`, `sad-pajamas-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 26
- **Copy:**
  1. You’re really making me stay up for this?
  2. {streak} days and it’s this late. Please.
  3. I’m half asleep and still here for our {streak} days.

### 16. final-streak-warning

**Final streak warning** · nudge

- **Trigger:** Near the end of the useful reminder window, and a meaningful streak would be lost.
- **Tone:** Concerned rather than angry. Keep copy short and direct.
- **Art:** `sad-hoodie-close`, `sad-pajamas-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 26
- **Copy:**
  1. Last chance for today.
  2. Almost out of time.
  3. Please. Just one set.
  4. It’s almost over for today.

### 17. rare-escalation

**Rare escalation** · nudge

- **Trigger:** A very long streak, repeated ignored reminders, and imminent loss.
- **Tone:** Use extremely rarely so it keeps its novelty. Comedic frustration rather than hostility.
- **Art:** `angry-hoodie-close`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 52
- **Copy:**
  1. {streak} days and THIS is how it ends?!
  2. I did not wait all day for this.
  3. Okay. I’m officially mad. Go. Now.

### 18. session-completed

**Session completed** · acknowledgment

- **Trigger:** The user finishes an ordinary session.
- **Tone:** Warm acknowledgment.
- **Art:** `smile2-hoodie-portrait`
- **Title:** `Nice work`
- **Copy:**
  1. There we go.
  2. Done. Nice and steady.
  3. That’s today’s. Good job.
  4. Session logged. Proud of you.

### 19. session-completed-after-reminders

**Session completed after reminders** · acknowledgment

- **Trigger:** The user completes a session after one or more escalating reminders.
- **Tone:** Playful recognition.
- **Art:** `smug-hoodie-portrait`, `smile2-hoodie-portrait`
- **Title:** `Nice work`
- **Copy:**
  1. Knew you’d do it.
  2. Took a few nudges. Worth it.
  3. See? Not so bad.
  4. Look who showed up.

### 20. streak-preserved-last-minute

**Streak preserved at last minute** · acknowledgment

- **Trigger:** A session was completed shortly before the streak would have broken.
- **Tone:** Relief and celebration.
- **Art:** `delighted-hoodie-portrait`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 14
- **Copy:**
  1. Okay. That was way too close.
  2. Phew. {streak} days, saved with no time to spare.
  3. I almost lost it. Don’t do that to me again.

### 21. streak-broken

**Streak broken** · nudge

- **Trigger:** A meaningful streak actually ended.
- **Tone:** Briefly acknowledge the loss rather than pretending it did not matter.
- **Art:** `sad-hoodie-close`
- **Title:** `Our {streak}-day streak ended`
- **Dev preview sample:** streak = 26
- **Copy:**
  1. We lost {streak} days. That one hurt.
  2. It’s over. {streak} days, gone. Let’s not dwell.
  3. I’m not going to pretend that didn’t matter.

### 22. immediate-post-break

**Immediate post-break** · nudge

- **Trigger:** The first appropriate contact after a streak break.
- **Tone:** Brief disappointment, then a transition toward recovery.
- **Art:** `sad-hoodie-portrait`, `normal-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Okay. Yesterday’s behind us. Ready to start over?
  2. It’s fine. Really. Want to start a new one?
  3. A fresh start is still a start.
  4. That’s over now. Want to begin again?

### 23. restart-after-broken-streak

**Restart after broken streak** · acknowledgment

- **Trigger:** The first new session after a streak break.
- **Tone:** Reassuring reset.
- **Art:** `smile2-hoodie-portrait`
- **Title:** `Day 1`
- **Copy:**
  1. Day 1. I’m still here.
  2. Back at it. Day 1.
  3. Fresh start. I’m glad you came back.

### 24. second-day-after-restart

**Second day after restart** · acknowledgment

- **Trigger:** The user follows through again after restarting.
- **Tone:** Reinforce recovery rather than dwelling on the loss.
- **Art:** `smile-hoodie-portrait`
- **Title:** `Day 2`
- **Copy:**
  1. Day 2. We’re moving again.
  2. Two days. Look at that.
  3. That’s the comeback. Day 2.

### 25. long-absence

**Long absence** · nudge

- **Trigger:** The user has not engaged for an extended period.
- **Tone:** Avoid pretending the streak still matters.
- **Art:** `normal-hoodie-portrait`, `sad-hoodie-portrait`
- **Title:** `{suggestion}`
- **Dev preview sample:** days = 12
- **Copy:**
  1. Hey. It’s been a while.
  2. {days} days. I’ve missed this.
  3. No guilt. Just checking in. Ready to try again?
  4. It’s been {days} days. Want to ease back in?

### 26. comeback-after-long-absence

**Comeback after long absence** · acknowledgment

- **Trigger:** The user returns and completes a session after a long absence.
- **Tone:** A relationship cue.
- **Art:** `smile2-hoodie-portrait`
- **Title:** `Welcome back`
- **Copy:**
  1. There you are.
  2. You came back. Good.
  3. Missed you. Nice to see you here.

### 27. new-personal-best-streak

**New personal-best streak** · acknowledgment

- **Trigger:** The streak exceeds the user’s prior record.
- **Tone:** Competitive.
- **Art:** `smug-hoodie-portrait`, `smug-pe-uniform-portrait`
- **Title:** `New record`
- **Dev preview sample:** streak = 32, record = 31
- **Copy:**
  1. Okay. New record. Now how far are we taking it?
  2. {streak} days. That’s a personal best.
  3. Beat the old record of {record}. Let’s go further.

### 28. approaching-personal-best

**Approaching personal best** · nudge

- **Trigger:** One or a few sessions from the previous record.
- **Tone:** Goal-gradient pressure.
- **Art:** `smug-hoodie-portrait`
- **Title:** `{streak}-day streak`
- **Dev preview sample:** streak = 29, record = 31, remaining = 3
- **Copy:**
  1. {remaining} more and you beat your record.
  2. Your record is {record}. We’re close.
  3. {remaining} to go. Don’t blink.

### 29. major-streak-milestone

**Major streak milestone** · acknowledgment

- **Trigger:** A 14, 30, 50, or 100-day streak, and so on.
- **Tone:** Celebrate visibly. Major milestones can justify rarer visual variation.
- **Art:** `laugh-hoodie-portrait`, `delighted-hoodie-portrait`, `laugh-sundress-portrait`, `delighted-sundress-portrait`
- **Title:** `{streak} days!`
- **Dev preview sample:** streak = 30
- **Copy:**
  1. {streak} days! Can you believe it?
  2. {streak}. I’m so proud of us.
  3. {streak} days. That’s no accident.
  4. {streak} days. Look what we built.

### 30. perfect-week

**Perfect week** · acknowledgment

- **Trigger:** The user completed every planned session that week.
- **Tone:** Keep this state relatively special.
- **Art:** `delighted-hoodie-portrait`, `laugh-hoodie-portrait`
- **Title:** `Perfect week`
- **Copy:**
  1. Perfect week.
  2. Every planned session, done. Perfect week.
  3. Not one missed. That’s a perfect week.

### 31. weekly-recovery

**Weekly recovery** · acknowledgment

- **Trigger:** The user had misses earlier in the week but completed the remaining planned sessions.
- **Tone:** Recognize the recovery.
- **Art:** `smile2-hoodie-portrait`
- **Title:** `Week back on track`
- **Copy:**
  1. You pulled the week back.
  2. Rough start, strong finish. Nicely done.
  3. Missed a few, then made it up. I’ll take that.

### 32. morning-reminder

**Morning reminder** · nudge

- **Trigger:** Morning is an appropriate user-selected reminder time.
- **Tone:** Fresh and low-pressure.
- **Art:** `smile-hoodie-portrait`, `smile-coat-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Want to get it out of the way early?
  2. Morning. Want to start the day with it?
  3. Early session? Then the rest of the day is free.
  4. Good morning. Today’s session is ready when you are.

### 33. weekend-reminder

**Weekend reminder** · nudge

- **Trigger:** The scheduled session occurs on a weekend.
- **Tone:** Slightly more casual. Don’t over-specialize unless useful.
- **Art:** `smile-hoodie-portrait`, `normal-hoodie-portrait`
- **Title:** `{suggestion}`
- **Copy:**
  1. Weekend session? An easy way to start the day.
  2. It’s the weekend. Still want to fit this in?
  3. No rush today. Whenever you’re ready.

### 34. first-completed-session

**First completed session** · acknowledgment

- **Trigger:** The user completes their first tracked session.
- **Tone:** Establish a positive association immediately.
- **Art:** `delighted-hoodie-portrait`, `smile2-hoodie-portrait`
- **Title:** `First session done`
- **Copy:**
  1. First one done. That’s how it starts.
  2. You did it. The first one is the hardest.
  3. Look at that. One down.

### 35. notification-free-success

**Notification after notification-free success** · acknowledgment

- **Trigger:** The user has been completing sessions before reminders fire.
- **Tone:** Reinforce self-initiation.
- **Art:** `smile-hoodie-portrait`, `smug-hoodie-portrait`
- **Title:** `Nice work`
- **Copy:**
  1. You beat me to it again.
  2. Done before I could even ask. I like this.
  3. Didn’t even need a reminder. Impressive.

## Images

27 images in `PostureAnalysisApp/Assets.xcassets/NotificationCharacter/`:

- `angry-hoodie-close`
- `angry-hoodie-portrait`
- `annoyed-hoodie-close`
- `annoyed-hoodie-portrait`
- `delighted-hoodie-close`
- `delighted-hoodie-portrait`
- `delighted-sundress-portrait`
- `laugh-hoodie-close`
- `laugh-hoodie-portrait`
- `laugh-sundress-portrait`
- `normal-hoodie-close`
- `normal-hoodie-portrait`
- `sad-hoodie-close`
- `sad-hoodie-portrait`
- `sad-pajamas-close`
- `sleepy-hoodie-close`
- `sleepy-hoodie-portrait`
- `sleepy-pajamas-close`
- `sleepy-pajamas-portrait`
- `smile-coat-portrait`
- `smile-hoodie-close`
- `smile-hoodie-portrait`
- `smile2-hoodie-close`
- `smile2-hoodie-portrait`
- `smug-hoodie-close`
- `smug-hoodie-portrait`
- `smug-pe-uniform-portrait`
