# NinePatch Studio

A native macOS GIF-first editor for animated chat-bubble decorations.

## Run

Open `NinePatchStudio.xcodeproj` in Xcode, or build from this directory:

```bash
xcodebuild -project NinePatchStudio.xcodeproj -scheme NinePatchStudio -configuration Debug -derivedDataPath /tmp/ninepatchstudio-derived CODE_SIGNING_ALLOWED=NO build
open "/tmp/ninepatchstudio-derived/Build/Products/Debug/NinePatch Studio.app"
```

## Workflow

1. Drop an animated GIF onto the window, or use **Drop / Import GIF**. The importer also accepts image formats supported by macOS ImageIO, including PNG and JPEG.
2. To import a pre-separated animation, select multiple image files together. Frames are sorted by filename and must have identical dimensions; each frame is assigned 0.10 seconds.
3. Inspect the animation using Play/Pause and the frame scrubber.
4. Drag the cyan guides or edit the stretch inset values. The same nine-slice boundaries apply to every frame. Orange guides show suggested content padding.
5. Resize the live preview to check the bubble at different dimensions.
6. Click **Export Frames + JSON**, choose a parent folder, and the app writes a new `NinePatchExport-*` folder containing `frame_0000.png`, `frame_0001.png`, etc. plus `ninepatch-config.json`. The JSON stores source dimensions, per-frame durations, stretch insets, and content insets.

## Integration note

The export provides PNG frames and metadata for integration. The current `NinePatchFrameAnimation` renderer consumes image asset names from the app's asset catalog, so the exported files still need to be added to the target app's assets and mapped to the `frameNames` array. The JSON is an integration manifest, not a runtime loader by itself.

Animated WebP support depends on the macOS ImageIO decoder. GIF is the primary input format.
