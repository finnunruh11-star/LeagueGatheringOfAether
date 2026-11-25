# 3. Host or join a CusOba game

**Goal:** Get everyone into the same lobby and start a match. The **host** opens the room. A **guest** joins it. The **lobby** is the screen where you pick characters before the match. These steps use a Windows PC, mouse, and keyboard. CusOba does not have built-in controller controls for this workflow.

## Open CusOba

1. **Mouse basics:** Slide the mouse to move the arrow on the screen. **Click** means press and release the left button once. **Double-click** means click twice quickly. **Right-click** means press and release the right button.
2. **If someone gave you a game download:** If it ends in `.zip`, right-click it in File Explorer and choose **Extract All...**, then **Extract**. Open the extracted folder and double-click the CusOba application (the `.exe` file). Don't run it from inside the ZIP or move the `.exe` away from its other folders.
3. **If you have the project folder instead:** Open Godot 4.7 (the project was tested with 4.7.1). In the Godot Project Manager, look for **CusOba**. If it isn't listed, click **Import**, browse to the CusOba folder, select `project.godot`, and open the project. In the editor, click the **Run Project** triangle near the upper right or press the **F5** key in the top row of the keyboard.
4. You're ready when you see **CusOba**, **Host game**, and **Join game**. Everyone should use the **same copy or release** of the game.

## A. Choose how you're connecting

| Where are you playing? | What to do |
|---|---|
| Same home internet connection | Connect to the same Wi-Fi or the same router. The guest uses the host's local IP shown in the lobby. Guest Wi-Fi often blocks devices from talking to each other; use the main home network. |
| Different homes | Use [Tailscale](https://tailscale.com/download) to connect the PCs to the same private network. The guest then uses the host's **Tailscale IPv4** address, not the host's home Wi-Fi address. See the steps below. |
| Just you, testing controls | Click **Practice (offline, add bots in the lobby)** instead. No internet setup or second player is needed. |

**For different homes with Tailscale:**

1. Each player opens the download page above, picks **Windows**, opens the downloaded installer, and follows it until Tailscale is installed.
2. The host signs in to Tailscale. From Tailscale's admin console, the host opens **Users** and uses **Invite users** to invite their friends to the host's private network (called a **tailnet**). Friends accept the invite and sign in to the Windows app using their invited account. Installing the app alone isn't enough if everyone is on a different tailnet.
3. With Tailscale connected, the host opens the Tailscale app or the **Machines** page in its admin console and finds their own PC's Tailscale IPv4 address. It normally starts with `100.`. Share that address and the game port privately with your friends. Keep Tailscale connected while you play.

## B. Host: open the lobby

1. On the CusOba main screen, click inside the box next to **Your name**. Hold **Ctrl**, tap **A**, then let go of both. This selects the text already there. Type the name you want friends to see.
2. Check the **Port** box next to **Host game**. A port is a separate number that tells CusOba where to connect. Leave it at `7777` unless you've agreed on a different number. If you need to change it, click inside it, use **Ctrl+A**, type the number, and press **Enter**.
3. Click **Host game**. If Windows Firewall asks about CusOba or Godot on your trusted home network, allow it for **Private networks**; don't turn off the firewall or open access for public Wi-Fi. Leave CusOba open in the **Lobby**.
4. At the top left, find **Hosting on port ... Friends join with your IP:**. An IP is the address the other PC will connect to. On home Wi-Fi, look for the address for your home connection (often `192.168...` or `10...`). If several addresses are listed and you don't know which to use, open Windows **Settings > Network & internet**, select your connected **Wi-Fi** or **Ethernet** connection, and look in its properties for **IPv4 address**. For Tailscale, use the address from step A instead. Send the address and port to your friends as **two separate values**.
5. Wait for each guest's name to appear on the left. Don't click **START MATCH** until everyone is in the lobby; new guests can't join a match already in progress.

## C. Guest: join the lobby

1. Open CusOba. Set **Your name** on the main screen. To replace text, click in the box, hold **Ctrl** and tap **A**, let go, then type.
2. Click inside **Host IP**, select the existing text the same way, and type the address your host gave you. Type the dots too. **Example:** `192.168.1.23` goes in **Host IP**; don't type `:7777`, a web link, or your own IP. The example is not an address to use unless it is the one the host actually gave you.
3. Look at **Port** next to **Host game**, even though you are joining. This box is shared by both buttons. Set it to the host's port, normally `7777`, and press **Enter** if you changed it.
4. Click **Join game** once. Wait while it connects and downloads the host's characters. You should reach the **Lobby**, see **Connected. Waiting for the host to start...**, and see your name marked **(you)**.

## D. Pick characters and start

1. **Host:** Click the dropdown (the small menu that opens when clicked) next to **Map**. For a gentle first game, choose **Training Arena** and skip bots until everyone can move. Choose **Bridge** for a one-lane match with full champion selection. **ARAM (Standard)** and **ARAM Mayhem** each offer two random champion cards per player; only Mayhem has augments.
2. **Everyone:** Click a character card in the middle of the lobby. Look at the row marked **(you)** to check your choice. When hosting, if you just clicked a bot's name to edit it, click your own name before choosing your own character.
3. **Everyone:** Click **Team** next to your name to switch between the blue and red sides. Use the colored stripe beside each name to see who's on which side. To play together on **Bridge**, pick the same color. The host can add opponents with **+ Blue bot** or **+ Red bot**, on the other color. A **bot** is a computer-controlled player. Choose **Brick** next to a bot for the easiest difficulty.
4. Leave **Spells** and **Runes** at their defaults for your first match. When everyone is ready, the **host** clicks **START MATCH** at the bottom left. Guests don't have this button.

## Your first minute in the match

1. **Move:** Point to nearby open ground and right-click. Your character walks there. If you lose track of your character in default controls, hold **Space** (the long key at the bottom of the keyboard) to center the view.
2. **Attack:** Point at a training dummy or an enemy, then right-click. In normal matches, work with your team to destroy the enemy **Nexus**, the large structure at the back of their base.
3. **Try an ability:** At the bottom of the screen, click the **+** above the first ability to unlock it. Point at a dummy or enemy. Hold **Q** to see where you're aiming, then let go of **Q** to use it. If the controls were changed, use the key printed below that ability instead.
4. **Leave or return to the lobby:** Press **Esc**, usually at the top left of the keyboard. Click **Resume** to keep playing or **Leave to main menu** to disconnect. The host can choose **End match - back to lobby** to bring everyone back to the lobby. The menu does not pause the match. If **Esc** closes the shop or cancels aiming first, press it again.

## If joining fails

| What you see | What to do |
|---|---|
| **Could not connect** or stuck on **Connecting** | Check that the host is still in the lobby, that the dots and digits in **Host IP** match what they sent, and that your **Port** matches theirs. |
| Same home network, but still can't connect | Check that both PCs are on the same home router and neither is on guest Wi-Fi. Check that Windows Firewall allows the game on the host's trusted private network. Don't disable the firewall. |
| Different homes, but still can't connect | Make sure both PCs are connected to the same Tailscale network and that the guest entered the host's **Tailscale** IP, not a home IP like `192.168...`. If your network or firewall is managed by someone else, ask them for help with access. |
| **Version mismatch** | Get the same release from the same place as the host and launch that copy. |
| **A match is in progress** | Wait for the host to return to the lobby, then click **Join game** again. |
| **Could not host on port 7777** | Close the other CusOba window if you're already hosting in it. Or set a different port, such as `7778`, and tell all guests to use the new number. |
| **Disconnected from host** | Ask if the host closed CusOba or lost their connection. Have them open a lobby again, then rejoin. |
