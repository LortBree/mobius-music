#version 460 core
#include <flutter/runtime_effect.glsl>

// Ambient atmospheric light field for MOBIUS. Not a gradient and not discrete
// blobs: several large, low-frequency ANISOTROPIC light fields of a controlled
// violet / magenta / subtle-cyan palette, overlapping softly over a near-black
// base, strongest at the top and fading to black toward the bottom.
//
// Design goals (from the visual spec):
//   * organic, irregular, no visible circles, no hard edges
//   * purple/violet dominant, magenta secondary, cyan barely-there
//   * conservative alpha compositing -- no additive neon bloom
//   * smooth vertical falloff so the lower half stays dark and readable
//
// Uniform order defines the Dart setFloat() indices (no samplers).

uniform vec2  uResolution;   // 0,1   surface size (px)
uniform float uTime;         // 2     seconds, for slow drift

// Palette (linear 0..1). Supplied from AmbientConfig on the Dart side.
uniform vec3 uBase;          // 3,4,5    near-black base
uniform vec3 uViolet;        // 6,7,8    primary
uniform vec3 uMagenta;       // 9,10,11  secondary
uniform vec3 uBlue;          // 12,13,14 violet->blue
uniform vec3 uCyan;          // 15,16,17 subtle cool accent

// Global tuning.
uniform float uIntensity;    // 18   overall multiplier
uniform float uFalloffTop;   // 19   where vertical mask starts easing (0..1 y)
uniform float uFalloffBottom;// 20   where it reaches ~0
uniform float uWarm;         // 21   1.0 = warm-side hue drift, 0.0 = cool

out vec4 fragColor;

// A soft, anisotropic, slightly-rotated light field centred at `c` (UV space).
// `r` is the x/y radius pair; `rot` rotates the ellipse so fields are not
// axis-aligned. Falloff is gaussian-like (exp) for a very soft, edgeless core.
float field(vec2 p, vec2 c, vec2 r, float rot) {
  vec2 d = p - c;
  float s = sin(rot);
  float co = cos(rot);
  // rotate into the field's local frame
  vec2 dl = vec2(d.x * co - d.y * s, d.x * s + d.y * co);
  // normalised squared distance in the ellipse
  vec2 q = dl / r;
  float dist2 = dot(q, q);
  return exp(-dist2 * 2.2);
}

// Slow, layered coordinate warp -- the "liquid" motion. Perturbs the sample
// point with a few phase-offset sinusoids so the light edges ripple, stretch
// and fold like ink diffusing in water, instead of sliding rigidly. Pure math:
// no allocation, no new uniforms, evaluated once per fragment.
vec2 warp(vec2 p, float t) {
  // Two octaves of cross-coupled flow at different scales/speeds. The x warp is
  // driven by y (and vice versa) so the field shears rather than merely
  // translating -- that shear is what reads as fluid.
  float w1x = sin(p.y * 3.1 + t * 0.11) + 0.5 * sin(p.y * 6.3 - t * 0.17);
  float w1y = cos(p.x * 2.7 - t * 0.13) + 0.5 * cos(p.x * 5.9 + t * 0.19);
  // Amplitude kept modest so the composition stays put; the edges flow and the
  // whole light body breathes along with the wandering fields.
  return p + vec2(w1x, w1y) * 0.065;
}

// Rotate a colour's HUE by `a` radians, preserving saturation/value. Used for a
// slow, BOUNDED colour shift -- the amplitude at the call sites is small so the
// palette breathes within violet<->magenta<->cool-violet and never wanders into
// green/yellow/orange (that would break the spec's controlled palette). Cheap:
// a fixed 3x3 rotation about the (1,1,1) luma axis, no branches.
vec3 hueShift(vec3 c, float a) {
  const vec3 k = vec3(0.57735); // normalised (1,1,1)
  float cosA = cos(a);
  // Rodrigues' rotation of the colour vector about the grey axis.
  return c * cosA
       + cross(k, c) * sin(a)
       + k * dot(k, c) * (1.0 - cosA);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;

  // Aspect-correct the X axis so fields keep their shape on wide windows.
  float aspect = uResolution.x / uResolution.y;
  vec2 p = vec2(uv.x * aspect, uv.y);

  float t = uTime;

  // Liquid domain warp applied to the sampling coordinate. Every field is then
  // evaluated in this flowing space, so they all ripple coherently as one
  // body of light rather than independent moving discs.
  vec2 pw = warp(p, t);

  // Very slow, desynchronised drift per field (sin/cos, small amplitude).
  // Each field: centre (aspect-scaled x), elliptical radius, rotation.
  // Composition is asymmetric and concentrated toward the TOP.

  // Fields WANDER across the upper region like slow ambient currents -- each on
  // its own dual-frequency, cross-coupled path (x and y use different periods
  // so the motion curves and loops instead of tracing a circle). Amplitudes are
  // large enough to read as real movement, but the y stays biased to the top so
  // the composition remains concentrated up high and the lower half stays dark.

  // FIELD 1 -- primary violet, upper-left / upper-center, large.
  vec2 c1 = vec2(
      (0.34 + 0.11 * sin(t / 22.0) + 0.05 * cos(t / 13.0)) * aspect,
       0.15 + 0.06 * cos(t / 18.0) + 0.03 * sin(t / 27.0));
  float f1 = field(pw, c1, vec2(0.55 * aspect, 0.34), 0.5) * 0.52;

  // FIELD 2 -- muted magenta, upper-center / slightly left.
  vec2 c2 = vec2(
      (0.50 + 0.12 * cos(t / 17.0) + 0.05 * sin(t / 25.0)) * aspect,
       0.12 + 0.06 * sin(t / 21.0) + 0.03 * cos(t / 15.0));
  float f2 = field(pw, c2, vec2(0.46 * aspect, 0.30), -0.3) * 0.56;

  // FIELD 3 -- violet->blue, upper-right, large, very soft.
  vec2 c3 = vec2(
      (0.76 + 0.10 * sin(t / 26.0) + 0.05 * cos(t / 16.0)) * aspect,
       0.17 + 0.06 * cos(t / 23.0) + 0.03 * sin(t / 31.0));
  float f3 = field(pw, c3, vec2(0.60 * aspect, 0.40), 0.7) * 0.24;

  // FIELD 4 -- subtle cyan accent, upper region, very large falloff. Barely
  // there; reduced further so it never reads as a cool patch.
  vec2 c4 = vec2(
      (0.62 + 0.13 * cos(t / 31.0) + 0.05 * sin(t / 19.0)) * aspect,
       0.30 + 0.07 * sin(t / 24.0) + 0.03 * cos(t / 33.0));
  float f4 = field(pw, c4, vec2(0.70 * aspect, 0.50), -0.2) * 0.07;

  // Compose colour by weighting each palette entry by its field. Each palette
  // colour now travels its hue over a wide, phase-offset cycle so the light
  // sweeps violet -> magenta -> blue -> CYAN and back -- a living colour
  // journey, not a static palette. A positive bias term pushes the swing toward
  // the cool (cyan/blue) side so cyan is actually reached, while the sine keeps
  // it returning to the warm violet/magenta home. Stays in the cool half of the
  // wheel -- no green/yellow/orange.
  // Sign of the hue-drift bias depends on the theme: cool (toward cyan/blue)
  // in dark mode, warm (toward red/orange) in light mode, so a warm palette
  // never drifts into cool hues and vice versa.
  float coolBias = uWarm > 0.5 ? -0.30 : 0.35;
  vec3 cViolet  = hueShift(uViolet,  coolBias + 0.85 * sin(t / 19.0));
  vec3 cMagenta = hueShift(uMagenta, coolBias + 0.95 * sin(t / 23.0 + 1.7));
  vec3 cBlue    = hueShift(uBlue,    coolBias + 0.80 * sin(t / 29.0 + 3.1));
  vec3 cCyan    = hueShift(uCyan,    coolBias + 0.70 * sin(t / 37.0 + 0.6));

  vec3 light =
      cViolet  * f1 +
      cMagenta * f2 +
      cBlue    * f3 +
      cCyan    * f4;

  // Subtle TOP-RIGHT "sun" bias: a soft directional lift anchored in the
  // top-right corner, so the aurora reads as if lit from an off-screen source
  // up-right rather than being perfectly flat. Kept faint -- it only warms the
  // existing fields, it is NOT a beam and never becomes a focal point. Distance
  // is measured to the top-right corner in aspect space; a gentle breathing
  // term keeps it alive.
  vec2 sunPos = vec2(1.0 * aspect, 0.0);
  float sunDist = distance(pw, sunPos);
  float sun = exp(-sunDist * sunDist * 0.9) * (0.85 + 0.15 * sin(t / 28.0));
  vec3 sunCol = hueShift(uBlue, coolBias + 0.5 * sin(t / 31.0 + 0.9));
  light += sunCol * sun * 0.10;

  // Smooth vertical mask: full at the top, ~0 by uFalloffBottom.
  float vmask = 1.0 - smoothstep(uFalloffTop, uFalloffBottom, uv.y);

  light *= vmask * uIntensity;

  // Soft tone-map keeps the brightest area from clipping to neon -- the result
  // stays "relatively dark" as the spec requires.
  light = light / (1.0 + light);

  // ---- BOTTOM LIGHT: "sunlight reaching an ocean floor" -------------------
  // A soft cool glow rising from the very bottom edge, crossed by a few faint,
  // slowly-drifting vertical shafts (god rays / caustics filtering down through
  // water). Kept subtle and cool so the lower half reads as gently lit rather
  // than dark-dead, without ever competing with the track list for attention.
  //
  // Rise: brightest at the bottom edge (uv.y = 1), fading out by ~0.55 up.
  float rise = smoothstep(0.55, 1.0, uv.y);
  rise *= rise; // ease-in so it hugs the bottom edge

  // God rays: low-frequency bands filtering DOWN-LEFT on a diagonal, as if the
  // light enters from the top-right corner and rakes across to the lower-left
  // (matching the sun bias above). The band coordinate mixes x with y so the
  // shafts are slanted, not vertical; phase drifts with time so they sway like
  // light through moving water. Two octaves, softened so they read as light.
  float rayCoord = (pw.x + (1.0 - uv.y) * 0.6) * 1.6;
  float rays = 0.55
             + 0.30 * sin(rayCoord * 3.0 + t * 0.06)
             + 0.15 * sin(rayCoord * 6.7 - t * 0.09);
  rays = clamp(rays, 0.0, 1.0);
  // Rays are strongest deep (bottom) and dissolve upward.
  float rayMask = smoothstep(0.45, 1.0, uv.y);

  // Cool floor colour -- lean on the cyan/blue end of the palette, hue-drifting
  // with the same living shift so it stays coherent with the top field.
  vec3 floorCol = mix(uCyan, uBlue, 0.5);
  floorCol = hueShift(floorCol, coolBias + 0.6 * sin(t / 34.0 + 2.2));

  float bottom = rise * (0.35 + 0.65 * rays * rayMask);
  vec3 bottomLight = floorCol * bottom * (0.16 * uIntensity);
  bottomLight = bottomLight / (1.0 + bottomLight);

  light += bottomLight;
  // -------------------------------------------------------------------------

  vec3 rgb = clamp(uBase + light, 0.0, 1.0);

  // Opaque; alpha 1 => premultiplied == straight.
  fragColor = vec4(rgb, 1.0);
}
