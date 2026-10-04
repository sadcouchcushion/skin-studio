# Skin Studio for Marvel Rivals: install and usage guide

Skin Studio lets you recolour Marvel Rivals skins on your PC and see the result on your hero in game. It has two halves that work together:

- **The Skin Studio app** (on your PC). This is where skins are opened, edited, saved as designs and built into mods.
- **The in-game panel** (`!!SkinLive`). Press **F8** in a match and a Skin Studio panel opens over the game. You can recolour your hero right there, and the changes show on the live character within a second or so.

The in-game panel is drawn by the app on your PC. **The panel only works while Skin Studio is running on the same PC**, so open the app before you launch the game.

---

## Requirements

- Windows 10 or 11.
- Marvel Rivals on Steam or Epic (any install folder).
- The **.NET 8 Runtime** from Microsoft, for material colour edits.
- About 2 GB free on `C:` for the texture cache.
- Optional: **Project Galacta** (Nexus mod 12806) to swap a freshly built mod into a running game without restarting.
- Optional: **Atelier** for the 3D preview, and Blender for 3D painting.

---

## Install

**Close Marvel Rivals before installing anything.**

Skin Studio comes as **two files**, both on the Nexus page's **Files** tab, and you need both:

- **Main file: the in-game mod** (`SkinStudio-InGame` zip): the three `!!SkinLive_9999999_P` files that go in the game's `~mods` folder.
- **Second file: the Skin Studio app** (`SkinStudio-App` zip): the app on your PC. The panel is drawn by this app, so without it F8 does nothing.

**1. Install the in-game mod (main file)**

- **With Vortex:** click **Mod Manager Download** on the main file and deploy. Vortex puts the three `!!SkinLive_9999999_P` files (`.pak`, `.ucas`, `.utoc`) in a subfolder of `~mods`. From there another UI mod (Project Galacta, for one) can load ahead of it and F8 does nothing, so Skin Studio copies them to the top of `~mods` when you open the app with the game closed. Open the app once after any Vortex install or update, before you play.
- **By hand:** open the game's `~mods` folder (on Steam: right-click Marvel Rivals > Manage > Browse local files, then open `MarvelGame\Marvel\Content\Paks\~mods`; create `~mods` if it does not exist). Unzip the `SkinStudio-InGame` download into it, so the three `!!SkinLive_9999999_P` files sit directly in `~mods`.

**2. Install the app (second file)**

1. On the Files tab, click **Manual Download** on the `SkinStudio-App` file. Don't install it with Vortex; it is a program, not a game mod.
2. Unzip it anywhere **outside** the game folder, for example your Downloads folder. Do not put it in `~mods`.
3. Double-click `SkinStudio\Start Skin Studio.bat` once. It sets Skin Studio up in your user folder (`%LOCALAPPDATA%\SkinStudio`), finds the game in your Steam or Epic library, adds **Skin Studio** to the Start menu and opens the app. You can delete the unzipped folder afterwards.
4. From then on, open Skin Studio from the Start menu. **Open it before you launch the game**, every time you want the F8 panel.

The app's work files, cache and built mods are kept in `%LOCALAPPDATA%\SkinStudio`, not in `~mods`, so the game never tries to load them.

**Using Vortex for other mods?** A Vortex redeploy can sweep loose files out of `~mods`, so after any deploy check the three `!!SkinLive` files are still there.

**Updating:** close Skin Studio and the game. Replace the three `!!SkinLive` files with the new main file, and run `Start Skin Studio.bat` from the new app file. Your designs and cache are kept.

**Upgrading from 1.0?** Version 1.0 was one download with a `SkinStudio` folder inside `~mods`. Delete that `~mods\SkinStudio` folder (your designs live in `%LOCALAPPDATA%\SkinStudio` and are kept), then follow the steps above.

The first time a skin is opened, the app extracts its textures from the game, which can take up to a minute. After that it is cached.

### Optional: the panel without the app window

When the app opens, it also starts a small background helper with no window. While the helper is running, the in-game panel keeps working even if you close the app window: the helper starts the panel's drawing process whenever Rivals runs, and that process closes with the game.

The helper only runs after the app has been opened since your last Windows sign-in. To have it start with Windows, put a shortcut in your Startup folder (`Win+R`, type `shell:startup`) whose target is:

```
powershell -WindowStyle Hidden -File "%LOCALAPPDATA%\SkinStudio\ingame\helper.ps1"
```

Delete the shortcut to undo it. If you're unsure, just open Skin Studio before every game.

---

## Using the in-game panel

1. Open **Skin Studio** from the Start menu.
2. Launch Marvel Rivals and go into a match. **The Practice Range is the best place.** The panel needs a hero on the field; it does nothing in the lobby, hero select or the gallery.
3. Press **F8**. The Skin Studio panel opens and the mouse switches over to it.
4. Press **F8** again to close it. The mouse goes back to the camera.

> **F8 is Skin Studio. F7 belongs to Project Galacta.** If you have Galacta installed, F7 reloads your mods; it does not open this panel.

### Live preview

The panel's home screen has a **Live preview** switch at the top. It is the same switch as the **LIVE PREVIEW** button in the app: flip either one and the other follows within a second or two.

- **On:** your edits and saved designs are painted onto your hero live.
- **Off:** F8 shows a single screen with **Turn on live preview**. Turning it off puts the game's own skin back on your hero straight away.

### Editing a part

- The home screen lists the parts of the hero you are playing. Tap one to open it.
- A strip of part thumbnails runs across the top, so you can switch part without going back.
- The tabs **Colour**, **Shine** and **Glow** pick which kind of map you are editing.
- **Layers** are shown as tabs (for example `1 Tint`, `2 Hue shift`, `+ Add`) and apply left to right. The selected layer's controls sit right under the tabs. Use **Move left**, **Move right** and **Delete layer** to rearrange them.
- Layer types include Tint, Paint, Hue shift, Gradient tint, Gradient paint, Grayscale, Invert, Colour family and Image, with sliders such as Strength, Saturation and Lightness, and a **Protect skin tones** option.
- **Colour history** holds the last 16 colours you used, in two rows. Tapping one reuses it and moves it to the front.
- On a part you haven't edited yet, pick a colour from the history, or start with **Tint** if you have no history yet.
- **Fine-tune** opens the full colour picker.
- **Undo** steps back. **Clear this map - back to vanilla** and **Clear every edit on this hero** reset things.
- **Text size** (Small, Medium, Large, Huge) is at the bottom of the home screen if the panel is hard to read.

Each change repaints the hero in under a second for most textures.

### Designs

Your edits are saved as **designs** in the app (`%LOCALAPPDATA%\SkinStudio\designs\`). The panel's **Designs** screen lists the saved designs for the hero you are playing and has a **New design** button.

When you spawn as a hero with live preview on, Skin Studio automatically puts the newest design made for **that skin** on your hero a second or two later. No key is needed. A skin with no design stays as it is. The first time on a skin, Skin Studio has to prepare it first, which can take up to a minute.

### Building a real mod

Live preview is only visible on your own screen and only while Skin Studio runs. To make a permanent mod that other people can use, build it:

- In the app: name the mod and click **BUILD MOD**. The mod is installed into `~mods` and a zip is saved in `%LOCALAPPDATA%\SkinStudio\output\` and your Downloads folder.
- In game: the panel's **Build mod** button does the same.

**Without Project Galacta**, a new build loads at your next game launch. If the game is using the old copy, it goes in when you quit Rivals. Live preview keeps your edits on the hero until then.

**With Project Galacta** installed and the game running, Skin Studio swaps the new build in for you using Galacta's F7 (it presses F7 for you). Then enter or leave a match or the Practice Range to see it. If the game doesn't respond within a few seconds, the panel asks you to press F7 yourself. A mod that wasn't in `~mods` when you logged in usually waits for your next launch, because Galacta only reloads the mods it found at login.

---

## Troubleshooting

**F8 does nothing.**
1. Is Skin Studio open? The panel is drawn by the app on your PC (the second file on the Files tab), so with nothing running F8 shows nothing. Open the app, then press F8 again; presses made before the app was running are thrown away.
2. Are you in a match with a hero on the field? The lobby has no hero to edit.
3. Are the three `!!SkinLive_9999999_P` files still in `~mods`? A Vortex redeploy can remove them. Are they directly in `~mods`, not only in a Vortex subfolder? Close the game and open Skin Studio, and it copies them up.
4. Did a game patch just come out? See below.

**The game crashes at launch after a patch.** This mod includes a small Blueprint, which a game update can break. Remove the three `!!SkinLive_9999999_P` files from `~mods` and wait for an updated version. Skins you built with Skin Studio are texture-only and are not affected. Also check other mods: older Blueprint, VFX and per-map mods are a common crash cause after an update.

**The mouse still turns the camera.** Tap the Windows key once, then click the panel.

**My built mod doesn't show.** Mods load when the game starts. Restart Rivals, or use Project Galacta (see Building a real mod).

**Material colours don't change.** Install the .NET 8 Runtime from Microsoft, then restart Skin Studio.

**Turning things off.** Switch live preview off, in the app or the panel. Your hero goes back to the game's own skin.

---

## Uninstall

1. Close Skin Studio and Marvel Rivals.
2. From `~mods`, delete the three `!!SkinLive_9999999_P` files, and also remove the mod in Vortex if you installed it that way (Skin Studio may have copied the files to the top of `~mods`, which Vortex does not remove).
3. Delete `%LOCALAPPDATA%\SkinStudio`. Copy its `designs` folder somewhere first if you want to keep your designs.
4. Delete **Skin Studio** from the Start menu, and the Startup shortcut if you made one.

---

## What's been tested

Seen working in game: F8 opens and closes the panel in a match, the mouse works in the panel, colour and material edits repaint the hero live, saved designs go back on automatically, the 16-colour Colour history and the Tint start work, the Live preview switch inside the panel works, and Skin Studio presses Galacta's F7 for you after a build.
