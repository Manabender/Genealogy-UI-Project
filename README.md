# Genealogy-UI-Project
A Bizhawk Lua script for improving Fire Emblem: Genealogy of the Holy War by adding modern UI elements.

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
- \[First time setup only\] Bind 2nd player A button to something. Anything. As long as you can press it.
- Load the script. Tools > Lua Console, Open "Genealogy UI Project.lua".
- The script should start running. It can be stopped and started by double-clicking it in the Lua Console. To confirm, place the in-game cursor on any unit, and its combat stats should appear at the bottom of the screen.
- At any time, you can press the B button to toggle all script displays on or off.

# Currently known issues (As of Sept 25, 2023)
- The way in which unit data is interpreted varies by unit. Some units may need to be interpreted in a way I don't know about yet. All units in the prologue and chapter 1 appear to be interpreted correctly. Some later units may not be.
- Second-generation player units almost definitely will not be read correctly. I know they will be different. I do not yet know how.
- The combat forecast may sometimes show the target as being able to counterattack even when they cannot. Specifically, I know that a silenced enemy will show as countering even though they are silenced and thus cannot.
- The stats overlay may sometimes show at times when it probably shouldn't. This is why I provide a global toggle button to make it go away when it is unwelcome. Eventually, I aim for this global toggle to be unnecessary; the overlay when show when it is welcome and hide when it is not.

# When reporting issues
Issue reports are welcome and encouraged. When reporting an issue, it is tremendously helpful to attach a savestate at the place where the issue occurs. Savestates can be found at \[Your Bizhawk folder\]/SNES/State.
