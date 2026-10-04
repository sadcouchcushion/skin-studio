# The in-game editor (v2) - build sheet

v1 was one key: F6 repainted the hero from the PNGs Skin Studio had written.
v2 is a panel you can actually edit in, opened with **F7**, with the full
desktop feature set - layer stacks, all ten modes, gradients, protect-skin,
image replace, colour picker, designs.

> **The panel is drawn on the PC, not in Unreal.** Skin Studio renders it to
> `<game>\Marvel\Content\SkinStudioLive\_panel.png`; in game an Image shows that
> PNG and an invisible Button reports the mouse; every click is hit-tested back
> here. So the Blueprint side is fixed and small, and **new panel features never
> need Unreal, a cook or a repack again** - they are a PowerShell change.

---

## How it hangs together

    F7  ->  bootstrap finds or creates WBP_SkinLiveEditor, Open()
            |
            |  SLC_<ms>_open / _t_<texture> / _tend / _d _m _u / _wu _wd / _close
            v
    live_preview.ps1 (the LIVE PREVIEW watcher)  +  ingame\panel_server.ps1
            |
            |  _panel.png + SkinLiveFrame.sav          (a new frame to show)
            |  <texture>.png + SLT_<texture>.sav + SkinLiveTex.sav
            v
    the game re-imports those textures onto the live character

Everything in both directions is a **file name**. Blueprint can write a save
slot (`SaveGameToSlot`) and ask whether one exists (`DoesSaveGameExist`), and
that is the whole channel - it needs no class of its own to read a file.

## Running it

Nothing new to start: the **LIVE PREVIEW** button in Skin Studio already
launches `live_preview.ps1 -WatchDesigns`, and that now serves the panel too.
A design saved in the desktop app also refreshes the hero by itself whenever
the panel exists in game.

Test it without the game:

    live_preview.ps1 -WatchDesigns -DesignDir <test> -LiveDir <test> -SaveDir <test> -FrameOut <test>

then write `SLC_*.sav` files into the test SaveDir and read the frames.
`%TEMP%\rs\pnl_*.ps1` are the stand-ins for the game.

---

## The Unreal half - once, then never again

Everything below is in `D:\SkinLiveUE`. The graphs are generated, not drawn:

    C:\rs\SkinStudio\ingame\gen_graphs.ps1     ->  D:\SkinLiveUE\paste\*.txt

### 1. The widget's layout (the only mouse work)

`WBP_SkinLiveEditor` already exists (created headlessly). Open it and drag an
**Overlay** from the Palette onto the empty Designer surface - that is the one
thing UE 5.3's Python cannot do (`RootWidgetClass` is protected and
`WidgetTree.RootWidget` is not exposed).

Then in the Output Log's Cmd box:

    py "D:/SkinLiveUE/build_editor_tree.py"

which adds `Image "Screen"` and `Button "Hit"` filling the Overlay, makes both
variables, starts them Collapsed, makes the button draw nothing in every state,
compiles and saves.

### 2. The graphs - FOUR pastes, compiling between each

★ **Order matters and is not cosmetic.** A pasted call to a custom event that
has not been compiled yet cannot find its function, and UE keeps orphaned data
pins but **never exec pins** (`ESaveOrphanPinMode::SaveAllButExec`), so the call
arrives with its wiring cut. Paste, press **Compile**, then paste the next:

| # | file | events | calls |
|---|---|---|---|
| 1 | `editor_1.txt` | `SendCmd`, `TrySwap` | nothing of ours |
| 2 | `editor_2.txt` | `SendMouse`, `Walk`, `Close` | level 1 |
| 3 | `editor_3.txt` | `Open`, `ReloadAll` | levels 1-2 |
| 4 | `editor_4.txt` | `Toggle`, Tick, mouse buttons, wheel | levels 1-3 |

Paste with the graph focused: `Set-Clipboard -Value (Get-Content <file> -Raw)`
then Ctrl+V in the Event Graph.

### 3. The bootstrap

Open `WBP_SkinLivePreviewBootstrap01`, select all in the Event Graph, delete,
paste `bootstrap.txt`, Compile, Save. It becomes small: an init breadcrumb, F6
(find or make the panel -> `ReloadAll`) and F7 (-> `Toggle` / `Open`).

### 4. Cook, pack, install

    UnrealEditor-Cmd.exe D:/SkinLiveUE/SkinLive.uproject -run=Cook -TargetPlatform=Windows -CookAll -unversioned -unattended -nopause -nosplash -stdout
    C:\rs\SkinStudio\ingame\build_live_mod.ps1 -Install

The build script now stages the panel widget as well, and refuses to pack when
the cooked class is missing the refresh chain - including the **MID Parent**
read, which is what makes a second refresh in the same match work.

★ Close the game before installing, do any Vortex deploy first, and confirm the
three `SkinLive_9999999_P.*` files really are in `~mods` before launching.

### 5. In game

Practice range (the lobby hero lives in a preview world mods cannot reach).
**F7** opens the panel, **F6** reloads every edited texture.

---

## ★ First in-game run, 2026-09-23 - it opens, and three things to fix

**F7 opened the panel in a match.** Proof on disk: `SkinLiveInit.sav` 17:39:24,
`_panel.png` delivered 17:39:42, `SkinLiveFired.sav` 17:39:54, and no leftover
`SLC_` commands. Then:

1. **Too small to read.** The delivered frame was **215x470**, not 430x929:
   Rivals reports a UMG DPI scale of ~0.5 and `Pnl-EnsureCanvas` multiplies the
   panel size by it, so it rendered half-size and half-resolution. Fix in
   `panel_server.ps1`: size the canvas in **viewport pixels** - something like
   `clamp(vw * 0.3, 480, 720)` wide - and give SkinPanel a **separate user zoom**
   for fonts. The game side is already correct (`SetDesiredSizeInViewport(tex px
   / GetViewportScale)` maps the image 1:1 to screen pixels).
2. **Works only once.** The watcher process was dead afterwards, and with no
   watcher there are no frames and no answers. Next run, keep its window in
   sight; afterwards check whether it is alive, whether `SLC_*.sav` files pile
   up (game talking, nobody listening) and whether `_panel.png` mtime advances.
   If the watcher does survive: F7 toggles, so a second press hides the panel,
   and `Open` deliberately refuses when there is no pawn.
3. **Hard to navigate.** Three levels (parts -> layer -> colour) is too deep for
   a keyboard-free panel; hit targets and the colour path want rethinking.

All three are PowerShell-side. The Unreal half is done unless the graph itself
needs new nodes (e.g. material vector params for live material editing).

### ✅ 2026-09-23 evening - size and navigation fixed (PC side, no repack)

Tested on the rig with the exact message the game sent (`open_1920_1080_50`),
frames read back:

- **Size.** `Pnl-EnsureCanvas` now works in viewport pixels: UI scale =
  `Vh / 1080 x text size`, width `440 x scale` (at most 45% of the screen),
  height 88% of the screen. At her 1920x1080 that is **550x950** with 17 px body
  text, where the game's run got 215x470 with 6 px. The game's DPI scale is
  only logged now. **Text size** (Small / Medium / Large / Huge, at the bottom of
  the home screen) is saved in `work\ingame\panel_zoom.txt`; Large = 660x950.
- **Two levels instead of three.** The part screen IS the editor: layers are
  tabs (`1 Tint`, `2 Hue shift`, `+ Add`) and the selected layer's controls sit
  right under them. The separate layer screen and its Done button are gone
  (`'layer'` is kept as an alias of `'part'`).
- **One tap to colour.** A vanilla map opens on the palette: tap a swatch and it
  becomes a tint layer and paints (0.6-0.7 s). Other kinds of layer start from
  the pills underneath. On an existing layer the palette comes before the
  picker, which is now under "Fine-tune".
- **Switch part without going back.** A strip of the hero's part thumbnails
  runs across the top of the part screen.
- **Bigger targets everywhere**: 42 px buttons, 36 px pills, 34 px swatches,
  42 px back/close, a wider scrollbar. Layer order is Move left / Move right /
  Delete layer buttons instead of 28 px icons.
- Backing out of the image picker without choosing now undoes the half-made
  image layer. An image layer with no file used to be left behind, and SkinArt
  throws on it at the next paint.

**In game, 2026-09-23 18:14:** with LIVE PREVIEW on in the studio, F7 showed
the new 550x950 panel, and desktop saves refreshed the hero by themselves. The
mouse still turned the camera, though. Rivals owns the input mode: `MarvelHUD`
keeps `InputModeUINeededCnt` / `bInputModeGaming`, and the game's own menus
call `NeedInputModeUI` / `StopNeedInputModeUI` (UFUNCTION names found in the
exe), so our plain `SetInputMode_GameAndUIEx` + `bShowMouseCursor` gets
overridden. **Workaround: tap the Windows key** (the game loses focus and lets
go of the mouse), then click the panel. Clicking the panel works in game after
that. The panel now says so in its footer when it opens. The proper fix is
for `Open` to call `NeedInputModeUI` on the HUD and `Close` to call
`StopNeedInputModeUI`. That needs a MarvelHUD stub in the UE project.

### 2026-09-24 - the proper mouse fix, and F6 shows material colours

✅ **CONFIRMED IN GAME 2026-09-24 (her words: "the mouse works now, no windows
key needed").** F7 hands the cursor over through MarvelHUD; the amber
Windows-key tip is gone from the panel's opening line (kept in the home hint as
the fallback). ✅ Also confirmed: **F7 closes it** (mouse back to the camera)
and **material colour edits update the hero** (the dye/BaseTint bake + blank
DyeingTexture). With LIVE PREVIEW on in the studio, "works only once" has not
come back - the dead-watcher lead was right.

**The mouse.** `Open` now asks the HUD for UI input the way Rivals' own menus
do: `MarvelHUD.NeedInputModeUINoBlock(InWidgetToFocus)`; `Close` calls
`StopNeedInputModeUINoBlock()`. Signatures were read out of the game exe's
reflection tables (the Rivals `FFunctionParams` carries two extra pointers
after the name), and the targets are in `global.utoc`'s script objects.

Our UE project has no `MarvelHUD` class (no C++, no Visual Studio), so:

- the graph calls two stock stand-ins on `GetHUD()`:
  `Actor.RemoveTickPrerequisiteActor(None)` and `Actor.ForceNetUpdate()`.
  Both are C++-virtual, so they are **not** `FUNC_Final` in our stock editor
  and compile to `EX_VirtualFunction` + a NAME, which the VM looks up on the
  real object at runtime. `ingame\patch_hud_calls.ps1` renames those two names
  after the cook (UAssetTool to_json / from_json, round trip byte-identical).
  ★ A Final stand-in would compile to `EX_FinalFunction` + an import and the
  rename would silently do nothing - checked in the editor DLL: no Final
  AActor/AHUD function has the one-object-param shape.
- a guard runs first: `ClassIsChildOf(GetObjectClass(HUD), <Info>)`, with the
  `/Script/Engine.Info` class import repointed to `/Script/Marvel.MarvelHUD`
  by the same script. A missing name is FATAL in `FindFunctionChecked`, so any
  other HUD takes the old `SetInputMode` path instead.
- `Close` only runs while the panel is open: the HUD counts Need/Stop, and an
  extra Stop would break the game's own menus.
- `build_live_mod.ps1 -HudMode NoBlock|Block|None` (default NoBlock) - switching
  needs no Unreal work. `None` = the old behaviour.
- ★ Risk: `InWidgetToFocus` is passed as None. If F7 crashes the game,
  rebuild with `-HudMode None`.
- ★★ **Crashed Rivals at launch on the first install (10:50):**
  `ObjectSerializationError ... ExecuteUbergraph_WBP_SkinLiveEditor: Bad name
  index 290/187`. A Zen package ships only the first
  `NamesReferencedFromExportDataCount` names of the legacy name map (the rest
  are header-only: import names are hashed away). The renamed FNames were
  APPENDED at ~290, so the bytecode pointed past the 187 shipped names. Fixed:
  names used by export data are INSERTED at the end of that section and the
  count grows (installed package now has 189 names); `patch_hud_calls.ps1`
  refuses any by-name call outside the section. ★ compare_class's "all
  script imports resolve" does NOT cover this - it checks imports, not names.

**F6 material colours.** Blueprint cannot read numbers, so `live_preview.ps1`
BAKES a material's dye and BaseTint edits into its `_D` PNG (ViewArt's
verified `DyeComposite`; BaseTint as edited/vanilla, because the game still
applies the vanilla BaseTint on top) and writes a 64x64 all-alpha-0
`_ColorID` PNG, which the Walk now swaps into `DyeingTexture`. Proven first
with a cooked probe on Viridian's jacket: alpha 0 = undyed, the art shows.
Undo writes the vanilla D and the vanilla mask back (the mask is linear
SRGB=false, so the usual lin->sRGB pre-comp is right for it too).

Rebuild, 2026-09-24: four pastes into an emptied Event Graph (F7 compiles in
the Blueprint editor, Ctrl+S saves), bootstrap re-compiled with
`py "D:/SkinLiveUE/compile_save.py"`, quit with
`py unreal.SystemLibrary.quit_editor()`. ★ `-ExecutePythonScript=` runs the
script and then QUITS the editor; `-ExecCmds="py <file>"` keeps it open.

### 2026-09-24 afternoon - washed-out colours, and texture edits win over the dye

✅ **Confirmed in game the same day** - her words: "it works, and well".

**Washed out = the live gamma.** `ImportFileAsTexture2D` makes sRGB-flagged
textures and copies the bytes; the vanilla D/S/AO/AN/M maps are sRGB-flagged
too (no `SRGB` property stored = default true; ColorID/N/ORM/MRO/FM store
`SRGB=false`). The live preview lin->sRGB encoded EVERY map on the old belief
that D maps are linear, so every D and S came out washed. `-Gamma auto` (the
default) now decides per texture from the vanilla flag, cached in
`work\ingame\srgb_flags.json`: a live D is byte-identical to what a build
injects. PNGs written under the old mode are rewritten once on start.

**Texture edits win (her rule, preview AND built mods).** `dyebake.ps1` is
shared by `live_preview.ps1`, `build_skin.ps1` and the 3D preview: for a dyed
material whose D she edits, the dye (with her colour edits) is baked into the
VANILLA D, her edits go on top, and the material's `_ColorID` is replaced by a
blank one (alpha 0 = undyed). Builds ship it full-size (DXT5, alpha 0
verified); the live preview uses 64x64. A D shared by several dyed materials
(Viridian's fur shell `Equip_04` reuses `Equip_01`'s D and mask with its own
palette) is baked with the D's OWN material; the others show that under her
edits, and a colour edit on only the sharer is not baked live (logged).

Still open: **"works only once"** needs the next in-game run to decide (the
checks are above). Best lead: Skin Studio's LIVE PREVIEW was **off**
(`work\live_preview.on` absent), so the watcher that served the 17:39 run was
one a Claude session had started at 17:34, not the studio's. Next run: turn
LIVE PREVIEW on in the studio and keep its window in sight. (Closing Skin
Studio also stops the watcher, by design.)

## ★ LIVE PREVIEW button in game + the helper (2026-09-27; ✅ in-panel switch and Galacta F7 auto-press confirmed in game by Alli 2026-10-02)

Her ask: "the live preview button to appear in game so the mod is self
contained". All PC-side, no cook: the game already shows whatever PNG the
watcher draws, so the button is drawn by the panel like everything else. What
was missing was something to START the watcher with the app closed.

- **One switch**: `work\live_preview.on` (the app's sticky flag). The app's
  button, the in-game button and the watcher all follow it
  (`ingame\livestate.ps1`: `LS-FlagOn` / `LS-SetFlag`).
- **One watcher**: `live_preview.ps1` takes the named mutex
  `Local\ChicorySkinStudioWatcher` (a test `-SaveDir` gets `_<md5>`); a second
  one logs "another Skin Studio watcher is already running" and stops.
  `LS-WatcherAlive` = `Mutex.TryOpenExisting`.
- **Watcher modes**: off = no render at start, no `SkinLiveOn`, `Update-Live`
  only remembers the design, `Pnl-PickDesign` / `Pnl-AutoApply` do nothing,
  `Pnl-DrawScreen` shows only `Pnl-DrawLiveOff`. `Set-LiveMode` switches: on =
  flag, `Update-Live` newest, `SkinLiveOn` + delete `SLA_*` (the game
  re-announces, the design for that skin paints); off = `Revert-AllLive`
  (vanilla PNGs + `Reset-PakList`), `Pnl-FlagLeaves` so the game re-imports now,
  `SkinLiveOn` removed. The loop polls the flag every 20th tick (the app path).
  `-LiveFlag` = test flag file; a `-SaveDir` without it is always on (old rigs).
- **Helper** (`ingame\helper.ps1`, mutex `Local\ChicorySkinStudioHelper`):
  Rivals up + no watcher + (flag on, or an `SLC_*_open_*` < 30 s old) ->
  `LS-StartHiddenWatcher` = `live_preview.ps1 -WatchDesigns -ExitWithGame`,
  `-WindowStyle Hidden`, console to `work\ingame\watcher.out/.err` (+ `.prev`).
  20 s between starts, 5 min after 3 instant deaths. Log `work\ingame\helper.log`.
- **The F8 that woke it**: `Pnl-Init` keeps SLC files < 30 s old when there is
  an `open_` with no later `close` (by `<ms>`), so the first poll opens the
  panel with its hero announce. Everything else is deleted as before.
- `-ExitWithGame`: two missed `LS-GameUp` checks (~5 s) -> remove `SkinLiveOn`,
  exit. `RS_SS_GAMEPROC` fakes the game (the rig uses a `ping` process).
- App: `Test-LiveOn` = flag AND (own watcher OR mutex); turning off with only
  the helper's watcher alive just clears the flag (the watcher reverts itself;
  running `-Clear` too would race it). FormClosing kills only its OWN watcher.
  A 2 s timer keeps the button label in step. `LS-StartHelper` on Shown.
- Rig: `Temp\rs\livetoggle.ps1` - 31 checks (off start, second watcher refused,
  in-game on/off, app flag on/off, helper on F8, kept F8, exit with game,
  resume with flag). Frames in `Temp\rs\pnl\ltframes`.

## Build mod with Project Galacta installed (2026-09-26)

When Galacta is installed and Rivals is running, the Build mod button skips
the live pak (livepak.ps1) and uses Galacta's own F7 instead
(`galacta.ps1`, `Pnl-GalactaTick`). Phase `galacta` on the job, three steps on
the Build screen: *Swap it in* (first F7: Galacta unmounts every mod, the game
releases the old `.ucas`, the new build is renamed in), *Reload it with
Galacta* (second F7: the game opens our new `.ucas` again = loaded), *See it on
your hero* (a level change). *Stop waiting* puts what is left on the pending
list. The live pak manifest is cleared on this route so an older live pak can
never win over the new mod after the level change.

★ **2026-09-27, her rule: only Galacta replaces the skin after a build.**
Without Galacta the Build mod button no longer builds or mounts a live pak:
it installs (`SS-SwapInstall`; held old copy -> pending until Rivals quits),
sets `Mount = 'nogalacta'` (or `'nogame'`) and finishes - no `SkinLiveMount`,
no `SLT_*`, no `SkinLiveTex`. `LP-Clear` runs on that route and at every
`Pnl-Init` (even mid-game), so an older live pak is never loaded from again.
livepak.ps1 and the `mounting` / `loading` phases stay in the code, unused.
Rig: `galpanel.ps1` sections 4-6 (26 checks).

Decoded from GAL_ModLoader 1.2.2: F7 = `ToggleMods`, which unmounts / remounts
the pak PATHS recorded after login - a mod file that did not exist then is
not reloaded (the panel reports that from what the game opens). Needs the
coexistence build (`!!SkinLive`, panel on F8) to be installed: with the
12:06 SkinLive, Galacta's WBP_UIDPanel wins and this panel never opens.

## Auto-apply on spawn + F7 pressed for her (cooked + installed 2026-09-27 01:58)

Her report: "the in-game mod doesn't automatically start if you're not using
a skin it has already loaded" = the hero stays vanilla until F6/F8.

- **Bootstrap `AutoTick`** - a 1 s looping timer started in OnInitialized
  (the bootstrap is never laid out, so no Tick; the probe proved timers run).
  0: `SkinLiveGalToggle` flag -> `GAL_ModLoader.ToggleMods` by name via
  Set Timer by Function Name -> `gal_1` / `gal_0`. 1: while `SkinLiveOn`
  exists, a pawn with no `SLA_<pawn>` marker -> write the marker ->
  Editor-Or-Create -> **`AutoStart`** (panel, paste 3): `auto_<pawn>` then
  Walk(Announce).
- **PC**: `auto` + `tend` -> `Pnl-PickDesign` (now BY SKIN: the design whose
  skin/ops cover the skins on the hero wins over "same hero") ->
  `Pnl-AutoApply` flags every `live` leaf of `_live.txt` for those skins +
  SkinLiveTex. Empty announce (mesh not attached yet) -> `Pnl-AutoRetry`
  drops the marker, 15 tries per pawn. `Pnl-Init` writes `SkinLiveOn` and
  clears `SLA_*` / a stale `SkinLiveGalToggle`; the studio deletes
  `SkinLiveOn` when it stops the watcher.
- Galacta: `SS-GalAsk` / `SS-GalAskCheck` in galacta.ps1 - the flag
  vanishing is the answer; not taken in 5 s or `gal_0` -> she presses F7.
- ★ Re-paste lesson: a pasted pin DEFAULT naming an asset only resolves if
  the asset is loaded - the 5 pm paste had silently lost `T_VariantWordmark`
  (build_live_mod would have refused it). `D:\SkinLiveUE\prep_paste.py`
  loads the logo, then opens the widget. ★ ue_drive `-Do type` into the Cmd
  box got truncated by autocomplete; `-Do setclip` + ctrl+v works.
- Rollback: old `SkinLive_9999999_P.*` in `D:\SkinLiveUE\pack\replaced\20260927-015834`;
  pre-change assets + pastes in `D:\SkinLiveUE\_backup\pre-auto-20260926-221624`.
- Rig tests: `Temp\rs\autotest.ps1` (16), `galtest.ps1` (63), `galpanel.ps1` (16).

## What is proven, and what is not

**Proven on the PC side** (frames read back from a test run, no game):
the parts list, part screen with Colour/Shine/Glow tabs, layer stack, all ten
modes, colour picker drag, swatches, sliders, designs screen, new design, add
layer, undo, revert. A colour drag repainted a 2K texture in 0.6-0.7 s.

**Not yet tried in game:** the Unreal half above - the widget, the four pastes,
and whether Rivals is happy with `AddToViewport` + cursor from our panel.
Galacta does all of it, which is the reason to expect it works.

## ★ The four things that make a generated paste actually land (UE 5.3)

Learned the hard way on 2026-09-22/23; `gen_graphs.ps1` now gets all four right,
and `check_paste.ps1` proves the files are self-consistent before they go near
the editor.

1. **Type references use the 5.3 syntax.** A pin's type object must be written
   `PinType.PinSubCategoryObject="/Script/CoreUObject.Class'/Script/Engine.Actor'"`
   (likewise `.Enum'...'`, `.ScriptStruct'...'`). The UE4 form `Class'"..."'`
   does not resolve: the pin arrives **untyped**, so casts fail with "the type
   of Object is undetermined" and every pin carrying a default is orphaned.
2. **A macro's input exec pin is `execute`, not `Exec`.** Only its outputs are
   `LoopBody` / `Completed`. Wiring to `Exec` drops the link **silently** (exec
   pins are never kept as orphans), the loop is never entered, everything below
   it is pruned as unreachable - and it all still **compiles clean**. The only
   tell is the cooked class missing the literals from inside the loop, which is
   exactly what `build_live_mod.ps1` caught ("panel widget has no 'BaseColor'").
3. **Pasted For Each loops stay wildcard.** `ResolvedWildcardType` is only ever
   set from a live connection change and nothing re-applies it on paste. Build
   loops from `Array_Length` + `For Loop` + `Get (a copy)` instead: those three
   re-type themselves on paste (`PropagateArrayTypeInfo` / `PropagatePinType`
   from `PostReconstructNode`).
4. **Paste in dependency order.** A call to a custom event that is not compiled
   yet loses its exec wires, so the four blocks go in with a Compile between.

Driving the editor from the shell (`ue_drive.ps1`), three more:

- **An asset editor is its own top-level window**, and the main one can be
  hidden behind it - `Process.MainWindowHandle` then reads 0 and every helper
  thinks Unreal is not running. Enumerate windows and match by title.
- **`SendKeys` reaches Slate; raw `SendInput` did not** (the INPUT struct is 40
  bytes on x64, and marshalling 32 makes the call fail silently). Ctrl+A,
  Ctrl+C, Ctrl+V and Delete all do nothing until you switch.
- **Windows refuses SetForegroundWindow from a background process**, so a click
  aimed at Unreal can land in whatever is actually in front - it went into the
  Claude window once. Focus, then **verify** the foreground before every click.

## Landmines already paid for

- skinlib's `SS-OpVal` only understands `[hashtable]`; an `[ordered]` layer
  silently reads as "no settings" and renders as a white tint.
- Never render a panel frame from inside a draw - it disposes the bitmap the
  draw is still using. Slow actions queue and run after the frame.
- `Export-Live`'s stale sweep treated `_panel.png` as a texture and deleted it;
  files starting with `_` are skipped now.
- UE 5.3 Python cannot add Blueprint variables, so the design uses **none**:
  the Tick throttle is stateless (`floor(t*15)` changing) and the bootstrap
  finds the panel with `GetAllWidgetsOfClass`.

## 32-colour palette removed, colour history only (2026-10-02, ✅ confirmed in game by Alli 2026-10-02)
Her call: "remove the 32 color swatches and just have a color history panel". panel_server.ps1 only (the app-linked panel is drawn on the PC; no Unreal/cook): the PnlPalette swatches are gone from the part screen and the vanilla-map quick start. The Recent strip is now "Colour history", holds 16 (two rows), and picking from it moves the colour to the front. A vanilla map with no history yet offers Tint as a pill. Backup: panel_server.ps1.bak-prehistory-20261002. Parse-checked; not rendered (Pnl-Init has side effects on the game's save folder).

## Nexus download: everything goes in ~mods (2026-10-03, PC side only, not yet installed on another PC)
Her ask: "i want to be able to put it in the mods folder only". The app can't RUN from ~mods: subfolder paks mount, and work\ holds 167 built .ucas + 16 GB of cache. So the zip goes into ~mods and a setup copies the app out:
- `nexus\make_nexus_zip.ps1 -Version X` -> `Downloads\Skin Studio X.zip` (46 MB): the !!SkinLive triplet from ~mods + `SkinStudio\Start Skin Studio.bat`, `setup.ps1`, `app\` (code, viewer, branding, colortool bin, blender usmap/py, tools\rrcli+ddstools+retoc.exe). Refuses if any .pak/.utoc/.ucas is under SkinStudio\.
- `nexus\setup.ps1`: robocopy app\ -> `%LOCALAPPDATA%\SkinStudio` when VERSION.txt differs (refuses while a powershell from there runs), writes `game_paks.txt` from the ~mods it sits in (walks up, so Vortex nesting works), Start menu shortcut, launches.
- skinlib.ps1 is portable now: `$SS_Root = $PSScriptRoot`, `$SS_Tools` = `<root>\tools` else `C:\rs\tools`, `SS-FindPaks` = RS_SS_PAKS, game_paks.txt, every Steam library (libraryfolders.vdf), Epic manifests, then the old default. dyebake's ~mods and the launcher bat follow. Dev copy resolves exactly as before. Backups `*.bak-preportable-20261003`.
- Tested: zip into a fake game's ~mods, setup -> AppData copy, paths resolve to the copy, and a real Luna 1031001 extraction from the copy's own tools matched the dev cache (80 PNGs). The GUI was not opened from the copy (its helper could start a second-copy watcher on her game).
- Users need the .NET 8 runtime (colortool is framework-dependent).
