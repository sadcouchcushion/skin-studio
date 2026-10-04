SKIN STUDIO - Marvel Rivals character model / skin mod generator
================================================================
Double-click "Run Skin Studio.bat".

WORKFLOW
1. Pick a hero on the left (search box filters). Pick a skin, hit OPEN SKIN
   (or double-click). First open of a skin extracts + renders its textures
   from the game paks (usually under a minute); after that it's instant
   (cached).
2. Click any texture thumbnail. White names = color maps (diffuse/emissive,
   safe to edit). Gray = technical maps (normals/ORM/masks) - locked unless
   you tick the Advanced box.
3. Choose an operation - the right-hand previews update live. Operations
   STACK: the Layers panel (far right) lists what's applied to the selected
   texture, top to bottom. "+ add panel op as new layer" appends the current
   panel settings (e.g. grayscale, then tint, then a hue shift); click a
   layer to load it into the panel, "update layer" saves the tweaks, and
   move up/down reorders. The panel previews as a DRAFT layer until you add
   or update - the amber label under the list tells you which mode you're in.
   APPLY TO THIS TEXTURE still means "exactly this one op" (it replaces the
   whole stack, with a confirm if there were 2+ layers).
   Available operations:
   - Recolor: Tint to color / Flat paint / Hue shift / HSL adjust /
     Grayscale / Invert, with a strength slider and "Protect skin tones"
     (leaves warm face/skin hues alone - ported from the Luna frost grade).
   - Gradient tint / Gradient paint: the color sweeps across the texture -
     top-to-bottom, left-to-right, diagonal, radial, or a 4-corner mesh
     (one color per corner, blended like a gradient mesh patch). Color A is
     the main swatch; B (and C/D for the mesh) appear next to the direction
     picker. Stacks like any other layer.
   - Replace with image: any picture, stretched onto the vanilla canvas.
   - Hand-edit: "send PNG to edit folder" copies the vanilla PNG out for
     Photoshop; save it (same size!) and pick "Use my hand-edited PNG".
   Hit APPLY TO THIS TEXTURE (thumbnail gets a pink dot).
   "bulk apply recolor" pushes one recolor over the outfit in one click
   (LOD2 merge atlas included, so distance colors match). Hair and face/eyes
   are only included if you tick their boxes; weapons/props can be unticked.
   Ctrl-click several thumbnails first to bulk-apply to exactly those.
   Bulk never removes earlier edits on other textures - the status bar warns
   if some remain; revert them individually.
4. Name the mod, BUILD MOD. The build runs in its own window:
   ddstools inject (UE 5.3, cubic) -> rrcli pack -> loose triplet installed
   at ~mods root (S9 rule) + zip in output\ and Downloads.
   Paks mount at game BOOT - restart Marvel Rivals to see it. With Project
   Galacta installed there is no restart: see PROJECT GALACTA below.

COLORS - MATERIALS (lighting / emissive / rim / tint / eyes) + PARTICLES (VFX)
- Top of the grid: [ Textures | Materials | Particles ] toggle.
- MATERIALS lists every named color baked into the skin's material instances -
  rim-light, emissive/glow, base tint, cel-shade, eye colors. Each row shows a
  swatch of the current color; "(lobby)" rows are the hero-select PREVIEW
  materials, the rest are the IN-MATCH ones (BaseTint is the strongest - it
  tints the whole surface). First switch extracts + reads the materials
  (~10-15s; cached).
- PARTICLES lists each ability EFFECT (one row per Niagara color-over-life
  gradient). Picking a color retints that whole effect's gradient to your hue,
  keeping its brightness ramp and fade (an icy-blue trail becomes a magenta
  trail of the same shape). First switch reads all the skin's VFX (~30-40s;
  cached).
- Click a row, "pick color...", APPLY COLOR (row gets a pink dot). Picker is
  sRGB; values stored linear + HDR-aware. "revert this color" undoes one.
  Bulk: "retint ALL shown" (and, for materials, "rim/emissive only").
- 3D PREVIEW (below) shows BaseTint and the dye regions on the model; rim
  light, emissive and particles still only show in game - the swatch is the
  intended value, verify in-game after building. Color edits ride in
  the SAME mod as texture edits (BUILD MOD packs all); color-only mods build too.
- Under the hood: SkinColorTool (colortool\, .NET 8 + UAssetAPI + Marvel.usmap).
  Materials = FLinearColor params; particles = the ColorCurve ShaderLUT (baked
  gradient). Load+re-serialize round-trips Rivals assets byte-identical, so only
  the touched floats change. No blueprints packed - S9-safe like textures.

3D PREVIEW (Model card, bottom right)
- 3D PREVIEW opens a window with the character wearing your design. Drag to
  orbit, wheel to zoom, right-drag to pan; Front / Back / Spin / Bg buttons
  (keys F, B, T). It follows your edits by itself: APPLY, revert, a colour
  change or opening another skin re-renders it within a couple of seconds,
  re-baking only the maps that changed.
- Shows: every colour map with your layers, BaseTint, and the DYE regions
  (a recolour's colour lives in its material - Viridian Vibes only looks green
  because of them). Dyed zones are drawn flat, the way the game paints them.
  Not shown: rim light, emissive, particles, the game's cel shading.
- A recolour (chroma) has no body of its own - the preview borrows its
  costume's mesh and dresses it with the recolour's materials.
- Needs Atelier installed (see ATELIER below): the mesh comes from its
  AtelierMesh decoder, about 10 s the first time per skin, cached after that
  in cache\<skin>\mesh\. The window is WebView2 + three.js (viewer\) reading
  straight from this folder - nothing listens on a network port.
- RS_SS_SMOKE=19 is the regression (off-screen window, APPLY, re-render).

BLENDER (view + paint on the 3D model)
- OPEN IN BLENDER (bottom-right group): bakes your current design onto
  full-res textures and opens the character in Blender (Steam install)
  wearing your mod. The mesh is decoded automatically with Atelier's
  AtelierMesh (same cache as 3D PREVIEW). Without Atelier it falls back to
  the old one-time FModel export (C:\rs\tools\FModel, preconfigured for
  Rivals; mappings at blender\Marvel.usmap) - Skin Studio watches the export
  folder and launches Blender automatically when the mesh lands.
- "what paints this?" uses the same automatic mesh, so it works on any skin
  now, including patch-only ones like Jubilee's Vampy Jammies.
- In Blender: sidebar (N key) > "Skin Studio" tab. Texture Paint mode
  paints directly on the model; "Send paint to Skin Studio" exports your
  painted maps, then "import painted textures" in the studio turns them
  into hand-edited ops (they replace any recolor stack on those textures).
- Changed your layers? "refresh textures in Blender" rebakes, then click
  "Reload textures" in Blender's Skin Studio tab.
- Geometry edits stay in Blender: meshes cannot be shipped back into the
  game with this pipeline (texture mods only - that's what keeps it safe).

LIVE PREVIEW IN GAME (F6)
- Judge a colour on the real model, in real light, without building a pak or
  restarting the game. LIVE PREVIEW sits beside BUILD MOD in the Build card:
  it writes your current design out as PNGs to
  <game>\Marvel\Content\SkinStudioLive\, one per edited texture, named after
  the vanilla texture. Then press F6 in game and the character repaints.
- Keep it running while you work: it re-exports every time you save a design
  (about 4 s cold, 1 s when nothing changed). THE LOOP:
      1. tweak a layer, click "save design"
      2. in game, if this character already changed this match, switch to
         another hero and back first (see below)
      3. press F6
  Use "save design", NOT Build Mod. Build Mod only seemed to work for this
  because it saves first; the build itself takes minutes and makes a pak the
  running game never loads (it will not even install while the game is open).
  Build Mod is for the END, with the game closed.
- F6 only changes a character ONCE per match for now. After the first press the
  game renames the swapped texture, so a second press finds nothing. Switching
  hero and back (or leaving and re-entering the range) gives you a fresh copy
  and F6 works again. A fix is planned; see ingame\ and GRAPH_RECIPE.md.
- LIVE PREVIEW is sticky: if it was on when you closed Skin Studio, it turns
  itself back on next time. (It used to switch off silently on close, and every
  save after that went nowhere.) "save design" now also tells you in the status
  bar whether your save reached the game.
- Comparing variants is just saving: whichever design you saved LAST is the one
  that goes live, so open another design, save it, press F6 and you are looking
  at that one instead. Textures the old design edited and the new one does not
  go back to vanilla on their own.
- NO KEY NEEDED WHEN YOU SPAWN (in-game mod from 2026-09-27): while LIVE
  PREVIEW runs, the in-game mod tells Skin Studio every time you spawn as a
  hero. Skin Studio picks the newest design made for THAT SKIN (not just that
  hero - a second skin of the same hero used to stay vanilla) and puts it on
  the hero by itself, a second or two after you spawn. A skin with no design
  simply stays as it is. First time on a skin, Skin Studio has to prepare it
  (up to a minute or so) before the colours arrive.
- LIVE PREVIEW IN GAME, NO APP NEEDED (2026-09-27): the in-game panel (F8)
  has the same LIVE PREVIEW button. Off, F8 shows one screen with "Turn on
  live preview"; on, it is the toggle at the top of the panel's home screen.
  Turning it off puts the game's own skin back on your hero straight away (no
  F6). The app's button and the in-game one are the SAME switch (the file
  work\live_preview.on) - flip either, the other follows within a second or two.
  How it works without the app: a small helper with no window
  (ingame\helper.ps1) waits for Rivals. While Rivals runs it starts the
  watcher - hidden - when live preview is on, or when you press F8 with it
  off, and that watcher ends when Rivals closes. Only one watcher ever runs:
  the app's own window, or the helper's. The app starts the helper when it
  opens; for no-app play the helper also needs to start with Windows (a
  shortcut in the Startup folder). Logs: work\ingame\helper.log and
  work\ingame\watcher.out. Rig test: Temp\rs\livetoggle.ps1 (31 checks).
- PRESS F6 IN A MATCH - the practice range is the place. In the lobby, hero
  select and the gallery there is no character actor to find, so F6 looks
  broken when it is working fine. (Lobby support is a planned change.)
- One-time setup: the in-game half is a tiny mod of its own. Build + install
  with   powershell -File ingame\build_live_mod.ps1 -Install
  Back it out by deleting SkinLive_9999999_P.pak/.ucas/.utoc from the game's
  Paks\~mods folder. If you use Vortex, let Vortex deploy FIRST and install
  this last - a redeploy sweeps loose files out of ~mods.
- Unlike a skin mod, this one DOES pack a blueprint, so treat it as the
  riskier of the two and pull it before a game patch. It is also the only
  part that needs re-testing after one.
- To undo: click LIVE PREVIEW again (or run live_preview.ps1 -Clear) and press
  F6 once more. It writes the VANILLA textures back out rather than deleting
  the PNGs, because deleting them cannot undo anything - a missing file just
  means "not edited", so the game keeps whatever it already loaded. That is
  also why turning it off takes a second or two instead of being instant.
  -Purge empties the folder without undoing anything, for when you are done.

PROJECT GALACTA (swap a new build in without restarting)
- If Project Galacta (Nexus 12806) is installed and enabled, and Rivals is
  running when a build finishes, Skin Studio swaps the new mod in through
  Galacta instead of waiting for a restart. Both BUILD MOD (desktop) and the
  in-game panel's Build mod button do it:
      1. Galacta's F7 unloads your mods - Skin Studio presses it FOR YOU
         through the in-game mod (2026-09-27), the game lets go of the old
         copy, and the new build goes in at once (a chime from the build
         window)
      2. F7 again, also pressed for you - Galacta reloads your mods (a second
         chime once the game really has it)
      3. you enter or leave a match or the Practice Range - the game shows
         the new build after a level change. That is Galacta's own rule;
         loaded assets stay until their level goes.
  If the game does not answer within a few seconds (an older in-game mod, or
  no Galacta loader), the screen asks you to press F7 yourself instead. The
  in-game mod's panel key is F8, so F7 belongs to Galacta alone.
  The whole mod comes along, material and particle colours included.
- "Installed" means Galacta's .pak/.utoc/.ucas are in the game's Paks folder
  (loose, ~mods, or a Vortex/Repak X folder). Disabled in Vortex (only in its
  staging folder) or renamed .bak_repak = not installed.
- Without Galacta, a build never touches the skin in the running game
  (2026-09-27). The in-game Build mod button installs it into ~mods (or, if
  the old copy is in use, when you quit Rivals) and it shows at your next
  launch; the live preview keeps your edits on the hero until then. The
  desktop BUILD MOD already worked this way.
- A mod that is NEW this session (it was not in ~mods when you logged in) most
  likely waits for your next launch: Galacta's F7 reloads the list of mods it
  found at login. Skin Studio watches what the game actually opens and tells
  you which way it went.
- Nothing is ever half-replaced: the new files are staged in
  <game>\Marvel\Content\SkinStudioSwap\ and renamed into ~mods only once the
  game has let go of the old ones. Esc in the build window (or "Stop waiting"
  in game) gives up; in game, the mod then goes in when you quit Rivals.
- Details: galacta.ps1. Rig tests: Temp\rs\galtest.ps1 (the helpers),
  galpanel.ps1 (the in-game panel), galbuild.ps1 (a real build).

NOTES
- Designs save to designs\<ModName>.json - reload any time, tweak, rebuild.
- Rename buttons: hero/skin ID labels are editable (heroes.json/skins.json);
  unknown "Hero 10xx" entries are the newer roster - open one, look at the
  textures, name it.
- A game update invalidates caches automatically (pak timestamp check).
- Headless rebuild: powershell -File build_skin.ps1 -Design designs\X.json
  -Install -Zip [-Version 1-1]
- Never edit technical maps with color ops unless you know why; that's what
  the Advanced lock is for.
- Texture mods are S9-safe (no blueprints are ever packed). The in-game live
  preview above is the one exception, and it is a separate container you can
  remove on its own.

THE LOOK
- The studio wears Variant UI's chrome in a light sage green instead of the
  logo pink: same neutral-grey surfaces, same rounded owner-drawn buttons and
  cards, same hand-painted sliders / drop-downs / colour picker, same dark
  title bar, same Black Ops One display face (bundled under the SIL OFL in
  branding\, credit in BlackOpsOne-OFL.txt).
- vuistyle.ps1 holds all of it and is GENERATED - do not hand-edit it. It is
  assembled out of C:\rs\ThemeStudio\ThemeStudio.ps1 line-for-line by
  build-vuistyle.ps1, so a fix made in Variant UI ports over by re-running:
      powershell -File build-vuistyle.ps1
  The three hand-written pieces (palette, type/branding, brand band + status
  bar) live in vuistyle.parts\ - edit those. To re-skin the whole studio,
  change the four Sage* entries in vuistyle.parts\palette.ps1 and rebuild.
- Branding art (the sage Variant lockup, the V badge, the window icon) is
  generated too: branding\build-branding.ps1 recolours the pink originals in
  ThemeStudio\branding. Re-run it after any logo change over there.
- Known, and shared with Variant UI on Windows 11 26200: list scrollbars,
  NumericUpDown spinners and checked tick-boxes are drawn by the OS visual
  style and come out light. uxtheme's dark-mode ordinals (SetPreferredAppMode
  / AllowDarkModeForWindow) no longer take on this build - AllowDarkModeForWindow
  returns False - so nothing in either studio can recolour them short of
  owner-drawing those controls.
- build-vuistyle.ps1 AST-checks the module it assembles and refuses to write one
  with a dangling reference. That guard exists because lifting line RANGES can
  leave a function reaching for a Variant UI global declared just outside its
  range - which is not a parse error, so it only shows up when you click the
  thing. That is what broke the colour picker once ($tt, $form).

LINKED MAPS (⇄) - why a recolor can only half-change in game
- Plenty of skins ship the SAME map two or three times under different names,
  because one skin folder holds more than one character form or costume state:
    1011001  T_1011001_1011_Body_D / _1012_ / _1013_   (Hulk, Banner, enraged)
    1060500  Textures\10600\T_10600_1060500_Equip_02_D
             Textures\10601\T_1060500_SpiritualFox_Equip02_D
  Recolor one and the others stay vanilla, so in game the mod changes on one
  form and not the other. 162 of 671 skins have at least one such pair.
- The studio marks those textures with ⇄ in the browser (hover for the names)
  and shows a tick box in the op panel: "also apply to the other version".
  Anything you apply, update, bulk or revert is carried across while it is on.
- Certain vs possible. If the names differ only by id numbers or by folder, it
  is the same artwork - the box is ticked for you and BUILD MOD offers to fill
  in any you missed. If the names differ by a WORD (SpiritualFox, Girl/Robot,
  GiantUAV/MicroUAV) it may or may not be the same thing, so the box is shown
  unticked - look at the two thumbnails and decide. Names that differ by a word
  AND sit in the same folder are never linked at all: that shape is always
  separate props (Bow/Quiver/Sword, Grenade/HandGun).
- build_skin.ps1 prints the same warning for a design built from the command
  line. RS_SS_SMOKE=5 is the regression test for all of it.

RECOLOR CHROMAS - one mod that covers the costume AND its recolors
- A chroma is a recolour of a costume sold as its own skin id, with its own copy
  of every map: Vampy Jammies 1064300 + Viridian Vibes 1064301 + Blue Breezes
  1064302. Edit the costume alone and every chroma of it stays vanilla in game.
- Open a costume that has recolours and two tick boxes appear under the SKINS
  list: "also edit its N recolors" (ticked) and "+ N possible recolors"
  (unticked). While ticked, everything you apply, layer, bulk or revert is
  carried onto the same map of those skins, and BUILD MOD ships all of them in
  ONE mod - the build log lists each skin it covers.
- Ticking is a statement about the whole design, not just the next edit: tick it
  and what you have already edited is carried across too; untick it and those
  copies are dropped again. Opening an older design with the box ticked extends
  it to the recolours (the status line says how many maps).
- What gets carried is the FINISHED ART, not the recipe. The costume's edited map
  is rendered to a PNG (work\chroma\<skin>\) and that same image is dropped onto
  the recolour, so all of them show exactly what you designed. Re-running the
  recipe on the recolour's own art instead would land on a different colour on
  every one of them.
- Their DYE COLOURS are re-aimed at the same time, and that is the part that
  actually made this work. A chroma's colour does not live only in its texture:
  its materials carry per-region dye colours ("Region 1 - ColorA/ColorB",
  "Region N - Color<R|G|B>Channel") picked by a _ColorID mask the costume itself
  does not ship, and the shader multiplies them over the diffuse. Viridian Vibes
  is green because MI_1064301_Body's Region 1 is #62A488 / #A1F8D3, while
  MI_1064300_Body has no Region params at all. Copy the art across and leave the
  dye alone and it comes out re-tinted - a brown paint job went muddy green in
  game.
  Setting them WHITE is not the answer either (v1-1 of Toasty Jubilee did, and
  the outfit went pale): the shader PAINTS those zones rather than tinting them,
  which is why a chroma's own art is desaturated there in the first place.
  Blacking out the _ColorID mask does NOT switch dyeing off either - proven in
  game: black selects "no region" and the zone renders WHITE. The mask is left
  alone. In a dyed zone the dye REPLACES the art (flat cyan art under a white
  dye rendered white), so the dye colour is the only lever there, and it is set
  to the design's own colour - the finished art averaged over the pixels that
  material's mask dyes - for the in-match AND lobby copy of each material.
  Everything the mask does not dye (skin, face, hands) shows the copied art
  exactly.
- Every map the two share is copied when its vanilla bytes differ - not only
  _D/_E/_S. Colour hides elsewhere too: Blue Breezes tints its hair through
  Hair_AO. Identical maps are skipped, so the mod stays small.
- Each dye REGION is coloured separately, so the shorts take the shorts' colour
  and the jacket the jacket's; the mask's green and blue channels mark sub-zones
  inside a region (the patches on the jacket) and are sampled separately again. The region lives in the _ColorID mask's ALPHA
  channel in steps of 255/7 (0 = undyed, 36 = region 1, 73 = 2, 109 = 3, 146 = 4,
  182 = 5, 219 = 6, 255 = 7); the RED channel is the light/dark ramp inside a
  region, so "Region N - ColorA" is sampled from the design over that region's
  dark pixels and "- ColorB" over its light ones. A region the mask never dyes
  is left alone.
  The switch that would turn dyeing off altogether (UseDyeing) is a STATIC
  SWITCH: flipping one on a cooked material orphans its shader map and the
  material silently stops rendering, so it is left alone.
  Only real dye colours are touched: HDR values, HSV control triples, direction
  vectors, shade ramps, and anything already white/black/grey are left alone.
- Which skins count as recolours is measured, not guessed: a recolour reuses the
  costume's technical maps (normals, ORM, metal/roughness, hair alpha) byte for
  byte, and the pak index carries a content hash per file. >=80% of the shared
  technical maps identical = certain; 50-80% = possible (those share the mesh but
  may be their own costume - Jeff's default and Gwenpool land there). 97 groups
  covering 246 skins on the S10 roster; the grouping is cached in
  cache\chroma_groups.json and rebuilt after a game update.
- The result differs per chroma, because each one's base art is different - a
  tint over Viridian Vibes' green is not the same colour as over the purple
  original. Check the chroma's own thumbnails by opening it directly.
- A prop that only the base costume ships (Vampy Jammies' balloon and pillow)
  is shared by the chromas in game, so editing it once already covers them.
- RS_SS_SMOKE=13 is the regression test for all of it.

SPECULAR MAPS (_S) - where "pearlescent" lives
- A part can look pearlescent / metallic / tinted-shiny in game while its color
  map (_D) is almost neutral. The colour of the SHINE comes from the _S map,
  which the material binds to its SpecularTexture parameter.
  White Fox 1060500 is the clean example: the tie and headphones are near-white
  silver in T_10600_1060500_Equip_01_D, and T_10600_1060500_Equip_01_S paints a
  magenta rim on the tie (hue ~300) and blue on the headphones (hue ~206-240).
  That pair is what reads as "pearlescent purple/silver".
- So _S counts as a COLOR map here, not a technical one - it is editable without
  the Advanced box, and the browser shows it white like a _D. Only normals, ORM
  and masks stay behind Advanced, because colour ops on those break shading.
  To move a part's whole look you normally recolor BOTH its _D and its _S.
- Category bulk-apply still sweeps _D/_E only, so a bulk recolor will not
  silently change every sheen in the skin. To bulk several _S maps, ctrl-click
  them and use bulk apply on the selection.
- Roles are recomputed when a skin is opened, not read back from thumbs.map, so
  changing SS-TexRole takes effect on already-cached skins without a re-extract.

COLOR FAMILY: PICKING THE BAND BY HAND
- "Recolor color family" moves ONE hue band and leaves everything else alone.
  Which band used to be auto-detected from the whole image - right for a texture
  with one obvious subject, useless on a shared atlas where a cap, badges, a red
  top, a tie and headphones sit on one sheet and you only want the magenta.
- In that mode the "Hue shift" slot becomes a "Color family" button reading
  "auto" or e.g. "300° ±25". Click it for the picker:
    * left pane  - the texture with everything OUTSIDE the band dropped to grey,
                   so the selection is literally what you see. Click a pixel to
                   take the band from it.
    * hue strip  - click or drag to set the centre; the band is drawn on it.
    * Centre / Width sliders, a live "selects N% of this texture" readout, and
      "detect again" for the old automatic behaviour.
    * "Detect the family automatically" keeps it on auto (what it always did).
- The preview mask comes from SkinArt.BandPreview, which feathers exactly the
  way the real op feathers, so what you see selected is what gets recolored.
- Stored in the design as bandCenter (-1 = auto) and bandWidth (0 = the 34°
  default), both optional - designs saved before this reload unchanged as auto.
- RS_SS_SMOKE=6 is the regression test: on White Fox's specular atlas it checks
  that band 300 moves the magenta and leaves the green, band 140 does the
  reverse, an op with no band keys still behaves as auto, and the panel carries
  the band into an op and reads it back.

WHEN A PART IGNORES THE TEXTURE ENTIRELY (BaseTint)
- A material can multiply its texture by a flat colour, and then no amount of
  repainting the texture will move it. White Fox 1060500: the tie and crop top
  are MI_10600_1060500_Laser_02 with BaseTint #442640 (dark violet), so gilding
  T_10600_1060500_Equip_01_D changed nothing on them - while the headphone ear
  cups, on MI_10600_1060500_Equip_01 with BaseTint #FFFFFF, followed the texture
  fine. Fix that kind in the Materials browse mode, not Textures.
- Material params come in lobby + in-match pairs, like textures do. Change both.
- To find out which material owns a part, don't read the atlas by eye - render
  it. C:\rs\_sagelook\matid.py flat-colours every material on the skin's mesh
  and writes a legend; matuv.py renders one material's UVs as colour so you can
  read a part's exact atlas coordinate. Both need the Blender bridge's FModel
  export of the mesh, and Blender's view transform set to Standard or the
  colours come back shifted.

"WHAT PAINTS THIS?"  (Blender card)
- Click a part of the model and the studio tells you what actually colours it:
  the material that owns it, that material's non-white colour parameters (the
  ones that MULTIPLY the texture and beat anything you paint), every texture it
  binds with your edits marked, and the exact spot on the atlas the point came
  from - with a crop of it.
- Both panes are LISTS you pick from. Select a colour parameter and "open this
  colour in Materials" takes you to that exact row - right material, right
  parameter, right copy - with the op panel already pointed at it, ready for a
  new colour and APPLY COLOR. Select a texture and "select this texture in the
  browser" does the same for the Textures tab. Double-click does either.
- Every copy of the material is listed separately (in-match and lobby), because
  both have to be changed - the list is how you get to each one.
- RS_SS_SMOKE=9 plus RS_SS_PAINTIDSHOT=<png> draws the dialog to a file without
  ever opening a window; that is how its layout gets checked. NB a RichTextBox
  renders blank under DrawToBitmap, which is why the summary is a Label.
- It needs the skin's mesh, i.e. the same one-off FModel export OPEN IN BLENDER
  walks you through. First use per mesh runs Blender headless for ~30s and
  caches four renders under cache\<skin>\paintid\; after that it is instant.
- How it works: blender\paintid.py renders the mesh twice - once with every
  material a distinct flat colour (which material owns a pixel) and once with
  every material outputting R=U, G=V (where in its atlas that pixel came from).
  Two passes total, whatever the material count. The view transform must be
  Standard or the colours come back shifted and the lookup is guesswork, and the
  legend is linear while the PNG is sRGB, so convert before comparing.
- Hex values shown match the Materials list (SkinArt.LinearToHex) - material
  params are stored LINEAR, so raw x255 would print a different, useless number.
- RS_SS_SMOKE=7 is the regression test: it checks White Fox's tie resolves to
  MI_10600_1060500_Laser_02 with its BaseTint flagged, and that a material whose
  tint IS white is not flagged.
- Fixed in passing: Find-SkinGltf looked for SK_<hero>_<skin>*, but meshes are
  often named for the CHUNK (SK_10600_1060500_Lobby), so both this and OPEN IN
  BLENDER used to report "no mesh export" for those skins.

BLENDER: MATERIALS THAT CAME UP UNTEXTURED
- bridge.py used to work out each material's texture from its NAME
  (MI_x_Equip_01 -> T_x_Equip_01_D), which is right for most materials and
  silently wrong for the rest. White Fox's MI_10600_1060500_Laser_02 - the tie
  and crop top - draws from T_10600_1060500_Equip_01_D, and there is no
  "Laser_02" texture at all, so it fell through to flat grey. Same for Laser_01
  and Laser_03.
- SS-BakeBlenderTex now writes _matmap.json beside the baked textures: the REAL
  material -> texture binding, read out of the MI packages (SS-EnsureMatTextures).
  bridge.py prefers it and only falls back to name matching for older bakes.
  Its log line says how many were bound from the map vs guessed - the White Fox
  lobby mesh went to 12 bound, all 12 from the map, 0 guessed.
- Materials with no diffuse at all (the fox-tail VFX, Eyes_02, the rim shells)
  still get the existing invisible / neutral / glassy treatment. That is correct:
  they are driven by colour parameters, not textures.
- SS-LoadColorMap now scans the WHOLE skin folder for MI_ assets, not just
  <skin>\Materials\. Props keep their materials beside them
  (Weapons\Tail\Materials\..., the MVP laptop) and those were missing from the
  Materials list as well as from the bridge. The material caches carry an 'm2'
  stamp suffix so they rebuild once after this change.
- NOTE Blender shows the TEXTURE, not the game's material tint. A part with a
  coloured BaseTint (the tie) looks like your painted texture in Blender and
  like texture x tint in game - which is exactly how the White Fox tie fooled
  everyone. Use "what paints this?" to see the tint.

MATERIAL COLOURS: WHAT IS SAFE TO EDIT
- UE stores a lot of things as FLinearColor that are NOT colours: light
  DIRECTIONS, world POSITIONS, tangents, and packed parameter triples. Picking a
  colour for one of those clamps it into 0-1 and wrecks the material. White Fox
  got retinted with 305 sites, of which 102 were MC_Shade ramp steps, plus
  PortalCenter (vanilla 10,000,000 / 457,515 / 6,201,983), TangentA/B and two
  light directions - and the skin came out broken in game.
- Two gates now decide what the Materials list even offers:
    1. the NAME must not look like a vector or a parameter pack (direction, dir,
       tangent, center, position, axis, tiling, param, mix, range, power,
       offset, fresnel, mask, uv, depth, bias, multiplier, intensity, roughness)
    2. the vanilla VALUE must sit inside 0..1 - anything HDR or out of range
       cannot be expressed by an sRGB picker, so it is not offered
  The value gate is the important one: a name list will always miss something.
- MC_Shade is the cel-shading ramp (3-4 grey steps per material that define how
  light falls off). It stays editable one at a time, but "retint ALL shown" now
  skips it - retinting the ramps is what flattens a skin.
- Designs saved before these rules carry the bad edits. They are pruned when the
  Materials list loads, and again at BUILD MOD with a dialog telling you how many
  went - so an old design cannot ship them. Rebuild after opening one.
- RS_SS_SMOKE=10 is the regression test.
- The colour PIPELINE itself is sound and was verified here: a patch changes only
  the colour floats (uasset byte-identical, uexp differs by 11 and 24 bytes),
  and the packed container carries those bytes through unchanged.

WHAT A RECOLOR'S DYE COLOURS REALLY DO  (settled in game, v1-9 probe)
- A dyed zone REPLACES the art with the dye colour. Proven by shipping a white
  dye on one recolor: the zone rendered a flat neutral (#91908F where the
  costume reads #8C5F47), not the art underneath. So the value to write is
  simply the design's own colour over that zone - nothing to multiply, nothing
  to compensate for.
- That white dye doubles as a LIGHT METER: it renders the lighting at that
  pixel on its own (L = 0.279 there), which makes every other prediction
  checkable. With L known, the raw sample predicts byte 100 and 126 at two
  points where the shots measured 94 and 123.
- Sample the art RAW: byte/255 IS the linear value. These maps are
  linear-flagged (the gamma landmine above), so running SrgbToLinear over them
  before writing a linear dye param converts twice and lands the zone about
  2.5x too dark - the costume's shorts read 140 while the recolors read 57.
- The dye colours that paint the bright accents have components ABOVE 1
  (0.47/2.00/0.36 green patches, 0.98/1.33/1.50 leg warmers). The "is this
  really a colour" gate refuses anything outside 0..1 - right for light
  DIRECTIONS, wrong here - so SS-IsRegionDye lets a param named
  "Region N - ColorA/B/GChannel/BChannel" through whatever its value. Do NOT
  scale the new colour up to the vanilla's brightness: that was tried in v1-8
  and makes zones glow that the costume does not.
- A dyed zone renders FLAT - one colour per region, ColorA to ColorB along the
  mask's red ramp - so it cannot carry painted fabric detail. SS-SampleDyeRegions
  pulls saturation back to the mean of the pixels' own saturation (averaging
  shaded pixels greys the mean), luminance held, capped at 1.6x.
- The costume itself has NO region dye params at all (0, against 280 on each of
  its recolors), so "copy the costume's dye block across" is not an option.
- To check a built mod without launching: rrcli unpack its MIs -> SkinColorTool
  dump -> diff against the skin's colors.json. work\_chk7\verify.ps1 does it.
- A dyed zone takes ONE colour for a whole region, and a region covers more of
  the atlas than is ever on screen, so the average sampled for it comes out
  diluted - Jubilee's shorts landed about half as warm as the costume's. There
  is no offline fix: visibility is a render question. CALIBRATE RECOLOURS is
  the answer, and it is built in - the "calibrate…" button beside the recolour
  tick box, or SS-SolveDyeCal from a script.
    1. BUILD THE METER MOD (in the dialog, or build_skin.ps1 -DyeMeter). Every
       recolour dye becomes 1,1,1. White paints nothing of its own, so the
       recolour now renders the LIGHTING - a photograph of the light landing on
       each dyed pixel. Install it and restart Rivals.
    2. Three screenshots in the hero gallery, same camera and pose: the costume,
       one recolour, and that recolour again with the meter installed.
    3. MEASURE AND SAVE. For every pixel the recolour paints differently from
       the costume: recolour/meter is the dye actually painting it - which is
       how a pixel finds WHICH dye param owns it, so no region ids are needed
       anywhere - and costume/meter is the albedo it should carry. The lighting
       cancels, so the scene light never has to be known or held constant
       between shots.
  The corrections land in the design as dyeCal, keyed by material and region
  (not by colour), so they survive re-sampling the design against new art. Every
  later build applies them; the meter build never does.
- THE CHECK THAT IT IS WORKING: the measured dye comes back equal to the value
  the design wrote (0.433/0.315/0.264 against 0.437/0.308/0.233 on Jubilee). If
  those disagree, the shots are misaligned or they are not the same pose - fix
  that rather than trusting the numbers. The dialog flags it per zone.
- Measured on Jubilee: the dark browns wanted about twice the red (shorts x2.14,
  chest patch x2.40), everything else about 15%. Zones that never showed on
  screen take the median correction rather than being left behind cool.
- Two traps worth knowing. The aligner locks onto a patch of BACKGROUND in the
  upper right, so a pattern that REPEATS gives it ties and it picks a shifted
  answer - which silently crosses one zone's pixels with another's. And reading
  a render against a region AVERAGE will mislead you: a point on the costume's
  shorts sits on a highlight (art ~0.92) while the region averages 0.45, which
  made the dye look like it multiplied the art for an hour. Compare like with
  like, or let the meter do it.
- RS_SS_SMOKE=16 is the regression: it paints three synthetic shots from known
  numbers, checks the solver recovers the dye it was given, that applying the
  answer lands the design within 0.05 of the albedo the costume shows, and that
  a meter build is white and carries no calibration. RS_SS_SMOKE=17 (plus
  RS_SS_CALSHOT=<png>) builds the dialog headless, checks nothing sits outside
  it or on top of anything else, and draws it to a file.
- To check a built mod without launching: rrcli unpack its MIs -> SkinColorTool
  dump -> diff against the skin's colors.json. work\_chk7\verify.ps1 does it.
- Read the title strip to tell which skin a screenshot holds - the order they
  were posted in is not always the order they were taken.

ONE MOD PER SKIN - ALWAYS  (a costume and its recolours, built separately)
- A design that carries a costume's recolours ALWAYS builds as one mod per skin
  (the standing rule from 2026-09-22), so a player can take the look on one
  recolour without it landing on the rest. There is no tick box: BUILD MOD and
  build_skin.ps1 both split by themselves, and the status line says how many
  mods are coming.
- The one exception is build_skin.ps1 -Combined, which the calibration dialog
  uses for the METER - a throwaway measuring install, not a mod to keep.
  (-PerSkin is still accepted from old scripts; it changes nothing.)
- If a design was shipped COMBINED before, its old container would load
  alongside the split mods - the build log warns when it finds one installed.
  Remove it in Vortex (or "uninstall all my mods"); the builder never deletes
  anything in ~mods itself.
- Every op already carries its skin id in its rel, so the split is a filter
  (SS-SplitDesignBySkin), and each piece is built by an ordinary run of
  build_skin.ps1 from work\_split\ - NOT designs\, so the pieces stay out of
  the Designs list. -Install / -Zip / -Version / -DyeMeter pass through.
- Naming: the mod name gets the skin's name appended (ToastyJubilee ->
  ToastyJubileeViridianVibes), so the containers can never collide, and the
  display name gets " - Viridian Vibes".
- It splits cleanly because a recolour is self-contained: on Jubilee, 0 of the
  recolours' 22 materials reference a costume texture. Worth re-checking on a
  new family before trusting a split (SS-EnsureMatTextures on the recolour,
  look for the costume's id).
- PROPS THE FAMILY SHARES live under the COSTUME's id (Jubilee's balloon and
  pillow are T_WP_1064300_*) and are used by all three skins, so they go in the
  costume's mod. Then no two split mods ever override the same file - but
  installing only a recolour's mod leaves those props vanilla.
- A calibration (dyeCal) is keyed without skin ids, so every piece carries it.
- RS_SS_SMOKE=18 is the regression; RS_SS_SMOKE=14 also fails on overlaps inside
  the Build card.

ATELIER (the free Rivals skin editor) - working alongside it
- Atelier (github.com/clownfetus/Atelier, GPL-3.0) is installed separately at
  %LOCALAPPDATA%\Atelier. Skin Studio RUNS three of its tools as outside
  programs and copies none of its code, so nothing about Skin Studio's own
  licence changes:
    Tools\AtelierMesh\AtelierMesh.exe  mesh -> .glb (3D PREVIEW, Blender, paint-ID)
    Tools\UAssetTool.exe               material <-> JSON (import / export)
    Tools\Mappings\*.usmap             the newest mappings (SS-BestUsmap)
- "import Atelier…" (above the Layers card) turns an Atelier project into a
  design. Only what differs from vanilla comes across: untouched imports are
  dropped (no byte off by more than 3 - a small painted logo still counts),
  edited PNGs are copied into imports\<Design>\ so later work in Atelier does
  not change the design behind your back (import again to pick it up), and
  material colours become colour edits. A changed value that is NOT a colour
  (Atelier shows packed settings like FXLobby_CommonFresnel_Param as colour
  pickers) is listed and left out, never carried silently.
- "export to Atelier…" saves the design, then writes it as a NEW Atelier
  project: full-size art with your layers, and every colour edit patched into
  its material. It never overwrites an existing project.
- Lossless both ways, verified on Toasty Jubilee: 23 layers came back
  byte-identical and 248 of 248 colours exact. RS_SS_SMOKE=20 re-checks it in
  work\_smoke20 (never designs\ or Atelier's own folder).
- Atelier's PNGs hold the same bytes as ours; only the tag differs (ours say
  gAMA 1.0, theirs carry none). Export strips the tag to match theirs.
- NEVER delete %LOCALAPPDATA%\Atelier\_cache\vanilla_paks by hand. It is a
  folder of HARDLINKS to the game's own paks - the same setup as the
  _patchdiff\minipaks folder whose recursive delete took the game's 73 GB.
  Skin Studio only reads it (and only when it matches the game exactly).
