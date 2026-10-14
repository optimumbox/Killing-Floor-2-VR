# Uploading the KF2VR Steam Workshop item

Instructions for an agent (or a person) updating the public **KF2VR** Workshop item,
[3817663661](https://steamcommunity.com/sharedfiles/filedetails/?id=3817663661), with SteamCMD.
The item holds the whole mod: VR players run it through the Play in VR / Play normally
choice, and desktop players joining a KF2-VR server download it automatically.

Everything the item needs is in this repository:

| Path | What it is |
| --- | --- |
| `tools/workshop/stage_workshop.py` | Builds the upload folder from a release, writes the SteamCMD item file and `upload.cmd` |
| `tools/workshop/item/workshop_item.vdf` | Item template: id, visibility, title and the **Workshop page description** |
| `tools/workshop/item/play.py`, `Play.cmd` | The Play in VR / Play normally window that Steam starts |
| `tools/workshop/item/preview.jpg` | Workshop preview image |
| `tools/workshop/KF2VR-Setup.ps1` | Shipped as `Setup KF2VR.cmd`; sets Killing Floor 2's Steam Launch Options |
| `docs/workshop/setup-guide.png` | The picture at the top of the Workshop page (linked by URL from the description) |

## Rules

- **Never type, store or ask for the Steam password or Steam Guard code.** SteamCMD prompts
  for them itself; the human types them in a visible terminal.
- **Keep `"publishedfileid" "3817663661"`.** Without it SteamCMD creates a brand-new item.
- **Keep `"visibility" "0"` (public).** Dedicated servers download Workshop items with an
  anonymous login, which cannot see unlisted, friends-only or private items. Desktop
  players would then fail to join.
- **The description and change note cannot contain `"` or `\`.** SteamCMD's KeyValues
  parser has no escapes and fails with a KeyValues error. BBCode (`[b]`, `[h1]`, `[url=...]`,
  `[img]`, `[list][*]`) is fine.
- **Upload only a verified release.** Every Steam player who joins a KF2-VR server gets the
  item's packages, so they must match what hosts run. The staging script refuses a release
  whose files don't match its `app/release.json`.
- **Release the Epic pack together with the item.** Epic players copy the same three
  packages by hand (`KF2VR.u`, `KF2VRNet.u`, `KF2VRHands.upk`); after an item update,
  publish a matching Epic pack (see `tools/epic-pack/`).

## One-time setup

1. **Upload permission.** The item is owned by the Steam account `optimumbox`. Another
   account can update it only after optimumbox adds it as a contributor: on the item page,
   Owner Controls > **Add/Remove Contributors** (the two accounts must be Steam friends).
   If SteamCMD reports `Access Denied` or `Failed to update workshop item`, this is
   missing. Stop and tell the human; there is no workaround.
2. **SteamCMD.** Download `https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip`
   from Valve, extract it to its own folder (e.g. `C:\steamcmd`) and run `steamcmd.exe +quit`
   once so it updates itself.
3. **Python 3.9+.** Any Python works; a release also bundles one at `app\runtime\python.exe`.

## Each update

1. **Build and test the release** the usual way, then extract the playable
   `KF2VR-Multiplayer-*.zip` (or use a live install). The folder must contain `app\`,
   `READ ME FIRST.txt` and `Start KF2-VR.cmd`.

2. **Update the Workshop page text if needed** in `tools/workshop/item/workshop_item.vdf`
   (the `"description"` value; one line). The upload replaces the page's description with
   this text, so edits made on the website are lost unless they are copied here first.
   The description's top image is
   `https://raw.githubusercontent.com/optimumbox/Killing-Floor-2-VR/vr-dlss-fixes/docs/workshop/setup-guide.png`;
   if that branch or file moves, update the URL. Leave the `__CONTENT__`, `__PREVIEW__`
   and `__CHANGENOTE__` placeholders alone.

3. **Stage** (from the repository root):

   ```bat
   python tools\workshop\stage_workshop.py --release "C:\path\to\extracted-release" --changenote "Short summary of what changed."
   ```

   It verifies the release, rebuilds `build\workshop-stage\Upload` from scratch, and writes
   `build\workshop-stage\workshop_item.vdf` and `build\workshop-stage\upload.cmd`. Expected
   output: `release verified (N files); staged M files, about 465 MB`, then the four BrewedPC
   packages with their SHA-256. Note those hashes for step 6.

   The staged layout must be:

   ```text
   Upload\Play.cmd, Setup KF2VR.cmd, KF2VR-Setup.ps1
   Upload\BrewedPC\Script\KF2VR.u, KF2VRNet.u, KF2VRNetClient.u
   Upload\BrewedPC\Packages\KF2VRHands.upk
   Upload\KF2VR\app\...   (no settings.json, sessions, logs or __pycache__)
   Upload\KF2VR\play.py, READ ME FIRST.txt, Start KF2-VR.cmd
   ```

   KF2 installs only an item's `BrewedPC` for desktop players; `play.py` copies those four
   packages into the launcher's `app\Packages` for VR players. Don't move them.

4. **Close Steam** fully (Steam > Exit) if it is signed in to the same account.

5. **Upload.** Open a terminal the human can see and type into, and run:

   ```bat
   build\workshop-stage\upload.cmd "C:\steamcmd\steamcmd.exe"
   ```

   The human enters the Steam account name, password and Steam Guard code. The upload sends
   only changed chunks, so later updates are quicker than the first. Success ends with lines
   like `Uploading content...`, `Committing update...` and `Success.`

   | Message | Cause |
   | --- | --- |
   | `Access Denied` / `Failed to update workshop item` | This account isn't the owner or a contributor (setup step 1) |
   | KeyValues or parse error | A `"` or `\` in the description or change note |
   | `Invalid Password` / `Two-factor code mismatch` | Login; the human retries |
   | `Limit Exceeded` / `Rate Limit Exceeded` | Steam throttling; wait and retry |
   | Content or preview file not found | The staging folder was moved or deleted after staging |

6. **Verify the public download** the way a dedicated server sees it:

   ```bat
   C:\steamcmd\steamcmd.exe +login anonymous +workshop_download_item 232090 3817663661 validate +quit
   ```

   It must end with `Success. Downloaded item 3817663661 to "...\steamapps\workshop\content\232090\3817663661"`.
   Check that the SHA-256 of the four files under that folder's `BrewedPC` matches step 3.
   If it fails with an error about the item's state, delete `C:\steamcmd\steamapps\workshop`
   (a stale download record) and run it again. `Access Denied` here means the item isn't public.

7. **Check the page** at <https://steamcommunity.com/sharedfiles/filedetails/?id=3817663661>:
   the Change Notes tab shows the new note and the description renders.

8. **Clean up.** Delete `build\workshop-stage` (about 465 MB); it's regenerated next time.

## After the upload

- Steam updates subscribers automatically; some players have to press Play once before
  Steam downloads the update.
- Hosts that start from the Workshop copy get the new packages on their next launch.
  Players on an older GitHub ZIP can't join until they update.
- Publish the matching GitHub release and Epic pack, and say in the release notes that the
  Workshop item carries the same packages.
