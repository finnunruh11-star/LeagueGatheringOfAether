"""Build original lane minion models and render their transparent Godot sprites."""

from pathlib import Path

import bpy
from mathutils import Vector


ART = Path(__file__).resolve().parent
TEAMS = {
    "blue": ("2862C8", "63BEFF", "B0E8FF"),
    "red": ("B12639", "FF6854", "FFC288"),
}


def material(name, hex_color, metallic=0.0, glow=0.0):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    color = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                  for c in channels) + (1.0,)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.4
    shader.inputs["Emission Color"].default_value = color
    shader.inputs["Emission Strength"].default_value = glow
    return mat


def finish(name, mat, bevel=0.0):
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        edge = obj.modifiers.new("Rounded edges", "BEVEL")
        edge.width = bevel
        edge.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def box(name, pos, size, mat, bevel=0.07, tilt=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler.y = tilt
    return finish(name, mat, bevel)


def gem(name, pos, size, mat, detail=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=1, location=pos)
    bpy.context.object.scale = size
    return finish(name, mat)


def rod(name, start, end, radius, mat, tip=None, sides=12):
    a, b = Vector(start), Vector(end)
    bpy.ops.mesh.primitive_cone_add(
        vertices=sides, radius1=radius, radius2=radius if tip is None else tip,
        depth=(b - a).length, location=(a + b) / 2,
    )
    bpy.context.object.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return finish(name, mat, 0.025)


def helmet(pos, size, armor, light):
    x, y, z = pos
    gem("Helmet", pos, (0.53 * size, 0.47 * size, 0.52 * size), armor, 2)
    box("Inset visor", (x + .12 * size, y - .39 * size, z - .05 * size),
        (.61 * size, .22 * size, .25 * size), dark)
    for dx in (-.03, .27):
        box("Eye", (x + dx * size, y - .506 * size, z - .035 * size),
            (.13 * size, .032, .10 * size), light, .02)


def melee(armor, trim, light):
    for x, y in ((-.30, -.20), (.30, .20)):
        box("Boot", (x + .09, y, .21), (.49, .43, .39), dark)
    box("Cuirass", (0, 0, .74), (1.06, .76, .83), armor, .16)
    helmet((.12, .02, 1.45), .87, steel, light)
    box("Shield rim", (-.41, -.50, .79), (.84, .26, 1.04), steel, .14, -.18)
    box("Shield enamel", (-.41, -.64, .79), (.66, .12, .86), armor, .12, -.18)
    gem("Shield boss", (-.40, -.72, .87), (.19, .10, .25), trim)
    gem("Sword hand", (.56, .12, .8), (.23, .23, .23), dark, 2)
    rod("Hilt", (.47, .12, .67), (.82, .12, 1.01), .10, dark)
    rod("Crossguard", (.66, .12, 1.20), (.99, .12, .87), .09, trim)
    rod("Blade", (.82, .12, 1.01), (1.48, .12, 1.67), .17, steel, .018, 4)


def ranged(armor, trim, light):
    rod("Mantle", (0, 0, .10), (0, 0, 1.21), .68, armor, .39, 8)
    rod("Hem", (0, 0, .10), (0, 0, .28), .69, trim, .64, 8)
    gem("Hood", (-.10, .03, 1.40), (.54, .46, .74), armor, 2)
    gem("Hood opening", (.04, -.32, 1.42), (.37, .22, .37), dark, 2)
    for x in (-.08, .20):
        gem("Eye", (x, -.515, 1.43), (.086, .045, .081), light, 2)
    gem("Mantle clasp", (.02, -.47, .93), (.15, .12, .19), trim)
    rod("Staff", (.58, -.20, .04), (1.05, -.20, 1.63), .09, dark)
    rod("Staff collar", (.96, -.20, 1.38), (1.05, -.20, 1.69), .17, steel)
    gem("Staff crystal", (1.09, -.20, 1.86), (.28, .26, .40), light)


def siege(armor, trim, light):
    box("Chassis", (0, 0, .55), (1.91, 1.30, .60), armor, .16)
    for x in (-.66, .66):
        for side in (-1, 1):
            rod("Tire", (x, side * .53, .42), (x, side * .91, .42), .42, dark)
            rod("Hub", (x, side * .89, .42), (x, side * .96, .42), .28, steel, sides=8)
            rod("Hub bolt", (x, side * .95, .42), (x, side * 1.00, .42), .13, trim, sides=6)
    box("Turret", (-.15, 0, 1.03), (1.27, .99, .73), armor, .15)
    for x in (-.52, -.11):
        box("Charge port", (x, -.50, 1.12), (.24, .07, .19), light, .04)
    rod("Barrel", (.13, -.15, 1.12), (1.52, -.27, 1.40), .29, steel, .25)
    rod("Muzzle housing", (1.19, -.24, 1.34), (1.58, -.28, 1.42), .34, armor)
    rod("Muzzle opening", (1.57, -.28, 1.42), (1.603, -.283, 1.427), .24, dark)
    rod("Muzzle core", (1.60, -.283, 1.427), (1.62, -.285, 1.431), .12, light)


def super_minion(armor, trim, light):
    for x, y in ((-.40, -.24), (.38, .20)):
        box("Greave", (x, y, .36), (.65, .60, .67), steel, .13)
        box("Foot", (x + .10, y - .11, .13), (.72, .68, .25), dark)
    box("Chest plate", (0, 0, 1.02), (1.38, .97, .92), armor, .21)
    gem("Reactor surround", (.04, -.50, 1.06), (.37, .16, .40), dark)
    gem("Reactor", (.04, -.62, 1.06), (.24, .13, .27), light)
    helmet((.12, .02, 1.69), .73, steel, light)
    for x, y, z in ((-.81, .02, 1.28), (.76, .23, 1.36)):
        gem("Pauldron", (x, y, z), (.48, .46, .45), armor, 2)
        gem("Pauldron crest", (x, y, z + .34), (.25, .26, .22), trim)
        box("Gauntlet", (x + .17, y - .16, .67), (.69, .65, .66), steel, .18, .24)
        box("Gauntlet inset", (x + .20, y - .49, .66), (.34, .08, .19), trim, .04)


def rig(scene):
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples = 32
    scene.render.resolution_x = scene.render.resolution_y = 144
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Khronos PBR Neutral"
    bpy.ops.object.camera_add(location=(0, -7, 7.5))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.8
    camera.rotation_euler = (Vector((0, 0, .89)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    for name, pos, power, size in (
        ("Key", (-3, -4, 6), 560, 4),
        ("Fill", (4, -2, 3), 280, 4),
        ("Rim", (1, 4, 5), 650, 3),
    ):
        bpy.ops.object.light_add(type="AREA", location=pos)
        lamp = bpy.context.object
        lamp.name = name
        lamp.data.energy, lamp.data.size = power, size
        lamp.rotation_euler = (-lamp.location).to_track_quat("-Z", "Y").to_euler()
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
            area.spaces.active.shading.color_type = "MATERIAL"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global dark, steel
    dark = material("Ink", "161F31", .15)
    steel = material("Bright steel", "A6B9CC", .5)
    empty = bpy.context.scene
    scenes = []
    for team, (base, accent, core) in TEAMS.items():
        palette = (material(f"{team} armor", base, .3),
                   material(f"{team} trim", accent, .2),
                   material(f"{team} light", core, glow=.7))
        for kind, build in (("melee", melee), ("ranged", ranged),
                            ("siege", siege), ("super", super_minion)):
            scene = bpy.data.scenes.new(f"{team}_{kind}")
            bpy.context.window.scene = scene
            build(*palette)
            rig(scene)
            scene.render.filepath = f"//../{scene.name}.png"
            scenes.append(scene)
    bpy.context.window.scene = scenes[0]
    bpy.data.scenes.remove(empty)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ART / "minions.blend"), compress=True)
    for scene in scenes:
        bpy.context.window.scene = scene
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
