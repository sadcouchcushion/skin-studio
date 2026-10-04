# Skin Studio <-> Blender bridge.
# Launched by Skin Studio:  blender --python bridge.py -- --gltf <mesh> --texdir <baked> --editdir <out> --skin <id>
# Imports the FModel glTF, rebinds every material to Skin Studio's baked design
# textures, and adds an N-panel (View3D > sidebar > "Skin Studio") with:
#   - Reload textures   (after "refresh textures in Blender" in the studio)
#   - Send paint to Skin Studio  (saves painted images into the studio's edit
#     folder; back in the studio hit "import painted textures")
import bpy, sys, os, re, json, shutil

def _args():
    a = sys.argv
    if '--' not in a:
        return {}
    tail = a[a.index('--') + 1:]
    return dict(zip(tail[::2], tail[1::2]))

OPTS = _args()
GLTF = OPTS.get('--gltf', '')
TEXDIR = OPTS.get('--texdir', '')
EDITDIR = OPTS.get('--editdir', '')
SKIN = OPTS.get('--skin', '?')

def norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())

def build_texmap():
    tex = {}
    if os.path.isdir(TEXDIR):
        for f in sorted(os.listdir(TEXDIR)):
            if f.lower().endswith('.png'):
                tex[norm(f[:-4])] = os.path.join(TEXDIR, f)
    return tex

def load_matmap():
    # {material name: baked png filename} written by SS-BakeBlenderTex from the
    # MI packages themselves. Authoritative - name matching below is only a
    # fallback for older bakes that predate the file.
    p = os.path.join(TEXDIR, '_matmap.json')
    if not os.path.isfile(p):
        return {}
    try:
        import json
        with open(p, 'r') as f:
            raw = json.load(f)
        return {norm(k): v for k, v in raw.items()}
    except Exception as e:
        _log("matmap unreadable: %s" % e)
        return {}

def match_mapped(mat_name, matmap):
    if not matmap:
        return None
    # Blender suffixes duplicate material names with .001 - strip it before
    # looking up, or every second copy falls through to the name guesser
    base = re.sub(r'\.\d+$', '', mat_name)
    fn = matmap.get(norm(base))
    if not fn:
        return None
    path = os.path.join(TEXDIR, fn)
    return path if os.path.isfile(path) else None

def match_diffuse(mat_name, texmap):
    # material 'MI_1031001_Equip_01' -> texture 'T_1031001_Equip_01_D.png'.
    # Compare on normalized tokens; prefer _D, then _E; fallback: unique substring hit.
    core = norm(re.sub(r'^(MI|M|MAT)_', '', mat_name, flags=re.I))
    if not core:
        return None
    exact_d = 't' + core + 'd'
    if exact_d in texmap:
        return texmap[exact_d]
    hits = [k for k in texmap if core in k and k.endswith('d')]
    if not hits:
        hits = [k for k in texmap if k.rstrip('d').endswith(core) or core in k]
    if len(hits) == 1:
        return texmap[hits[0]]
    if hits:
        hits.sort(key=len)
        return texmap[hits[0]]
    return None

def rebind_materials():
    texmap = build_texmap()
    matmap = load_matmap()
    _log("matmap entries: %d" % len(matmap))
    bound = 0
    mapped = 0
    for mat in bpy.data.materials:
        if not mat.users:
            continue
        # effect/helper materials the game never draws as solid surfaces:
        # M_Hide rig aids, rim-light overlay shells, facial blendshape helpers.
        # In Blender they import as opaque black shells over the real body.
        up = mat.name.upper()
        if any(tok in up for tok in ('HIDE', 'RIM_', '_RIM', 'OUTLINE', '_BS')):
            _make_invisible(mat)
            continue
        path = None
        if any(tok in up for tok in ('HEAD', 'FACE', 'SKIN')):
            # the Lobby mesh's head UVs are laid out for the lobby Skin_D sheet,
            # NOT the in-match Head_01_D (features land offset otherwise)
            skin_key = next((k for k in texmap if k.endswith('skind')), None)
            if skin_key:
                path = texmap[skin_key]
        if not path:
            # what the game's material actually binds, before any guessing
            path = match_mapped(mat.name, matmap)
            if path:
                mapped += 1
        if not path:
            path = match_diffuse(mat.name, texmap)
        if not path and 'HAIR' in up:
            # lash/brow card materials (Hair_03 etc.) draw from the hairline
            # sheet - without it they render as black slabs over the eyes
            key = next((k for k in texmap if 'hairline' in k), None)
            if key is None:
                key = next((k for k in texmap if 'hair' in k), None)
            if key:
                path = texmap[key]
        if not path:
            if 'EYE' in up:
                _make_glassy(mat)   # translucent highlight/tear layer
            else:
                _neutralize(mat)
            continue
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf is None:
            bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
            out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
            if out is None:
                out = nt.nodes.new('ShaderNodeOutputMaterial')
            nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
        img = None
        for existing in bpy.data.images:
            if existing.filepath == path:
                img = existing
                break
        if img is None:
            img = bpy.data.images.load(path)
            # game diffuse maps are LINEAR-space data; Blender defaults PNGs to
            # sRGB which double-darkens them into mud (the gamma landmine again)
            try:
                img.colorspace_settings.name = 'Linear Rec.709'
            except Exception:
                try:
                    img.colorspace_settings.name = 'Non-Color'
                except Exception:
                    pass
        node = next((n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.name == 'SkinStudioTex'), None)
        if node is None:
            node = nt.nodes.new('ShaderNodeTexImage')
            node.name = 'SkinStudioTex'
            node.location = (bsdf.location.x - 320, bsdf.location.y)
        node.image = img
        nt.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
        # hair/lash/brow are alpha-masked cards - without opacity they render
        # as solid slabs. Other D-map alphas are shader masks, NOT opacity, so
        # only cutout the hair-family materials.
        if any(tok in mat.name.upper() for tok in ('HAIR', 'LASH', 'BROW')):
            try:
                nt.links.new(node.outputs['Alpha'], bsdf.inputs['Alpha'])
                _set_alpha_clip(mat)
            except Exception:
                pass
        bound += 1
    # placeholder objects FModel ships inside the glb
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH' and obj.name.upper().startswith(('ICOSPHERE', 'SPHERE', 'CUBE')):
            bpy.data.objects.remove(obj, do_unlink=True)
    print('[SkinStudio] rebound %d materials to design textures (%d from the material map, %d matched by name)' % (bound, mapped, bound - mapped))
    _log('rebound %d materials (%d mapped, %d by name)' % (bound, mapped, bound - mapped))

def _set_alpha_clip(mat):
    for attr, val in (('blend_method', 'CLIP'), ('surface_render_method', 'DITHERED')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    try:
        mat.alpha_threshold = 0.35
    except Exception:
        pass

def _flat_basecolor(mat, rgba):
    # imported materials can drive Base Color from a (black) attribute link -
    # disconnect it, a flat default alone does not win against a link
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        return None
    for link in list(bsdf.inputs['Base Color'].links):
        nt.links.remove(link)
    bsdf.inputs['Base Color'].default_value = rgba
    return bsdf

def _neutralize(mat):
    # unmatched but real surface (teeth, mouth interior): neutral gray
    _flat_basecolor(mat, (0.55, 0.55, 0.6, 1.0))

def _make_glassy(mat):
    # eye highlight / tear-film overlay: nearly clear instead of a solid pane
    bsdf = _flat_basecolor(mat, (0.85, 0.9, 0.95, 1.0))
    if bsdf is not None:
        bsdf.inputs['Alpha'].default_value = 0.08
    for attr, val in (('blend_method', 'BLEND'), ('surface_render_method', 'BLENDED')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass

def _make_invisible(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is not None:
        bsdf.inputs['Alpha'].default_value = 0.0
    _set_alpha_clip(mat)

class SKINSTUDIO_OT_reload(bpy.types.Operator):
    bl_idname = 'skinstudio.reload_tex'
    bl_label = 'Reload textures'
    bl_description = 'Re-read the design textures baked by Skin Studio (use after "refresh textures in Blender")'
    def execute(self, context):
        n = 0
        for img in bpy.data.images:
            try:
                if img.filepath and os.path.normpath(img.filepath).lower().startswith(os.path.normpath(TEXDIR).lower()):
                    img.reload()
                    n += 1
            except Exception:
                pass
        for area in context.screen.areas:
            area.tag_redraw()
        self.report({'INFO'}, 'reloaded %d textures' % n)
        return {'FINISHED'}

class SKINSTUDIO_OT_send(bpy.types.Operator):
    bl_idname = 'skinstudio.send_paint'
    bl_label = 'Send paint to Skin Studio'
    bl_description = 'Save every painted/modified texture into the Skin Studio edit folder'
    def execute(self, context):
        os.makedirs(EDITDIR, exist_ok=True)
        sent = []
        for img in bpy.data.images:
            if not img.is_dirty:
                continue
            if img.filepath:
                fp = os.path.normpath(bpy.path.abspath(img.filepath))
                if not fp.lower().startswith(os.path.normpath(TEXDIR).lower()):
                    continue
                try:
                    img.save()                   # write paint back to the baked file
                    dst = os.path.join(EDITDIR, os.path.basename(fp))
                    shutil.copyfile(fp, dst)
                    sent.append(os.path.basename(fp))
                except Exception as e:
                    print('[SkinStudio] save failed for %s: %s' % (img.name, e))
            else:
                # painted onto a fresh canvas (Single Image mode / "New") -
                # rescue it into the edit folder under its image name
                try:
                    name = img.name if img.name.lower().endswith('.png') else img.name + '.png'
                    dst = os.path.join(EDITDIR, name)
                    img.filepath_raw = dst
                    img.file_format = 'PNG'
                    img.save()
                    sent.append(name)
                except Exception as e:
                    print('[SkinStudio] canvas save failed for %s: %s' % (img.name, e))
        if not sent:
            # leave a forensic trail: what images exist and where they point
            _log('send found no paint; image inventory:')
            for img in bpy.data.images:
                _log('  img %r dirty=%s filepath=%r' % (img.name, img.is_dirty, img.filepath))
        with open(os.path.join(EDITDIR, '_blender_session.json'), 'w') as fh:
            json.dump({'skin': SKIN, 'sent': sent}, fh)
        self.report({'INFO'}, 'sent %d texture(s) - use "import painted textures" in Skin Studio' % len(sent))
        return {'FINISHED'}

class SKINSTUDIO_PT_panel(bpy.types.Panel):
    bl_label = 'Skin Studio'
    bl_idname = 'SKINSTUDIO_PT_panel'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'Skin Studio'
    def draw(self, context):
        col = self.layout.column()
        col.label(text='skin %s' % SKIN)
        col.operator('skinstudio.reload_tex', icon='FILE_REFRESH')
        col.operator('skinstudio.send_paint', icon='EXPORT')
        col.separator()
        col.label(text='Texture Paint mode paints')
        col.label(text='straight onto these maps.')
        col.label(text='Geometry edits stay here -')
        col.label(text='they cannot ship to the game yet.')

CLASSES = (SKINSTUDIO_OT_reload, SKINSTUDIO_OT_send, SKINSTUDIO_PT_panel)

def register():
    for c in CLASSES:
        bpy.utils.register_class(c)

def _shade_material_preview():
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == 'VIEW_3D':
                for space in area.spaces:
                    if space.type == 'VIEW_3D':
                        space.shading.type = 'MATERIAL'
    return None  # one-shot timer

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bridge_last.log')

def _log(msg):
    print('[SkinStudio] ' + msg)
    try:
        with open(LOG, 'a') as fh:
            fh.write(msg + '\n')
    except Exception:
        pass

def _load_scene():
    # runs AFTER the UI is up (interactive) or directly (background). Importing
    # during interactive --python startup fails silently: the glTF add-on and
    # window context are not ready yet.
    try:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        if GLTF and os.path.isfile(GLTF):
            _log('importing %s' % GLTF)
            bpy.ops.import_scene.gltf(filepath=GLTF)
            rebind_materials()
            _log('scene ready: %d objects' % len(bpy.data.objects))
        else:
            _log('glTF not found: %r' % GLTF)
        if not bpy.app.background:
            _shade_material_preview()
    except Exception as exc:
        _log('bridge error: %r' % exc)
    return None  # one-shot timer

def main():
    try:
        os.remove(LOG)
    except Exception:
        pass
    _log('bridge start (background=%s) skin=%s' % (bpy.app.background, SKIN))
    register()
    if bpy.app.background:
        _load_scene()
    else:
        bpy.app.timers.register(_load_scene, first_interval=0.8)

main()
