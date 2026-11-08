import Foundation

/// Frozen expected traces for `WorkoutGoldenTraceTests`. Change one only for an intentional, reviewed behaviour change.
enum WorkoutGoldenTraces {
    static let perSideRows = """
        t=10.00 state framing dumbbell_row set=1 reps=0 side=left counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise dumbbell_row epoch=1
        t=10.00 speak "Workout coach ready. One-arm dumbbell rows, two sets of 8 to 10 each arm. Stand side-on to the phone with your left arm nearer it, bend forward, and rest your other hand on a bench."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still dumbbell_row 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready dumbbell_row set=1 reps=0 side=left counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising dumbbell_row set=1 reps=0 side=left counting=true
        t=11.00 control exercise dumbbell_row epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 2. Go."
        t=11.00 tip show row.reminder.squeeze "Squeeze your shoulder blade." (reminder)
        > frames demo dumbbell_row 34 frames @0.1 (3.4s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.40 input startPosition true
        t=14.40 input rep epoch=2 sides=left,right
        t=14.40 state ready dumbbell_row set=1 reps=0 side=right counting=false
        t=14.40 control counting false
        t=14.40 control exercise dumbbell_row epoch=3
        t=14.40 clearFeedback
        t=14.40 speak "Left arm done, 1 rep. Switch to your right arm. Say start when you're ready."
        > frames still dumbbell_row 5 frames @0.1 (0.5s)
        t=14.50 control sessionPhase ready
        t=14.50 input startPosition false
        t=14.60 input startPosition true
        > send .start
        t=14.90 command start (touch)
        t=14.90 state exercising dumbbell_row set=1 reps=0 side=right counting=true
        t=14.90 control exercise dumbbell_row epoch=4
        t=14.90 clearFeedback
        t=14.90 control counting true
        t=14.90 speak "Set 1 of 2. Go."
        t=14.90 tip show row.reminder.neck "Keep your neck neutral." (reminder)
        > frames demo dumbbell_row 34 frames @0.1 (3.4s)
        t=15.00 control sessionPhase exercising
        t=15.00 input startPosition false
        t=15.10 input startPosition true
        t=16.80 input startPosition false
        t=17.90 tip clear
        t=18.30 input startPosition true
        t=18.30 input rep epoch=4 sides=left,right
        t=18.30 state resting dumbbell_row set=2 reps=0 side=left counting=false
        t=18.30 control counting false
        t=18.30 control exercise dumbbell_row epoch=5
        t=18.30 clearFeedback
        t=18.30 speak "Right arm done, 1 rep. Set 1 done. Rest up. I'll tell you when it's time for set 2."
        > frames still dumbbell_row 610 frames @0.1 (61.0s)
        t=18.40 control sessionPhase resting
        t=18.40 input startPosition false
        t=18.50 input startPosition true
        t=78.50 speak "Rest is up. Say start for set 2."
        > send .start
        t=79.30 command start (touch)
        t=79.30 state exercising dumbbell_row set=2 reps=0 side=left counting=true
        t=79.30 control exercise dumbbell_row epoch=6
        t=79.30 clearFeedback
        t=79.30 control counting true
        t=79.30 speak "Set 2 of 2. Go."
        t=79.30 tip show row.reminder.brace "Brace your core." (reminder)
        > frames demo dumbbell_row 34 frames @0.1 (3.4s)
        t=79.40 control sessionPhase exercising
        t=79.40 input startPosition false
        t=79.50 input startPosition true
        t=81.20 input startPosition false
        t=82.30 tip clear
        t=82.70 input startPosition true
        t=82.70 input rep epoch=6 sides=left,right
        t=82.70 state ready dumbbell_row set=2 reps=0 side=right counting=false
        t=82.70 control counting false
        t=82.70 control exercise dumbbell_row epoch=7
        t=82.70 clearFeedback
        t=82.70 speak "Left arm done, 1 rep. Switch to your right arm. Say start when you're ready."
        > frames still dumbbell_row 5 frames @0.1 (0.5s)
        t=82.80 control sessionPhase ready
        t=82.80 input startPosition false
        t=82.90 input startPosition true
        > send .start
        t=83.20 command start (touch)
        t=83.20 state exercising dumbbell_row set=2 reps=0 side=right counting=true
        t=83.20 control exercise dumbbell_row epoch=8
        t=83.20 clearFeedback
        t=83.20 control counting true
        t=83.20 speak "Set 2 of 2. Go."
        t=83.20 tip show row.reminder.squeeze "Squeeze your shoulder blade." (reminder)
        > frames demo dumbbell_row 34 frames @0.1 (3.4s)
        t=83.30 control sessionPhase exercising
        t=83.30 input startPosition false
        t=83.40 input startPosition true
        t=85.10 input startPosition false
        t=86.20 tip clear
        t=86.60 input startPosition true
        t=86.60 input rep epoch=8 sides=left,right
        t=86.60 state exerciseComplete dumbbell_row set=2 reps=0 side=left counting=false
        t=86.60 control counting false
        t=86.60 control exercise dumbbell_row epoch=9
        t=86.60 clearFeedback
        t=86.60 speak "Right arm done, 1 rep. One-Arm Dumbbell Row complete. Say another round or end workout."
        > send .endWorkout
        t=86.60 command endWorkout (touch)
        t=86.60 state ended dumbbell_row set=2 reps=0 side=left counting=false
        t=86.60 clearFeedback
        t=86.60 speak "Workout ended. Nice work." (interrupts)
        t=86.60 listen disable paused
        t=86.60 camera idle
        t=86.60 control resetTracking
        t=86.60 input startPosition false
        t=86.60 input framing lost
        > view saves history (phase ended)
        t=86.60 history save record plan=none planID=none id=workout entries=1
        t=86.60 history save entry dumbbell_row "One-Arm Dumbbell Row" outcome=none sets=[1 rep L, 1 rep R, 1 rep L, 1 rep R]
        t=86.60 reminders workoutSaved
        > view close
        t=86.60 listen disable paused
        t=86.60 control resetTracking
        t=86.60 input framing lost
        t=86.60 speech stopAll
        t=86.60 audio deactivate
        """

    static let airSquatTwoSets = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 2. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 553 frames @0.1 (55.3s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.30 state exercising air_squat set=1 reps=2 counting=true
        t=20.30 input startPosition false
        t=21.90 input startPosition true
        t=21.90 input rep epoch=2 sides=left,right
        t=22.00 state exercising air_squat set=1 reps=3 counting=true
        t=24.00 input startPosition false
        t=25.60 input startPosition true
        t=25.60 input rep epoch=2 sides=left,right
        t=25.70 state exercising air_squat set=1 reps=4 counting=true
        t=27.70 input startPosition false
        t=29.30 input startPosition true
        t=29.30 input rep epoch=2 sides=left,right
        t=29.40 state exercising air_squat set=1 reps=5 counting=true
        t=31.40 input startPosition false
        t=33.00 input startPosition true
        t=33.00 input rep epoch=2 sides=left,right
        t=33.10 state exercising air_squat set=1 reps=6 counting=true
        t=35.10 input startPosition false
        t=36.00 tip show squat.reminder.brace "Brace your core." (reminder)
        t=36.70 input startPosition true
        t=36.70 input rep epoch=2 sides=left,right
        t=36.80 state exercising air_squat set=1 reps=7 counting=true
        t=38.80 input startPosition false
        t=39.00 tip clear
        t=40.40 input startPosition true
        t=40.40 input rep epoch=2 sides=left,right
        t=40.50 state exercising air_squat set=1 reps=8 counting=true
        t=42.50 input startPosition false
        t=44.10 input startPosition true
        t=44.10 input rep epoch=2 sides=left,right
        t=44.20 state exercising air_squat set=1 reps=9 counting=true
        t=46.20 input startPosition false
        t=47.80 input startPosition true
        t=47.80 input rep epoch=2 sides=left,right
        t=47.90 state exercising air_squat set=1 reps=10 counting=true
        t=49.90 input startPosition false
        t=51.50 input startPosition true
        t=51.50 input rep epoch=2 sides=left,right
        t=51.60 state exercising air_squat set=1 reps=11 counting=true
        t=53.60 input startPosition false
        t=55.20 input startPosition true
        t=55.20 input rep epoch=2 sides=left,right
        t=55.30 state exercising air_squat set=1 reps=12 counting=true
        t=57.30 input startPosition false
        t=58.90 input startPosition true
        t=58.90 input rep epoch=2 sides=left,right
        t=59.00 state exercising air_squat set=1 reps=13 counting=true
        t=61.00 tip show squat.reminder.breathe "Breathe in on the way down." (reminder)
        t=61.00 input startPosition false
        t=62.60 input startPosition true
        t=62.60 input rep epoch=2 sides=left,right
        t=62.70 state exercising air_squat set=1 reps=14 counting=true
        t=64.00 tip clear
        t=64.70 input startPosition false
        t=66.30 input startPosition true
        t=66.30 input rep epoch=2 sides=left,right
        t=66.30 state resting air_squat set=2 reps=0 counting=false
        t=66.30 control counting false
        t=66.30 control exercise air_squat epoch=3
        t=66.30 clearFeedback
        t=66.30 speak "Set 1 done, 15 reps. Rest up. I'll tell you when it's time for set 2."
        > frames still air_squat 610 frames @0.1 (61.0s)
        t=66.40 control sessionPhase resting
        t=66.40 input startPosition false
        t=66.50 input startPosition true
        t=126.50 speak "Rest is up. Say start for set 2."
        > send .start
        t=127.30 command start (touch)
        t=127.30 state exercising air_squat set=2 reps=0 counting=true
        t=127.30 control exercise air_squat epoch=4
        t=127.30 clearFeedback
        t=127.30 control counting true
        t=127.30 speak "Set 2 of 2. Go."
        t=127.30 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 553 frames @0.1 (55.3s)
        t=127.40 control sessionPhase exercising
        t=127.40 input startPosition false
        t=127.50 input startPosition true
        t=129.20 input startPosition false
        t=130.30 tip clear
        t=130.80 input startPosition true
        t=130.80 input rep epoch=4 sides=left,right
        t=130.90 state exercising air_squat set=2 reps=1 counting=true
        t=132.90 input startPosition false
        t=134.50 input startPosition true
        t=134.50 input rep epoch=4 sides=left,right
        t=134.60 state exercising air_squat set=2 reps=2 counting=true
        t=136.60 input startPosition false
        t=138.20 input startPosition true
        t=138.20 input rep epoch=4 sides=left,right
        t=138.30 state exercising air_squat set=2 reps=3 counting=true
        t=140.30 input startPosition false
        t=141.90 input startPosition true
        t=141.90 input rep epoch=4 sides=left,right
        t=142.00 state exercising air_squat set=2 reps=4 counting=true
        t=144.00 input startPosition false
        t=145.60 input startPosition true
        t=145.60 input rep epoch=4 sides=left,right
        t=145.70 state exercising air_squat set=2 reps=5 counting=true
        t=147.70 input startPosition false
        t=149.30 input startPosition true
        t=149.30 input rep epoch=4 sides=left,right
        t=149.40 state exercising air_squat set=2 reps=6 counting=true
        t=151.40 input startPosition false
        t=152.50 tip show squat.reminder.brace "Brace your core." (reminder)
        t=153.00 input startPosition true
        t=153.00 input rep epoch=4 sides=left,right
        t=153.10 state exercising air_squat set=2 reps=7 counting=true
        t=155.10 input startPosition false
        t=155.50 tip clear
        t=156.70 input startPosition true
        t=156.70 input rep epoch=4 sides=left,right
        t=156.80 state exercising air_squat set=2 reps=8 counting=true
        t=158.80 input startPosition false
        t=160.40 input startPosition true
        t=160.40 input rep epoch=4 sides=left,right
        t=160.50 state exercising air_squat set=2 reps=9 counting=true
        t=162.50 input startPosition false
        t=164.10 input startPosition true
        t=164.10 input rep epoch=4 sides=left,right
        t=164.20 state exercising air_squat set=2 reps=10 counting=true
        t=166.20 input startPosition false
        t=167.80 input startPosition true
        t=167.80 input rep epoch=4 sides=left,right
        t=167.90 state exercising air_squat set=2 reps=11 counting=true
        t=169.90 input startPosition false
        t=171.50 input startPosition true
        t=171.50 input rep epoch=4 sides=left,right
        t=171.60 state exercising air_squat set=2 reps=12 counting=true
        t=173.60 input startPosition false
        t=175.20 input startPosition true
        t=175.20 input rep epoch=4 sides=left,right
        t=175.30 state exercising air_squat set=2 reps=13 counting=true
        t=177.30 input startPosition false
        t=177.50 tip show squat.reminder.breathe "Breathe in on the way down." (reminder)
        t=178.90 input startPosition true
        t=178.90 input rep epoch=4 sides=left,right
        t=179.00 state exercising air_squat set=2 reps=14 counting=true
        t=180.50 tip clear
        t=181.00 input startPosition false
        t=182.60 input startPosition true
        t=182.60 input rep epoch=4 sides=left,right
        t=182.60 state exerciseComplete air_squat set=2 reps=0 counting=false
        t=182.60 control counting false
        t=182.60 control exercise air_squat epoch=5
        t=182.60 clearFeedback
        t=182.60 speak "Set 2 done, 15 reps. Air Squat complete. Say another round, change exercise, or end workout."
        > send .endWorkout
        t=182.60 command endWorkout (touch)
        t=182.60 state ended air_squat set=2 reps=0 counting=false
        t=182.60 clearFeedback
        t=182.60 speak "Workout ended. Nice work." (interrupts)
        t=182.60 listen disable paused
        t=182.60 camera idle
        t=182.60 control resetTracking
        t=182.60 input startPosition false
        t=182.60 input framing lost
        > view saves history (phase ended)
        t=182.60 history save record plan=none planID=none id=workout entries=1
        t=182.60 history save entry air_squat "Air Squat" outcome=none sets=[15 reps, 15 reps]
        t=182.60 reminders workoutSaved
        > view close
        t=182.60 listen disable paused
        t=182.60 control resetTracking
        t=182.60 input framing lost
        t=182.60 speech stopAll
        t=182.60 audio deactivate
        """

    static let routineTwoItems = """
        t=10.00 state framing air_squat item=1 set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat item=1 set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat item=1 set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 109 frames @0.1 (10.9s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat item=1 set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.30 state exercising air_squat item=1 set=1 reps=2 counting=true
        t=20.30 input startPosition false
        t=21.90 input startPosition true
        t=21.90 input rep epoch=2 sides=left,right
        t=21.90 state resting wall_push_up item=2 set=1 reps=0 counting=false
        t=21.90 control counting false
        t=21.90 control exercise wall_push_up epoch=3
        t=21.90 clearFeedback
        t=21.90 speak "Set 1 done, 3 reps. Air Squat complete. Up next: wall push-up, 1 set of 2. Rest up."
        > frames still wall_push_up 602 frames @0.1 (60.2s)
        t=22.00 control sessionPhase resting
        t=22.00 input framing lost
        t=22.10 input startPosition true
        t=22.70 input framing reliable
        t=82.00 state ready wall_push_up item=2 set=1 reps=0 counting=false
        t=82.00 speak "Rest is up. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        t=82.10 control sessionPhase ready
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=83.10 state exercising wall_push_up item=2 set=1 reps=0 counting=true
        t=83.10 control exercise wall_push_up epoch=4
        t=83.10 clearFeedback
        t=83.10 control counting true
        t=83.10 speak "Set 1 of 1. Go."
        t=83.10 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 71 frames @0.1 (7.1s)
        t=83.20 control sessionPhase exercising
        t=83.20 input startPosition false
        t=83.30 input startPosition true
        t=84.60 input startPosition false
        t=86.10 tip clear
        t=86.50 input startPosition true
        t=86.50 input rep epoch=4 sides=left,right
        t=86.60 state exercising wall_push_up item=2 set=1 reps=1 counting=true
        t=88.30 input startPosition false
        t=90.20 input startPosition true
        t=90.20 input rep epoch=4 sides=left,right
        t=90.20 state exerciseComplete wall_push_up item=2 set=1 reps=0 counting=false
        t=90.20 control counting false
        t=90.20 control exercise wall_push_up epoch=5
        t=90.20 clearFeedback
        t=90.20 speak "Set 1 done, 2 reps. Wall Push-Up complete. Golden Routine complete. Say another round, change exercise, or end workout."
        > send .endWorkout
        t=90.20 command endWorkout (touch)
        t=90.20 state ended wall_push_up item=2 set=1 reps=0 counting=false
        t=90.20 clearFeedback
        t=90.20 speak "Workout ended. Nice work." (interrupts)
        t=90.20 listen disable paused
        t=90.20 camera idle
        t=90.20 control resetTracking
        t=90.20 input startPosition false
        t=90.20 input framing lost
        > view saves history (phase ended)
        t=90.20 history save record plan="Golden Routine" planID=expectedRoutine id=workout entries=2
        t=90.20 history save entry air_squat "Air Squat" outcome=completed sets=[3 reps]
        t=90.20 history save entry wall_push_up "Wall Push-Up" outcome=completed sets=[2 reps]
        t=90.20 reminders workoutSaved
        > view close
        t=90.20 listen disable paused
        t=90.20 control resetTracking
        t=90.20 input framing lost
        t=90.20 speech stopAll
        t=90.20 audio deactivate
        """

    static let pauseAndResume = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Tap Start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 2. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 72 frames @0.1 (7.2s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.20 state exercising air_squat set=1 reps=2 counting=true
        > send .pause
        t=18.20 command pause (touch)
        t=18.20 state paused(user) air_squat set=1 reps=2 counting=false
        t=18.20 control counting false
        t=18.20 speak "Paused. Tap Resume when ready." (interrupts)
        > frames still air_squat 20 frames @0.1 (2.0s)
        t=18.30 control sessionPhase paused(user)
        > send .resume
        t=20.20 command resume (touch)
        t=20.20 state exercising air_squat set=1 reps=2 counting=true
        t=20.20 control counting true
        t=20.20 speak "Resuming at 2." (interrupts)
        > frames demo air_squat 72 frames @0.1 (7.2s)
        t=20.30 control sessionPhase exercising
        t=22.10 input startPosition false
        t=23.70 input startPosition true
        t=23.70 input rep epoch=2 sides=left,right
        t=23.80 state exercising air_squat set=1 reps=3 counting=true
        t=25.80 input startPosition false
        t=27.40 input startPosition true
        t=27.40 input rep epoch=2 sides=left,right
        t=27.40 state resting air_squat set=2 reps=0 counting=false
        t=27.40 control counting false
        t=27.40 control exercise air_squat epoch=3
        t=27.40 clearFeedback
        t=27.40 speak "Set 1 done, 4 reps. Rest up. I'll tell you when it's time for set 2."
        > frames still air_squat 50 frames @0.1 (5.0s)
        t=27.50 control sessionPhase resting
        t=27.50 input startPosition false
        t=27.60 input startPosition true
        > send .pause
        t=32.40 command pause (touch)
        t=32.40 speak "You're resting. Tap Start for the next set." (status)
        > frames still air_squat 30 frames @0.1 (3.0s)
        > send .resume
        t=35.40 command resume (touch)
        t=35.40 speak "Tap Start to begin the set." (status)
        > frames still air_squat 530 frames @0.1 (53.0s)
        t=87.50 speak "Rest is up. Tap Start for set 2."
        > send .start
        t=88.40 command start (touch)
        t=88.40 state exercising air_squat set=2 reps=0 counting=true
        t=88.40 control exercise air_squat epoch=4
        t=88.40 clearFeedback
        t=88.40 control counting true
        t=88.40 speak "Set 2 of 2. Go."
        t=88.40 tip show squat.reminder.brace "Brace your core." (reminder)
        > frames demo air_squat 146 frames @0.1 (14.6s)
        t=88.50 control sessionPhase exercising
        t=88.50 input startPosition false
        t=88.60 input startPosition true
        t=90.30 input startPosition false
        t=91.40 tip clear
        t=91.90 input startPosition true
        t=91.90 input rep epoch=4 sides=left,right
        t=92.00 state exercising air_squat set=2 reps=1 counting=true
        t=94.00 input startPosition false
        t=95.60 input startPosition true
        t=95.60 input rep epoch=4 sides=left,right
        t=95.70 state exercising air_squat set=2 reps=2 counting=true
        t=97.70 input startPosition false
        t=99.30 input startPosition true
        t=99.30 input rep epoch=4 sides=left,right
        t=99.40 state exercising air_squat set=2 reps=3 counting=true
        t=101.40 input startPosition false
        t=103.00 input startPosition true
        t=103.00 input rep epoch=4 sides=left,right
        t=103.00 state exerciseComplete air_squat set=2 reps=0 counting=false
        t=103.00 control counting false
        t=103.00 control exercise air_squat epoch=5
        t=103.00 clearFeedback
        t=103.00 speak "Set 2 done, 4 reps. Air Squat complete. Tap Another Round or End Workout."
        > send .endWorkout
        t=103.00 command endWorkout (touch)
        t=103.00 state ended air_squat set=2 reps=0 counting=false
        t=103.00 clearFeedback
        t=103.00 speak "Workout ended. Nice work." (interrupts)
        t=103.00 listen disable paused
        t=103.00 camera idle
        t=103.00 control resetTracking
        t=103.00 input startPosition false
        t=103.00 input framing lost
        > view saves history (phase ended)
        t=103.00 history save record plan=none planID=none id=workout entries=1
        t=103.00 history save entry air_squat "Air Squat" outcome=none sets=[4 reps, 4 reps]
        t=103.00 reminders workoutSaved
        > view close
        t=103.00 listen disable paused
        t=103.00 control resetTracking
        t=103.00 input framing lost
        t=103.00 speech stopAll
        t=103.00 audio deactivate
        """

    static let coachMuted = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=true mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak muted "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        > send .readGuideAloud
        t=10.00 speak "This is the air squat. Face the phone and step back until your whole body is in view. Stand tall with your feet about shoulder-width apart. Push your hips back and bend your knees until your thighs are about level with the floor, keeping your knees over your toes. Then drive through your heels to stand all the way up. That's one rep." (status, interrupts)
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak muted "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak muted "Set 1 of 1. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 109 frames @0.1 (10.9s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.30 state exercising air_squat set=1 reps=2 counting=true
        t=20.30 input startPosition false
        t=21.90 input startPosition true
        t=21.90 input rep epoch=2 sides=left,right
        t=21.90 state exerciseComplete air_squat set=1 reps=0 counting=false
        t=21.90 control counting false
        t=21.90 control exercise air_squat epoch=3
        t=21.90 clearFeedback
        t=21.90 speak muted "Set 1 done, 3 reps. Air Squat complete. Say another round or end workout."
        > send .endWorkout
        t=21.90 command endWorkout (touch)
        t=21.90 state ended air_squat set=1 reps=0 counting=false
        t=21.90 clearFeedback
        t=21.90 speak muted "Workout ended. Nice work." (interrupts)
        t=21.90 listen disable paused
        t=21.90 camera idle
        t=21.90 control resetTracking
        t=21.90 input startPosition false
        t=21.90 input framing lost
        > view saves history (phase ended)
        t=21.90 history save record plan=none planID=none id=workout entries=1
        t=21.90 history save entry air_squat "Air Squat" outcome=none sets=[3 reps]
        t=21.90 reminders workoutSaved
        > view close
        t=21.90 listen disable paused
        t=21.90 control resetTracking
        t=21.90 input framing lost
        t=21.90 speech stopAll
        t=21.90 audio deactivate
        """

    static let voiceRepeat = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > voice heard "repeat that" -> repeatLast
        t=10.00 command repeatLast (voice "repeat that")
        t=10.00 repeat last="Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > voice heard "start" -> start
        t=11.00 command start (voice "start")
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 72 frames @0.1 (7.2s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.20 state exercising air_squat set=1 reps=2 counting=true
        > voice heard "repeat that" -> repeatLast
        t=18.20 command repeatLast (voice "repeat that")
        t=18.20 repeat last="Set 1 of 1. Go."
        > voice heard "mute coach" -> muteCoach
        t=18.20 command muteCoach (voice "mute coach")
        t=18.20 mute coach=true mic=false
        t=18.20 speech stopAll
        > voice heard "repeat that" -> repeatLast
        t=18.20 command repeatLast (voice "repeat that")
        t=18.20 repeat muted
        > voice heard "unmute coach" -> unmuteCoach
        t=18.20 command unmuteCoach (voice "unmute coach")
        t=18.20 mute coach=false mic=false
        t=18.20 speak "Coach voice on." (status)
        > voice heard "repeat that" -> repeatLast
        t=18.20 command repeatLast (voice "repeat that")
        t=18.20 repeat last="Set 1 of 1. Go."
        > frames demo air_squat 35 frames @0.1 (3.5s)
        t=20.10 input startPosition false
        t=21.70 input startPosition true
        t=21.70 input rep epoch=2 sides=left,right
        t=21.70 state exerciseComplete air_squat set=1 reps=0 counting=false
        t=21.70 control counting false
        t=21.70 control exercise air_squat epoch=3
        t=21.70 clearFeedback
        t=21.70 speak "Set 1 done, 3 reps. Air Squat complete. Say another round or end workout."
        > send .endWorkout
        t=21.70 command endWorkout (touch)
        t=21.70 state ended air_squat set=1 reps=0 counting=false
        t=21.70 clearFeedback
        t=21.70 speak "Workout ended. Nice work." (interrupts)
        t=21.70 listen disable paused
        t=21.70 camera idle
        t=21.70 control resetTracking
        t=21.70 input startPosition false
        t=21.70 input framing lost
        > view saves history (phase ended)
        t=21.70 history save record plan=none planID=none id=workout entries=1
        t=21.70 history save entry air_squat "Air Squat" outcome=none sets=[3 reps]
        t=21.70 reminders workoutSaved
        > view close
        t=21.70 listen disable paused
        t=21.70 control resetTracking
        t=21.70 input framing lost
        t=21.70 speech stopAll
        t=21.70 audio deactivate
        """

    static let framingLost = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 72 frames @0.1 (7.2s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.20 state exercising air_squat set=1 reps=2 counting=true
        > frames empty 20 frames @0.1 (2.0s)
        t=18.30 input framing reliable guidance=stepIntoView
        t=18.30 input startPosition false
        t=18.60 input framing unreliable guidance=stepIntoView
        t=18.70 state exercising air_squat set=1 reps=2 counting=false
        t=19.50 speak "I can't see you. Step into view, facing the phone."
        > frames still air_squat 20 frames @0.1 (2.0s)
        t=20.30 input framing lost
        t=20.40 input startPosition true
        t=21.00 input framing reliable
        t=21.10 state exercising air_squat set=1 reps=2 counting=true
        > frames demo air_squat 72 frames @0.1 (7.2s)
        t=24.10 input startPosition false
        t=25.70 input startPosition true
        t=25.70 input rep epoch=2 sides=left,right
        t=25.80 state exercising air_squat set=1 reps=3 counting=true
        t=27.80 input startPosition false
        t=29.40 input startPosition true
        t=29.40 input rep epoch=2 sides=left,right
        t=29.40 state exerciseComplete air_squat set=1 reps=0 counting=false
        t=29.40 control counting false
        t=29.40 control exercise air_squat epoch=3
        t=29.40 clearFeedback
        t=29.40 speak "Set 1 done, 4 reps. Air Squat complete. Say another round or end workout."
        > send .endWorkout
        t=29.40 command endWorkout (touch)
        t=29.40 state ended air_squat set=1 reps=0 counting=false
        t=29.40 clearFeedback
        t=29.40 speak "Workout ended. Nice work." (interrupts)
        t=29.40 listen disable paused
        t=29.40 camera idle
        t=29.40 control resetTracking
        t=29.40 input startPosition false
        t=29.40 input framing lost
        > view saves history (phase ended)
        t=29.40 history save record plan=none planID=none id=workout entries=1
        t=29.40 history save entry air_squat "Air Squat" outcome=none sets=[4 reps]
        t=29.40 reminders workoutSaved
        > view close
        t=29.40 listen disable paused
        t=29.40 control resetTracking
        t=29.40 input framing lost
        t=29.40 speech stopAll
        t=29.40 audio deactivate
        """

    static let correctiveTips = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Say start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 2. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames squat-without-standing motion from 0.0s 95 frames @0.1 (9.5s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.80 input startPosition false
        t=14.00 tip clear
        t=16.90 input startPosition true
        t=16.90 input rep epoch=2 sides=left,right
        t=17.00 state exercising air_squat set=1 reps=1 counting=true
        t=18.90 input startPosition false
        > speech activity true
        t=20.50 listen coachSpeaking true
        > frames squat-without-standing motion from 9.5s 20 frames @0.1 (2.0s)
        > speech activity false
        t=22.50 listen coachSpeaking false
        > frames squat-without-standing motion from 11.5s 200 frames @0.1 (20.0s)
        t=22.60 tip show squat.stand_up "Stand all the way up." (corrective)
        t=22.60 speak "Stand all the way up."
        t=23.00 input startPosition true
        t=23.00 input rep epoch=2 sides=left,right
        t=23.10 state exercising air_squat set=1 reps=2 counting=true
        t=25.00 input startPosition false
        t=25.60 tip clear
        t=29.10 input startPosition true
        t=29.10 input rep epoch=2 sides=left,right
        t=29.20 state exercising air_squat set=1 reps=3 counting=true
        t=31.10 input startPosition false
        t=33.40 tip show squat.stand_up "Stand all the way up." (corrective)
        t=33.40 speak "Stand all the way up."
        t=35.20 input startPosition true
        t=35.20 input rep epoch=2 sides=left,right
        t=35.30 state exercising air_squat set=1 reps=4 counting=true
        t=36.40 tip clear
        t=37.20 input startPosition false
        t=41.30 input startPosition true
        t=41.30 input rep epoch=2 sides=left,right
        t=41.40 state exercising air_squat set=1 reps=5 counting=true
        > send .endWorkout
        t=42.50 command endWorkout (touch)
        t=42.50 state ended air_squat set=2 reps=0 counting=false
        t=42.50 control counting false
        t=42.50 clearFeedback
        t=42.50 speak "Workout ended. Nice work." (interrupts)
        t=42.50 listen disable paused
        t=42.50 camera idle
        t=42.50 control resetTracking
        t=42.50 input startPosition false
        t=42.50 input framing lost
        > view saves history (phase ended)
        t=42.50 history save record plan=none planID=none id=workout entries=1
        t=42.50 history save entry air_squat "Air Squat" outcome=none sets=[5 reps]
        t=42.50 reminders workoutSaved
        > view close
        t=42.50 listen disable paused
        t=42.50 control resetTracking
        t=42.50 input framing lost
        t=42.50 speech stopAll
        t=42.50 audio deactivate
        """

    static let timedHold = """
        t=10.00 state framing shoulder_press set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 state ready shoulder_press set=1 reps=0 counting=false
        t=10.00 control exercise shoulder_press epoch=1
        t=10.00 speak "Workout coach ready. Dumbbell shoulder press, two sets of 8 to 10. Face the phone and hold a dumbbell in each hand just above your shoulders. Tap Start when you're ready."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > send .start
        t=10.00 command start (touch)
        t=10.00 state exercising shoulder_press set=1 reps=0 counting=false
        t=10.00 control exercise shoulder_press epoch=2
        t=10.00 clearFeedback
        t=10.00 speak "Set 1 of 2. Hold for 15 seconds. Go."
        t=10.00 tip show press.reminder.brace "Brace your core." (reminder)
        > wait 15.0s
        t=13.00 tip clear
        t=20.00 speak "5 seconds." (status)
        t=25.00 state resting shoulder_press set=2 reps=0 counting=false
        t=25.00 control exercise shoulder_press epoch=3
        t=25.00 clearFeedback
        t=25.00 speak "Set 1 done, 15 seconds. Rest up. I'll tell you when it's time for set 2."
        > wait 91.0s
        t=115.00 speak "Rest is up. Say start for set 2."
        > send .start
        t=116.00 command start (touch)
        t=116.00 state exercising shoulder_press set=2 reps=0 counting=false
        t=116.00 control exercise shoulder_press epoch=4
        t=116.00 clearFeedback
        t=116.00 speak "Set 2 of 2. Hold for 15 seconds. Go."
        t=116.00 tip show press.reminder.breathe "Breathe out as you press." (reminder)
        > wait 15.1s
        t=119.00 tip clear
        t=126.00 speak "5 seconds." (status)
        t=131.00 state exerciseComplete shoulder_press set=2 reps=0 counting=false
        t=131.00 control exercise shoulder_press epoch=5
        t=131.00 clearFeedback
        t=131.00 speak "Set 2 done, 15 seconds. Dumbbell Shoulder Press complete. Say another round or end workout."
        > send .endWorkout
        t=131.10 command endWorkout (touch)
        t=131.10 state ended shoulder_press set=2 reps=0 counting=false
        t=131.10 clearFeedback
        t=131.10 speak "Workout ended. Nice work." (interrupts)
        t=131.10 listen disable paused
        t=131.10 camera idle
        t=131.10 control resetTracking
        > view saves history (phase ended)
        t=131.10 history save record plan=none planID=none id=workout entries=1
        t=131.10 history save entry shoulder_press "Dumbbell Shoulder Press" outcome=none sets=[15 s, 15 s]
        t=131.10 reminders workoutSaved
        > view close
        t=131.10 listen disable paused
        t=131.10 control resetTracking
        t=131.10 speech stopAll
        t=131.10 audio deactivate
        """

    static let todayBonusTaken = """
        t=10.00 state framing wall_push_up item=1 set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise wall_push_up epoch=1
        t=10.00 speak "Workout coach ready. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready wall_push_up item=1 set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Hands on the wall, arms straight to start, or say start."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising wall_push_up item=1 set=1 reps=0 counting=true
        t=11.00 control exercise wall_push_up epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 71 frames @0.1 (7.1s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.50 input startPosition false
        t=14.00 tip clear
        t=14.40 input startPosition true
        t=14.40 input rep epoch=2 sides=left,right
        t=14.50 state exercising wall_push_up item=1 set=1 reps=1 counting=true
        t=16.20 input startPosition false
        t=18.10 input startPosition true
        t=18.10 input rep epoch=2 sides=left,right
        t=18.10 state exerciseComplete wall_push_up item=1 set=1 reps=0 counting=false
        t=18.10 control counting false
        t=18.10 control exercise wall_push_up epoch=3
        t=18.10 clearFeedback
        t=18.10 speak "Set 1 done, 2 reps. Wall Push-Up complete. Today's Session complete. Say another round or end workout."
        t=18.10 card effort amount=2 reps sets=1 preselected=none
        t=18.10 listen acceptsEffort true
        > voice effort easy
        t=18.10 card none
        t=18.10 listen acceptsEffort false
        t=18.10 bonusOffer amount=1 rep
        t=18.10 listen acceptsBonus true
        > voice bonus accept
        t=18.10 bonusOffer none
        t=18.10 listen acceptsBonus false
        t=18.10 input startBonus amount=1
        t=18.10 state ready wall_push_up item=2 set=1 reps=0 counting=false
        t=18.10 speak "One more. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=18.20 control sessionPhase ready
        t=18.20 input startPosition false
        t=18.30 input startPosition true
        > send .start
        t=19.10 command start (touch)
        t=19.10 state exercising wall_push_up item=2 set=1 reps=0 counting=true
        t=19.10 control exercise wall_push_up epoch=4
        t=19.10 clearFeedback
        t=19.10 control counting true
        t=19.10 speak "Set 1 of 1. Go."
        t=19.10 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 34 frames @0.1 (3.4s)
        t=19.20 control sessionPhase exercising
        t=19.20 input startPosition false
        t=19.30 input startPosition true
        t=20.60 input startPosition false
        t=22.10 tip clear
        t=22.50 input startPosition true
        t=22.50 input rep epoch=4 sides=left,right
        t=22.50 state exerciseComplete wall_push_up item=2 set=1 reps=0 counting=false
        t=22.50 control counting false
        t=22.50 control exercise wall_push_up epoch=5
        t=22.50 clearFeedback
        t=22.50 speak "Set 1 done, 1 rep. Wall Push-Up complete. Today's Session complete. Say another round or end workout."
        t=22.50 card bonus amount=1 rep sets=1 preselected=none
        t=22.50 listen acceptsEffort true
        > tap rate okay
        t=22.50 card none
        t=22.50 listen acceptsEffort false
        t=22.50 listen acceptsBonus false
        t=22.50 evidence adaptive push/push.wall_push_up prescribed=2 reps confirmed=2 reps (trackerAccepted) sets=[2 reps] tracker=tracked:2 reps effort=easy tooHard=false bonus={offered=1 rep accepted=true completed=1 rep effort=okay} completion=completed prescription=originalPrescription calibration=none workout=this
        > send .endWorkout
        t=22.50 command endWorkout (touch)
        t=22.50 state ended wall_push_up item=2 set=1 reps=0 counting=false
        t=22.50 clearFeedback
        t=22.50 speak "Workout ended. Nice work." (interrupts)
        t=22.50 listen disable paused
        t=22.50 camera idle
        t=22.50 control resetTracking
        t=22.50 input startPosition false
        t=22.50 input framing lost
        > view saves history (phase ended)
        t=22.50 history save record plan="Today's Session" planID=todaySessionPlan id=workout entries=2
        t=22.50 history save entry wall_push_up "Wall Push-Up" outcome=completed sets=[2 reps]
        t=22.50 history save entry wall_push_up "Bonus: Wall Push-Up" outcome=completed sets=[1 rep]
        t=22.50 reminders workoutSaved
        > view close
        t=22.50 listen disable paused
        t=22.50 control resetTracking
        t=22.50 input framing lost
        t=22.50 speech stopAll
        t=22.50 audio deactivate
        """

    static let todayBonusDeclined = """
        t=10.00 state framing wall_push_up item=1 set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise wall_push_up epoch=1
        t=10.00 speak "Workout coach ready. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready wall_push_up item=1 set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Hands on the wall, arms straight to start, or say start."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising wall_push_up item=1 set=1 reps=0 counting=true
        t=11.00 control exercise wall_push_up epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 71 frames @0.1 (7.1s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.50 input startPosition false
        t=14.00 tip clear
        t=14.40 input startPosition true
        t=14.40 input rep epoch=2 sides=left,right
        t=14.50 state exercising wall_push_up item=1 set=1 reps=1 counting=true
        t=16.20 input startPosition false
        t=18.10 input startPosition true
        t=18.10 input rep epoch=2 sides=left,right
        t=18.10 state exerciseComplete wall_push_up item=1 set=1 reps=0 counting=false
        t=18.10 control counting false
        t=18.10 control exercise wall_push_up epoch=3
        t=18.10 clearFeedback
        t=18.10 speak "Set 1 done, 2 reps. Wall Push-Up complete. Today's Session complete. Say another round or end workout."
        t=18.10 card effort amount=2 reps sets=1 preselected=none
        t=18.10 listen acceptsEffort true
        > tap rate easy
        t=18.10 card none
        t=18.10 listen acceptsEffort false
        t=18.10 bonusOffer amount=1 rep
        t=18.10 listen acceptsBonus true
        > tap decline bonus
        t=18.10 bonusOffer none
        t=18.10 listen acceptsBonus false
        t=18.10 evidence adaptive push/push.wall_push_up prescribed=2 reps confirmed=2 reps (trackerAccepted) sets=[2 reps] tracker=tracked:2 reps effort=easy tooHard=false bonus={offered=1 rep accepted=false completed=none effort=none} completion=completed prescription=originalPrescription calibration=none workout=this
        > send .endWorkout
        t=18.10 command endWorkout (touch)
        t=18.10 state ended wall_push_up item=1 set=1 reps=0 counting=false
        t=18.10 clearFeedback
        t=18.10 speak "Workout ended. Nice work." (interrupts)
        t=18.10 listen disable paused
        t=18.10 camera idle
        t=18.10 control resetTracking
        t=18.10 input startPosition false
        t=18.10 input framing lost
        > view saves history (phase ended)
        t=18.10 history save record plan="Today's Session" planID=todaySessionPlan id=workout entries=1
        t=18.10 history save entry wall_push_up "Wall Push-Up" outcome=completed sets=[2 reps]
        t=18.10 reminders workoutSaved
        > view close
        t=18.10 listen disable paused
        t=18.10 control resetTracking
        t=18.10 input framing lost
        t=18.10 speech stopAll
        t=18.10 audio deactivate
        """

    static let todayTooHard = """
        t=10.00 state framing wall_push_up item=1 set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise wall_push_up epoch=1
        t=10.00 speak "Workout coach ready. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready wall_push_up item=1 set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Hands on the wall, arms straight to start, or say start."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising wall_push_up item=1 set=1 reps=0 counting=true
        t=11.00 control exercise wall_push_up epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 34 frames @0.1 (3.4s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.50 input startPosition false
        t=14.00 tip clear
        t=14.40 input startPosition true
        t=14.40 input rep epoch=2 sides=left,right
        t=14.40 state exercising wall_push_up item=1 set=1 reps=1 counting=true
        > send .tooHard
        t=14.40 command tooHard (touch)
        t=14.40 adaptive easierSwapOption -> wall_push_up reducedRange=true target=push.wall_push_up.shallow 2 reps
        t=14.40 tooHardOffer easier="Shallow Wall Push-Up" 2 reps
        > tap take easier version
        t=14.40 adaptive issueEasierSwap wall_push_up reducedRange=true target=push.wall_push_up.shallow 2 reps
        t=14.40 tooHardOffer none
        t=14.40 command nextSet (touch)
        t=14.40 state exerciseComplete wall_push_up item=1 set=1 reps=0 counting=false
        t=14.40 control counting false
        t=14.40 control exercise wall_push_up epoch=3
        t=14.40 clearFeedback
        t=14.40 speak "Set 1 done, 1 rep. Wall Push-Up complete. Today's Session complete. Say another round or end workout."
        t=14.40 card effort amount=1 rep sets=1 preselected=tooHard
        t=14.40 listen acceptsEffort true
        t=14.40 input startEasierSwap wall_push_up reducedRange=true amount=2
        t=14.40 state ready wall_push_up item=2 set=1 reps=0 counting=false
        t=14.40 speak "Let's try an easier version. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > frames still wall_push_up(reduced) 10 frames @0.1 (1.0s)
        t=14.50 control sessionPhase ready
        t=14.50 input startPosition false
        t=14.60 input startPosition true
        > send .start
        t=15.40 command start (touch)
        t=15.40 state exercising wall_push_up item=2 set=1 reps=0 counting=true
        t=15.40 control exercise wall_push_up(reduced) epoch=4
        t=15.40 clearFeedback
        t=15.40 control counting true
        t=15.40 speak "Set 1 of 1. Go."
        t=15.40 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        t=15.40 card none
        t=15.40 listen acceptsEffort false
        t=15.40 evidence adaptive push/push.wall_push_up prescribed=5 reps confirmed=1 rep (trackerAccepted) sets=[1 rep] tracker=tracked:1 rep effort=tooHard tooHard=true bonus={none} completion=switchedToEasier prescription=originalPrescription calibration=none workout=this
        > frames demo wall_push_up(reduced) 70 frames @0.1 (7.0s)
        t=15.50 control sessionPhase exercising
        t=15.50 input startPosition false
        t=15.60 input startPosition true
        t=17.00 input startPosition false
        t=18.40 tip clear
        t=18.70 input startPosition true
        t=18.70 input rep epoch=4 sides=left,right
        t=18.80 state exercising wall_push_up item=2 set=1 reps=1 counting=true
        t=20.80 input startPosition false
        t=22.40 input startPosition true
        t=22.40 input rep epoch=4 sides=left,right
        t=22.40 state exerciseComplete wall_push_up item=2 set=1 reps=0 counting=false
        t=22.40 control counting false
        t=22.40 control exercise wall_push_up(reduced) epoch=5
        t=22.40 clearFeedback
        t=22.40 speak "Set 1 done, 2 reps. Shallow Wall Push-Up complete. Today's Session complete. Say another round or end workout."
        t=22.40 card effort amount=2 reps sets=1 preselected=none
        t=22.40 listen acceptsEffort true
        > tap rate okay
        t=22.40 card none
        t=22.40 listen acceptsEffort false
        t=22.40 evidence adaptive push/push.wall_push_up.shallow prescribed=2 reps confirmed=2 reps (trackerAccepted) sets=[2 reps] tracker=tracked:2 reps effort=okay tooHard=false bonus={none} completion=completed prescription=easierPrescription calibration=none workout=this
        > send .endWorkout
        t=22.40 command endWorkout (touch)
        t=22.40 state ended wall_push_up item=2 set=1 reps=0 counting=false
        t=22.40 clearFeedback
        t=22.40 speak "Workout ended. Nice work." (interrupts)
        t=22.40 listen disable paused
        t=22.40 camera idle
        t=22.40 control resetTracking
        t=22.40 input startPosition false
        t=22.40 input framing lost
        > view saves history (phase ended)
        t=22.40 history save record plan="Today's Session" planID=todaySessionPlan id=workout entries=2
        t=22.40 history save entry wall_push_up "Wall Push-Up" outcome=completed sets=[1 rep]
        t=22.40 history save entry wall_push_up "Easier: Shallow Wall Push-Up" outcome=completed sets=[2 reps]
        t=22.40 reminders workoutSaved
        > view close
        t=22.40 listen disable paused
        t=22.40 control resetTracking
        t=22.40 input framing lost
        t=22.40 speech stopAll
        t=22.40 audio deactivate
        """

    static let calibrationProbe = """
        t=10.00 state framing wall_push_up item=1 set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise wall_push_up epoch=1
        t=10.00 speak "Workout coach ready. Wall push-ups, two sets of 6 to 10. Stand an arm's length from a wall, side-on to the phone, and place your hands on the wall at shoulder height."
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        t=10.00 speak "Say “what can I say” anytime to see voice commands." (status)
        > frames still wall_push_up 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready wall_push_up item=1 set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Hands on the wall, arms straight to start, or say start."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising wall_push_up item=1 set=1 reps=0 counting=true
        t=11.00 control exercise wall_push_up epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 1. Go."
        t=11.00 tip show wallpush.reminder.hands "Hands at shoulder height." (reminder)
        > frames demo wall_push_up 71 frames @0.1 (7.1s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.50 input startPosition false
        t=14.00 tip clear
        t=14.40 input startPosition true
        t=14.40 input rep epoch=2 sides=left,right
        t=14.50 state exercising wall_push_up item=1 set=1 reps=1 counting=true
        t=16.20 input startPosition false
        t=18.10 input startPosition true
        t=18.10 input rep epoch=2 sides=left,right
        t=18.10 state exerciseComplete wall_push_up item=1 set=1 reps=0 counting=false
        t=18.10 control counting false
        t=18.10 control exercise wall_push_up epoch=3
        t=18.10 clearFeedback
        t=18.10 speak "Set 1 done, 2 reps. Wall Push-Up complete. Finding your starting point complete. Say another round or end workout."
        t=18.10 card effort amount=2 reps sets=1 preselected=none
        t=18.10 listen acceptsEffort true
        > tap rate okay
        t=18.10 card none
        t=18.10 listen acceptsEffort false
        t=18.10 probe store evidence calibration push/push.wall_push_up prescribed=2 reps confirmed=2 reps (trackerAccepted) sets=[2 reps] tracker=tracked:2 reps effort=okay tooHard=false bonus={none} completion=completed prescription=none calibration=expectedCalibration workout=this
        t=18.10 probe result effort=okay confirmed=2 reps
        > view close
        t=18.10 history not saved record plan="Finding your starting point" planID=none id=workout entries=1
        t=18.10 history not saved entry wall_push_up "Wall Push-Up" outcome=completed sets=[2 reps]
        t=18.10 listen disable paused
        t=18.10 camera idle
        t=18.10 control resetTracking
        t=18.10 input startPosition false
        t=18.10 input framing lost
        t=18.10 speech stopAll
        t=18.10 audio deactivate
        """

    static let saveOnce = """
        t=10.00 state framing air_squat set=1 reps=0 counting=false
        t=10.00 camera idle
        t=10.00 mic off
        t=10.00 mute coach=false mic=false
        > appear (app active)
        t=10.00 audio configureBaseCategory
        t=10.00 camera starting
        t=10.00 control resetTracking
        t=10.00 listen enable
        > camera running
        t=10.00 camera running
        t=10.00 input opened
        t=10.00 control exercise air_squat epoch=1
        t=10.00 speak "Workout coach ready. Air squats, two sets of 15. Face the phone and step back until your whole body is in view, feet about shoulder-width apart."
        > frames still air_squat 10 frames @0.1 (1.0s)
        t=10.10 input framing lost
        t=10.20 input startPosition true
        t=10.70 input framing reliable
        t=10.70 state ready air_squat set=1 reps=0 counting=false
        t=10.70 speak "Looks good. Tap Start when you're ready."
        t=10.80 control sessionPhase ready
        > send .start
        t=11.00 command start (touch)
        t=11.00 state exercising air_squat set=1 reps=0 counting=true
        t=11.00 control exercise air_squat epoch=2
        t=11.00 clearFeedback
        t=11.00 control counting true
        t=11.00 speak "Set 1 of 2. Go."
        t=11.00 tip show squat.reminder.heels "Weight in your heels." (reminder)
        > frames demo air_squat 109 frames @0.1 (10.9s)
        t=11.10 control sessionPhase exercising
        t=11.10 input startPosition false
        t=11.20 input startPosition true
        t=12.90 input startPosition false
        t=14.00 tip clear
        t=14.50 input startPosition true
        t=14.50 input rep epoch=2 sides=left,right
        t=14.60 state exercising air_squat set=1 reps=1 counting=true
        t=16.60 input startPosition false
        t=18.20 input startPosition true
        t=18.20 input rep epoch=2 sides=left,right
        t=18.30 state exercising air_squat set=1 reps=2 counting=true
        t=20.30 input startPosition false
        t=21.90 input startPosition true
        t=21.90 input rep epoch=2 sides=left,right
        t=21.90 state resting air_squat set=2 reps=0 counting=false
        t=21.90 control counting false
        t=21.90 control exercise air_squat epoch=3
        t=21.90 clearFeedback
        t=21.90 speak "Set 1 done, 3 reps. Rest up. I'll tell you when it's time for set 2."
        > frames still air_squat 20 frames @0.1 (2.0s)
        t=22.00 control sessionPhase resting
        t=22.00 input startPosition false
        t=22.10 input startPosition true
        > send .endWorkout
        t=23.90 command endWorkout (touch)
        t=23.90 state ended air_squat set=2 reps=0 counting=false
        t=23.90 clearFeedback
        t=23.90 speak "Workout ended. Nice work." (interrupts)
        t=23.90 listen disable paused
        t=23.90 camera idle
        t=23.90 control resetTracking
        t=23.90 input startPosition false
        t=23.90 input framing lost
        > view saves history (phase ended)
        t=23.90 history save record plan=none planID=none id=workout entries=1
        t=23.90 history save entry air_squat "Air Squat" outcome=none sets=[3 reps]
        t=23.90 reminders workoutSaved
        > view close
        t=23.90 listen disable paused
        t=23.90 control resetTracking
        t=23.90 input framing lost
        t=23.90 speech stopAll
        t=23.90 audio deactivate
        """
}
