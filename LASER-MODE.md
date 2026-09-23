# Laser Drive (PC)

Choose **Laser Drive** on startup. The original four-lane Arcade mode remains
available. The **Modes** button is always present; during mouse-captured play,
press Esc or controller Start to pause first, then select Game Mode Select.
Switching mode cancels an active import and leaves an online lobby.

Laser Drive has its own `laser-songs` directory, preferences, controller profiles
and score file under the game's user data directory. Existing Arcade songs and
scores are not migrated or modified. Import YouTube/SoundCloud links, osu!mania
files or PNG song cards from the Laser Library. These are generated adaptations,
not official arcade charts. Exported PNG cards retain six-button/laser data.
Laser Drive is currently a single-player mode; Arcade retains its multiplayer.

## Playing

- Four BT buttons: D F J K. Two FX buttons: C M.
- Left/right lasers: mouse X/Y; keyboard alternatives Q/W and O/P.
- Enter / mapped Start starts a song and pauses/resumes gameplay.
- Hit chip notes at the line. Hold long BT/FX notes for their ticks.
- Turn in the laser's direction to track it; make a quick matching turn for slams.
- Scoring uses Critical / Near / Error, hold/laser ticks, chain and a normalized
  10,000,000 maximum. Finish with at least 70% gauge to clear.
- Music FX, highway tilt, note speed, timing offset, volumes and visual effects
  are adjustable. Laser judgment windows and generation are this game's rules;
  exact parity with every Sound Voltex arcade revision is not claimed.

## Home / DIY controllers

Choose Controllers, select a device/profile, then choose the firmware's input
mode: HID keyboard/mouse or joystick. Remap BT/FX/Start buttons and both axes.
Select wrapping encoder mode for axes that jump from maximum back to minimum;
non-wrapping mode for finite analog axes; rate mode for spring-centered sticks.
Tune inversion, sensitivity and jitter threshold while watching the live input
readout. Controller Start pauses. In Track Select, right knob changes the song
and left knob changes difficulty. Reconnect a selected device through this menu
if Windows enumerates it with a new device ID.

This supports the standard keyboard, mouse and joystick events Windows/Godot
exposes. Hardware has not been physically tested here. Vendor-specific raw USB
protocols, cabinet lighting and force feedback are not implemented. A controller
which does not expose standard input requires compatible firmware or its driver.
No universal compatibility claim is made for arbitrary DIY firmware.

All visual assets and animations are original. This is an independent arcade-
inspired mode, not a Konami product; it includes no Sound Voltex assets or music.
