# DLSS, sharpening and related fork changes

This fork adds NVIDIA DLSS Super Resolution to the VR adapter, plus a few fixes
found while playing with threaded rendering.

## DLSS

Launcher: **Play solo**, **Host a game** and **Join a friend** show a **DLSS**
dropdown (Off, DLAA, Quality, Balanced, Performance, Ultra Performance) and a
**DLSS sharpness** slider (0 = off, 1-100) when VR is selected. The choices are
saved in `launcher.json`; a join saves only these personal settings.

| Mode | Per-axis input | Index example (2688 output) |
| --- | --- | --- |
| DLAA | 100% | 2688 x 2688 |
| Quality | 66.7% | 1792 x 1792 |
| Balanced | 58% | 1559 x 1559 |
| Performance | 50% | 1344 x 1344 |
| Ultra Performance | 33.3% | 896 x 896 |

The output size follows the existing render-scale setting.

How it works (`native/adapter/Dlss.{h,cpp}`):

- Each sequential eye pass renders at the mode's input size. `StereoViews`
  applies a Halton(2,3) sub-pixel jitter to the submitted projection and records
  the unjittered matrices (jitter conventions as in the Dishonored VR mod).
- When an eye pass completes, its snapshot command copies the eye image and the
  HDR scene's D24S8 depth target, generates camera-only motion vectors from depth
  and a double-precision current-to-previous clip matrix, and evaluates that
  eye's own NGX feature (separate histories). All GPU work runs in a private
  `ID3DDeviceContextState`, so engine state is untouched.
- Optional AMD FidelityFX CAS (MIT) sharpening follows DLSS; DLSS 2.5.1+ ignores
  its own sharpness parameter.
- Any NGX failure is logged and the adapter returns to ordinary rendering.
- The launcher passes `KF2VR_DLSS`, `KF2VR_DLSS_SHARPNESS` and `KF2VR_NGX_DIR`
  (the release's `Native` folder, which holds `nvngx_dlss.dll`).

Motion vectors model the camera only; moving Zeds, hands and weapons rely on
DLSS's colour rejection.

Tests: `kf2vr_dlss_math_test` (ctest) checks jitter direction, reprojection,
camera origin and mode sizes. `kf2vr_dlss_smoke <dir with nvngx_dlss.dll>` runs
every mode, with and without sharpening, on an RTX GPU.

## Threaded-rendering HUD fix

With threaded rendering, KF2 creates the HUD ScriptedTextures as
`R8G8B8A8_UNORM` and binds render targets as slot lists, so `HudTextAlpha` never
registered them: wheel icons collapsed to opaque strokes and interaction text
vanished. Registration now accepts the UNORM format and single-target slot lists;
under threaded rendering only, a registration may also match recently cleared
HUD-size textures or claim the next bind of its exact size. One-thread behaviour
is unchanged.

## Bloat bile screen splatter

The Bloat bile camera-lens particles (`KFCameraLensEmit_Puke`, `_Puke_Light`)
are a full-view translucent emitter whose overdraw is very costly at VR eye
resolution. The launcher checkbox **Hide Bloat bile screen splatter** (default on)
sets `KF2VR_HIDE_BILE_LENS=1`, and the adapter skips `AddCameraLensEffect` for
those classes. Other screen effects are unchanged.

## Support grip lock (physical stocks)

A support grip acquired at the foregrip stays held, and engaged for two-hand
accuracy, while the grip is held, however far the tracked support position
drifts; releasing the grip lets go (`VRHandInventory.Update`,
`VRWeaponPresenter.SupportIsEngaged`). Pair with **Support-hand aim: Physical
stock - gun hand aims**.

## Launcher

Pages that outgrow the window grow it to fit, and Back/Start keep their space.
