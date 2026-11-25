# 1. Add your first CusOba character

**Goal:** Make a character called **Copper Scout**, see it in the lobby, and use one of its abilities. You do not need Blender, an AI tool, or a controller. These file steps are for Windows.

## Before you start

- **Point** means move the mouse until the arrow on the screen is over the thing named in the instructions. **Click** means press and release the left mouse button once. **Right-click** uses the right button. **Double-click** means click the left button twice quickly.
- **Press Ctrl+C** means hold down the key labeled **Ctrl**, tap **C**, then let go of both. It copies what you selected. **Ctrl+V** pastes it. **Ctrl+S** saves your work. **Enter** confirms a name or starts a new line in a text editor.
- Open CusOba and stop at the main screen with **Host game** and **Join game**. If you haven't opened it before, follow [Open CusOba](host-or-join.md#open-cusoba) first.

## A. Copy a character that already works

1. On the main screen, click **Open characters folder**. A Windows File Explorer window opens. You should see folders named `gizmo`, `ember`, and others.
2. Click the `gizmo` folder **once** to select it. Press **Ctrl+C**. Do not go inside it yet.
3. Press **Ctrl+V** in the same window. You should have both `gizmo` and a new folder named something like `gizmo - Copy`.
4. Right-click **the copy**, choose **Rename**, type `copper_scout`, and press **Enter**. Leave the original `gizmo` alone. Double-click `copper_scout` to open your copy.
5. In File Explorer, click **View > Show > File name extensions** if the `.json` ending isn't visible. The file inside the copy should be named exactly `character.json`. The `.json` file is a text recipe for the character: it stores the display name, stats, and abilities.

**If you downloaded a character instead:** If it came as a `.zip`, right-click it, choose **Extract All...**, then **Extract**. Open the extracted folder until you find the folder that directly contains `character.json`. Copy **that whole folder**, including its pictures and other files, into the folder CusOba opens with **Open characters folder**. Use a unique folder name, such as `copper_scout`. Skip B and go to C. Do not copy the `.zip` or an extra wrapper folder.

## B. Give the copy a new name

1. Inside `copper_scout`, right-click `character.json`. Choose **Open with > Notepad**. If needed, use **Choose another app**, select **Notepad**, and choose **Just once**. This changes the contents of the file, not its filename.
2. Near the top, find this line:

   ```json
   "name": "Gizmo",
   ```

3. Click on that line. Replace **only** the word `Gizmo` with `Copper Scout`. Leave both pairs of quotation marks and the comma. The line should look like this:

   ```json
   "name": "Copper Scout",
   ```

4. Press **Ctrl+S**. Close Notepad. You now have a separate character with Gizmo's abilities. Keep the rest unchanged until you've tested it.

Your folders should look like this:

```text
CusOba\
  characters\
    gizmo\
      character.json
    copper_scout\
      character.json
```

## C. Check that it works in a match

1. Click the CusOba window to go back to it. On the main screen, click **Reload content**. Look for **Reloaded.** If the game shows **Content problems**, check whether the message names your folder.
2. Click **Practice (offline, add bots in the lobby)**. In the lobby (the screen before a match), click the menu next to **Map** and choose **Training Arena**.
3. Click the **Copper Scout** character card. Check that the row marked **(you)** now says **Copper Scout**. You can play alone for this test.
4. Click **START MATCH**. Point at an empty patch of ground and right-click. Your character should move there.
5. At the bottom of the screen, click the small **+** above the first ability, **Q**. This spends your starting skill point so you can use the ability. Right-click the ground to get near a training dummy, point at the dummy, then hold the **Q** key and let go to fire. The dummy should show damage if the shot hits. These are the default controls; use the key printed under the ability if it was changed in **Settings**.
6. To finish testing, press **Esc** (usually the upper-left key) and click **Leave to main menu**.

## D. Make it yours, one change at a time

- **Change health:** In your copy of `character.json`, find `"max_hp": 600,` and try `"max_hp": 650,`. Keep the number outside quotation marks. Save, reload, and test again. Change one thing at a time so it's easy to tell what broke.
- **Add art:** A PNG is a picture file. Put a character picture named exactly `sprite.png` inside `copper_scout`, next to `character.json`. The Gizmo copy has no `sprite` setting, so CusOba picks up `sprite.png` automatically. Use a transparent background so it doesn't walk around inside a rectangle. For the picture shown in character select and on the match interface, add a separate `portrait.png` next to it. Save any changes and click **Reload content** again.
- **Change abilities or use animations:** After the simple version works, see the [character modding reference](../characters/MODDING.md) for what the different settings do. For art made in Blender, use [Guide 2](blender-character-prompts.md).

## E. Let friends use it

- **You're hosting:** Reload your content from the main menu **before** clicking **Host game**. Friends get the host's character files automatically when they join. They don't have to install your character separately.
- **You're a guest:** In the online lobby, click **Suggest a character...**. In the folder picker, open `copper_scout` and confirm that folder (not the whole `characters` folder or the `character.json` file). The host opens **Character suggestions**, picks your entry, and clicks **Approve**. It then appears for everyone in the lobby. Approval is only for that hosted session; it doesn't save a copy on the host's computer. Suggestions accept JSON, PNG and WebP files, up to 64 files and 8 MiB total. For a permanent copy, the host can install your folder before hosting.

## If something doesn't work

| What you see | What to do |
|---|---|
| No Copper Scout card | Check that `character.json` sits directly inside `copper_scout`, not inside a second folder. Make sure the filename isn't `character.json.txt`, save in Notepad, and click **Reload content**. Choose **Training Arena**: both ARAM modes only offer two random characters. |
| **Content problems** after editing | Read the filename and line number shown. Check the quotes and commas on that line and the one just above it. If needed, copy a fresh `character.json` from `gizmo` over the broken file **in your copy** and redo the name change. |
| The character looks like a colored circle | That's normal without art. If you added art, check for `sprite.png` (not `sprite.png.png`), then reload. `portrait.png` alone doesn't change how the character looks on the map. |
| The ability button is dark | Spend a skill point with the **+** above it. If it worked once, wait a few seconds for the ability to become ready again. |
