import Foundation

/// Frozen speech and microphone callback ordering for `SpeechActivityTraceTests`.
enum SpeechActivityGoldenTraces {
    static let shortTimedHold = """
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
        t=10.00 listen coachSpeaking true
        t=10.00 speak "Workout coach ready. Dumbbell shoulder press, two sets of 8 to 10. Face the phone and hold a dumbbell in each hand just above your shoulders. Tap Start when you're ready."
        t=10.00 listen coachSpeaking false
        > voice status listening
        t=10.00 mic listening
        t=10.00 input voiceControl true
        > send .start
        t=10.00 command start (touch)
        t=10.00 state exercising shoulder_press set=1 reps=0 counting=false
        t=10.00 control exercise shoulder_press epoch=2
        t=10.00 clearFeedback
        t=10.00 listen coachSpeaking true
        t=10.00 speak "Set 1 of 1. Hold for 1 second. Go."
        t=10.00 tip show press.reminder.brace "Brace your core." (reminder)
        t=10.00 listen coachSpeaking false
        > advance 1.1s
        t=11.00 state exerciseComplete shoulder_press set=1 reps=0 counting=false
        t=11.00 control exercise shoulder_press epoch=3
        t=11.00 clearFeedback
        t=11.00 tip clear
        t=11.00 listen coachSpeaking true
        t=11.00 speak "Set 1 done, 1 second. Dumbbell Shoulder Press complete. Say another round or end workout."
        t=11.10 listen coachSpeaking false
        > send .endWorkout
        t=11.10 command endWorkout (touch)
        t=11.10 state ended shoulder_press set=1 reps=0 counting=false
        t=11.10 clearFeedback
        t=11.10 listen coachSpeaking true
        t=11.10 speak "Workout ended. Nice work." (interrupts)
        t=11.10 listen disable paused
        t=11.10 camera idle
        t=11.10 control resetTracking
        t=11.10 listen coachSpeaking false
        """

    static let controllerAudioResponseToCoachSpeakingState = """
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio active true
        t=0.00 recognizer start
        > test supplies coach-speaking state: greeting begins
        t=0.00 recognizer stop
        t=0.00 audio active false
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=43 names=allowBluetoothA2DP,defaultToSpeaker,duckOthers,mixWithOthers
        t=0.00 audio active true
        > test supplies coach-speaking state: greeting ends
        t=0.00 audio active false notifyOthersOnDeactivation
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio active true
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio active true
        t=0.00 recognizer start
        t=0.00 recognizer restartTask
        t=0.00 heard "start"
        t=0.00 command start
        > test supplies coach-speaking state: response begins
        t=0.00 recognizer stop
        t=0.00 audio active false
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=43 names=allowBluetoothA2DP,defaultToSpeaker,duckOthers,mixWithOthers
        t=0.00 audio active true
        > test supplies coach-speaking state: response ends
        t=0.00 audio active false notifyOthersOnDeactivation
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio active true
        t=0.00 audio category AVAudioSessionCategoryPlayAndRecord mode=AVAudioSessionModeDefault optionsRaw=41 names=allowBluetoothA2DP,defaultToSpeaker,mixWithOthers
        t=0.00 audio active true
        t=0.00 recognizer start
        """
}
