# Image generation prompts

Tool: built-in `imagegen`, with `transparent_background: true`. PNGs are generated
artwork, not vector masters. The selected outputs were resized to 1024 × 1024
with macOS `sips`; no external image API was used.

## App icon — initial generation

Use case: logo-brand. Create ONE finished native macOS app icon for StudyQuest, a serious but motivating learning application with daily study quests, spaced repetition, and stage progression. Asset: square 1024x1024 PNG app icon, not a mockup or presentation sheet. A refined rounded-square blue-to-cyan gradient tile with subtle dimensional bevel and restrained soft lighting, centered with transparent space outside the tile, approximately 10% transparent canvas inset per side, macOS Dock-compatible proportions. The sole central white sculptural mark combines an OPEN BOOK with a clear UPWARD EXPLORATION PATH: two broad simple white page shapes, the central book crease naturally flowing upward into a gently ascending ribbon/path with a simple angled tip. Aim for a memorable integrated silhouette, a book that opens toward progress, rather than multiple overlaid symbols. Large thick forms, generous negative space, very few elements, strong contrast, legible at 16 and 32 pixels. White and pale icy cyan highlights on saturated deep blue lower-left to cyan upper-right base. Elegant subtle depth, mostly front-facing, clean geometric edges. No letters, no words, no numbers, no star, no extra badges, no outlines of tiny page lines, no ornament, no photoreal background, no watermark. Transparent background outside rounded-square tile, not checkerboard drawn into pixels.

## App icon — first refinement

Reference: initial generated app icon.

Edit this exact app icon. Preserve the central white open-book and rising curved arrow mark, blue-cyan gradient, shape, proportions, and lighting. Fix ONLY exterior alpha edge quality: remove ALL colored speckles, cyan mist, blue noise, halo, and detached pixels outside the rounded-square tile. The entire surrounding 10% canvas margin must be completely transparent RGBA alpha=0. Give the rounded-square perimeter a precise smooth antialiased geometric boundary, no exterior shadow or glow. Keep the tile and symbol otherwise unchanged. Output one square icon only, no text, no checkerboard texture.

## App icon — final refinement

Reference: first refined app icon. Selected output: `studyquest-icon.png`.

Use the uploaded icon as an identity reference. Create a clean professional production version of this exact blue-cyan rounded-square macOS app icon. Keep the same white open book and white curved rising path/arrow silhouette, same layout, same palette and mild dimensionality. Re-render the whole asset from scratch as clean vector-like shapes with only very smooth gradients and restrained interior shading. Tile perimeter must be perfectly smooth crisp rounded rectangle with antialiasing; absolute clean fully transparent canvas outside it; NO exterior shadows, NO glow, NO pixels outside perimeter, NO fuzzy colored border, NO speckles, NO grain. Make tile occupy 80% of canvas width and height and precisely centered. One square 1024x1024 icon only.

## Standalone mark — generation

Use case logo-brand. Generate ONE clean standalone transparent-background brand symbol for StudyQuest. Flat vector-like filled solid COBALT BLUE (#1260E8) silhouette: a wide open book at bottom with two simple curved pages meeting at a downward-pointing central spine; from the center a thick gently S-curved path rises above the book, ending in a clear arrow pointing upper right. Elegant broad page shapes, no printed lines, no words, no page fold textures. Path and book are integrated into ONE memorable logo, with a clean transparent gap between the arrow and the right page. Simple smooth crisp antialiased shapes, no tiny strokes. Center the mark in a square canvas at roughly two thirds width and half height. Single solid blue fill throughout. Completely transparent outside symbol including inner gaps. No shadows, no gradient, no texture, no surrounding badge or square tile, no mockup, no outlines, no extra objects, no watermark.

## Standalone mark — final refinement

Reference: generated blue standalone mark. Selected output: `studyquest-mark.png`.

Clean up this logo into a finished brand asset. Remove ALL blue glow, all haze, all shadows and all semi-transparent exterior color. Keep only the solid blue open book and curved arrow as hard-edged filled shapes. The logo must look like a precision SVG vector export: completely opaque uniform blue inside the shapes, completely transparent outside the shapes. Include a thin transparent V-shaped crease between the two book pages to keep it legible. No gradients, no light, no effects, no grain, no speckles. Output on transparent square canvas.
