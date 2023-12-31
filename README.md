# Genealogy-UI-Project
A Bizhawk Lua script for improving Fire Emblem: Genealogy of the Holy War by adding modern UI elements.

# What this script does
The Genealogy UI Project was created in order to add modern information display improvements to a game that predates them. These improvements are heavily inspired by Fire Emblem Engage, and should be a very welcome aid to anyone looking to explore Fire Emblem history after being introduced to the series by recent entries. Specifically, this script implements the following:

- On-hover unit stat display. Just by placing your cursor on a unit, you can see it's Attack, Hit, Avoid, Defense, Movement, equipped weapon, and much more -- just like in Engage.
- Improved combat forecast. The concept of a combat forecast was still in its infancy in this game's day. Whenever you go to attack a unit, you'll see a much better forecast with more information and calculated values -- very similar to Engage.
- Health bars. Every unit's relative health is shown by a small green bar at their feet.
- Enemy threat ranges. You can easily see what squares are safe and what squares are not, just like in modern Fire Emblem. Individual enemy units can have their ranges highlighted. Also included is a "maximal" mode, which shows what spaces the enemy would threaten if they were not blocked by your units; very useful if you are considering a tactical retreat.

![Demonstration of on-hover unit stat display and health bars](/genealogy%20overlay.png)
![Demonstration of improved combat forecast](/genealogy%20forecast.png)
![Demonstration of threat display](/genealogy%20threat.png)

This script was specifically designed to only include quality-of-life improvements. No part of it alters the gameplay or the game's natural difficulty in any way. No information is displayed that can't already be seen elsewhere in the game (or, in some cases, calculated yourself). Game memory is only ever read, never written to.

# What you will need
- Bizhawk v2.9.1. Other versions may or may not work, even later versions.
- A legally-obtained ROM file of Fire Emblem - Seisen no Keifu. (The author does not condone piracy. Please obtain your copy legally.)
- The "Project Naga" fan translation patch, Beta 7 version. (The script was developed and tested with a patched ROM. Unpatched or differently-patched ROMs may or may not work.)

# How to use
- \[First time setup only\] Patch your ROM with the fan translation patch. Instructions for this can be found in the same place where the patch can be found. 
- \[First time setup only\] Download the "Genealogy UI Project.lua" file. It can be saved anywhere, but it is recommended to save it to \[Your Bizhawk folder\]/Lua.
- Open Bizhawk.
- \[First time setup only\] BSNES core must be used. Config > Preferred Cores > SNES > BSNES.
- Load the game ROM.
- \[First time setup only\] Enable 2nd player controller. SNES > Controller Configuration > set Port 2 to Gamepad.
- \[First time setup only\] Bind 2nd player's A, B, X, Y, L, and R buttons to something. Anything. As long as you can press them.
- Load the script. Tools > Lua Console, Open "Genealogy UI Project.lua".
- The script should start running. It can be stopped and started by double-clicking it in the Lua Console. To confirm, place the in-game cursor on any unit, and its combat stats should appear at the bottom of the screen.
- At any time, you can press player 2 A button to toggle all script displays on or off.
- You can press player 2 B button to place a mark on the cursor's square. Press player 2 B on a marked square to remove the mark. Press and hold player 2 X for one second to remove all marks.
- You can press player 2 L button to cycle threat display; between "highlighted units only", "all enemy units", and "no threat display".
- You can press player 2 R button to toggle threat calculation mode; defaults to "normal", but when switched to "maximal", all blue and green units will be ignored and treated as though they do not block enemy movement.
- You can press player 2 Y button to highlight an enemy unit in the threat display. Their threat range will appear red, and the tile they are on will appear yellow to denote that this specific unit is highlighted. Press player 2 Y on a highlighted unit to remove its highlight.

# Currently known issues (As of Oct 19, 2023)
- The way in which unit data is interpreted varies by unit. Some units may need to be interpreted in a way I don't know about yet. All units in the prologue and chapter 1 appear to be interpreted correctly. Some later units may not be.
- Second-generation player units almost definitely will not be read correctly. I know they will be different. I do not yet know how.
- The combat forecast may sometimes show the target as being able to counterattack even when they cannot. Specifically, I know that a silenced enemy will show as countering even though they are silenced and thus cannot.
- Healing caused by Nosferatu is not reflected in the combat forecast. (This will be fixed at some point)
- The stats overlay may sometimes show at times when it probably shouldn't. This is why I provide a global toggle button to make it go away when it is unwelcome. Eventually, I aim for this global toggle to be unnecessary; the overlay will show when it is welcome and hide when it is not.
- If there is a player unit in a castle, their health bar may display at the castle entrance on the map. This is a low-priority issue, but a known one nonetheless.
- The "Unit Window" option in-game must be set to ON. If off, no part of the script will work. This issue will not be fixed; the unit window is required to determine the color of a unit. (Note that the option is on by default, so this hardly matters.)
- The "Terrain Window" option in-game must be set to ON. If off, the stats overlay and health bars will only show when the cursor is on a unit. This issue will not intentionally be fixed, but might be resolved as a side-effect of a future update. (Note that the option is on by default, so this hardly matters.)
- Threat ranges may not display correctly until at least one unit from each enemy faction has had the cursor placed on them long enough for the game to display their HP bubble.

# When reporting issues
Issue reports are welcome and encouraged. When reporting an issue, it is tremendously helpful to attach a savestate at the place where the issue occurs. Savestates can be found at \[Your Bizhawk folder\]/SNES/State.
