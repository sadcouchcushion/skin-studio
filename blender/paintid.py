# "What paints this?" - render the skin's mesh twice so any point on the model
# can be traced to the material that owns it AND the exact spot on that
# material's texture atlas.
#
#   blender.exe -b --python paintid.py -- <mesh.glb> <out dir>
#
# Writes into <out dir>:
#   legend.json          material name -> the LINEAR rgb it was given
#   id-front.png         every material a distinct flat colour
#   id-back.png
#   uv-front.png         every material renders R=U, G=V of its own UVs
#   uv-back.png
#
# Two passes, not one per material: the id pass says WHICH material a pixel is,
# the uv pass says WHERE in that material's atlas it came from, and together
# they answer the question for any pixel at a fixed cost.
#
# Traps, all of which bit while writing this:
#  * view transform MUST be Standard. Under Filmic/AgX the emission colours come
#    back shifted and the legend lookup turns into guesswork.
#  * the legend is LINEAR, the PNG is sRGB - convert before comparing.
#  * don't introspect RenderEngine subclasses for bl_idname (HydraRenderEngine
#    has none and throws); just try the engine names in order.
#  * FModel's glb ships Icosphere / Sphere / Cube placeholders - delete them or
#    they sit in front of the character.
import bpy, sys, math, json, os, colorsys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("PAINTID FAIL: need <mesh.glb> <out dir>")
    sys.exit(1)
GLB, OUT = argv[0], argv[1]
if not os.path.isdir(OUT):
    os.makedirs(OUT)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
for ob in list(bpy.data.objects):
    if ob.type == 'MESH' and ob.name.split('.')[0] in ('Icosphere', 'Sphere', 'Cube'):
        bpy.data.objects.remove(ob, do_unlink=True)

mats = sorted({s.material.name for ob in bpy.data.objects if ob.type == 'MESH'
               for s in ob.material_slots if s.material})
print("PAINTID materials: %d" % len(mats))
if not mats:
    print("PAINTID FAIL: no materials on the mesh")
    sys.exit(1)

legend = {}
n = len(mats)
for i, name in enumerate(mats):
    r, g, b = colorsys.hsv_to_rgb((i % n) / float(n), 1.0, 1.0 if i % 2 == 0 else 0.55)
    legend[name] = [r, g, b]
with open(os.path.join(OUT, 'legend.json'), 'w') as f:
    json.dump(legend, f, indent=1)

def flat_pass():
    for m in bpy.data.materials:
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Strength'].default_value = 1.0
        c = legend.get(m.name, [0, 0, 0])
        em.inputs['Color'].default_value = (c[0], c[1], c[2], 1.0)
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
        m.blend_method = 'OPAQUE'

def uv_pass():
    for m in bpy.data.materials:
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Strength'].default_value = 1.0
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        comb = nt.nodes.new('ShaderNodeCombineXYZ')
        nt.links.new(tc.outputs['UV'], sep.inputs['Vector'])
        nt.links.new(sep.outputs['X'], comb.inputs['X'])
        nt.links.new(sep.outputs['Y'], comb.inputs['Y'])
        nt.links.new(comb.outputs['Vector'], em.inputs['Color'])
        nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
        m.blend_method = 'OPAQUE'

mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for ob in bpy.data.objects:
    if ob.type != 'MESH':
        continue
    for c in ob.bound_box:
        w = ob.matrix_world @ Vector(c)
        mn = Vector((min(mn[i], w[i]) for i in range(3)))
        mx = Vector((max(mx[i], w[i]) for i in range(3)))
ctr = (mn + mx) / 2.0
size = max((mx - mn).x, (mx - mn).y, (mx - mn).z)

scene = bpy.context.scene
for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try:
        scene.render.engine = eng
        break
    except Exception:
        continue
scene.render.resolution_x = 720
scene.render.resolution_y = 960
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.compression = 15
try:
    scene.eevee.taa_render_samples = 1        # flat colour - antialiasing only muddies the lookup
except Exception:
    pass
try:
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
except Exception as e:
    print("PAINTID view transform: %s" % e)
scene.world = bpy.data.worlds.new("W")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)

cam_data = bpy.data.cameras.new("C")
cam = bpy.data.objects.new("C", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.type = 'ORTHO'
cam_data.ortho_scale = size * 1.05
d = size * 2.0

def shoot(prefix, tag, front):
    if front:
        cam.location = ctr + Vector((0, -d, 0))
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:
        cam.location = ctr + Vector((0, d, 0))
        cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    scene.render.filepath = os.path.join(OUT, '%s-%s.png' % (prefix, tag))
    bpy.ops.render.render(write_still=True)
    print("PAINTID wrote %s" % scene.render.filepath)

flat_pass()
shoot('id', 'front', True)
shoot('id', 'back', False)
uv_pass()
shoot('uv', 'front', True)
shoot('uv', 'back', False)
print("PAINTID DONE")
