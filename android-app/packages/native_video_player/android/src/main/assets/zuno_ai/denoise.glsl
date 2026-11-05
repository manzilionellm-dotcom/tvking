#version 100
precision highp float;
uniform highp sampler2D uInput;
uniform vec2 uSize;
// Media3 1.5.1 Factory.DEFAULT livre du RGB BT.709 électrique (gamma).
// Ne pas appliquer une seconde OETF. Le réseau travaille sur Y' du même domaine.
vec3 gammaAt(vec2 p) {
    p = clamp(p, vec2(0.0), uSize-1.0);
    return texture2D(uInput, (p+0.5)/uSize).rgb;
}
void main() {
    vec2 p = floor(gl_FragCoord.xy);
    vec3 center = gammaAt(p);
    float y = dot(center, vec3(0.2126,0.7152,0.0722));
    vec3 sum = vec3(0.0);
    float norm = 0.0;
    for (int dy=-1; dy<=1; dy++) {
        for (int dx=-1; dx<=1; dx++) {
            vec3 c = gammaAt(p+vec2(float(dx),float(dy)));
            float delta = dot(c,vec3(0.2126,0.7152,0.0722))-y;
            float spatial = dx==0 && dy==0 ? 4.0 : (dx!=0 && dy!=0 ? 0.5 : 1.0);
            float weight = spatial*exp(-delta*delta/(2.0*0.035*0.035));
            sum += weight*c;
            norm += weight;
        }
    }
    // Débruitage spatial léger, pas une promesse de restauration universelle.
    vec3 rgb = mix(center, sum/norm, 0.15);
    gl_FragColor = vec4(rgb, dot(rgb,vec3(0.2126,0.7152,0.0722)));
}
