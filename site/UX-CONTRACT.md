# Catalog interaction contract

Business source: PRODUCT.md, derived from the explicit user brief. This single list/detail experience has no remote writes or destructive operations.

| Capability     | Canonical owner             | Source of truth | Allowed variants          | Verification          |
| -------------- | --------------------------- | --------------- | ------------------------- | --------------------- |
| Select/Listbox | Native select in index.html | DESIGN.md       | sort, country, strength   | DOM interaction check |
| Form           | Search in app.mjs           | PRODUCT.md      | local search              | search/clear checks   |
| Scrollbar      | Global style.css            | DESIGN.md       | dialog stable gutter      | static audit          |
| Toast          | notify in app.mjs           | this contract   | favorite/storage feedback | DOM check             |
| Detail overlay | native dialog in app.mjs    | this contract   | beer, about               | open/close checks     |

Search, style, origin, country, strength, sort, favorites mode and locale are URL state. Filtering resets the visible count to 20. Load more appends 20. Closing a beer restores catalog state and logical trigger focus. Browser Back closes the detail without clearing filters. Russian/English switches translate every owned label and keep the selected beer and filters.

Favorites save locally with guarded storage access. Storage failures keep session favorites and explain the limit. No empty list looks like a load failure. Failed initial catalog loading offers reload. Packshot failures display a labeled no-photo state and preserve card geometry.

Modal uses browser modal semantics, accessible title, inert background and browser focus containment. Close and Escape remove detail URL state and restore focus. Native select popup behavior is deliberately platform-owned. The main document scrolls; long modal content scrolls within its body.

Animated Topography is decorative and aria-hidden. One bilingual animation pause/resume button controls both the background and the countries marquee independently of filters. It remains available when WebGL is absent because the CSS marquee still works. The user's pause choice persists locally when possible. Reduced-motion preference makes a static background and one manually scrollable country sequence, and disables the motion toggle with explanatory text. Hidden tabs do not animate. Duplicated country sequences are aria-hidden; keyboard focus pauses the marquee for reading. Safari uses prefixed backdrop blur; browsers lacking blur retain readable, more opaque surfaces. Foreground focus and click targets never move with the background.
