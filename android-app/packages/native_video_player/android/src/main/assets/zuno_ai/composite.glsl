#version 100
precision highp float;
uniform highp sampler2D uInput;
uniform highp sampler2D uColor;
uniform vec2 uSize;
vec4 colorAt(vec2 p) { return texture2D(uColor,(clamp(p,vec2(0.0),uSize-1.0)+0.5)/uSize); }
void main() {
    vec2 pixel = floor(gl_FragCoord.xy);
    vec2 source = floor(pixel*0.5);
    vec4 values = texture2D(uInput,(source+0.5)/uSize);
    // DepthToSpace DCR : canaux 0,1 sur la première ligne, puis 2,3.
    float index = mod(pixel.x,2.0)+2.0*mod(pixel.y,2.0);
    float prediction = index<0.5 ? values.r : index<1.5 ? values.g : index<2.5 ? values.b : values.a;
    prediction = clamp(prediction,0.0,1.0);
    // Bilinéaire manuel : aucune extension de filtrage float requise.
    vec2 p = gl_FragCoord.xy*0.5-0.5;
    vec2 base = floor(p);
    vec2 f = fract(p);
    vec4 color = mix(mix(colorAt(base),colorAt(base+vec2(1,0)),f.x),
                     mix(colorAt(base+vec2(0,1)),colorAt(base+vec2(1,1)),f.x),f.y);
    // Modifier Y' en conservant Cb/Cr équivaut à ajouter le même delta aux R'G'B'.
    vec3 gamma = clamp(color.rgb+vec3(prediction-color.a),0.0,1.0);
    // Même domaine électrique que les autres effets SDR de Media3 1.5.1.
    gl_FragColor = vec4(gamma,1.0);
}
