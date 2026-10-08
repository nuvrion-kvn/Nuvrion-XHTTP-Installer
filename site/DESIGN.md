---
version: alpha
name: "Атлас пива / Beer Atlas"
description: "A warm glass beer atlas over the StreamMedia animated topographic background"
colors:
  background: "#17110c"
  panel: "#2d2119"
  raised: "#433025"
  line: "#68503a"
  text: "#f5ebdc"
  muted: "#c2af96"
  primary: "#e5bd7c"
  gold: "#e5bd7c"
  success: "#c6cea4"
  image-stage: "#e5d5b9"
  scrollbar: "#9d8263"
  glass: "rgba(50, 35, 23, 0.10)"
  glass-strong: "rgba(43, 30, 21, 0.42)"
  glass-border: "rgba(247, 213, 164, 0.22)"
  glass-highlight: "rgba(255, 238, 209, 0.15)"
  glass-image: "rgba(245, 220, 182, 0.12)"
typography:
  display:
    fontFamily: "Lora, Georgia, serif"
  body:
    fontFamily: "Nunito Sans, Arial, sans-serif"
  utility:
    fontFamily: "Manrope, Arial, sans-serif"
rounded:
  DEFAULT: "18px"
  control: "12px"
  pill: "999px"
spacing:
  page-max: "1520px"
  gutter: "48px"
  section-gap: "80px"
components:
  button:
    height: "44px"
    backgroundColor: "{colors.primary}"
    textColor: "{colors.background}"
    rounded: "{rounded.control}"
  card:
    rounded: "{rounded.DEFAULT}"
    backgroundColor: "{colors.glass}"
    textColor: "{colors.text}"
  dialog:
    rounded: "24px"
    backgroundColor: "{colors.glass-strong}"
    textColor: "{colors.text}"
---

# Атлас пива Design System

## Overview

Creative North Star: a collector’s bottle shelf behind warm frosted glass, floating over the slowly flowing contours from StreamMedia. The existing editorial catalog structure comes from the StreamMedia reference. The current user explicitly requested warmer typography, colors, iPhone-like translucent panels, more beer and Animated Topography, then the actual reference background and transparent bottle cutouts. Audience: Russian and English readers exploring real beer styles on phone, tablet or desktop. Product register: one searchable catalog and one shared detail dialog, with a small editorial guide.

Runtime token ownership: Model A. `scripts/generate.py` reads these frontmatter colors, typography, rounded and spacing values and writes `dist/tokens.css`. `style.css` consumes generated variables. Never hand-edit generated tokens. The background uses the reference's unmodified MIT-licensed Topolines 0.3.0 engine, with the original seed, geometry and idle motion settings. The latest user request adapts only the background palette to warm coffee, bronze ambient glows and honey contours (#cba875). Foreground tokens own glass surfaces and type.

## Colors

Coffee canvas base and muted honey contours sit behind walnut and cocoa foreground surfaces. Honey primary marks active controls, links, focus and ABV. Text is ivory and secondary text warm sand. Glass uses explicitly translucent brown fills and champagne borders. Product stages use translucent opal glass. Packshots have true alpha backgrounds and normal blending, preserving white labels and glass highlights without rectangular photo mattes. Prefer official transparent originals; otherwise isolate the supplied product with background extraction. Intentional lifestyle photography uses cover framing. Scrollbars inherit a visible warm bronze thumb. Forced colors preserve system controls.

## Typography

Self-hosted Lora and Nunito Sans variable fonts cover Cyrillic and Latin. Lora gives display and card names a warm book-like character at weight 500–650; Nunito Sans body is softer and readable at 450 with 1.65 line height. Manrope remains the utility/numeric face with tabular figures. Every heading is sentence-like without a trailing period. No compressed uppercase paragraphs.

The wordmark is the deliberate uppercase exception: «АТЛАС ПИВА» in Russian and «BEER ATLAS» in English. Keep both words on one line in the header and footer. Header size is 26px desktop, 22px phone and 20px on narrow phones; the footer is 23px.

## Layout

Max width 1520px, 48px desktop gutters, 24px tablet, 16px mobile. Hero copy on left, beer flight on right. Catalog is five columns above 1250px, four above 1000px, three above 720px, two on phones. At 360px cards remain at least 150px wide. Document owns page scrolling. Detail dialog owns its long body scroller and retains a reachable close bar.

## Elevation & Depth

Translucent surfaces use lighter glass: ordinary panel opacity 10%, stronger overlay opacity 42%, opal product stage opacity 12%. The combined card/stage tint is about 21% opaque. Backdrop blur is 3px for shared surfaces, 2px for phone cards, 4px for the header and 6px for the detail dialog. Small badges use 2px and feedback/animation controls 3px. Keep foreground text and product images fully opaque. Saturation and the prefixed Safari property remain. A thin champagne rim and very subtle highlight give the glass a readable edge. Hero photography has a warm dark fade. Card hover lifts 3px and brightens its border. The reference Topolines WebGL canvas stays behind the whole page. It caps DPR at 1 and frame rate at 18 desktop/12 mobile, stops in hidden tabs, uses one static frame for reduced motion, and exposes a bilingual pause/resume button. Without WebGL it shows the reference's CSS contour fallback and explains that the background is static. Avoid expensive pointer refraction and neon glows. Unsupported backdrop-filter gets a warmer, more opaque fallback with legible text.

## Shapes

Cards 18px, controls 12px, pills 999px, detail surface 24px. Quiet geometric line icons. Ingredient explanations use readable disclosure rows, not ornamental bubbles.

## Components

Native buttons own actions; anchors own section navigation. Native select owns sorting/country/strength popups; OS geometry is accepted. Search is a labeled search input with a localized clear button. Catalog state and locale persist in URL. Cards use one open button and a separate favorite button, never nested.

Dialog owner: one native `dialog.showModal()` surface with browser inert background/focus containment, Escape, explicit close, focus restoration and stable scroll lock. Favorite owner: one state operation for catalog and details. Status owner: one polite live region and one stable toast.

Default, hover, focus and pressed states are shared. Active filters use honey with aria-pressed. Pending initial data has a labeled spinner; failure has retry. Empty favorites explain how to add; no matches offer reset. Reduced motion removes transforms and smooth scrolling and freezes Animated Topography. No browser alerts or prompts.

The countries strip continuously moves left over 28 seconds per sequence. Four equal copies and a one-quarter track translation create a seamless loop without empty gaps across the supported page width. Only the first copy is exposed to assistive technology. The shared animation control pauses both contours and the strip; keyboard focus pauses the strip for reading. Reduced motion makes a single manually scrollable country sequence.

## Do's and Don'ts

- Keep real beer labels prominent and readable
- Translate content and accessible names together
- Link manufacturer sources and label incomplete composition
- Do not invent ratings or IBU figures
- Do not add periods to headings
