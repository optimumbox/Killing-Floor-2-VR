# Single-pass stereo

**Single-pass stereo** (launcher, VR, Steam build only) renders both eyes from
one viewport draw: one scene submission with two views side by side in a
double-width target, instead of two complete sequential eye passes. Most of the
render thread's per-frame work (visibility, lighting setup, draw submission
overhead) is then paid once instead of twice, which is where a CPU-bound
headset gains its frame time. DLSS upscales each eye from its half of that
target.

KF2 replaces several stock Unreal Engine 3 renderer paths with its own
single-view code, so two views in one scene needed the following fixes.

## Render changes

- **Visibility for both eyes.** With one view KF2 uses its own visibility path
  (`InitViews`); with two it fell back to stock UE3 code it never otherwise
  runs, which dropped unlit surfaces (HUD panels, the interaction wheel, laser,
  pop-up text) and flickered the right eye. Both views now run KF2's own
  per-view visibility, setup and translucency sorting, with the family-wide
  steps (including shadow setup for both views) once per frame.
- **Occlusion culling from the left eye.** UE3 keeps one pending occlusion
  query per object in the player's view state, so two views in one frame
  overwrote each other's queries. The right eye runs visibility without a view
  state (frustum culling) and then takes a state of its own for late passes;
  the left eye keeps the player's state and runs occlusion queries alone.
  KF2's GPU HiZ culling, which used views[0] against the whole two-eye depth
  buffer, is off with it. The left eye's queries were drawn with the right
  eye's view constants still in the GPU buffer (the RHI fills a shadow copy and
  did not upload it before the queries), so every box was tested from the
  wrong projection and walls, doors and objects popped out; the left eye's
  constants are now written before its first query. `-kf2vr-sp-no-occlusion`
  returns to frustum culling only.
- **The game's own two-view lighting.** Lighting is no longer split per eye,
  which had darkened the right eye's shadows. A per-eye split remains as a
  diagnostic (`-kf2vr-sp-split-lighting`).
- **Right-eye full-screen passes.** Some KF2 passes set the viewport to the eye
  but also offset their full-screen quad by the eye's position, which only
  works for a view at x = 0, so the right eye's quad fell outside its viewport.
  Such quads are moved back into the right eye. This brings the SPH fluid gore
  to both eyes.
- **Whole-scene shadows in both eyes.** KF2 fits whole-scene shadows (such as
  moonlight) to one dependent view, sizes their per-view fade for that view
  alone and marks them relevant only there, so the right eye had none. While
  shadows are projected, the left eye's shadow is also projected into the right
  eye (the eyes are 6 cm apart, so it covers both).
- **HBAO+ per eye.** KF2 passes NVIDIA HBAO+ the whole two-eye depth buffer with
  its input viewport disabled. Each eye's call now gets that eye's rectangle.
- **DLSS world depth.** KF2 clears depth before the first-person foreground;
  the adapter keeps world depth for DLSS motion vectors. Single-pass clears per
  eye rectangle through RHIClear's clear-quad path (the viewport does not cover
  the whole target), which never reached the ClearDepthStencilView guard, so
  DLSS motion vectors treated the world as infinitely far away: right for head
  rotation only, and the image softened while moving. RHIClear is hooked and
  eye clears go through the guard, which matches the depth buffer by resource
  and accepts depth-only eye clears.
- **Lens flares in both eyes.** Lens flare components (such as headlight
  rings) fade by the occlusion coverage of their primitive, read through a
  per-state cache. The right eye's late state runs no queries, so it evaluates
  the flare occlusion parameter with the left eye's state.
- **HBAO+ in single-pass.** KF2 uses HBAO+ 2.x, whose output covers the whole
  render target and is only correct for a viewport at the origin. Each eye
  renders into a scratch copy (the right eye as its own eye-sized frame: depth
  copied to the origin of an eye-sized texture) and only its rectangle is
  copied back, in a private D3D11 context state. KF2 reads the AO target
  between the two eyes' calls, so both eyes are rendered at the left eye's
  call; without that the right eye lost its lighting.
- **Screen-space reflections per eye.** KF2's reflection compute shader
  (0x3605d0, the DX11 path) treats the whole scene buffer as one view with
  views[0]'s camera, so both eyes were traced as one wide image with the left
  eye's camera. The pass now runs once per eye with that eye as views[0], and
  its dispatch is replaced by the same shader limited to the eye's rectangle
  (`StereoReflections.h`, translated from the game's bytecode; hit UVs map back
  into the two-eye buffer). `kf2vr_stereo_reflections_test` checks each eye
  against the eye traced alone, and against KF2's own shader when
  `KF2VR_GLOBAL_SHADER_CACHE` names `GlobalShaderCache-PC-D3D-SM5.bin`.

## Screen effects

The launcher's VR options **HBAO+ ambient occlusion** and **Screen-space
reflections** (saved, initially off) turn those effects on and let the VR
script keep them; lens flares and film grain stay off. The options apply in
either mode, but they were verified with single-pass stereo; with sequential eye
passes, screen-space effects can resolve differently per eye.

## Diagnostics

Launch arguments, all off by default: `-kf2vr-sp-split` (each eye as its own
submission), `-kf2vr-sp-split-lighting`, `-kf2vr-sp-separate-state` (a second
view state for the right eye), `-kf2vr-sp-left-occlusion`,
`-kf2vr-sp-right-occlusion`, and `-kf2vr-eye-capture` (saves both raw eyes and
the headset atlas as PNGs beside `native.log` every 10 seconds).
