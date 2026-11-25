# 2. Get a Blender character model with copy-and-paste prompts

**Goal:** Make one original character model, turn it into a picture, and see that picture in CusOba. Start with one still image. You can add animations later.

**The important part:** Blender works with 3D models. CusOba's characters use **sprites**, which are flat pictures drawn on the map. A `.blend`, `.glb`, `.gltf`, or `.fbx` file is not a playable CusOba character. Make a 3D model, render a transparent PNG, then save it as `sprite.png` next to `character.json`.

## A. Pick and paste a prompt

A **prompt** is a set of instructions you give an AI tool. Check what your tool actually makes before asking it for a model:

| Your tool makes... | Use... | What you should get |
|---|---|---|
| Pictures only | **Prompt 1** | Reference art to feed into a 3D generator that accepts images, or to show a modeler. It's not a 3D file. |
| Downloadable 3D models | **Prompt 2** | An editable Blender `.blend` file or an importable `.glb` file. |
| Rigging or animation for existing models | **Prompt 3**, after Prompt 2 | The same model with moving parts and separate animations. Skip this for your first sprite. |

**How to paste:** Point at the start of the prompt text, hold the left mouse button, move the pointer to the end of the text, then let go. Hold **Ctrl**, tap **C**, and let go. Click inside the AI tool's message box, hold **Ctrl**, tap **V**, and let go. Click the tool's **Send** or **Generate** button. You can paste these as written or replace the character idea and colors with your own.

### Prompt 1: Concept art for Copper Scout

```text
Design an original character called Copper Scout for a colorful top-down
arena game: a squat forest courier robot with a large teal hood, copper
shoulder plates, chunky boots, and one bright amber eye.

Make a reference sheet with front, side, and back views of the SAME character.
Use eye-level straight-on views without perspective distortion. Keep the
proportions, colors, and accessories consistent. Stand it upright, legs
slightly apart and arms angled away from its sides. Show the whole body,
including the feet. Use a plain light gray background. No text, scenery,
particles, dramatic shadows, or extra characters.

Make the head, shoulders, and boots recognizable when the image is shrunk
to a small icon. Prefer large shapes and clear colors over tiny details.
```

If your 3D tool takes only one picture, ask the image tool for a **separate full-body front view** of the same character. Upload that single image rather than the whole sheet, which a 3D tool might interpret as three characters.

### Prompt 2: An editable 3D model for Blender

```text
Create an original, editable 3D model for Blender: Copper Scout, a squat
forest courier robot with a large teal hood, copper shoulder plates, chunky
boots, and one amber eye. Make it readable from a slightly overhead game
camera and at small size. Use a strong outline, large colored shapes, and
simple materials. The front and back should be easy to tell apart.

Create one full-body character, about 2 Blender units tall, standing upright
with its feet at ground height (Z = 0) and centered over X = 0, Y = 0. Keep
the hood, eye, boots, and arm plates editable. Use clean surfaces at joints
and no loose fragments, background, floor, base, logo, or floating effects.
Use a relaxed standing pose that leaves a little space between the arms
and body. Keep materials visible without missing external image files.

If you can deliver a .blend, include a square orthographic preview camera
about 42 degrees above the ground, pointed at the whole character, with simple
lighting and transparent PNG render output. If you only export .glb, embed
the textures in it. Deliver a real editable 3D file, not a screenshot.
```

For a different character, replace the first paragraph. For example: *“A round pebble gardener with a moss cap, bright orange gloves, two broad stone feet, and a simple watering can. Use a slate, green, and orange palette.”* Keep the delivery and framing instructions.

### Prompt 3: Animate the model without moving it across the scene

```text
Use my existing Copper Scout Blender model. Keep its silhouette, proportions,
colors, and accessories. Add an armature (a skeleton that poses the model)
and bind the mesh to it so the hood and armor don't collapse at the joints.
Keep the feet on the ground and the model centered when it is standing.

Make separate, named Blender Actions: idle (loop), run (loop), attack
(one swing with a clear contact pose), and cast_q (one wind-up, release,
and recovery). Idle and run should loop cleanly. Animate the run in place:
do not move the whole character across the floor. Keep the camera and
lighting still during each clip. Don't bake flashes or smoke into the model.

Return the editable Blender file if you can. Preview the four clips
separately so I can check the loop seam, the feet, and the main poses.
```

If a result looks wrong, ask for **one specific correction** before making the sprite. For example: *"Keep this model and palette. Remove the pedestal and return the updated 3D file."*

## B. Turn the model into one picture

1. **Open the model.** If you don't have [Blender](https://www.blender.org/download/), download and install it first. If you got a `.blend`, open Blender, choose **File > Open**, and pick that file. If you got a `.glb`, start a blank scene with **File > New > General**. Click **Cube** in the object list at the upper right, then press **Delete**. Choose **File > Import > glTF 2.0 (.glb/.gltf)**, select your `.glb`, and click **Import glTF 2.0**. Leave the default **Camera** and **Light** in the scene.
2. **Set up a camera if the file did not come with a usable one.** For a centered, 2-unit-tall model in the General scene, click **Camera** in the upper-right object list. Point inside the big 3D view and tap **N** to open its side panel. Click **Item**. Set **Location** X/Y/Z to `0`, `-5`, `5.3`, and **Rotation** X/Y/Z to `48`, `0`, `0` in degrees. To replace a number, double-click it, type the new number, and press **Enter**. With the camera still selected, click the green camera icon in the Properties panel on the lower right. Under **Lens**, set **Type** to **Orthographic** and **Orthographic Scale** to `3.5`. If a `.blend` has no camera at all, put one in first with **Add > Camera** in the 3D view.
3. **Set the background and size.** In the Properties panel, open **Render Properties > Film** and tick **Transparent**. In **Output Properties**, set the resolution X and Y to `256` and the percentage to `100%`. If you want to keep these changes, use **File > Save As** and save a new Blender file. Don't replace the original.
4. **Render** (make a picture): click **Render > Render Image** at the top. In the completed image, look for the whole character, with a little room above the head and below the feet. The background should show a gray checkerboard, which means it is see-through. If the character is cut off, increase **Orthographic Scale** and render again. If it is tiny, decrease the scale. If it's dark, check that there's a light (you can add one from **Add > Light > Sun** in the 3D view).
5. In the render window, click **Image > Save As...**. Pick a location you can find again, such as **Desktop**. Set the format to **PNG**, set **Color** to **RGBA** (the A preserves transparency), name it `sprite.png`, and click **Save As Image**.

If Blender opens a model with a different size or origin, the camera numbers above are only a starting point. The render is the check: the model should fill most of the picture, with the head and feet both visible and no floor, pedestal, or extra objects.

## C. See it in CusOba

1. If you haven't made **Copper Scout** yet, follow [Guide 1](add-a-character.md) through its Practice test first.
2. Put `sprite.png` **inside** `copper_scout`, right next to `character.json`. You do not need to copy the 3D file into CusOba. If you also want a card picture, put a second PNG called `portrait.png` in the same folder.
3. Back in CusOba, click **Reload content**, then **Practice (offline, add bots in the lobby)**. Pick **Training Arena**, click **Copper Scout**, and click **START MATCH**. Make sure the new sprite is visible and recognizable while walking around, not just when looking at it full-size in Blender. If it appears as a colored circle, check the exact filename and that you reloaded before opening Practice.

**Want real animation next?** Render separate frames and pack them into a **sprite sheet** (a grid of equally sized pictures). Keep the camera, zoom, and frame alignment consistent, and keep the character's feet near the same point in each frame. For eight directions, CusOba expects rows starting at screen-right and proceeding clockwise. Use the [sprite reference](../characters/MODDING.md#sprites) to connect the sheets to your character. [Clorinde's art folder](../characters/clorinde/art/) is a working example of the model-to-sheets workflow, not a required tool for the steps above.
