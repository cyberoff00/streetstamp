# StreetStamps Editorial Air Design

**Status:** Approved for planning
**Date:** 2026-03-29

## Goal

Refresh the StreetStamps iOS app from a functional but visually rigid interface into a restrained, premium travel product. The target direction is "high-end travel magazine" with a modern iOS material system: warm editorial surfaces, green-led branding, light glass navigation layers, and clear floating hierarchy.

## Product Intent

StreetStamps should feel like a travel journal curated by an editor, not a dashboard assembled from utility cards. The app needs to preserve its current information density and navigation model while replacing flat, static presentation with:

- editorial rhythm
- lighter material hierarchy
- quieter but more deliberate color use
- more breathable spacing and typography
- modern floating system chrome

This refresh should improve first impression, polish, and cohesion without making the app playful, retro, or visually loud.

## Experience Principles

### 1. Editorial First

Every page should read like a composed layout before it reads like a utility screen. Titles, hero blocks, and key actions should have intentional prominence. Supporting controls should step back.

### 2. Restrained Luxury

The interface should feel premium through spacing, proportion, texture, and hierarchy. It should not depend on saturated color, heavy shadows, or dense ornament.

### 3. Green as Identity, Not Wallpaper

Green remains the brand anchor, but it should appear as a refined signal color rather than a full-screen default. Large green fills should be rare and purposeful.

### 4. Floating System Layers

Navigation bars, tab bars, segmented controls, floating action areas, and modal surfaces should feel suspended above content with light translucency and gentle edge definition.

### 5. Stable Functionality

This is a visual system refactor, not a product rewrite. Existing flows, content models, and navigation behavior remain intact unless small interaction changes are required to support the new visual hierarchy.

## Art Direction

### Core Mood

- premium travel editorial
- modern field journal
- calm, airy, curated
- warm daylight rather than cold tech white

### What It Is Not

- not retro film cosplay
- not skeuomorphic leather/passport UI
- not generic glassmorphism everywhere
- not bold neon or luxury fashion black-gold branding

## Color Direction

The palette should stay recognizably green, but mature into a softer, more editorial system.

### Primary Palette Roles

- `Brand Green`: a deeper moss or sage-leaning green for emphasis, selected tabs, CTAs, active filters, and progress cues
- `Mist Background`: a warm off-white base with a subtle green-gray cast to replace plain white
- `Paper Surface`: the main content surface for editorial cards and sections
- `Ink Text`: a softened near-black with green undertones for major typography
- `Fog Border`: a pale neutral-green divider for thin strokes and separators
- `Metal Accent`: rare warm gray or muted champagne accents for badges, premium markers, or collectible moments

### Usage Rules

- Use green primarily on high-value interaction points, not as a blanket fill.
- Prefer tonal depth over saturation.
- Avoid introducing unrelated accent families unless tied to existing semantic states.
- Keep destructive and warning colors standard and isolated to system moments.

## Material System

The app should use three visual layers consistently.

### 1. Base Layer

The page background should feel soft and atmospheric, like paper lit by daylight. It can use subtle gradients and faint tonal shifts, but should remain understated.

### 2. Floating Glass Layer

Used for:

- top navigation chrome
- tab bar
- floating filters
- quick action trays
- sheets and transient overlays

Characteristics:

- semi-translucent
- light blur
- soft white highlight edge
- minimal tint from surrounding context
- quiet, diffused shadow

### 3. Editorial Card Layer

Used for:

- destination summaries
- memory cards
- progress modules
- stat and profile blocks

Characteristics:

- more paper-like than glass-like
- nearly opaque
- soft corners
- restrained shadow
- thin border or tonal edge instead of obvious outlines

This split is important. If every card becomes glass, the app loses clarity and feels generic.

## Typography Direction

Typography should be composed like editorial design: less app-default, more structured hierarchy.

### Title Behavior

- primary page titles should feel like magazine section headers
- use stronger scale contrast, not just heavier weight
- avoid making everything uppercase unless it serves a specific label function

### Body Behavior

- body text should remain highly readable and efficient
- supporting text should use color and spacing to recede, not tiny font sizes alone

### Hierarchy Rules

- three dominant levels per screen: headline, focal content, supporting metadata
- captions and labels should align to a shared rhythm instead of appearing as many unrelated text sizes

## Layout and Spacing

The current app feels rigid partly because many screens read as stacked functional blocks. The refresh should create more breathing room and clearer rhythm.

### Rules

- increase vertical breathing room around headers and hero modules
- reduce the sense of every element occupying equal visual weight
- use grouped spacing rather than uniform padding everywhere
- let some sections feel intentionally open

## Navigation Chrome

### Top Navigation

Top headers should become slim floating glass bars that sit above the page content. They should feel like a lens or label layer, not a thick utility strip.

Requirements:

- translucent material
- fine edge highlight
- less visual heaviness than current opaque card bars
- stable title alignment
- support for menu, back, and right actions without breaking symmetry

### Tab Bar

The tab bar should feel lighter and more premium:

- floating above the page bottom
- thinner visual footprint
- selected state uses tonal green, subtle glow, and higher text confidence
- unselected state stays quiet and elegant

The tab bar should read as system chrome, not a solid footer block.

## Page Structure

Each major screen should adopt an editorial composition instead of a generic feed scaffold.

### Home

The Home tab should become the strongest statement page in the app.

Composition:

- atmospheric top field
- confident but restrained main heading
- primary start action as the hero object
- secondary hints or status tucked below rather than competing with the hero

The current layout centers the CTA but still feels static. The new version should feel staged and intentional.

### Memory / Collection

- cover-style page intro
- cleaner card stacking
- filters in floating glass containers
- stronger image/content hierarchy

### Lifelog / World

- map and progress modules should feel like an atlas spread
- data summaries should be grouped into calmer paper cards
- controls should float rather than be boxed into rigid slabs

### Friends / Social

- keep information efficient
- use more restrained surfaces so social content feels curated rather than noisy
- emphasize people and moments over UI framing

### Profile

- treat profile as an editorial dossier rather than a settings-adjacent page
- avatar, level, and achievements should feel collectible and composed

## Component Rules

### Buttons

- primary buttons: restrained green, slightly sculpted through light and shadow, never candy-like
- secondary buttons: paper or glass depending on context
- icon buttons in chrome should feel embedded into material, not pasted on top

### Chips and Filters

- place in floating glass groups
- selected state should rely on tonal contrast and text confidence, not thick strokes alone

### Sheets and Modals

- use floating material with more depth than page chrome
- preserve clarity with near-opaque content panels where needed
- keep corners soft and spacious

### Lists

- avoid endless repeated white rows
- group rows into composed sections with clear breathing room

## Motion Direction

Motion should be subtle and precise.

### Principles

- use low-amplitude spring transitions
- favor fade + slight vertical lift over large scale transforms
- introduce content in staggered layers: title, primary module, then supporting content
- give glass chrome quicker feedback than content cards

### Avoid

- bouncy toy-like motion
- constant ambient animation across the screen
- large parallax effects

## Implementation Strategy

The refresh should be delivered in two phases.

### Phase 1: Foundation

- define new theme tokens
- create reusable material primitives
- update unified navigation and tab chrome
- refresh Home as the reference page

### Phase 2: Rollout

- expand the visual system to Memory, Lifelog, Friends, and Profile
- standardize cards, chips, sheets, and headers
- smooth transitions and interaction states

## Success Criteria

The redesign is successful when:

- the app feels visually unified across tabs
- the first impression is premium, calm, and distinctive
- green remains recognizably on-brand without dominating every screen
- headers and tab bars feel lighter and more modern
- content cards feel editorial rather than utility-first
- the app remains readable and efficient during real use

## Constraints

- preserve existing navigation flows unless a small visual interaction change is necessary
- avoid introducing broad new product scope
- stay compatible with the current SwiftUI structure where practical
- do not let visual experimentation degrade clarity, accessibility, or performance
