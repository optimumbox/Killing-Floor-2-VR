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
- **No occlusion culling in single-pass.** UE3 keeps one pending occlusion
  query per object in the player's view state, so two views in one frame
  overwrite each other's queries; in practice objects, walls and enemies
  popped in and out of either eye. Both eyes now cull by view frustum only: the
  right eye runs visibility without a view state, and neither eye reads or
  submits occlusion queries.
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
  eye rectangle, which the guard did not recognise, so DLSS saw only the weapon
  and aliased nearby geometry. The guard now knows both eye rectangles.

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
