#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Paper grain: each small cell of the page a little lighter or darker,
/// by up to `amount` of full brightness. A hash of the position, nothing
/// else, so it never changes and never asks to be redrawn.
[[ stitchable ]] half4 paperGrain(float2 position, half4 color, float amount) {
    float2 cell = floor(position * 1.5);
    float n = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
    half shift = half((n - 0.5) * 2.0 * amount);
    return half4(color.rgb + shift * color.a, color.a);
}
