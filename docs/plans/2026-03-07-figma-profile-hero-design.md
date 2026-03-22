# Figma Profile Hero Design

**Date:** 2026-03-07

**Goal:** Restyle the friend profile upper half to match the provided Figma frame, while keeping the sofa scene on the original mint palette. Apply the same sofa-scene backdrop language to my profile card without converting it into a full-bleed page.

## Figma Summary

The referenced frame (`wy0b6jKyQt6om7mtEazlmM`, node `174:4`) has four defining traits:

- A full-width mint hero background on the friend page
- A wider, flatter sofa scene with lamp, floor shadow, and speech bubbles
- A white rounded info sheet docked under the hero
- Floating glass-style top controls instead of the current header bar

## Product Translation

### Friend Profile

- Replace the current top bar plus card-like hero with a full-bleed mint hero
- Keep existing data and actions (`坐一坐`, delete friend, stats), but restyle them to match the Figma composition
- Keep the sofa palette on the previous mint values rather than switching to the more saturated teal from the raw Figma export
- Move optional bio text out of the hero so the upper half stays visually aligned with the design

### My Profile

- Reuse the same sofa-scene artwork and mint backdrop treatment
- Keep the layout inside the existing rounded profile card rather than expanding it to full width
- Preserve my-profile-only interactions such as the equipment shortcut and name editing

## Shared Approach

- Convert `SofaProfileSceneView` from a fully boxed scene into the reusable sofa artwork layer
- Add shared hero chrome pieces for mint backdrop, level pill, and stat row styling
- Compose friend and self headers differently around the same artwork so they stay visually related without forcing identical page structure

## Validation

- Visual match against the Figma screenshot for the friend upper half
- My profile uses the same mint sofa backdrop language but remains contained in a rounded card
- Build the app target and confirm no compilation regressions
