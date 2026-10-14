KF2-VR - pack for Epic Games players (desktop)
==============================================

Steam players get the mod automatically from the Steam Workshop when they join
a KF2-VR server. The Epic copy of Killing Floor 2 cannot use the Workshop, so
copy these files in once by hand. This lets you join KF2-VR servers on desktop
(mouse and keyboard or controller); VR play needs the full KF2-VR release.

The files must match the host's KF2-VR version. Hosts that use the KF2VR Steam
Workshop item update automatically, so always use the newest pack from
https://github.com/optimumbox/Killing-Floor-2-VR/releases and copy it again
(overwrite) after each update. If joining fails with a package or version
mismatch, your pack is out of date.

This pack: 2026-10-14 (same game packages as the KF2VR Workshop item).

Windows (Epic Games Launcher)
-----------------------------
1. Close Killing Floor 2.
2. Extract this ZIP (right-click it, Extract All).
3. Double-click "Install KF2VR for Epic.bat" in the extracted folder.
   It finds your Epic copy of Killing Floor 2 and copies the KF2VR folder
   into its KFGame\BrewedPC folder. If Windows asks for administrator
   permission, click Yes (the default Epic folder is in Program Files).
   If Windows shows "Windows protected your PC", click More info, then
   Run anyway.
4. Start Killing Floor 2 and join the server from the server browser.

If it cannot find the game, it asks you to drag your KillingFloor2 folder
into its window. To do it by hand instead, copy the "KF2VR" folder into
  <Epic install folder>\KillingFloor2\KFGame\BrewedPC\
(by default C:\Program Files\Epic Games\KillingFloor2\KFGame\BrewedPC\)
so you end up with ...\KFGame\BrewedPC\KF2VR\KF2VR.u and two more files.

Steam Deck / Linux (Heroic Games Launcher)
------------------------------------------
1. Close Killing Floor 2.
2. Extract this pack, open a terminal in the extracted KF2VR-Epic-Pack folder and run:

     B=$(find ~ -maxdepth 6 -type d -path '*KillingFloor2/KFGame/BrewedPC' 2>/dev/null | head -1) && mkdir -p "$B/KF2VR" && cp -v KF2VR/* "$B/KF2VR/"

   It prints one "->" line per file. If it prints nothing, find your
   KillingFloor2/KFGame/BrewedPC folder by hand and copy the KF2VR folder into it.
3. Start Killing Floor 2 and join the server.

Removing it
-----------
Delete the KF2VR folder inside KFGame\BrewedPC. Nothing else is changed.

Notes
-----
- Only join KF2-VR servers with these files; ordinary servers do not use them.
- Unofficial fan-made mod by Kvasir94 and optimumbox, not affiliated with
  Tripwire Interactive or Epic Games. https://github.com/optimumbox/Killing-Floor-2-VR
