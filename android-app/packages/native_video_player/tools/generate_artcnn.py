#!/usr/bin/env python3
"""Port reproductible ONNX → fragments GLES2, sans changer un poids entraîné.

Dépendances de développement uniquement : numpy, onnx, onnxruntime.
Le lecteur Android n'embarque aucun de ces moteurs Python.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
import onnx
from onnx import numpy_helper
import onnxruntime as ort

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'android/src/main/assets/zuno_ai'
MODEL = ROOT / 'tools/artcnn_reference/ArtCNN_C4F16.onnx'
MODEL_SHA = '7a6436299b8c757dbb7084ac39a25c310db1941133e73d1ee3e74c8b3bddc1ca'
UPSTREAM = 'f606e1f0ba7e6f0ab55049f33dac4d854819b00b'


def scalar(v):
    s = format(float(v), '.9g')
    return s if any(x in s for x in '.eE') else s + '.0'


def vector(v):
    return 'vec4(' + ','.join(scalar(x) for x in v) + ')'


def generate():
    assert hashlib.sha256(MODEL.read_bytes()).hexdigest() == MODEL_SHA
    model = onnx.load(MODEL)
    weights = {x.name: numpy_helper.to_array(x) for x in model.graph.initializer}
    # Schéma explicitement vérifié : 7 convolutions SAME/zero, ReLU 1..4,
    # connexion longue après conv5, shuffle DCR x2 puis clamp de sortie.
    assert [n.op_type for n in model.graph.node] == [
        'Conv', 'Conv', 'Relu', 'Conv', 'Relu', 'Conv', 'Relu', 'Conv', 'Relu',
        'Conv', 'Add', 'Conv', 'DepthToSpace', 'Clip']
    header = '// Poids ArtCNN MIT, attribution complète dans LICENSE-ArtCNN.txt.\n'
    for layer in range(7):
        w = weights[f'kernel_oih_{layer}']
        b = weights[f'const_{layer * 2 + 1}']
        assert w.shape == ((16 if layer < 6 else 4), (1 if layer == 0 else 16), 3, 3)
        code = [header, '#version 100\nprecision highp float;\n',
                'uniform highp sampler2D uInput;\nuniform highp sampler2D uSkip;\nuniform vec2 uSize;\n',
                'vec4 readFeature(vec2 p, float group) {\n',
                ' if (p.x < 0.0 || p.y < 0.0 || p.x >= uSize.x || p.y >= uSize.y) return vec4(0.0);\n']
        if layer == 0:
            code += [' return vec4(texture2D(uInput, (p + 0.5) / uSize).a, 0.0, 0.0, 0.0);\n}\n']
        else:
            code += [' vec2 tile = vec2(mod(group,2.0), floor(group/2.0));\n',
                     ' return texture2D(uInput, (p + 0.5 + tile*uSize)/(uSize*2.0));\n}\n']
        code += ['void main() {\n',
                 ' vec2 pixel = floor(gl_FragCoord.xy);\n',
                 ' vec2 tile = floor(pixel/uSize);\n',
                 ' float group = tile.x + 2.0*tile.y;\n',
                 ' vec2 p = mod(pixel,uSize);\n']
        groups = 1 if layer == 0 else 4
        for ig in range(groups):
            for y in range(3):
                for x in range(3):
                    code += [f' vec4 v{ig}{y}{x} = readFeature(p + vec2({x-1}.0,{y-1}.0), {ig}.0);\n']
        code += [' vec4 result = vec4(0.0);\n']
        for og in range(len(b)//4):
            code += [f' {"if" if og == 0 else "else if"} (group < {og + 0.5}) {{\n',
                     f'  result = {vector(b[og*4:og*4+4])};\n']
            for ig in range(groups):
                for y in range(3):
                    for x in range(3):
                        if layer == 0:
                            op = vector(w[og*4:og*4+4, 0, y, x]) + f' * v{ig}{y}{x}.x'
                        else:
                            # GLSL mat4 est colonnaire : chaque colonne multiplie
                            # un canal d'entrée, chaque ligne produit un canal de sortie.
                            matrix = w[og*4:og*4+4, ig*4:ig*4+4, y, x].T.flatten()
                            op = 'mat4(' + ','.join(scalar(v) for v in matrix) + f') * v{ig}{y}{x}'
                        code += [f'  result += {op};\n']
            code += [' }\n']
        if layer in range(1, 5):
            code += [' result = max(result, vec4(0.0));\n']
        if layer == 5:
            code += [' result += texture2D(uSkip, gl_FragCoord.xy / (uSize*2.0));\n']
        # Pas de clamp implicite ici : les features négatives sont indispensables.
        code += [' gl_FragColor = result;\n}\n']
        (ASSETS / f'conv{layer}.glsl').write_text(''.join(code))
    make_reference()
    files = ['vertex.glsl', 'denoise.glsl', *[f'conv{i}.glsl' for i in range(7)], 'composite.glsl',
             'reference-input.rgba', 'reference-output.rgba']
    hashes = {name: hashlib.sha256((ASSETS / name).read_bytes()).hexdigest() for name in files}
    fingerprint = hashlib.sha256(''.join(f'{n}:{hashes[n]}\n' for n in files).encode()).hexdigest()
    manifest = {'model': 'ArtCNN_C4F16', 'upstreamCommit': UPSTREAM, 'modelSha256': MODEL_SHA,
                'pipelineSha256': fingerprint, 'scale': 2, 'referenceWidth': 16, 'referenceHeight': 12,
                'denoiseStrength': 0.15, 'files': hashes}
    (ASSETS / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'modelSha256': MODEL_SHA, 'pipelineSha256': fingerprint, 'assets': len(files)}))


def make_reference():
    # Mélange déterministe : couleurs, plage sombre, bord franc et grain.
    # Le sens des lignes est celui des textures GL (ligne zéro en bas).
    h, w = 12, 16
    yy, xx = np.mgrid[:h, :w]
    rgb = np.stack([(xx*17+yy*7)%256, (yy*21+xx*3)%256, (xx*11+yy*13)%256], axis=2).astype(np.uint8)
    rgb[:, w//2:] = np.minimum(rgb[:, w//2:]//2 + 65, 255)
    rgba = np.concatenate([rgb, np.full((h,w,1),255,np.uint8)], axis=2)
    (ASSETS / 'reference-input.rgba').write_bytes(rgba.tobytes())
    # Factory.DEFAULT de Media3 1.5.1 utilise déjà le domaine électrique BT709.
    gamma = rgb.astype(np.float32)/255
    center_y = gamma @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    weighted = np.zeros_like(gamma)
    total = np.zeros((h,w),np.float32)
    for dy in range(-1,2):
        for dx in range(-1,2):
            neighbor = gamma[np.clip(yy+dy,0,h-1),np.clip(xx+dx,0,w-1)]
            delta = neighbor @ np.array([0.2126,0.7152,0.0722],np.float32) - center_y
            spatial = 4 if dx == dy == 0 else (0.5 if dx and dy else 1)
            weight = spatial*np.exp(-(delta*delta)/(2*0.035*0.035))
            weighted += neighbor*weight[...,None]
            total += weight
    denoised = (gamma*0.85 + weighted/total[...,None]*0.15).astype(np.float32)
    luma = denoised @ np.array([0.2126,0.7152,0.0722],np.float32)
    session = ort.InferenceSession(str(MODEL), providers=['CPUExecutionProvider'])
    prediction = session.run(None, {'input':luma[None,None]})[0][0,0]
    assert prediction.shape == (h*2,w*2) and np.isfinite(prediction).all()
    fy,fx=np.mgrid[:h*2,:w*2].astype(np.float32)
    fy=(fy+0.5)/2-0.5; fx=(fx+0.5)/2-0.5
    y0=np.floor(fy).astype(int); x0=np.floor(fx).astype(int)
    wy=(fy-y0)[...,None]; wx=(fx-x0)[...,None]
    def sample(dx,dy): return denoised[np.clip(y0+dy,0,h-1),np.clip(x0+dx,0,w-1)]
    base=(sample(0,0)*(1-wx)+sample(1,0)*wx)*(1-wy)+(sample(0,1)*(1-wx)+sample(1,1)*wx)*wy
    base_y=base @ np.array([0.2126,0.7152,0.0722],np.float32)
    out=np.clip(base+(prediction-base_y)[...,None],0,1)
    out8=np.rint(np.clip(out,0,1)*255).astype(np.uint8)
    result=np.concatenate([out8,np.full((h*2,w*2,1),255,np.uint8)],axis=2)
    (ASSETS / 'reference-output.rgba').write_bytes(result.tobytes())


if __name__ == '__main__':
    generate()
