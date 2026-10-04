# In-game menu — build sheet

The Skin Studio counterpart to Project Galacta: a menu inside Marvel Rivals that
re-applies the open design onto the live character, so a colour can be judged on
the real model, in real light, without building a pak or restarting.

Decoded from `Project Galacta Mod 12806 1.2.2` on 2026-09-20. The PC half is
built and working (`live_preview.ps1`); this is the half that needs Unreal.

> **★★★★ v1 WORKS IN GAME — 2026-09-21 22:2x.** Jubilee in "Vampy Jammies"
> (`1064300`) turned pink in the practice range on F6: PNG on disk →
> `ImportFileAsTexture2D` → `SetTextureParameterValue` on a dynamic material
> instance, in a live Shipping build, **no repack and no restart**. Hosted by the
> **vanilla** `WBP_UIDPanel`. Read the next section before anything else in this
> file — much of what follows it is the *diagnosis history*, and several of its
> conclusions were wrong.

---

# ★★★★ The shipped recipe — read this first

Everything here is confirmed in game, not reasoned. `ingame\build_live_mod.ps1`
already defaults to all of it; one command builds and installs:

    C:\rs\SkinStudio\ingame\build_live_mod.ps1 -Install

## The four things that make it load

1. **Bootstrap = a four-string name swap in the vanilla panel.** Repoint
   `WBP_UIDPanel`'s existing child class `WBP_BackstageShader_Progress02_C` at
   our widget. Equal-length ASCII, in place (path 63, leaf 30, `_C` 32,
   `Default__` 41) so nothing in the package moves. No rebuilt panel, and
   nothing of Galacta's is redistributed.

2. **★★★ Blank the host's stored property block for that child.** This was the
   real cause of every crash — *not* our Blueprint, which was never wrong.
   `WBP_UIDPanel` is one of the game's own packages, so it serialises properties
   **unversioned = positionally**: the 13-byte block it stores for that child
   reads schema slots **77 and 98** of a class that inherits
   `PyWidget_CompileInfo_Resident`. Point it at a plain `UserWidget` subclass and
   those indices walk off the end of the schema → junk `FProperty*` →
   `EXCEPTION_ACCESS_VIOLATION reading 0x0` at *construction*. Which is why
   bisecting the graph never moved it.

   Fix is two bytes: rewrite the fragment header so the panel stores **no**
   properties for the child. `FUnversionedHeader::FFragment::Pack()` =
   `SkipNum | bHasAnyZeroes<<7 | bIsLast<<8 | ValueNum<<9`, so an empty
   terminated header is `0x0100` → bytes `00 01`. The block is found **by
   content** (signature `4D 02 14 03 04 00 00 00 01 00 00 00 00`, must appear
   exactly once), so a game patch that moves it fails loudly instead of being
   mis-patched.

3. **★★★ The export's declared size is a budget, and 6 is the right number.**
   `AsyncLoading2.cpp:6459` enforces it and the assert *names the real figure*,
   which makes the engine a precise oracle — iterate with `-ChildExportSize <n>`.
   Consumption depends on the block's **content**, not only on our class:

   | declared | tail bytes | engine consumed |
   |---|---|---|
   | 13 (vanilla) | old fragment words left in place | **22** — over-ran |
   | 22 | zeroed | **6** |
   | **6** | zeroed | **6** ✓ loads |

   The shipped block is exactly `00 01 00 00 00 00` — the 2-byte empty header
   plus a length field reading zero. **Zeroing the tail is part of the fix, not
   tidiness**: leaving the old words there is what made it over-read to 22.
   Growing the export means sliding every later `SerialOffset` and
   `BulkDataStartOffset` by the delta (`FObjectExport` is **96** bytes here — the
   72-byte figure is Zen's `FExportMapEntry`, a different thing).

4. **Ship TAGGED properties, never unversioned ones.** In the authoring
   project's `Config/DefaultEngine.ini`:

       [Core.System]
       CanUseUnversionedPropertySerialization=False

   ★ Do not confuse the two "unversioned"s — they pull opposite ways.
   **Package-summary** unversioned (`-unversioned` on the cook commandlet) is
   **required** or rrcli refuses the package; **property** unversioned (the ini
   above) **must be off** or the game throws `ObjectSerializationError`. The
   build script refuses to pack a package with `PKG_UnversionedProperties` set.

## ★★ Trigger from an InputKey event — never Event Tick

Breadcrumbs written by the widget itself and read off disk afterwards:

| file | written? | meaning |
|---|---|---|
| `SkinLiveInit.sav` | **yes** | `Event On Initialized` ran — our class loads *and executes* |
| `SkinLiveConstruct.sav` | **no** | `Event Construct` never ran — the widget gets **no Slate widget** |
| `SkinLiveFired.sav` | **yes** | **F6 reaches it** |

Blanking the property block drops the child's `Slot`, so the widget is created
but never **arranged** — and Slate only ticks arranged widgets. So `Construct`
never fires and neither does `Tick`. Input delegates are bound in
`NativeOnInitialized` (`UInputDelegateBinding::BindInputDelegates(GetClass(),
PC->InputComponent, this)`), which runs regardless of layout, so they work. This
is also why Galacta triggers from an `InputKeyDelegateBinding` and sets its
injected child `ESlateVisibility::Collapsed`.

The old note in this file that "an input-key event at login is fatal" was doubly
wrong: it is the only thing that *does* work. The "Tick poll" section below is
kept only as history — **do not build it.**

## ★★ How to get any signal out of a Shipping build

`PrintString` is compiled out and the game's logs are encrypted, so a breadcrumb
has to be a file. Two nodes, no new asset:

    Load Game From Slot (SlotName "HighlightSettings")  ->  Save Game to Slot (SlotName "<mark>")

`LoadGameFromSlot` borrows the game's own existing save object, so there is **no
class pin to resolve**. Files land in
`%LOCALAPPDATA%\Marvel\Saved\SaveGames\<mark>.sav`.

★ Do **not** use `Create Save Game Object`: `USaveGame` is `UCLASS(abstract)` and
`CreateSaveGameObject` returns **nullptr** for a null or base class, so the chain
silently writes nothing. And a T3D paste referencing a Blueprint SaveGame
subclass gets that reference **silently dropped** if the editor's asset registry
has not seen it yet.

## ★ Press F6 in a MATCH, not at the menu

The graph searches `Get Player Pawn` → `Get Attached Actors`, so it only finds
anything where a pawn exists and the character is attached to it. **At the login
screen and in the lobby there is no pawn**, the loop runs over an empty list, and
it looks exactly like "F6 does nothing". The practice range is the test bed.

`GetAttachedActors` is `BlueprintPure` — **no exec pins**. The refresh chain's
exec entry point is the first **For Each Loop**, not that node.

## ★ Verdict procedure — every single test

"It launches" means **nothing**: a *rejected* container makes the game boot
perfectly, because the engine throws out the whole thing and loads none of it.
Two launches were wasted on that. Before each test:

1. delete `%LOCALAPPDATA%\Marvel\Saved\pak_invalid.txt`
2. note the `%LOCALAPPDATA%\Marvel\Saved\Crashes` folder **count**

After it: **absent `pak_invalid` = it mounted**, and the crash count says the
rest. The `<ErrorMessage>` in
`Crashes\<newest>\CrashContext.runtime-xml` is plain text and names the exact
package, export and fault; the `<CallStack>` is useless in a shipping build.

★ **Vortex can sweep our loose files out of `~mods`.** A redeploy ran after an
install once and removed `SkinLive_9999999_P.*`, leaving a launch that proved
nothing. **Do Vortex deploys first, install ours last, and confirm the three
files are actually in `~mods` before launching.**

## The container recipe that mounts

Mix the two tools — package data from `retoc to-zen --version UE5_3`, companion
pak from **rrcli's 416-byte stub** (0 files, **encrypted index: true**). retoc's
own 347-byte pak has `encrypted index: false` and the engine rejects the entire
container. Flags at `.utoc` offset 80: working `0x09`, retoc's `0x08`. Staging
layout is `<leaf>/Marvel/Content/Marvel/<path>`, and the stage leaf becomes the
container name.

★ **`rrcli` IS `retoc`** — the binary is `retoc-rivals-cli.exe`, a Rivals fork.
The old "tried two packers" bisection tested one implementation twice.

## After any graph edit

★ **Deleting nodes silently orphans the chain**, and a clean compile does not
mean the exec chain is connected — unreachable nodes are pruned with no error.
Clearing an old breadcrumb paste once took out `Event Tick` with it, leaving all
22 refresh nodes unreachable; it compiled clean and cooked to a class containing
no `ImportFileAsTexture2D` at all. **The cooked name table is the proof.**
`build_live_mod.ps1`'s graph check does exactly this diff, so never pass
`-NoGraphCheck` on a real build.

---

## How the loop works

    Skin Studio  ──►  <game>\Marvel\Content\SkinStudioLive\T_1025502_..._D.png
                            │
                            ▼
    in game, on a keypress: ImportFileAsTexture2D  ──►  MID SetTextureParameterValue

No pak, no mount, no restart. **Mounting cannot do this** — once a texture
package is loaded, UE keeps it cached by name and remounting over it changes
nothing. Galacta's `MountPak` is only for loading mods at login, before assets
load. Live editing has to go through the material, not the package.

### The protocol is only filenames

One PNG per edited texture, named after the **vanilla texture asset**
(`T_1025502_10250_Hair_D.png`). In game we walk the character's material slots
and, for each one, read the current texture out of the `BaseColor` / `Normal` /
`ORM` parameter, take that texture's object name, and look for a file of that
name in the drop folder.

So there is no manifest to keep in sync and nothing to parse in Blueprint:
`ImportFileAsTexture2D` returning null **is** the "not edited" test.

---

## Verified, so the design rests on facts not hope

Reflected names confirmed present in `Marvel-Win64-Shipping.exe`:

| Function | Module | Why we need it |
|---|---|---|
| `ImportFileAsTexture2D` | `KismetRenderingLibrary` | PNG on disk → texture, at runtime |
| `CreateDynamicMaterialInstance` | `PrimitiveComponent` | a MID we are allowed to write to |
| `GetTextureParameterValue` | ✗ **NOT `MaterialInterface`** — see below | read the vanilla texture → its name |
| `SetTextureParameterValue` | `MaterialInstanceDynamic` | the actual swap |
| `GetMaterialSlotNames`, `GetNumMaterials` | `SkinnedMeshComponent` | walk the slots |

★ **Correction, 2026-09-22 — the third row above was wrong.** Resolved from the
game's own reflection (`retoc print-script-objects global.utoc`, owner resolved
via `outer_index`): **`K2_GetTextureParameterValue` is owned by
`MaterialInstanceConstant` and `MaterialInstanceDynamic` only.** There is no
`MaterialInterface` version, so the vanilla texture **cannot** be read off a
static material — the node will not connect. This invalidated the first version
of `GRAPH_RECIPE.md`'s edit B; see the warning there.

★ **Open question it exposed, untested:** after the first F6 the slot's material
is the MID and its `BaseColor` holds the **imported** texture, which
`ImportFileAsTexture2D` creates via `CreateTransient` with no name (so:
`Texture2D_0`, not `T_…_D`). Press two would then look for `Texture2D_0.png` and
skip. **The live preview may only work once per game session** — only one
successful press was ever recorded. Test before building anything else on top.

And the character materials really do expose the maps as named parameters —
checked against `MI_1031001_Body`, whose parameter list is `BaseColor`,
`Normal`, `ORM`, plus vector params `BaseTint`, `RimLightColor`, `FX_Color_01`.
Same shape on every character MI spot-checked.

Engine: **UE 5.3** (FModel reports `UeVersion=84082689` = 0x05030001).

---

## Assets to author

Galacta ships 40; we need four.

*Status: 1 and 2 are **built, installed and working** — shipped as
`WBP_SkinLivePreviewBootstrap01`. 3 and 4 are still v2; see the roadmap at the
end of this file.*

1. **`WBP_SkinLive`** — the mod. Collapsed, no visuals at first. On `Construct`,
   bind a refresh key. On that key: find the player's character mesh, walk its
   material slots, and for each slot and each of the three parameters do
   read-name → import → set. Cache the MIDs so a second refresh is cheap.
2. **`WBP_UIDPanel` (override)** — the bootstrap. See the open question below.
3. **`SS_SettingHandler`** — derives `/Script/Marvel.UISettingEntrySettingHandler`,
   overrides `BP_GetCurrentValue` / `BP_OnChanged` / `BP_OnBtnClicked`, switches
   on a `SettingKey` string. Only needed once we want the refresh key to be
   configurable; skip for v1.
4. **`SS_Other_Composite` + `SS_Other_Additions` + a `SettingPageLayoutTable`
   override** — the Settings page rows. Also v2. The whole trick is that the
   composite stacks the vanilla "Other" rows with ours, and only the single
   `OtherSettingTable` row of `SettingPageLayoutTable` is repointed at it.

### v1 is deliberately tiny

Asset 1 plus a bootstrap. One key, no UI. Everything in asset 1 is **stock
Engine and UMG** — no `/Script/Marvel` class is referenced at all, so the stub
project for it needs nothing Marvel-specific. That is worth protecting: keep
`MarvelFileUtil` out of v1 even though it is available.

---

## The bootstrap — solved, and it needs no stub trickery

Galacta gets constructed by overriding `/Game/Marvel/UI/Blueprints/Login/WBP_UIDPanel`
and adding a collapsed child, `WBP_Injection`, of class `WBP_Galacta_C`. The game
builds that panel every boot, so its `Construct` always runs.

I diffed Galacta's copy against the vanilla one (extracted fresh from
`pakchunkUI-Windows.utoc`; byte-identical to the July extraction in `C:\rs\uifull`,
so the panel has not changed across patches). Two findings changed the plan.

### The vanilla panel is a thin stub

Its `.uexp` is **510 bytes** and contains essentially just `BPTYPE_Normal`. The
40-name table lists the widget *types* as imports, and the real layout comes from
the Python class `PyWidget_UIDPanel`. Galacta's copy is 83 names and a 2,257-byte
uexp full of `Anchors` / `Offsets` / `Padding` / `Stretch` — they **rebuilt the
panel by hand in UE** rather than splicing bytes.

Galacta's copy also carries `/Engine/UnknownPackage` and `UnknownExport` —
unresolved imports — **and the mod ships and works**. So the game tolerates an
imperfect rebuild of this panel. Route A is proven by example, if we want it.

### ★ But the vanilla already imports a child Blueprint class

The vanilla tree contains a child widget of class
`WBP_BackstageShader_Progress02_C`. We do not need to *add* an export — we can
**repoint that existing child at our own class**. That turns the whole bootstrap
into a name-table string swap, the same class of edit this workshop already does
to materials, instead of structural surgery on a cooked package.

The four strings, with the byte lengths that matter:

| chars | string |
|---:|---|
| 63 | `/Game/Marvel/UI/Blueprints/Squad/WBP_BackstageShader_Progress02` |
| 32 | `WBP_BackstageShader_Progress02_C` |
| 41 | `Default__WBP_BackstageShader_Progress02_C` |
| 30 | `WBP_BackstageShader_Progress02` |

UE's name table is length-prefixed and the summary stores offsets past it, so a
different-length name shifts everything after it. **Avoid that entirely by
choosing names of exactly matching length**: a 30-character leaf inside a
33-character path gives 63, and `_C` / `Default__` then fall out at 32 and 41 on
their own. Nothing in the package has to move, and the edit is a straight
in-place byte replacement.

The cost: we replace that child rather than adding one, so the backstage-shader
progress widget stops rendering on the login screen. Galacta's build appears to
have dropped its class import too, so this is evidently tolerable — but confirm
by looking at the login screen after the first install.

**Plan: route B, with route A as the fallback** we already know works.
## Gamma calibration, first thing after it renders

`ImportFileAsTexture2D` hands back an **sRGB-flagged** texture. Character colour
maps are **linear-flagged**. Left alone, the shader applies an sRGB→linear read
that the vanilla texture never gets, and the preview comes out dark — the Luna
bug again, this time at preview time.

`live_preview.ps1 -Gamma` pre-compensates for it, defaulting to `srgb`
(lin→sRGB, which cancels it exactly). Measured shift on a real texture: **54
luminance**, the same order as the original Luna bug, so this is not subtle and
will be obvious the moment the first preview renders.

The moment the in-game side works, check a flat mid-grey against the built mod:

- preview matches the build → leave it on `srgb`, done
- preview too **bright** → `-Gamma none` (the import was not sRGB-flagged after all)
- preview too **dark** → `-Gamma linear`

Bake the answer in as the default and delete the other two branches.

---

## Packing

Same as every other mod here: author in UE, cook, then `rrcli pack` the cooked
tree into the loose `.pak/.ucas/.utoc` triplet at the `~mods` root. Galacta's
container is named `!ProjectGalacta_9999999_P` — the leading `!` and the high
chunk id are there to sort it last so it wins every override.

---

# Built — 2026-09-21

`ingame\build_live_mod.ps1` does the whole second half in one go: extract the
vanilla panel from the live game, patch it, stage, pack, install. Run it with
`-Install` after any re-cook. The mod is installed as `SkinLive_9999999_P` and
is backed out by deleting those three files from `~mods`.

Four things bit on the way through, all now guarded in the script.

## ★ A Widget Blueprint saved without Compile cooks to an EMPTY class

The asset was saved at 10:37 with the full pasted graph in it, and cooked to a
1,614-byte uasset / **219-byte uexp** holding nothing but `BPTYPE_Normal` — no
ubergraph, no functions, no imports. The cook log was completely clean: no
warning, no error, exit code 0. Nothing anywhere says the class came out hollow.

The editor asset keeps graph data regardless of compile state, so the *source*
looked perfect the whole time — every node name was in its name table.

**Compile, then Save, then cook.** Headless equivalent, which is what fixed it:

    UnrealEditor-Cmd.exe <uproject> -run=pythonscript -script=compile_save.py

The tell either way: the cooked `.uexp` is a few hundred bytes instead of a few
thousand, and the cooked name table has no `ExecuteUbergraph_` entry. The build
script now refuses to pack unless the cooked uasset contains
`ExecuteUbergraph_…`, `ImportFileAsTexture2D`, `SetTextureParameterValue` and
`BaseColor`.

## ★ The cook must be `-unversioned` or rrcli rejects it

`rrcli pack` fails with **"Expected to find zero UE3 version, got 864"**. Rivals
ships unversioned packages — after the tag and `LegacyFileVersion` the summary is
all zeroes, no UE3/UE4/UE5 version and no custom-version array:

    shipped :  c183 2a9e  f8ff ffff  0000 0000  0000 0000 …
    ours    :  c183 2a9e  f8ff ffff  6003 0000  0a02 0000 …   (864, 522, …)

UAT passes `-unversioned` by default; a hand-run `-run=Cook` does **not**. It is
not a one-field fix — a versioned summary also carries the custom-version array,
so every offset after it moves. Re-cook, don't patch:

    -run=Cook -TargetPlatform=Windows -CookAll -unversioned -unattended -nopause -nosplash -stdout

## ★ Extract the vanilla panel from the LIVE game, never from `C:\rs\uifull`

The July extraction's `.uexp` is **three bytes out of date** (offsets 0x106,
0x113, 0x116). The `.uasset` is byte-identical, so the name table is unchanged
and it would have looked fine on a casual check. Two independent paths — `rrcli
unpack` of `pakchunkUI-Windows.utoc`, and `retoc to-legacy` across the whole
Paks dir with the game AES key — agree with each other and disagree with the
July copy. `retoc` over the whole dir also settles the patch-chunk question:
`Patch_-Windows_1.1.3870120_P` carries **no** override of this package, so the
UI chunk copy is the effective one.

We are overriding this package, so shipping a stale one is the fatal-on-launch
case. The script now always re-extracts and prints both SHA-256 prefixes.

## The child-class swap is confirmed real, not an unused import

Parsed the vanilla panel's import table (FObjectImport is **32** bytes in UE5,
not 28 — there is a trailing `bImportOptional`). Three entries matter:

    [-16] Package  /Game/Marvel/UI/Blueprints/Squad/WBP_BackstageShader_Progress02
    [-26] Class    WBP_BackstageShader_Progress02_C              outer=-16
    [-25] CDO      Default__WBP_BackstageShader_Progress02_C     outer=-16

The **CDO import is the proof**: UE only imports a class's default object when
something in the package uses it as a *template* for an instanced subobject.
Every genuine child of this widget tree shows the same class+CDO pair
(`Default__CanvasPanel`, `Default__MarvelTextBlock`, `Default__ScaleBox` …), and
the backstage-shader class sits in exactly that pattern. Repointing those three
strings swaps a child that really does get built.

Name hashes do not need recomputing: the two `uint16` after each name entry are
**zero** in Rivals' packages anyway, and `FNameHelper::MakeFromLoaded` rebuilds
the hash from the string on load. Equal-length swap, nothing moves.

## ★ How F6 actually reaches a UserWidget — and the lifetime question

> **Answered in game.** The mechanism below is right, and the worry is not: F6
> fires from the login panel's widget **long after login**, in the practice
> range. `SkinLiveFired.sav` proves it. The panel is not torn down, or at least
> its binding outlives the login screen. The generalisation at the end of this
> section still stands as the escape hatch if a patch ever changes that.

`UUserWidget::NativeOnInitialized` runs
`UInputDelegateBinding::BindInputDelegates(GetClass(), PC->InputComponent, this)`
— that is the *only* thing that binds a widget's input-key events, and the
cooked class carries the matching `BlueprintInputKeyDelegateBinding` /
`InputKeyDelegateBindings` / `IE_Pressed` data, so the wiring is right.

But note what it depends on: **an owning PlayerController must already exist**
when the widget initialises, and the binding lives only as long as the widget.
`WBP_UIDPanel` is the *login* panel. If it is torn down after login, F6 goes
with it, and the place you actually want to judge a colour — the practice range —
may be long past that. This is the first thing to find out in game, and it is
empirical, not arguable.

If F6 turns out to be dead outside the login screen, the fix is a different host
widget, and the pipeline generalises cleanly: pick a victim child class in a
widget that *is* alive where you need it, then name our asset so the four
strings match its lengths byte-for-byte (leaf, path, `_C`, `Default__`), re-cook,
re-patch. Only the names change; none of the machinery does.

## ★ First install crashed — and it proved the bootstrap works

The game crashed on launch. The Rivals `Saved\Logs` files are obfuscated, but
**`%LOCALAPPDATA%\Marvel\Saved\Crashes\<id>\CrashContext.runtime-xml` is plain
text**, and its `<ErrorMessage>` names the package and the export:

    ObjectSerializationError: /Game/Marvel/SkinLive/UI/Widgets/WBP_SkinLivePreviewBootstrap01
      - WidgetBlueprintGeneratedClass ...WBP_SkinLivePreviewBootstrap01_C:
        Bad export index 67108863/7.

Read that carefully, because it is good news twice over:

1. **The game was loading OUR widget.** The four-string name swap in
   `WBP_UIDPanel` worked — route B is proven. That was the risky, unprecedented
   part of this whole plan.
2. `pak_invalid.txt` is empty, so the container mounted cleanly too.

The failure is narrow: the engine cannot deserialize our
`WidgetBlueprintGeneratedClass`. `67108863` is `0x3FFFFFF`, so the loader read a
garbage `FPackageIndex` (raw `0x04000000`) where an object reference belonged —
a stream desync inside that one export. `/7` is the export count, and our
package really does have 7 exports, so nothing was dropped.

### Ruled out, with evidence — do not re-investigate these

- **rrcli did not corrupt the package.** Packed with rrcli, then read back with
  *both* tools: import map order preserved (50 = 50, identical), export count
  preserved (7), export-data name prefix preserved, and the `.uexp` byte-identical
  to the cook. Cross-reading rrcli's container with retoc gives the same bytes.
- **Name-table reordering is normal, not damage.** After packing, names 0-39 are
  unchanged and only index 40+ move. That split is exactly right: 0-39 are the
  names the *export data* references (`CallFunc_*`, `Temp_int_*`, `BaseColor`,
  `UberGraphFrame`, property and struct names) and 40+ are header-only names
  (imports, exports, package name), which Zen rebuilds by design.
- **Property serialisation format matches.** Our export data opens with a
  two-byte unversioned-property header (`18 01 …`), the same shape as the game's
  own cooked `WBP_UIDPanel` (`00 02 …`). We are not on the wrong scheme.
- **Class shape matches a published mod.** Galacta's `WBP_Galacta` has the same
  parent (`UserWidget`), the same generated-class type, the same export kinds
  (ubergraph function, `InpActEvt_*` input events, `InputKeyDelegateBinding`,
  CDO, class, WidgetTree) — and it also uses InputKey events in a UserWidget.

### ★★ ROOT CAUSE: unversioned PROPERTY serialization

> **Half right — necessary, but not the crash.** Switching our package to tagged
> properties *is* required and is in the shipped recipe. It did not fix the
> crash, because the offending positional read was in **the host's** stored
> property block, not in ours. Same mechanism, wrong package. Keep the ini
> setting; read the top of this file for the actual cause.

The empty control crashed too — same error, now on the **CDO** of a widget with
three exports and no graph at all:

    - WBP_SkinLivePreviewBootstrap02_C .../Default__WBP_SkinLivePreviewBootstrap02_C:
      Bad export index 10754047/3.

An empty `UserWidget` CDO serialises almost nothing, so the fault could not be in
our graph. It is in the **property schema**. Compare the package flags:

| package | PackageFlags | `PKG_UnversionedProperties` (0x2000) |
|---|---|---|
| ours (01 and 02) | `0x80002200` | **set** |
| game's `WBP_UIDPanel` | `0x80002200` | set |
| **Galacta's `WBP_Galacta`** | `0x80040200` | **not set** |

**Unversioned property serialization identifies properties by their POSITION in
the class layout, not by name.** It is meant for cooked content where the
runtime class layout is guaranteed to match the cooker's. Ours is cooked against
**stock UE 5.3**; the game runs a **modified** engine (`S10.0_release`, with its
own UMG — `MarvelTextBlock`, `MarvelHorizontalBox`, `PyWidget_*`). So our CDO's
property stream gets decoded against Marvel's `UUserWidget` layout, desyncs, and
the loader eventually reads a garbage `FPackageIndex`. The two crash values —
`0x3FFFFFF` then `0xA41BFF` — being different flavours of garbage fits exactly.

The game's own packages can use it safely because their cooker *is* their engine.
A mod cannot. Galacta ships tagged properties, which is why Galacta works.

**Fix** — `D:\SkinLiveUE\Config\DefaultEngine.ini`:

    [Core.System]
    CanUseUnversionedPropertySerialization=False

Then re-cook. Properties are then written as name tags, which the loader matches
by name and skips when unknown — which is exactly what a mod needs. The build
script now refuses to pack a package with `PKG_UnversionedProperties` set and
names this fix in the error.

Note this is the *opposite* of the summary-level `-unversioned` cook flag, which
we still need. Two different meanings of "unversioned":

- **package summary** unversioned — no engine version in the header. **Required**
  (`-unversioned` on the cook commandlet), or rrcli refuses the package.
- **property** unversioned — positional property encoding. **Must be off**, or
  the game crashes on load.

### The bisection that found it

`WBP_SkinLivePreviewBootstrap02` — an **empty** UserWidget, no graph, 126 bytes
of export data, same 30-character name so the swap stays byte-exact. Built and
installed in place of 01. One launch splits the remaining space:

- **loads fine** → this engine is happy with a stock-UE-5.3-cooked widget class,
  and the problem is something *in* the graph (most likely the bytecode's object
  references, or the `InputKeyDelegateBinding`). Add back in stages.
- **same crash** → a stock UE 5.3 cook cannot produce a Blueprint class this
  build will load at all, and the route changes: match the engine more closely,
  or drop the authored class and drive the swap some other way.

Build either with the same script:

    .\build_live_mod.ps1 -Widget WBP_SkinLivePreviewBootstrap02 -NoGraphCheck -Install
    .\build_live_mod.ps1 -Install          # back to the real one

It also takes `-Packer retoc`, which builds the container with `retoc to-zen`
instead of `rrcli pack` (uncompressed, different implementation of the same
conversion) — worth a try only if the evidence above turns out to be wrong.

## ★★ Second crash, and what the bisection proved

> **✗ SUPERSEDED — the bisection was sound, its conclusion was not.** The table
> is real and reproducible; the reading of it is wrong. "An input-key event at
> the login screen is fatal" is false — Galacta ships one, removing F6 did not
> fix the crash, and F6 is what works today. What actually separated the empty
> control from the graph build was `UberGraphFrame`: adding it changed the
> class's **property count**, which is what tipped the host's positional
> over-read from surviving by luck into faulting. Confirmed — `01` (crashes) has
> `UberGraphFrame` in its cooked class, `02` (loads) does not. The content of the
> graph was never relevant, which is exactly why every cut through it changed
> nothing.

With tagged properties the package loads. The next launch died differently —
`EXCEPTION_ACCESS_VIOLATION reading 0x0`, no package named. Three launches
settled it:

| build | result |
|---|---|
| no mod at all | launches |
| **empty** widget, same child-class swap | **launches** |
| same widget + the F6 graph | access violation, **35 s in** |

The crashing run went 15:44:38 → 15:45:13. Thirty-five seconds is load time: the
graph body never ran and F6 was never pressed. The empty control differs only by
having no graph, and therefore no `InputKeyDelegateBinding` export.

**So: an input-key event on a widget constructed at the login screen is fatal.**
`UUserWidget::NativeOnInitialized` runs
`BindInputDelegates(GetClass(), PC->InputComponent, this)`, and at the login
screen there is no PlayerController or InputComponent yet. Stock UE 5.3 guards
it — `if (InClass && InputComponent && SupportsInputDelegate(InClass))` — and
Marvel's fork evidently does not.

**Two good things fell out of this:**

1. **Route B is proven sound.** The empty widget goes through the identical
   four-string swap and the game launches normally. We do *not* need Galacta's
   add-a-child rebuild.
2. It kills the old open question about binding lifetime by making it moot.

### ...but removing the binding did NOT fix it

Rebuilt with the input-key event replaced by a Tick poll (below). Verified in the
cooked package: no `InputKeyDelegateBinding` export at all, 6 exports instead of
7, `Tick` present as a real function export. **Still the same access violation**,
51 s in. So the input binding was not the cause, or not the only one.

Further ruled out, all from files, no launches:

- **Every engine name the graph imports exists in the shipping exe** —
  `BlueprintPathsLibrary`, `ProjectContentDir`, `ConvertRelativePathToFull`,
  `WasInputKeyJustPressed`, `GetAttachedActors`, `K2_GetComponentsByClass`,
  `KismetRenderingLibrary`, `ImportFileAsTexture2D`,
  `CreateDynamicMaterialInstance`, `K2_GetTextureParameterValue`,
  `SetTextureParameterValue`, `GetNumMaterials`, `Concat_StrStr`,
  `GetObjectName`, `GetPlayerPawn`, `GetPlayerController`. So no script import
  resolves to null.
- **Package flags are right.** Ours `0x80000200` = `PKG_FilterEditorOnly` +
  `PKG_Cooked`. The game's own widgets are the same plus
  `PKG_UnversionedProperties`, which we deliberately dropped. Galacta adds only
  `PKG_RequiresLocalizationGather`. Nobody has `PKG_ContainsScript`.

★ **The graph never ran in the crashing F6 build** — that build had no Tick, so
its ubergraph was never entered, and it still crashed. Whatever this is, it
happens at **load or construction**, not execution. That leaves only what the
crashing package has and the working empty control does not:

| | 02 — launches | 01 — crashes |
|---|---|---|
| widget tree | empty, no root | `CanvasPanel` root |
| functions | none | ubergraph + Tick |
| imports | 9 | 54 |

Next cut: delete the Canvas Panel from 01, keep the graph. It is also a
candidate *fix*, not just a probe — this widget draws nothing, and 02 proves a
Widget Blueprint compiles, cooks and loads with no root widget at all, so the
"needs a root to be valid" line earlier in this document is simply wrong.

### The Tick poll (replaces the fatal input-key event)

> **✗✗ SUPERSEDED — DO NOT BUILD THIS.** Both of its premises are false. The
> input-key event was never fatal (see the shipped recipe at the top), and a Tick
> poll **cannot work here at all**: blanking the host's property block drops the
> child's `Slot`, the widget is never arranged, and Slate does not tick
> unarranged widgets — so `Event Tick` never fires. This was actually built and
> tested, and it is what made "F6 does nothing" look like a trigger problem.
> Kept only so the dead end is not walked twice.

Replace the F6 event with a Tick poll. No dynamic binding object is created, so
nothing touches the PlayerController at initialise time, and it works whenever
the widget is alive and a PC exists rather than only if one existed at init.

In `WBP_SkinLivePreviewBootstrap01`, Graph tab:

1. **Delete the `F6` node.** That node is what creates the
   `InputKeyDelegateBinding` — it is the whole problem.
2. Add **Event Tick**.
3. Add **Get Player Controller** (Player Index 0).
4. Add **Is Valid** (the macro with two exec pins), input = that controller.
5. Add **Was Input Key Just Pressed** — Target = the controller, Key = `F6`.
   (`UFUNCTION(BlueprintCallable)` on `APlayerController`, verified in the 5.3
   headers.)
6. Add **Branch**, Condition = its return value.

Wire: `Event Tick` → `Is Valid` → (Is Valid) → `Branch` → (True) →
**`Get Attached Actors`**, which is the first node of the existing chain and is
what the F6 node used to feed. Then Compile, Save, re-cook, rebuild, install.

## Also missing, deliberately noted

Step 5 of `GRAPH_RECIPE.md` — the `Add` that pushes Get Player Pawn onto
`Targets` — is **not in the built graph** (no `Array_Add`, no `Targets` variable
in the cooked name table). The graph walks the pawn's *attached actors* only.
**Moot either way** now that it works: in the practice range the mesh is on an
attached actor, and the lobby fix below replaces the search wholesale.

---

# Roadmap past v1

v1 = asset 1 + the bootstrap, and it is done. What remains, cheapest first.

## 1. Lobby and hero-gallery preview

Today the search is `Get Player Pawn` → `Get Attached Actors`, so **F6 does
nothing wherever there is no pawn** — the lobby, hero select, the gallery. That
is where a skin actually gets judged, so this is the biggest usability jump for
the least work.

Swap both nodes for **`Get All Actors Of Class`** (ActorClass = `Actor`) feeding
the same first `For Each Loop`: three wire drags, no new machinery. Heavy per
press — it walks every actor in the level — but this is a manual keypress, so
heavy is fine.

## 2. Revert, and design variants — ✅ DONE 2026-09-21, no Blueprint work

**Revert was never Blueprint work.** `ImportFileAsTexture2D` returning null is
the "not edited" test, so once a texture has been swapped into the MID, deleting
the PNG and pressing F6 again does *nothing* — `Is Valid` fails and the modified
texture stays. So the old `-Clear` (and the stale-op sweep, which logged "back to
vanilla") **could not undo anything in a running game**, and said it had.

`live_preview.ps1 -Clear` now **writes the vanilla PNGs** into the drop folder
instead of deleting them, from `cache\<skin>\png\src\`. F6 then re-imports
vanilla and the character goes back, with zero new nodes. `-Purge` is the old
delete-the-files behaviour, for cleaning up afterwards.

★ **The gamma trap on that path, honoured:** the cached vanilla PNGs are raw
exports, while the drop folder expects `SkinArt.SaveLivePng`'s pre-compensated
output, or the revert lands washed out. Restore goes through the same writer.
Verified: each restored file is **byte-identical** to a fresh
`Load` → `SaveLivePng(…, 'srgb')`, and sits ~55 luminance off the raw cache PNG,
which is exactly the expected pre-compensation.

**Variants need nothing new either.** `-WatchDesigns` (now what the GUI's LIVE
PREVIEW button launches) follows **whichever design was saved last**, so opening
another design and saving it switches the preview — and the stale sweep reverts
whatever the previous design owned and the new one does not. Tested: Pink (6
textures) → Blue (1 texture) gives "1 live, 5 back to vanilla". An in-game F8
cycler would be a convenience, not a requirement.

Two details that matter if this is ever reworked:

- `_live.txt` is **ours alone** — the Blueprint reads filenames and nothing else
  — so it now carries `leaf|skin|rel|vanilla png|live-or-vanilla`. The vanilla
  path is stored outright so `-Clear` can undo from a cold process with no tex
  index and no cache rebuild, and the 5th column stops a fresh process
  re-reverting files that are already vanilla.
- A manifest in the **old** bare-filename format still reverts: the skin id is in
  the texture name (`T_1064300_Body_D.png`) and the cache is
  `cache\<skin>\png\src\`, so `Find-VanillaPng` recovers the source from the
  filename alone. This mattered — her live folder was in that format.

## 3. Auto-refresh without a keypress

`Event Tick` is unavailable for good (unarranged widget, see the top of this
file), but **timers live on the world, not on Slate**. `Set Timer by Function
Name` / `Set Timer by Event` called once from `Event On Initialized` — which is
proven to run, `SkinLiveInit.sav` — should fire regardless of layout. Untested,
and it is the only cheap way to close the loop fully: save in Skin Studio with
`-Watch` on, and the game repaints on its own a second later.

## 4. v2 — real controls in game

Assets 3 and 4 from the list above: `SS_SettingHandler` deriving
`/Script/Marvel.UISettingEntrySettingHandler`, a CompositeDataTable stacking the
vanilla "Other" rows with ours, and `SettingPageLayoutTable` repointed at it.
Buttons and dropdowns on the real Settings page, no alt-tab.

### Reconnaissance, 2026-09-22 — the plan checks out, with two corrections

Done from files, no launches. Everything v2 needs exists and is located:

| thing | where | note |
|---|---|---|
| `UISettingEntrySettingHandler` | script object, **with a CDO** | ✓ derivable. Sits in a family of ~100 concrete handlers (`UISettingEntryVolumeHandler`, …) — the pattern is exactly as decoded |
| `GraphicSettingEntry` | `/Game/Marvel/Data/DataTable/UI/Setting/GameUserSettingStructure/GraphicSettingEntry` | ★ **a CONTENT UserDefinedStruct, not a script struct** — zero hits in `print-script-objects`. Good news: a DataTable references it by path, so it needs no stub |
| `SettingPageLayoutTable` | `/Game/Marvel/Data/DataTable/UI/Setting/SettingPageLayout/` — **pakchunk0**, not pakchunkUI | 6,195-byte uasset / 610-byte uexp, plain `DataTable` |
| `Other_PageLayoutTable` | `.../SettingPageLayout/Default/` | imported by the above **by full package path** |

★ **Correction: `OtherSettingTable` is a FIELD, not a row.** The name table's
only row-shaped names are `Default`, `PS4P`, `PS5P`, `XBOXS`, `XBOXX` — so
`SettingPageLayoutTable` is keyed by **platform**, and each row holds one
reference per page. On PC the row is `Default`, and `OtherSettingTable` is a
property inside it. (The property names are absent from the file because it is
one of the game's own unversioned packages — positional, so names aren't stored.
Same mechanism as the `WBP_UIDPanel` property block.)

### ★★ Which means the override is a name swap again — no re-authoring

The reference to `Other_PageLayoutTable` is an **import by package path**, and
that path is a plain string in the name table. So repointing it is the *same*
equal-length byte swap already proven on `WBP_UIDPanel`, rather than
re-serialising one of the game's unversioned packages in the editor and hoping
the positional layout survives. `build_live_mod.ps1` already has the machinery.

The arithmetic (derived, not guessed — path **86**, leaf **21**, so a 64-char
folder + `/` + a 21-char leaf):

    victim  /Game/Marvel/Data/DataTable/UI/Setting/SettingPageLayout/Default/Other_PageLayoutTable
    ours    /Game/Marvel/SkinLive/Data/DataTable/UI/Setting/PageLayout/Other/SkinLive_OtherLayouts

Both 86 / 21. Cost of the swap: the vanilla "Other" settings page stops showing
its own rows unless our composite stacks them back in — which is exactly what a
CompositeDataTable is for, so that is a feature here rather than a loss.

**Still unverified, and the next thing to check:** the row struct's field order
(to know which positional slot `OtherSettingTable` occupies), and whether
`CompositeDataTable` can be authored in a stock UE 5.3 project against a
*content* RowStruct we do not have the source asset for. Worth doing only once
roadmap item 1 is proven — this carries its own patch fragility on top of the
panel's, and a second vanilla override doubles the surface a game patch can
break.