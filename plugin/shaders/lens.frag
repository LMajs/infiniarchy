#version 440
// Barrel "lens" over the whole canvas scene: the middle stays 1:1, content
// bends and compresses toward the rim, and everything past the rim fades into
// the frame color — the curved CRT/fisheye look of the canvas overview.
// Canvas.qml mirrors lensMap() in JS for hit-testing; keep them in sync.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;   // 0 = flat
    float aspect;     // width / height
    float feather;    // rim softness in uv units
    vec4 frameColor;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 - 0.5;
    vec2 q = p * vec2(aspect, 1.0);
    float r2 = dot(q, q);
    float k = strength * 0.42;
    vec2 uv = 0.5 + p * (1.0 + k * r2) / (1.0 + k * 0.18);

    vec2 edge = min(uv, 1.0 - uv);
    float inside = smoothstep(0.0, feather, min(edge.x, edge.y));
    float vignette = mix(1.0, 1.0 - smoothstep(0.15, 1.25, r2), clamp(strength * 0.55, 0.0, 1.0));

    vec4 scene = texture(source, clamp(uv, 0.0, 1.0));
    scene.rgb *= vignette;
    fragColor = mix(frameColor, scene, inside) * qt_Opacity;
}
