# StudyQuest branding

An open book becomes a rising exploration path, representing daily learning and
stage progression. The app icon uses a blue-to-cyan rounded tile, white pages,
and restrained dimensional shading. Neither asset contains text.

- `studyquest-icon.png`: 1024 × 1024 RGBA master for the macOS app icon, with
  transparent space outside the rounded tile.
- `studyquest-mark.png`: 1024 × 1024 RGBA standalone blue interpretation of the
  book/path symbol, intended for light backgrounds. Use the app icon when stronger
  separation from a dark background is needed.
- `StudyQuest.icns`: the packaged app icon, containing 16, 32, 128, 256, and 512pt
  representations at 1× and 2× resolution.

Generated with the built-in imagegen tool. See [PROMPTS.md](PROMPTS.md) for the
generation and refinement prompts. The mark is a simplified generated variant,
not a pixel-exact extraction. Both final PNGs were resized to 1024px using `sips`.

## Regenerate the macOS icon

Run from the repository root on macOS. This uses the checked-in PNG; it does not
call an image service or require an API key.

```bash
mkdir -p build/StudyQuest.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/branding/studyquest-icon.png \
    --out "build/StudyQuest.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  sips -z "$double" "$double" assets/branding/studyquest-icon.png \
    --out "build/StudyQuest.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns build/StudyQuest.iconset -o assets/branding/StudyQuest.icns
```

Then run `./scripts/bundle-app.sh`. It copies the icon to the app bundle's
`Contents/Resources` and sets `CFBundleIconFile` before signing the bundle.
