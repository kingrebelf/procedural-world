"""Copies the parts of the CC0 Quaternius kits the game uses into assets/models.

Usage: python3 tools/prepare_kits.py KITS_DIR
KITS_DIR holds the unzipped kits (characters/, anim/, anim2/, fantasy_props/, scifi_mega/,
and ../village_kit/). Building pieces and props (village/, scifi/, props/) keep their glTF
materials with textures resized to 1024 px. For people Textures are resized
to 1024 px and stripped out of the glTF files: the game builds its own materials
(clothing, skin tones, hair colours) in code, so the files only carry geometry, skins
and animations.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets" / "models"


def strip_gltf(src: Path, dst: Path) -> None:
    d = json.loads(src.read_text())
    for k in ("images", "textures", "samplers"):
        d.pop(k, None)
    for m in d.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        for k in ("baseColorTexture", "metallicRoughnessTexture"):
            pbr.pop(k, None)
        for k in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            m.pop(k, None)
    dst.write_text(json.dumps(d))
    for b in d.get("buffers", []):
        shutil.copy(src.parent / b["uri"], dst.parent / b["uri"])


def texture(src: Path, dst: Path, size: int = 1024) -> None:
    img = Image.open(src)
    img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "P") else "RGB")
    img.resize((size, size), Image.LANCZOS).save(dst, optimize=True)


def people(kits: Path) -> None:
    out = ROOT / "people"
    out.mkdir(parents=True, exist_ok=True)
    base = kits / "characters" / "Universal Base Characters[Standard]"
    bodies = base / "Base Characters" / "Godot - UE"
    for n in ("Superhero_Male_FullBody", "Superhero_Female_FullBody"):
        strip_gltf(bodies / f"{n}.gltf", out / f"{n}.gltf")
    hair = base / "Hairstyles" / "Rigged to Head Bone" / "glTF (Godot -Unreal)"
    for f in hair.glob("*.gltf"):
        strip_gltf(f, out / f.name)
    normals = base / "Base Characters" / "Textures" / "Normals Unity - Godot"
    texture(bodies / "T_Superhero_Male_Dark.png", out / "body_male_albedo.png")
    texture(bodies / "T_Superhero_Female_Dark_BaseColor.png", out / "body_female_albedo.png")
    texture(normals / "T_Superhero_Male_Normal.png", out / "body_male_normal.png")
    texture(normals / "T_Superhero_Female_Normal.png", out / "body_female_normal.png")
    texture(bodies / "T_Superhero_Male_Roughness.png", out / "body_male_rough.png", 512)
    texture(bodies / "T_Superhero_Female_Roughness.png", out / "body_female_rough.png", 512)
    for i in (1, 2):
        texture(hair / f"T_Hair_{i}_BaseColor.png", out / f"hair_{i}_albedo.png")
        texture(normals / f"T_Hair_{i}_Normal.png", out / f"hair_{i}_normal.png")
    texture(bodies / "T_Eye_Brown.png", out / "eye_albedo.png", 256)
    anim = ROOT / "anim"
    anim.mkdir(parents=True, exist_ok=True)
    shutil.copy(kits / "anim" / "Universal Animation Library[Standard]" / "Unreal-Godot" / "UAL1_Standard.glb", anim / "UAL1.glb")
    shutil.copy(kits / "anim2" / "Universal Animation Library 2[Standard]" / "Unreal-Godot" / "UAL2_Standard.glb", anim / "UAL2.glb")
    # The root-motion exports: tools/bake_anims.gd measures how fast each clip travels.
    shutil.copy(kits / "anim" / "Universal Animation Library[Standard]" / "Unreal-Godot" / "UAL1_Standard_RM.glb", anim / "UAL1_RM.glb")
    shutil.copy(kits / "anim2" / "Universal Animation Library 2[Standard]" / "Unreal-Godot" / "UAL2_Standard_RM.glb", anim / "UAL2_RM.glb")


def kit_models(names, gltf_dirs, tex_dirs, out: Path, size: int = 1024) -> None:
    """Copies glTF models with their buffers, and their textures resized, into one folder.
    Textures are looked up in tex_dirs first (e.g. a kit's Godot-convention normals)."""
    out.mkdir(parents=True, exist_ok=True)
    done = set()
    for n in names:
        src = next((d / f"{n}.gltf" for d in gltf_dirs if (d / f"{n}.gltf").exists()), None)
        if src is None:
            sys.exit(f"missing model {n}")
        d = json.loads(src.read_text())
        for b in d.get("buffers", []):
            shutil.copy(src.parent / b["uri"], out / b["uri"])
        for im in d.get("images", []):
            uri = im["uri"]
            if uri in done:
                continue
            path = next((t / uri for t in tex_dirs + [src.parent] if (t / uri).exists()), None)
            if path is None:
                sys.exit(f"missing texture {uri} for {n}")
            texture(path, out / uri, size)
            done.add(uri)
        (out / f"{n}.gltf").write_text(json.dumps(d))


VILLAGE = ["Floor_WoodDark", "Floor_UnevenBrick", "Floor_Brick", "Wall_Plaster_Straight", "Wall_UnevenBrick_Straight",
    "Wall_Plaster_Window_Wide_Round", "Wall_Plaster_Door_Round", "Wall_UnevenBrick_Door_Round", "Stair_Interior_Solid",
    "Roof_RoundTiles_4x4", "Roof_RoundTiles_6x6", "Roof_Front_Brick4", "Roof_Front_Brick6", "Prop_WoodenFence_Single", "Corner_Exterior_Wood", "Prop_Chimney",
    # Village houses.
    "Wall_UnevenBrick_Window_Wide_Round", "Wall_Plaster_WoodGrid", "Window_Wide_Round1", "WindowShutters_Wide_Round_Open",
    "WindowShutters_Wide_Round_Closed", "Door_1_Round", "Door_2_Round", "Roof_RoundTiles_6x8", "Roof_RoundTiles_4x6", "Prop_Chimney2",
    "Wall_Plaster_Window_Thin_Round", "Window_Thin_Round1", "Wall_UnevenBrick_Window_Thin_Round", "Corner_Exterior_Brick",
    "Prop_Vine2", "Prop_Vine5", "Balcony_Simple_Straight", "Overhang_Plaster_Long"]
SCIFI = ["Platform_Metal", "Platform_DarkPlates", "WallAstra_Straight", "WallAstra_Straight_Window", "TopSimple_Straight",
    "Door_Frame_Square", "Platform_Stairs_4WideTall", "Column_Simple", "Prop_Computer", "Prop_Crate3", "Prop_Light_Floor",
    # Outpost buildings and yard props.
    "WallAstra_Straight_Flat_Window", "WallBand_Straight", "WallWindow_Straight", "TopAstra_Straight", "TopCables_Straight",
    "TopPlastic_Straight", "Door_Metal", "Platform_Simple", "Platform_Squares", "Column_Astra", "Column_Pipes", "Column_Large_Straight",
    "Prop_Light_Wide", "Prop_Barrel_Large", "Prop_Crate4", "Prop_Vent_Big", "Prop_Vent_Small", "Prop_Fan_Small", "Prop_AccessPoint",
    "Prop_PipeHolder", "ShortWall_Metal2_Straight", "ShortWall_DarkMetal2_Straight", "Prop_Rail_4", "Prop_Cable_3"]
PROPS = ["Workbench", "Workbench_Drawers", "Anvil_Log", "Cauldron", "Whetstone", "Barrel", "Crate_Wooden", "Bucket_Metal",
    "Axe_Bronze", "Pickaxe_Bronze", "Sword_Bronze", "Shield_Wooden", "Torch_Metal",
    # Furniture and decor you can build.
    "Bed_Twin1", "Bench", "Bookcase_2", "Cabinet", "Chair_1", "Table_Large", "Stool", "Nightstand_Shelf", "Shelf_Simple",
    "Shelf_Arch", "CandleStick_Stand", "Lantern_Wall", "Banner_1", "Banner_2", "WeaponStand", "Dummy",
    "Stall_Empty", "Stall_Cart_Empty", "FarmCrate_Apple", "Barrel_Apples", "Crate_Metal", "Vase_2", "Pot_1", "BookStand",
    "Peg_Rack", "Cage_Small",
    # Furnishing village house interiors.
    "Bed_Twin2", "Table_Plate", "Table_Fork", "Table_Knife", "Mug", "Chalice", "CandleStick", "CandleStick_Triple",
    "Candle_1", "Candle_2", "Chandelier", "BookGroup_Medium_1", "BookGroup_Small_1", "Book_Stack_1", "Scroll_1",
    "Shelf_Small_Bottles", "Potion_1", "Potion_2", "Bottle_1", "Bag", "Pouch_Large", "Coin_Pile", "Bucket_Wooden_1",
    "FarmCrate_Carrot", "FarmCrate_Empty", "Barrel_Holder", "Anvil", "Chain_Coil", "Rope_1", "Pot_1_Lid", "Vase_4",
    "Vase_Rubble_Medium", "Book_5"]


def build_kits(kits: Path) -> None:
    vk = kits.parent / "village_kit" / "Medieval Village MegaKit[Standard]"
    kit_models(VILLAGE, [vk / "glTF"], [vk / "Textures" / "Normals Godot-Unity"], ROOT / "village")
    sf = kits / "scifi_mega" / "Modular SciFi MegaKit[Standard]"
    kit_models(SCIFI, [p for p in (sf / "glTF").rglob("*") if p.is_dir()] + [sf / "glTF"], [sf / "Textures"], ROOT / "scifi")
    fp = kits / "fantasy_props"
    kit_models(PROPS, [fp / "Exports" / "glTF"], [fp / "Textures"], ROOT / "props")


if __name__ == "__main__":
    k = Path(sys.argv[1])
    if len(sys.argv) > 2 and sys.argv[2] == "build":
        build_kits(k)
        sys.exit(0)
    people(k)
    build_kits(k)
    (ROOT / "LICENSE-CC0.txt").write_text(
        "Models and animations in this folder are by Quaternius (quaternius.com),\n"
        "released under CC0 1.0 Universal (public domain). No attribution required;\n"
        "credited here with thanks.\n")
