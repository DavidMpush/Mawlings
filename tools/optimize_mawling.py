"""Create a lightweight, vertex-colored gameplay GLB from the supplied Mawling.glb.

Requires numpy, Pillow and fast-simplification. The source GLB is never modified.
"""
import io
import json
import struct
from pathlib import Path

import fast_simplification as fs
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "Mawling.glb"
TARGET = ROOT / "assets" / "Mawling_game.glb"
TRIANGLES = 3000


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
    source, binary = read_glb(SOURCE)
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

    simplified, new_faces, collapses = fs.simplify(positions, faces, target_count=TRIANGLES, return_collapses=True)
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
        "nodes": [{"name": "Mawling", "mesh": 0, "rotation": source["nodes"][0]["rotation"]}],
        "meshes": [{"name": "Mawling game mesh", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "Mawling vertex colors", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0.9}, "doubleSided": True}],
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
    with TARGET.open("wb") as output:
        output.write(struct.pack("<III", 0x46546C67, 2, length))
        output.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        output.write(json_bytes)
        output.write(struct.pack("<I4s", len(payload), b"BIN\x00"))
        output.write(payload)
    print(f"{SOURCE.stat().st_size:,} -> {TARGET.stat().st_size:,} bytes; {len(faces):,} -> {len(new_faces):,} triangles")


if __name__ == "__main__":
    main()
