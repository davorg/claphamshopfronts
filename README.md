# Clapham Shopfronts

A holding page for a project documenting Clapham’s changing shopfronts. The static site lives in `docs/`, ready for GitHub Pages; there is no build step or JavaScript dependency.

## Preview locally

```sh
python3 -m http.server 8000 --directory docs
```

Visit `http://localhost:8000`.

## Design and artwork

The page uses Cormorant Garamond, DM Sans, and Caveat from Google Fonts, with local fallback fonts. Styles are in `docs/styles.css`.

The hero is a responsive collage of eight watercolour interpretations of the original photographs in `pics/`. It uses four columns on larger screens and two on phones. The paper, tape, and small rotations are CSS. Motion respects the visitor’s reduced-motion setting.

Finished paintings are in `docs/images/watercolours/`. Each has a full-size WebP and a smaller version for the page. A reusable, flattened collage is in `docs/images/hero-collage.webp`.

See [the artwork notes](artwork/README.md) for individual image links, source photographs, and the exact imagegen prompts.
