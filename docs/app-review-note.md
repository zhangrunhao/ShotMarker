# App Review Note

ShotMarker does not require sign-in, a demo account, or a server connection. All training records and generated videos stay on the user's devices.

Core functionality requires a physical iPhone with a paired Apple Watch and the ShotMarker Watch app installed. The iPhone training list is empty until a Watch training session is completed and synced.

Suggested review flow:

1. Launch ShotMarker on the iPhone once so WatchConnectivity can activate.
2. Launch ShotMarker on the paired Apple Watch.
3. If prompted, allow Health/Workout access. The Watch app only writes a generic workout session so watchOS keeps the training screen active during a session; it does not read Health data.
4. On Apple Watch, long-press the main circular button to start training.
5. While training is active, double-tap the same button one or more times to record markers.
6. Long-press the button again to end the training session. The session will sync to the iPhone automatically.
7. On iPhone, open the synced training record from the "训练记录" list.
8. Choose one or more videos from Photos. For the most reliable test, record a short iPhone video while the Watch training session is active so the video creation time overlaps the marker times.
9. Allow Photos access when prompted. ShotMarker reads the selected video's creation time and media content, generates highlight clips around the marker times, and saves the resulting video back to Photos.

Notes:

- The selected video must include a valid creation time. Videos without creation metadata are rejected because ShotMarker aligns markers to the video timeline using absolute timestamps.
- Photos add permission is used only to save the generated highlight video.
- If Watch sync takes a moment, leave the iPhone app open and reopen the Watch app; pending Watch sessions are retained locally and retried.
- The diagnostics/log export button in the iPhone toolbar is included to help troubleshoot local Watch sync or video generation issues during testing.
