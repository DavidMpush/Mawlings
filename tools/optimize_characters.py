"""Create lightweight, vertex-colored gameplay GLBs from supplied character models.

Requires numpy, Pillow and fast-simplification. The source GLB is never modified.
"""
import io
import json
import struct
import argparse
from pathlib import Path

import fast_simplification as fs
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = {
    "mawling": ("Mawling", 3000),
    "bog_king": ("BogKing", 8000),
    "nibbler": ("Nibbler", 2500),
    "rock": ("Rock", 1500, "props"),
    "leaf": ("Leaf", 1500, "props"),
    # Hunyuan deliveries with spaces in their file names: (output, triangles, folder, source).
    "mire_reaper": ("MireReaper", 3000, "characters", "Mire Reaper"),
    "root_arch": ("RootArch", 3000, "props", "root arch"),
    "fallen_log": ("FallenLog", 2000, "props", "fallen log"),
    "pond_seeds": ("PondSeeds", 1500, "props", "pond seeds"),
    "flower": ("Flower", 1200, "props", "flower"),
    # Biomass crystals shown on corpses (scripts/corpse_visuals.gd), by rank.
    "small_drop": ("SmallDrop", 800, "props", "smallsharddrop"),
    "medium_drop": ("MediumDrop", 1200, "props", "mediumdrop"),
    "big_drop": ("BigDrop", 2000, "props", "bigdrop"),
    # Fluch-Totem objective (scripts/objectives/curse_totem.gd).
    "totem": ("CurseTotem", 2000, "props", "CurseTotem"),
    # Alpha-Kern pickup and Migrationsschlund (stage 10 objectives).
    "alpha_core": ("AlphaCore", 1500, "props", "alphacore"),
    "migration_pit": ("MigrationPit", 3000, "props", "migration pit"),
    # Jäger (hunter.gd).
    "hunter_beetle": ("HunterBeetle", 3000, "characters", "Hunter Beetle"),
    # Delivery 27.09.2026 (afternoon).
    "skitter": ("Skitter", 2500, "characters", "Skitter"),
    "moorbrut": ("Moorbrut", 1200, "characters", "moorbrut"),
    "moosschlund": ("Moosschlund", 8000, "characters", "moosschlund"),
    "bog_king_new": ("BogKingNew", 8000, "characters", "Bog King new"),
    "elite_crown": ("EliteCrown", 800, "props", "Elite Crown"),
    "nest": ("BroodNest", 2500, "props", "nest"),
    # Aschenkröte apex (scripts/apex_toad.gd), delivered 27.09.2026.
    "ash_toad": ("AshToad", 8000, "characters", "Ash Toad"),
    # Wüstenwelt "Dürrschlund" (stage 19), delivered 27.09.2026.
    "sandwurm": ("Sandwurm", 8000, "characters", "sandwurm"),
    "sandgrub": ("Sandgrub", 1200, "characters", "sandgrub"),
    "sandportal": ("SandPortal", 3000, "props", "sandportal"),
    "ribbones": ("RibBones", 2500, "props", "ribbones"),
    "rockarch": ("RockArch", 2500, "props", "rockarch"),
    "sandstone": ("SandstoneCliff", 2000, "props", "sandstone"),
    "cactus": ("Cactus", 1500, "props", "cactus"),
    "skull": ("GiantSkull", 3000, "props", "skull"),
}
# Hunyuan meshes split ~30 % of their vertices along UV seams. Unwelded, the
# simplifier treats every seam as a border and leaves splinter-like shards, so
# these models are welded by position first (colours averaged per point).
WELD = {"mire_reaper", "root_arch", "fallen_log", "pond_seeds", "flower", "small_drop", "medium_drop", "big_drop", "totem", "alpha_core", "migration_pit", "hunter_beetle", "skitter", "moorbrut", "moosschlund", "bog_king_new", "elite_crown", "nest", "ash_toad", "sandwurm", "sandgrub", "sandportal", "ribbones", "rockarch", "sandstone", "cactus", "skull"}


def read_glb(path):
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data)
    assert magic == 0x46546C67 and version == 2 and total == len(data)
    length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + length])
    binary_start = 20 + length + 8
    return document, data[binary_start:]


def accessor(document, binary, index):
    item = document["accessors"][index]
    view = document["bufferViews"][item["bufferView"]]
    dtype = {5126: np.dtype("<f4"), 5125: np.dtype("<u4"), 5123: np.dtype("<u2")}[item["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[item["type"]]
    start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    return np.ndarray((item["count"], width), dtype=dtype, buffer=binary, offset=start, strides=(stride, dtype.itemsize)).copy()


def append_buffer(payload, views, values, target=None):
    raw = np.ascontiguousarray(values).tobytes()
    offset = len(payload)
    payload.extend(raw)
    payload.extend(b"\x00" * (-len(payload) % 4))
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
    if target is not None:
        view["target"] = target
    views.append(view)
    return len(views) - 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character", choices=[*CHARACTERS, "all"], default="all", nargs="?")
    arguments = parser.parse_args()
    for character in CHARACTERS if arguments.character == "all" else [arguments.character]:
        optimize(character)


def optimize(character):
    name, triangles, *extra = CHARACTERS[character]
    folder = extra[0] if extra else "characters"
    source_name = extra[1] if len(extra) > 1 else name
    source_path = ROOT / "assets" / "source" / character / f"{source_name}.glb"
    if not source_path.exists():
        # Freshly delivered models may still sit directly in assets/.
        source_path = ROOT / "assets" / f"{source_name}.glb"
    target_path = ROOT / "assets" / "gameplay" / folder / f"{name}_game.glb"
    target_path.parent.mkdir(parents=True, exist_ok=True)
    source, binary = read_glb(source_path)
    primitive = source["meshes"][0]["primitives"][0]
    positions = accessor(source, binary, primitive["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(source, binary, primitive["attributes"]["TEXCOORD_0"]).astype(np.float64)
    faces = accessor(source, binary, primitive["indices"]).reshape(-1, 3).astype(np.int32)
    base_texture = source["textures"][source["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    image_def = source["images"][base_texture["source"]]
    image_view = source["bufferViews"][image_def["bufferView"]]
    offset = image_view.get("byteOffset", 0)
    image = Image.open(io.BytesIO(binary[offset:offset + image_view["byteLength"]])).convert("RGB")
    pixels = np.asarray(image)
    x = np.clip(np.rint(uv[:, 0] * (image.width - 1)).astype(int), 0, image.width - 1)
    y = np.clip(np.rint((1.0 - uv[:, 1]) * (image.height - 1)).astype(int), 0, image.height - 1)
    srgb = pixels[y, x].astype(np.float32) / 255.0
    original_colors = srgb
    if character in WELD:
        _, first, inverse = np.unique(np.round(positions, 6), axis=0, return_index=True, return_inverse=True)
        inverse = inverse.reshape(-1)
        welded_colors = np.zeros((len(first), 3), dtype=np.float32)
        np.add.at(welded_colors, inverse, original_colors)
        welded_colors /= np.bincount(inverse, minlength=len(first))[:, None]
        positions = positions[first]
        original_colors = welded_colors
        faces = inverse[faces].astype(np.int32)
        faces = faces[(faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])]

    simplified, new_faces, collapses = fs.simplify(positions, faces, target_count=triangles, return_collapses=True)
    replayed, replay_faces, mapping = fs.replay_simplification(positions.astype(np.float32), faces, collapses)
    assert len(replayed) == len(simplified) and len(replay_faces) == len(new_faces)
    valid = mapping >= 0
    colors = np.zeros((len(simplified), 3), dtype=np.float32)
    counts = np.zeros(len(simplified), dtype=np.float32)
    np.add.at(colors, mapping[valid], original_colors[valid])
    np.add.at(counts, mapping[valid], 1)
    colors /= np.maximum(counts[:, None], 1)
    colors = np.clip(colors * 1.05, 0, 1)
    # Vertex colors encode the broad hand-painted palette without 4K maps.
    colors = np.rint(colors * 31) / 31

    normals = np.zeros_like(simplified, dtype=np.float64)
    points = simplified[new_faces]
    face_normals = np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0])
    for corner in range(3):
        np.add.at(normals, new_faces[:, corner], face_normals)
    lengths = np.linalg.norm(normals, axis=1)
    normals /= np.maximum(lengths[:, None], 1e-10)

    payload = bytearray()
    views = []
    position_view = append_buffer(payload, views, simplified.astype("<f4"), 34962)
    normal_view = append_buffer(payload, views, normals.astype("<f4"), 34962)
    color_view = append_buffer(payload, views, colors.astype("<f4"), 34962)
    indices_view = append_buffer(payload, views, new_faces.astype("<u4"), 34963)
    document = {
        "asset": {"version": "2.0", "generator": "Mawlings gameplay mesh optimizer"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0, "rotation": source["nodes"][0]["rotation"]}],
        "meshes": [{"name": f"{name} game mesh", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": f"{name} vertex colors", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0.9}, "doubleSided": True}],
        "accessors": [
            {"bufferView": position_view, "componentType": 5126, "count": len(simplified), "type": "VEC3", "min": simplified.min(axis=0).tolist(), "max": simplified.max(axis=0).tolist()},
            {"bufferView": normal_view, "componentType": 5126, "count": len(simplified), "type": "VEC3"},
            {"bufferView": color_view, "componentType": 5126, "count": len(simplified), "type": "VEC3"},
            {"bufferView": indices_view, "componentType": 5125, "count": new_faces.size, "type": "SCALAR"},
        ],
        "bufferViews": views,
        "buffers": [{"byteLength": len(payload)}],
    }
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    length = 12 + 8 + len(json_bytes) + 8 + len(payload)
    with target_path.open("wb") as output:
        output.write(struct.pack("<III", 0x46546C67, 2, length))
        output.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        output.write(json_bytes)
        output.write(struct.pack("<I4s", len(payload), b"BIN\x00"))
        output.write(payload)
    print(f"{name}: {source_path.stat().st_size:,} -> {target_path.stat().st_size:,} bytes; {len(faces):,} -> {len(new_faces):,} triangles")


if __name__ == "__main__":
    main()
