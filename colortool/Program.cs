using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using Newtonsoft.Json.Linq;
using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.PropertyTypes.Objects;
using UAssetAPI.PropertyTypes.Structs;
using UAssetAPI.UnrealTypes;
using UAssetAPI.Unversioned;

// Skin Studio color helper. Reads/writes FLinearColor parameters in Rivals
// material-instance and Niagara assets via UAssetAPI + the Marvel usmap - the
// same net8 parser rrcli's KawaiiPhysics binding uses. Load+Write round-trips
// Rivals assets byte-identical (verified), so editing one color property and
// re-serializing leaves everything else bit-exact - no risky byte-hunting.
//
// Verbs:
//   dump  <usmap> <out.json> <asset.uasset|@list>...   named colors -> json
//   patch <usmap> <edits.json> <out_dir>               apply colors, re-serialize
//   dumpjson  <usmap> <asset|@list>...   (debug) full UAssetAPI json next to each
//   roundtrip <usmap> <asset|@list>...   (debug) byte-identity self-test
//
// Colors are addressed by (export index, ordinal) where ordinal is the position
// of the FLinearColor in a deterministic depth-first walk of that export - dump
// and patch walk identically, so the ordinals always line up.
namespace SkinColorTool
{
    static class Program
    {
        const string DepDir = @"C:\rs\tools\rrcli\KawaiiPhysicsBinding";

        static int Main(string[] args)
        {
            AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
            {
                string simple = new AssemblyName(e.Name).Name;
                string cand = Path.Combine(DepDir, simple + ".dll");
                return File.Exists(cand) ? Assembly.LoadFrom(cand) : null;
            };
            try { return Run(args); }
            catch (Exception ex) { Console.WriteLine("FATAL: " + ex); return 1; }
        }

        static int Run(string[] args)
        {
            if (args.Length < 2) { Usage(); return 2; }
            switch (args[0])
            {
                case "dump": return Dump(args);
                case "patch": return Patch(args);
                case "addvec": return AddVec(args);
                case "clonemi": return CloneMi(args);
                case "animcolor": return AnimColor(args);
                case "dumpjson": return DumpJson(args);
                case "roundtrip": return RoundTrip(args);
                default: Usage(); return 2;
            }
        }

        static void Usage()
        {
            Console.WriteLine("usage:");
            Console.WriteLine("  SkinColorTool dump  <usmap> <out.json> <asset.uasset|@list>...");
            Console.WriteLine("  SkinColorTool patch <usmap> <edits.json> <out_dir>");
            Console.WriteLine("  SkinColorTool dumpjson  <usmap> <asset|@list>...");
            Console.WriteLine("  SkinColorTool roundtrip <usmap> <asset|@list>...");
        }

        // ---- shared ------------------------------------------------------------
        static string Fn(FName n) { return n == null ? null : (n.Value == null ? null : n.Value.Value); }
        static string F(float v) { return v.ToString("R", CultureInfo.InvariantCulture); }

        static List<string> ExpandArgs(string[] args, int start)
        {
            var paths = new List<string>();
            for (int i = start; i < args.Length; i++)
            {
                if (args[i].StartsWith("@"))
                    foreach (string ln in File.ReadAllLines(args[i].Substring(1)))
                    { string t = ln.Trim(); if (t.Length > 0) paths.Add(t); }
                else paths.Add(args[i]);
            }
            return paths;
        }

        sealed class Site
        {
            public int Export;
            public int Ordinal;
            public string Name;
            public string Kind = "linear";          // "linear" (material) | "curve" (Niagara)
            public LinearColorPropertyData Prop;     // linear sites
            public ArrayPropertyData Lut;            // curve sites: ShaderLUT float[] (N*4 RGBA)
        }

        // deterministic DFS: every FLinearColor in every NormalExport (material
        // params), PLUS every NiagaraDataInterfaceColorCurve ShaderLUT (particle
        // color-over-life gradient - where Niagara actually stores its colors).
        static List<Site> Collect(UAsset asset)
        {
            var sites = new List<Site>();
            for (int e = 0; e < asset.Exports.Count; e++)
            {
                var ne = asset.Exports[e] as NormalExport;
                if (ne == null) continue;
                int[] ord = { 0 };
                Walk(ne.Data, null, e, ord, sites);
            }
            CollectCurves(asset, sites);
            return sites;
        }

        // Niagara color curves: each NiagaraDataInterfaceColorCurve export bakes its
        // gradient into ShaderLUT = N samples x 4 floats (RGBA). One editable
        // "particle color" per such export (addressed by export index, ordinal 0).
        static void CollectCurves(UAsset asset, List<Site> sites)
        {
            int idx = 0;
            for (int e = 0; e < asset.Exports.Count; e++)
            {
                var ne = asset.Exports[e] as NormalExport;
                if (ne == null) continue;
                if (Fn(asset.Exports[e].GetExportClassType()) != "NiagaraDataInterfaceColorCurve") continue;
                var lut = FindArray(ne.Data, "ShaderLUT");
                if (lut == null || lut.Value == null || lut.Value.Length < 4 || lut.Value.Length % 4 != 0) continue;
                sites.Add(new Site { Export = e, Ordinal = 0, Kind = "curve", Name = "ParticleColor_" + (++idx), Lut = lut });
            }
        }

        static ArrayPropertyData FindArray(IList<PropertyData> data, string name)
        {
            if (data == null) return null;
            foreach (var p in data) { var a = p as ArrayPropertyData; if (a != null && Fn(p.Name) == name) return a; }
            return null;
        }

        static float LutF(ArrayPropertyData lut, int i) { return ((FloatPropertyData)lut.Value[i]).Value; }
        static void SetLut(ArrayPropertyData lut, int i, float v) { ((FloatPropertyData)lut.Value[i]).Value = v; }

        // Recolor a baked color gradient to a target hue while preserving each
        // sample's brightness (incl. HDR) and alpha - so an icy-blue trail becomes
        // e.g. a magenta trail of the same intensity ramp, not a flat repaint.
        static void RetintLut(ArrayPropertyData lut, float tr, float tg, float tb)
        {
            float mx = Math.Max(tr, Math.Max(tg, tb));
            float ur, ug, ub;
            if (mx <= 1e-6f) { ur = ug = ub = 0f; } else { ur = tr / mx; ug = tg / mx; ub = tb / mx; }
            int n = lut.Value.Length / 4;
            for (int k = 0; k < n; k++)
            {
                float L = 0.299f * LutF(lut, k * 4) + 0.587f * LutF(lut, k * 4 + 1) + 0.114f * LutF(lut, k * 4 + 2);
                SetLut(lut, k * 4, ur * L); SetLut(lut, k * 4 + 1, ug * L); SetLut(lut, k * 4 + 2, ub * L);
                // alpha (k*4+3) preserved
            }
        }

        static void Walk(IList<PropertyData> list, string ctx, int e, int[] ord, List<Site> sites)
        {
            if (list == null) return;
            foreach (var prop in list) WalkOne(prop, ctx, e, ord, sites);
        }

        static void WalkOne(PropertyData prop, string ctx, int e, int[] ord, List<Site> sites)
        {
            var lc = prop as LinearColorPropertyData;
            if (lc != null)
            {
                sites.Add(new Site { Export = e, Ordinal = ord[0]++, Name = ctx ?? Fn(prop.Name), Prop = lc });
                return;
            }
            var st = prop as StructPropertyData;
            if (st != null)
            {
                string childCtx = ctx;
                // a material vector param carries its human name in a sibling ParameterInfo
                if (Fn(st.StructType) == "VectorParameterValue") childCtx = ParamName(st) ?? ctx;
                Walk(st.Value, childCtx, e, ord, sites);
                return;
            }
            var arr = prop as ArrayPropertyData;
            if (arr != null && arr.Value != null)
            {
                foreach (var inner in arr.Value) WalkOne(inner, ctx, e, ord, sites);
            }
        }

        static string ParamName(StructPropertyData vpv)
        {
            if (vpv.Value == null) return null;
            foreach (var sub in vpv.Value)
            {
                var st = sub as StructPropertyData;
                if (st != null && Fn(st.Name) == "ParameterInfo" && st.Value != null)
                    foreach (var pi in st.Value)
                    {
                        var np = pi as NamePropertyData;
                        if (np != null && Fn(np.Name) == "Name") return Fn(np.Value);
                    }
            }
            return null;
        }

        // ---- dump --------------------------------------------------------------
        // dump <usmap> <out.json> <strip_prefix|-> <asset|@list>...
        // strip_prefix ("-" = none): removed from each asset path so the json holds
        // a stable rel id (e.g. Marvel/Content/.../MI_x.uasset), not a temp path.
        static int Dump(string[] args)
        {
            if (args.Length < 5) { Usage(); return 2; }
            var usmap = new Usmap(args[1]);
            string outJson = args[2];
            string strip = args[3] == "-" ? null : args[3];
            var paths = ExpandArgs(args, 4);
            var sb = new StringBuilder();
            sb.Append("[\n");
            bool first = true;
            int ok = 0, err = 0, total = 0;
            foreach (var path in paths)
            {
                try
                {
                    var asset = new UAsset(path, EngineVersion.VER_UE5_3, usmap);
                    var sites = Collect(asset);
                    string cls = asset.Exports.Count > 0 ? Fn(asset.Exports[0].GetExportClassType()) : "?";
                    string id = path;
                    if (strip != null)
                    {
                        int ix = path.IndexOf(strip, StringComparison.OrdinalIgnoreCase);
                        if (ix >= 0) id = path.Substring(ix + strip.Length).TrimStart('\\', '/').Replace('\\', '/');
                    }
                    if (!first) sb.Append(",\n");
                    first = false;
                    sb.Append(" {\"asset\":").Append(JStr(id))
                      .Append(",\"class\":").Append(JStr(cls))
                      .Append(",\"colors\":[");
                    for (int i = 0; i < sites.Count; i++)
                    {
                        var s = sites[i];
                        float cr, cg, cb, ca; int samples = 0;
                        if (s.Kind == "curve")
                        {
                            samples = s.Lut.Value.Length / 4;
                            double ar = 0, ag = 0, ab = 0, aa = 0;
                            for (int k = 0; k < samples; k++)
                            { ar += LutF(s.Lut, k * 4); ag += LutF(s.Lut, k * 4 + 1); ab += LutF(s.Lut, k * 4 + 2); aa += LutF(s.Lut, k * 4 + 3); }
                            cr = (float)(ar / samples); cg = (float)(ag / samples); cb = (float)(ab / samples); ca = (float)(aa / samples);
                        }
                        else { var c = s.Prop.Value; cr = c.R; cg = c.G; cb = c.B; ca = c.A; }
                        if (i > 0) sb.Append(',');
                        sb.Append("{\"export\":").Append(s.Export)
                          .Append(",\"ordinal\":").Append(s.Ordinal)
                          .Append(",\"kind\":").Append(JStr(s.Kind))
                          .Append(",\"name\":").Append(JStr(s.Name ?? ""))
                          .Append(",\"r\":").Append(F(cr))
                          .Append(",\"g\":").Append(F(cg))
                          .Append(",\"b\":").Append(F(cb))
                          .Append(",\"a\":").Append(F(ca));
                        if (s.Kind == "curve") sb.Append(",\"samples\":").Append(samples);
                        sb.Append('}');
                    }
                    sb.Append("]}");
                    total += sites.Count; ok++;
                }
                catch (Exception ex) { Console.WriteLine("ERR " + Path.GetFileName(path) + ": " + ex.Message); err++; }
            }
            sb.Append("\n]\n");
            File.WriteAllText(outJson, sb.ToString());
            Console.WriteLine($"dump: {ok} assets, {total} colors, {err} err -> {outJson}");
            return ok > 0 ? 0 : 1;
        }

        // ---- patch -------------------------------------------------------------
        // edits.json: [ {asset, rel, edits:[{export,ordinal,r,g,b[,a]}]} ]
        // a omitted => original alpha preserved (matches the font-tool convention).
        static int Patch(string[] args)
        {
            if (args.Length < 4) { Usage(); return 2; }
            var usmap = new Usmap(args[1]);
            var edits = JArray.Parse(File.ReadAllText(args[2]));
            string outDir = args[3];
            int assetsW = 0, sitesW = 0, err = 0, miss = 0;
            foreach (var ae in edits)
            {
                string src = (string)ae["asset"];
                string rel = (string)ae["rel"];
                var elist = (JArray)ae["edits"];
                try
                {
                    var asset = new UAsset(src, EngineVersion.VER_UE5_3, usmap);
                    var sites = Collect(asset);
                    var map = new Dictionary<long, Site>();
                    foreach (var s in sites) map[((long)s.Export << 32) | (uint)s.Ordinal] = s;
                    int applied = 0;
                    foreach (var ed in elist)
                    {
                        int ex = (int)ed["export"], ordi = (int)ed["ordinal"];
                        Site site;
                        if (!map.TryGetValue(((long)ex << 32) | (uint)ordi, out site))
                        { Console.WriteLine($"  MISS {rel} @{ex}/{ordi}"); miss++; continue; }
                        float r = (float)(double)ed["r"], g = (float)(double)ed["g"], b = (float)(double)ed["b"];
                        if (site.Kind == "curve") { RetintLut(site.Lut, r, g, b); applied++; continue; }
                        var cur = site.Prop.Value;
                        float a = ed["a"] != null ? (float)(double)ed["a"] : cur.A;
                        site.Prop.Value = new FLinearColor(r, g, b, a);
                        applied++;
                    }
                    if (applied > 0)
                    {
                        string outPath = Path.Combine(outDir, rel.Replace('/', Path.DirectorySeparatorChar));
                        Directory.CreateDirectory(Path.GetDirectoryName(outPath));
                        asset.Write(outPath);
                        assetsW++; sitesW += applied;
                    }
                }
                catch (Exception ex) { Console.WriteLine("ERR " + rel + ": " + ex.Message); err++; }
            }
            Console.WriteLine($"patch: {assetsW} assets, {sitesW} sites written, {miss} missed, {err} err -> {outDir}");
            return assetsW > 0 ? 0 : 1;
        }

        // ---- addvec ------------------------------------------------------------
        // addvec <usmap> <edits.json> <out_dir>
        // Adds VectorParameterValues overrides to a MaterialInstanceConstant that
        // has none stored (a no-override MI renders the parent's baked defaults,
        // which colortool patch cannot reach). Entry layout mirrors a donor MI on
        // the same parent byte-for-byte: ParameterInfo{Name,Association,Index} +
        // ParameterValue{LinearColor} + ExpressionGUID{Guid}.
        // edits.json: [{asset, rel, adds:[{param, r, g, b, a?, guid?}]}]
        // guid = the parent expression's GUID (copy it from any sibling MI that
        // overrides the same param); the game matches by name, but a real GUID
        // keeps the asset indistinguishable from an editor-authored override.
        static int AddVec(string[] args)
        {
            if (args.Length < 4) { Usage(); return 2; }
            var usmap = new Usmap(args[1]);
            var edits = JArray.Parse(File.ReadAllText(args[2]));
            string outDir = args[3];
            int assetsW = 0, added = 0, err = 0;
            foreach (var ae in edits)
            {
                string src = (string)ae["asset"];
                string rel = (string)ae["rel"];
                try
                {
                    var asset = new UAsset(src, EngineVersion.VER_UE5_3, usmap);
                    var ne = asset.Exports[0] as NormalExport;
                    if (ne == null) { Console.WriteLine("ERR " + rel + ": export 0 not a NormalExport"); err++; continue; }
                    ArrayPropertyData arr = null;
                    foreach (var p in ne.Data)
                        if (Fn(p.Name) == "VectorParameterValues") { arr = p as ArrayPropertyData; break; }
                    // A target that stores NO vector params at all cannot be served here.
                    // Adding the array means adding a property to the export, and these
                    // packages are UNVERSIONED: the export header is an index of WHICH schema
                    // properties follow, and UAssetAPI replays the header it read (that replay
                    // is what keeps an untouched asset byte-identical). Keep it and the header
                    // describes the old, shorter property set; drop it to force regeneration
                    // and the regenerated one desyncs the nested entry headers instead - proved
                    // both ways on MI_Common_TriangleErase_UI_SquadFadeOut, and with ZERO adds
                    // (bare empty array) too, so it is the array property itself, not the
                    // entries. Both failures still round-trip "IDENTICAL" because the garbage is
                    // preserved verbatim - byte-identity is NOT a correctness check here.
                    // Adding entries to an array that ALREADY exists is fine and is the
                    // supported case. For an MI with none, use clonemi - but check the donor's
                    // scalars AND static switches, not just its textures: cloning
                    // MI_Common_TriangleScale_UI_Left1 onto the SquadFadeIn/FadeOut transition
                    // MIs silently swapped Scale_Triangle/SmoothLine_* and dropped
                    // UseSphereFlare=True, which is what turned the screen-change wipe black.
                    if (arr == null)
                    {
                        Console.WriteLine("ERR " + rel + ": no VectorParameterValues array to extend"
                            + " - addvec cannot create one (unversioned export header). Use clonemi.");
                        err++; continue;
                    }
                    var list = new List<PropertyData>(arr.Value);
                    foreach (var ad in (JArray)ae["adds"])
                    {
                        string pname = (string)ad["param"];
                        float r = (float)(double)ad["r"], g = (float)(double)ad["g"], b = (float)(double)ad["b"];
                        float a = ad["a"] != null ? (float)(double)ad["a"] : 1f;

                        var entry = new StructPropertyData(FName.FromString(asset, list.Count.ToString()),
                                                           FName.FromString(asset, "VectorParameterValue"));
                        var info = new StructPropertyData(FName.FromString(asset, "ParameterInfo"),
                                                          FName.FromString(asset, "MaterialParameterInfo"));
                        var nameP = new NamePropertyData(FName.FromString(asset, "Name"));
                        nameP.Value = FName.FromString(asset, pname);
                        var assoc = new EnumPropertyData(FName.FromString(asset, "Association"));
                        assoc.EnumType = FName.FromString(asset, "EMaterialParameterAssociation");
                        assoc.InnerType = FName.FromString(asset, "ByteProperty");
                        assoc.Value = FName.FromString(asset, "GlobalParameter");
                        var idx = new IntPropertyData(FName.FromString(asset, "Index"));
                        idx.Value = -1;
                        info.Value = new List<PropertyData> { nameP, assoc, idx };

                        var valS = new StructPropertyData(FName.FromString(asset, "ParameterValue"),
                                                          FName.FromString(asset, "LinearColor"));
                        var lin = new LinearColorPropertyData(FName.FromString(asset, "ParameterValue"));
                        lin.Value = new FLinearColor(r, g, b, a);
                        valS.Value = new List<PropertyData> { lin };

                        var guidS = new StructPropertyData(FName.FromString(asset, "ExpressionGUID"),
                                                           FName.FromString(asset, "Guid"));
                        var guid = new GuidPropertyData(FName.FromString(asset, "ExpressionGUID"));
                        guid.Value = ad["guid"] != null ? Guid.Parse((string)ad["guid"]) : Guid.Empty;
                        guidS.Value = new List<PropertyData> { guid };

                        entry.Value = new List<PropertyData> { info, valS, guidS };
                        list.Add(entry);
                        added++;
                    }
                    arr.Value = list.ToArray();
                    string outPath = Path.Combine(outDir, rel.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(outPath));
                    asset.Write(outPath);
                    // Read it back before calling it done. UAssetAPI reports a broken export as a
                    // console WARNING and hands back garbage rather than throwing, and the file
                    // still round-trips byte-identical, so neither the exit code nor a roundtrip
                    // self-test catches it - only re-reading the values does. A silently corrupt
                    // MI ships into the pak and the game renders whatever it makes of it.
                    var back = new UAsset(outPath, EngineVersion.VER_UE5_3, usmap);
                    var have = new Dictionary<string, FLinearColor>();
                    foreach (var s in Collect(back))
                        if (s.Kind == "linear" && s.Name != null) have[s.Name] = s.Prop.Value;
                    bool good = true;
                    foreach (var ad in (JArray)ae["adds"])
                    {
                        string pname = (string)ad["param"];
                        FLinearColor got;
                        if (!have.TryGetValue(pname, out got))
                        { Console.WriteLine($"  VERIFY FAIL {rel}: {pname} not readable after write"); good = false; continue; }
                        float wr = (float)(double)ad["r"], wg = (float)(double)ad["g"], wb = (float)(double)ad["b"];
                        if (Math.Abs(got.R - wr) > 1e-4 || Math.Abs(got.G - wg) > 1e-4 || Math.Abs(got.B - wb) > 1e-4)
                        { Console.WriteLine($"  VERIFY FAIL {rel}: {pname} read back as ({F(got.R)},{F(got.G)},{F(got.B)})"); good = false; }
                    }
                    if (!good) { File.Delete(outPath); err++; continue; }
                    assetsW++;
                }
                catch (Exception ex) { Console.WriteLine("ERR " + rel + ": " + ex.Message); err++; }
            }
            Console.WriteLine($"addvec: {assetsW} assets, {added} params added, {err} err -> {outDir}");
            return assetsW > 0 ? 0 : 1;
        }

        // ---- clonemi -----------------------------------------------------------
        // clonemi <usmap> <spec.json> <out_dir>
        // Re-identify a DONOR MaterialInstanceConstant as another MI on the same
        // parent, then apply color edits. Only touches name-map strings and color
        // values on an asset UAssetAPI parsed intact, so serialization stays on
        // the proven byte-identical path - no hand-built unversioned headers
        // (addvec's constructed MaterialParameterInfo headers corrupt on write).
        // Use when the real target MI stores no parameter overrides at all.
        // spec.json: [{donor, donorLeaf, targetLeaf, rel, edits:[{export,ordinal,r,g,b,a?}]}]
        static int CloneMi(string[] args)
        {
            if (args.Length < 4) { Usage(); return 2; }
            var usmap = new Usmap(args[1]);
            var specs = JArray.Parse(File.ReadAllText(args[2]));
            string outDir = args[3];
            int assetsW = 0, err = 0;
            foreach (var sp in specs)
            {
                string donor = (string)sp["donor"];
                string dLeaf = (string)sp["donorLeaf"];
                string tLeaf = (string)sp["targetLeaf"];
                string rel = (string)sp["rel"];
                try
                {
                    var asset = new UAsset(donor, EngineVersion.VER_UE5_3, usmap);
                    var names = asset.GetNameMapIndexList();
                    int renamed = 0;
                    for (int i = 0; i < names.Count; i++)
                    {
                        string s = names[i].Value;
                        if (s != null && s.Contains(dLeaf))
                        {
                            asset.SetNameReference(i, new FString(s.Replace(dLeaf, tLeaf)));
                            renamed++;
                        }
                    }
                    // The package summary's PackageName/FolderName FString is raw, not a
                    // name-map entry - retoc keys the Zen package identity on it and
                    // SILENTLY DROPS the asset if it disagrees with the file path.
                    if (asset.FolderName != null && asset.FolderName.Value != null
                        && asset.FolderName.Value.Contains(dLeaf))
                    {
                        asset.FolderName = new FString(asset.FolderName.Value.Replace(dLeaf, tLeaf));
                        renamed++;
                    }
                    // Optional extra renames: fix the /Game/ directory when donor and
                    // target live in different folders, or redirect a texture override
                    // the donor carries that the target must not inherit.
                    var renames = (JArray)sp["renames"];
                    if (renames != null)
                    {
                        foreach (var rn in renames)
                        {
                            string from = (string)rn["from"], to = (string)rn["to"];
                            for (int i = 0; i < names.Count; i++)
                            {
                                string s = asset.GetNameReference(i).Value;
                                if (s != null && s.Contains(from))
                                { asset.SetNameReference(i, new FString(s.Replace(from, to))); renamed++; }
                            }
                            if (asset.FolderName != null && asset.FolderName.Value != null
                                && asset.FolderName.Value.Contains(from))
                            { asset.FolderName = new FString(asset.FolderName.Value.Replace(from, to)); renamed++; }
                        }
                    }
                    int applied = 0;
                    var elist = (JArray)sp["edits"];
                    if (elist != null)
                    {
                        var sites = Collect(asset);
                        var map = new Dictionary<long, Site>();
                        foreach (var s in sites) map[((long)s.Export << 32) | (uint)s.Ordinal] = s;
                        foreach (var ed in elist)
                        {
                            int ex = (int)ed["export"], ordi = (int)ed["ordinal"];
                            Site site;
                            if (!map.TryGetValue(((long)ex << 32) | (uint)ordi, out site))
                            { Console.WriteLine($"  MISS {rel} @{ex}/{ordi}"); continue; }
                            float r = (float)(double)ed["r"], g = (float)(double)ed["g"], b = (float)(double)ed["b"];
                            var cur = site.Prop.Value;
                            float a = ed["a"] != null ? (float)(double)ed["a"] : cur.A;
                            site.Prop.Value = new FLinearColor(r, g, b, a);
                            applied++;
                        }
                    }
                    string outPath = Path.Combine(outDir, rel.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(outPath));
                    asset.Write(outPath);
                    Console.WriteLine($"  {tLeaf}: {renamed} name(s) rebound, {applied} colors set");
                    assetsW++;
                }
                catch (Exception ex) { Console.WriteLine("ERR " + rel + ": " + ex.Message); err++; }
            }
            Console.WriteLine($"clonemi: {assetsW} assets, {err} err -> {outDir}");
            return assetsW > 0 ? 0 : 1;
        }

        // ---- animcolor ---------------------------------------------------------
        // animcolor <usmap> <spec.json> <out_dir>
        // Rewrites the keyframe VALUES of widget-animation colour tracks
        // (MovieSceneParameterSection -> ColorParameterNamesAndCurves). Widget
        // animations write these params onto the brush material every playback,
        // stomping whatever the MaterialInstance stores - so for an animated
        // param the keyframes ARE the live colour source.
        // spec.json: [{asset, rel, sets:[{param, r, g, b}]}]  (alpha left alone)
        static int AnimColor(string[] args)
        {
            if (args.Length < 4) { Usage(); return 2; }
            var usmap = new Usmap(args[1]);
            var specs = JArray.Parse(File.ReadAllText(args[2]));
            string outDir = args[3];
            int assetsW = 0, keysW = 0, err = 0;
            foreach (var sp in specs)
            {
                string src = (string)sp["asset"];
                string rel = (string)sp["rel"];
                try
                {
                    var asset = new UAsset(src, EngineVersion.VER_UE5_3, usmap);
                    int wrote = 0;
                    foreach (var export in asset.Exports)
                    {
                        var ne = export as NormalExport;
                        if (ne == null || ne.Data == null) continue;
                        foreach (var p in ne.Data)
                        {
                            var arr = p as ArrayPropertyData;
                            if (arr == null || Fn(arr.Name) != "ColorParameterNamesAndCurves") continue;
                            foreach (var entryP in arr.Value)
                            {
                                var entry = entryP as StructPropertyData;
                                if (entry == null) continue;
                                string pname = null;
                                foreach (var f in entry.Value)
                                {
                                    var np = f as NamePropertyData;
                                    if (np != null && Fn(np.Name) == "ParameterName") { pname = Fn(np.Value); break; }
                                }
                                if (pname == null) continue;
                                foreach (var st in (JArray)sp["sets"])
                                {
                                    if ((string)st["param"] != pname) continue;
                                    float[] rgb = { (float)(double)st["r"], (float)(double)st["g"], (float)(double)st["b"] };
                                    string[] chans = { "RedCurve", "GreenCurve", "BlueCurve" };
                                    for (int c = 0; c < 3; c++)
                                        wrote += SetChannelKeys(entry, chans[c], rgb[c]);
                                }
                            }
                        }
                    }
                    if (wrote > 0)
                    {
                        string outPath = Path.Combine(outDir, rel.Replace('/', Path.DirectorySeparatorChar));
                        Directory.CreateDirectory(Path.GetDirectoryName(outPath));
                        asset.Write(outPath);
                        assetsW++; keysW += wrote;
                        Console.WriteLine($"  {Path.GetFileName(rel)}: {wrote} keyframe value(s) set");
                    }
                    else Console.WriteLine($"  {Path.GetFileName(rel)}: no matching colour tracks");
                }
                catch (Exception ex) { Console.WriteLine("ERR " + rel + ": " + ex.Message); err++; }
            }
            Console.WriteLine($"animcolor: {assetsW} assets, {keysW} keys written, {err} err -> {outDir}");
            return assetsW > 0 ? 0 : 1;
        }

        // Set every keyframe value (and the default, if flagged) of one float
        // channel inside a ColorParameterNameAndCurves entry. The channel nests as
        // StructPropertyData(name) -> MovieSceneFloatChannelPropertyData whose
        // FMovieSceneFloatChannel holds the key values; reflection copes with
        // UAssetAPI field-name drift between versions.
        static int SetChannelKeys(StructPropertyData entry, string chanName, float v)
        {
            int wrote = 0;
            foreach (var f in entry.Value)
            {
                var wrap = f as StructPropertyData;
                if (wrap == null || Fn(wrap.Name) != chanName) continue;
                foreach (var inner in wrap.Value)
                {
                    object chan = inner.GetType().GetProperty("Value") != null
                        ? inner.GetType().GetProperty("Value").GetValue(inner) : null;
                    if (chan == null) continue;
                    var t = chan.GetType();
                    if (!t.Name.Contains("FloatChannel")) continue;
                    var valuesF = t.GetField("Values") ?? null;
                    var valuesP = t.GetProperty("Values");
                    object valuesObj = valuesF != null ? valuesF.GetValue(chan)
                                     : (valuesP != null ? valuesP.GetValue(chan) : null);
                    // Boxed struct elements would silently drop writes - use indexed
                    // write-back for arrays/lists so mutations always land.
                    var asArray = valuesObj as Array;
                    var asList = valuesObj as System.Collections.IList;
                    int n = asArray != null ? asArray.Length : (asList != null ? asList.Count : 0);
                    for (int i = 0; i < n; i++)
                    {
                        object kv = asArray != null ? asArray.GetValue(i) : asList[i];
                        if (kv == null) continue;
                        var vt = kv.GetType();
                        var vf = vt.GetField("Value");
                        var vp = vt.GetProperty("Value");
                        bool set = false;
                        if (vf != null && vf.FieldType == typeof(float)) { vf.SetValue(kv, v); set = true; }
                        else if (vp != null && vp.PropertyType == typeof(float) && vp.CanWrite) { vp.SetValue(kv, v); set = true; }
                        if (set)
                        {
                            if (asArray != null) asArray.SetValue(kv, i); else asList[i] = kv;
                            wrote++;
                        }
                    }
                    var dvF = t.GetField("DefaultValue");
                    var dvP = t.GetProperty("DefaultValue");
                    if (dvF != null && dvF.FieldType == typeof(float)) dvF.SetValue(chan, v);
                    else if (dvP != null && dvP.PropertyType == typeof(float) && dvP.CanWrite) dvP.SetValue(chan, v);
                }
            }
            return wrote;
        }

        // ---- debug verbs -------------------------------------------------------
        static int DumpJson(string[] args)
        {
            var usmap = new Usmap(args[1]);
            int ok = 0, err = 0;
            foreach (var path in ExpandArgs(args, 2))
            {
                try
                {
                    var asset = new UAsset(path, EngineVersion.VER_UE5_3, usmap);
                    string json = asset.SerializeJson();
                    File.WriteAllText(Path.ChangeExtension(path, ".json"), json);
                    string cls = asset.Exports.Count > 0 ? Fn(asset.Exports[0].GetExportClassType()) : "?";
                    Console.WriteLine($"OK  {Path.GetFileName(path)}  class={cls}  exports={asset.Exports.Count}  json={json.Length}B");
                    ok++;
                }
                catch (Exception ex) { Console.WriteLine($"ERR {Path.GetFileName(path)}: {ex.GetType().Name}: {ex.Message}"); err++; }
            }
            Console.WriteLine($"done: {ok} ok, {err} err");
            return err > 0 && ok == 0 ? 1 : 0;
        }

        static int RoundTrip(string[] args)
        {
            var usmap = new Usmap(args[1]);
            string tmp = Path.Combine(Path.GetTempPath(), "sct_rt");
            Directory.CreateDirectory(tmp);
            foreach (var path in ExpandArgs(args, 2))
            {
                string leaf = Path.GetFileName(path);
                try
                {
                    var asset = new UAsset(path, EngineVersion.VER_UE5_3, usmap);
                    string outUasset = Path.Combine(tmp, leaf);
                    asset.Write(outUasset);
                    string inUexp = Path.ChangeExtension(path, ".uexp");
                    string outUexp = Path.ChangeExtension(outUasset, ".uexp");
                    long a1, a2;
                    bool uaOk = FilesEqual(path, outUasset, out a1, out a2);
                    long _u1, _u2;
                    bool uxOk = !File.Exists(inUexp) || FilesEqual(inUexp, outUexp, out _u1, out _u2);
                    Console.WriteLine($"{(uaOk && uxOk ? "IDENTICAL" : "DIFFERS  ")} {leaf}  uasset({a1}->{a2},{(uaOk ? "=" : "X")}) uexp({(uxOk ? "=" : "X")})");
                }
                catch (Exception ex) { Console.WriteLine($"ERR {leaf}: {ex.GetType().Name}: {ex.Message}"); }
            }
            return 0;
        }

        static bool FilesEqual(string a, string b, out long la, out long lb)
        {
            byte[] ba = File.ReadAllBytes(a), bb = File.ReadAllBytes(b);
            la = ba.Length; lb = bb.Length;
            if (ba.Length != bb.Length) return false;
            for (int i = 0; i < ba.Length; i++) if (ba[i] != bb[i]) return false;
            return true;
        }

        static string JStr(string s)
        {
            if (s == null) return "\"\"";
            var sb = new StringBuilder("\"");
            foreach (char ch in s)
            {
                if (ch == '"' || ch == '\\') sb.Append('\\').Append(ch);
                else if (ch == '\n') sb.Append("\\n");
                else if (ch == '\r') sb.Append("\\r");
                else if (ch == '\t') sb.Append("\\t");
                else if (ch < 32) sb.Append("\\u").Append(((int)ch).ToString("x4"));
                else sb.Append(ch);
            }
            sb.Append('"');
            return sb.ToString();
        }
    }
}
