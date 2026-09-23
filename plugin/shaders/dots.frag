#version 440
// Infinite dot grid that pans and zooms with the canvas.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // item size in px
    vec2 offset;    // canvas origin in px
    float spacing;  // dot pitch in px
    float radius;   // dot radius in px
    vec4 dotColor;
};

void main() {
    vec2 pos = qt_TexCoord0 * size - offset;
    vec2 cell = mod(pos, spacing) - spacing * 0.5;
    float d = length(cell);
    float a = 1.0 - smoothstep(radius - 0.6, radius + 0.6, d);
    fragColor = dotColor * a * qt_Opacity;
}
