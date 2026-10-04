// Skin Studio 3D preview. Hosted in a WebView2 inside Skin Studio, with the
// virtual host https://skinstudio.local/ mapped onto C:\rs\SkinStudio, so every
// path below is relative to the studio folder.
//
// Skin Studio writes cache\<skin>\view\scene.json and then posts
//   {"cmd":"load","scene":"cache/<skin>/view/scene.json"}
// The mesh is AtelierMesh's .glb (geometry + one material slot per MI, no
// textures). Textures are bound here by the SAME rules as blender\bridge.py,
// so the viewer and Blender agree about which map dresses which part.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const ROOT = '../';                     // viewer/ -> studio root
const $ = (id) => document.getElementById(id);
const status = (t) => { $('status').textContent = t || ''; };
const hud = (t) => { $('hud').textContent = t || ''; };
const post = (o) => { try { window.chrome.webview.postMessage(JSON.stringify(o)); } catch (e) {} };

// ---- renderer / scene -------------------------------------------------------
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NoToneMapping;
$('view').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const BG = [new THREE.Color(0x1d211e), new THREE.Color(0xd9ded9)];
let bgDark = true;
scene.background = BG[0];

const camera = new THREE.PerspectiveCamera(30, 1, 0.5, 5000);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.12;

scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8f8a, 1.6));
const key = new THREE.DirectionalLight(0xffffff, 1.4);
key.position.set(0.6, 1.0, 1.2);
scene.add(key);
const fill = new THREE.DirectionalLight(0xffffff, 0.5);
fill.position.set(-1.0, 0.4, -0.8);
scene.add(fill);

function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  renderer.domElement.style.width = w + 'px';
  renderer.domElement.style.height = h + 'px';
  camera.aspect = w / Math.max(1, h);
  camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);
resize();

let spin = false;
renderer.setAnimationLoop(() => {
  if (spin && model) model.rotation.y += 0.01;
  controls.update();
  renderer.render(scene, camera);
});

// ---- texture cache ----------------------------------------------------------
// url -> { ver, tex }. A rev bump in scene.json reloads only the maps whose
// version (file write time) changed, so re-applying one layer is quick.
const texCache = new Map();
async function loadTex(url, ver) {
  const hit = texCache.get(url);
  if (hit && hit.ver === ver) return hit.tex;
  const r = await fetch(ROOT + url + '?v=' + ver, { cache: 'no-store' });
  if (!r.ok) throw new Error(url + ': ' + r.status);
  // colorSpaceConversion 'none': the PNGs carry gAMA chunks, and the bytes are
  // LINEAR data - the browser must not "correct" them on decode
  const bmp = await createImageBitmap(await r.blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
  const tex = new THREE.Texture(bmp);
  tex.flipY = false;                               // glTF UV convention
  tex.colorSpace = THREE.LinearSRGBColorSpace;     // same as the Blender bridge's 'Linear Rec.709'
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  tex.needsUpdate = true;
  if (hit) hit.tex.dispose();
  texCache.set(url, { ver, tex });
  return tex;
}

// ---- material rules (mirror of bridge.py rebind_materials) -------------------
const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]/g, '');
const HIDE = ['HIDE', 'RIM_', '_RIM', 'OUTLINE', '_BS', 'SHOWRIMLIGHT'];

function pickTexture(slot, sc) {
  const up = slot.toUpperCase();
  const files = Object.keys(sc.tex);
  const byNorm = {};
  for (const f of files) byNorm[norm(f.replace(/\.png$/i, ''))] = f;
  // lobby head UVs are laid out for the lobby Skin_D sheet, not Head_01_D
  if (['HEAD', 'FACE', 'SKIN'].some((t) => up.includes(t))) {
    const k = Object.keys(byNorm).find((k) => k.endsWith('skind'));
    if (k) return byNorm[k];
  }
  const base = slot.replace(/\.\d+$/, '');
  if (sc.matmap && sc.matmap[base] && sc.tex[sc.matmap[base]] !== undefined) return sc.matmap[base];
  const core = norm(base.replace(/^(MI|M|MAT)_/i, ''));
  if (core) {
    if (byNorm['t' + core + 'd']) return byNorm['t' + core + 'd'];
    let hits = Object.keys(byNorm).filter((k) => k.includes(core) && k.endsWith('d'));
    if (!hits.length) hits = Object.keys(byNorm).filter((k) => k.replace(/d+$/, '').endsWith(core) || k.includes(core));
    if (hits.length) { hits.sort((a, b) => a.length - b.length); return byNorm[hits[0]]; }
  }
  if (up.includes('HAIR')) {
    const k = Object.keys(byNorm).find((k) => k.includes('hairline')) || Object.keys(byNorm).find((k) => k.includes('hair'));
    if (k) return byNorm[k];
  }
  return null;
}

async function dress(root, sc) {
  const slots = new Map();                       // material name -> [mesh]
  root.traverse((o) => {
    if (!o.isMesh) return;
    o.frustumCulled = false;                     // skinned bounds are the bind pose; never cull
    const mats = Array.isArray(o.material) ? o.material : [o.material];
    for (const m of mats) {
      if (!slots.has(m.name)) slots.set(m.name, []);
      slots.get(m.name).push(o);
    }
  });
  let bound = 0, hidden = 0;
  const jobs = [];
  for (const [name, meshes] of slots) {
    const up = name.toUpperCase();
    const hair = ['HAIR', 'LASH', 'BROW'].some((t) => up.includes(t));
    if (HIDE.some((t) => up.includes(t))) {
      for (const o of meshes) swapMat(o, name, null);
      hidden++;
      continue;
    }
    const file = pickTexture(name, sc);
    const tint = (sc.tints && sc.tints[name.replace(/\.\d+$/, '')]) || null;
    const m = new THREE.MeshStandardMaterial({ name, roughness: 0.85, metalness: 0.0 });
    if (tint) m.color.setRGB(tint[0], tint[1], tint[2]);       // linear, like the game's BaseTint
    if (hair) { m.alphaTest = 0.5; m.side = THREE.DoubleSide; }
    if (!file) {
      if (up.includes('EYE')) { m.transparent = true; m.opacity = 0.18; m.depthWrite = false; }
      else m.color.setRGB(0.55, 0.55, 0.55);
    } else {
      bound++;
      jobs.push(loadTex(sc.texBase + file, sc.tex[file]).then((t) => { m.map = t; m.needsUpdate = true; })
        .catch((e) => console.warn(e)));
    }
    for (const o of meshes) swapMat(o, name, m);
  }
  await Promise.all(jobs);
  return { bound, hidden, slots: slots.size };
}

// replace one named material on a mesh (null = hide that slot)
function swapMat(o, name, m) {
  if (Array.isArray(o.material)) {
    o.material = o.material.map((x) => (x.name === name ? (m || invisible) : x));
  } else if (o.material.name === name) {
    if (m) o.material = m; else o.visible = false;
  }
}
const invisible = new THREE.MeshBasicMaterial({ visible: false });

// ---- load / reload ----------------------------------------------------------
const gltfLoader = new GLTFLoader();
let model = null, modelGlb = null, framed = false;

function frame(front = true) {
  if (!model) return;
  const box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3()), c = box.getCenter(new THREE.Vector3());
  const d = (size.y / 2) / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 1.15;
  controls.target.copy(c);
  camera.position.set(c.x, c.y + size.y * 0.04, c.z + (front ? d : -d));
  camera.near = d / 100; camera.far = d * 20; camera.updateProjectionMatrix();
  controls.update();
}

let busy = Promise.resolve();
function load(sceneUrl) { busy = busy.then(() => doLoad(sceneUrl)).catch((e) => { status('could not load: ' + e.message); post({ ev: 'error', msg: String(e.message) }); }); return busy; }

async function doLoad(sceneUrl) {
  const r = await fetch(ROOT + sceneUrl + '?t=' + Date.now(), { cache: 'no-store' });
  if (!r.ok) throw new Error('scene ' + r.status);
  const sc = await r.json();
  if (!model || modelGlb !== sc.glb) {
    status('loading model...');
    const g = await gltfLoader.loadAsync(ROOT + sc.glb);
    if (model) scene.remove(model);
    model = g.scene;
    modelGlb = sc.glb;
    // Unreal is Z-up centimetres; AtelierMesh already writes glTF Y-up
    scene.add(model);
    framed = false;
  }
  status('dressing...');
  const st = await dress(model, sc);
  if (!framed) { frame(true); framed = true; }
  status('');
  hud(`${sc.title || sc.skin}  ·  ${st.bound} of ${st.slots - st.hidden} parts textured` + (sc.note ? '  ·  ' + sc.note : ''));
  post({ ev: 'loaded', skin: sc.skin, rev: sc.rev, bound: st.bound, slots: st.slots });
}

// ---- UI ---------------------------------------------------------------------
$('bFront').onclick = () => frame(true);
$('bBack').onclick = () => frame(false);
$('bSpin').onclick = () => { spin = !spin; $('bSpin').classList.toggle('on', spin); };
$('bBg').onclick = () => { bgDark = !bgDark; scene.background = BG[bgDark ? 0 : 1]; };
window.addEventListener('keydown', (e) => {
  if (e.key === 'f' || e.key === 'F') frame(true);
  else if (e.key === 'b' || e.key === 'B') frame(false);
  else if (e.key === 't' || e.key === 'T') $('bSpin').click();
});

if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener('message', (e) => {
    let m; try { m = JSON.parse(e.data); } catch (_) { return; }
    if (m.cmd === 'load') load(m.scene);
    else if (m.cmd === 'front') frame(true);
  });
}
const q = new URLSearchParams(location.search).get('scene');
if (q) load(q); else status('waiting for Skin Studio...');
post({ ev: 'ready' });
