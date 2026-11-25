#!/usr/bin/env python3
"""Exécute les fragments livrés dans EGL/GLES et compare à la référence ONNX.

Utilise EGL Mesa sans écran si disponible. Ce test logiciel prouve le calcul,
jamais les performances d'une box. Le test Android refait la même vérification
sur son vrai pilote avant de permettre l'activation.
"""
import ctypes as c
import ctypes.util
import json
import os
from pathlib import Path

import numpy as np

os.environ.setdefault('EGL_PLATFORM', 'surfaceless')
ASSETS = Path(__file__).resolve().parents[1] / 'android/src/main/assets/zuno_ai'
egl = c.CDLL(ctypes.util.find_library('EGL'))
P = c.c_void_p
I = c.c_int
U = c.c_uint
F = c.c_float


def api(name, result, args):
    f = getattr(egl, name)
    f.restype, f.argtypes = result, args
    return f


api('eglGetProcAddress', P, [c.c_char_p])
api('eglGetDisplay', P, [P])
api('eglInitialize', U, [P, P, P])
api('eglChooseConfig', U, [P, P, P, I, P])
api('eglCreateContext', P, [P, P, P, P])
api('eglCreatePbufferSurface', P, [P, P, P])
api('eglMakeCurrent', U, [P, P, P, P])
api('eglTerminate', U, [P])


def ints(*items): return (I*len(items))(*items)


def gl(name, result, *args):
    address = egl.eglGetProcAddress(name.encode())
    assert address, name
    return c.CFUNCTYPE(result, *args)(address)


display = egl.eglGetDisplay(None)
assert egl.eglInitialize(display, None, None), 'EGL initialise'
config, count = P(), I()
assert egl.eglChooseConfig(display, ints(0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3040,4,0x3033,1,0x3038), c.byref(config),1,c.byref(count)) and count.value
context = egl.eglCreateContext(display,config,None,ints(0x3098,2,0x3038))
surface = egl.eglCreatePbufferSurface(display,config,ints(0x3057,1,0x3056,1,0x3038))
assert context and surface and egl.eglMakeCurrent(display,surface,surface,context)

GetString=gl('glGetString',c.c_char_p,U)
GetError=gl('glGetError',U)
CreateShader=gl('glCreateShader',U,U)
ShaderSource=gl('glShaderSource',None,U,I,P,P)
CompileShader=gl('glCompileShader',None,U)
GetShaderiv=gl('glGetShaderiv',None,U,U,P)
GetShaderInfoLog=gl('glGetShaderInfoLog',None,U,I,P,P)
CreateProgram=gl('glCreateProgram',U)
AttachShader=gl('glAttachShader',None,U,U)
BindAttribLocation=gl('glBindAttribLocation',None,U,U,c.c_char_p)
LinkProgram=gl('glLinkProgram',None,U)
GetProgramiv=gl('glGetProgramiv',None,U,U,P)
GenTextures=gl('glGenTextures',None,I,P)
BindTexture=gl('glBindTexture',None,U,U)
TexParameteri=gl('glTexParameteri',None,U,U,I)
TexImage2D=gl('glTexImage2D',None,U,I,I,I,I,I,U,U,P)
GenFramebuffers=gl('glGenFramebuffers',None,I,P)
BindFramebuffer=gl('glBindFramebuffer',None,U,U)
FramebufferTexture2D=gl('glFramebufferTexture2D',None,U,U,U,U,I)
CheckFramebufferStatus=gl('glCheckFramebufferStatus',U,U)
Viewport=gl('glViewport',None,I,I,I,I)
UseProgram=gl('glUseProgram',None,U)
GetUniformLocation=gl('glGetUniformLocation',I,U,c.c_char_p)
Uniform1i=gl('glUniform1i',None,I,I)
Uniform2f=gl('glUniform2f',None,I,F,F)
ActiveTexture=gl('glActiveTexture',None,U)
VertexAttribPointer=gl('glVertexAttribPointer',None,U,I,U,U,I,P)
EnableVertexAttribArray=gl('glEnableVertexAttribArray',None,U)
DrawArrays=gl('glDrawArrays',None,U,I,I)
Finish=gl('glFinish',None)
ReadPixels=gl('glReadPixels',None,I,I,I,I,U,U,P)


def check():
    error=GetError()
    assert error==0, f'GLES error {hex(error)}'


def shader(kind, code):
    result=CreateShader(kind)
    data=c.c_char_p(code.encode())
    ShaderSource(result,1,c.byref(data),None)
    CompileShader(result)
    ok=I(); GetShaderiv(result,0x8B81,c.byref(ok))
    if not ok.value:
        log=c.create_string_buffer(10000)
        GetShaderInfoLog(result,len(log),None,log)
        raise AssertionError(log.value.decode())
    return result


def program(fragment):
    result=CreateProgram()
    AttachShader(result,shader(0x8B31,(ASSETS/'vertex.glsl').read_text()))
    AttachShader(result,shader(0x8B30,fragment))
    BindAttribLocation(result,0,b'aPosition')
    LinkProgram(result)
    ok=I(); GetProgramiv(result,0x8B82,c.byref(ok)); assert ok.value
    return result


def texture(w,h,half=True,pixels=None):
    tid=U(); GenTextures(1,c.byref(tid)); BindTexture(0x0DE1,tid)
    for name,value in [(0x2801,0x2600),(0x2800,0x2600),(0x2802,0x812F),(0x2803,0x812F)]: TexParameteri(0x0DE1,name,value)
    buffer=None if pixels is None else c.create_string_buffer(pixels)
    TexImage2D(0x0DE1,0,0x881A if half else 0x1908,w,h,0,0x1908,0x140B if half else 0x1401,buffer)
    fbo=U(); GenFramebuffers(1,c.byref(fbo)); BindFramebuffer(0x8D40,fbo)
    FramebufferTexture2D(0x8D40,0x8CE0,0x0DE1,tid,0)
    assert CheckFramebufferStatus(0x8D40)==0x8CD5
    check()
    return tid.value,fbo.value,w,h


quad=np.array([-1,-1,1,-1,-1,1,1,1],np.float32)
def draw(prog,target,source,second=0,second_name=b'uSkip'):
    BindFramebuffer(0x8D40,target[1]); Viewport(0,0,target[2],target[3]); UseProgram(prog)
    Uniform2f(GetUniformLocation(prog,b'uSize'),16,12)
    ActiveTexture(0x84C0); BindTexture(0x0DE1,source); Uniform1i(GetUniformLocation(prog,b'uInput'),0)
    if second:
        ActiveTexture(0x84C1); BindTexture(0x0DE1,second); Uniform1i(GetUniformLocation(prog,second_name),1)
    VertexAttribPointer(0,2,0x1406,0,0,quad.ctypes.data); EnableVertexAttribArray(0)
    DrawArrays(5,0,4); check()


names=['denoise.glsl',*[f'conv{i}.glsl' for i in range(7)],'composite.glsl']
programs=[program((ASSETS/n).read_text()) for n in names]
input_texture=texture(16,12,False,(ASSETS/'reference-input.rgba').read_bytes())
targets=[texture(16,12),texture(32,24),texture(32,24),texture(32,24),texture(16,12),texture(32,24,False)]
draw(programs[0],targets[0],input_texture[0])
draw(programs[1],targets[1],targets[0][0])
draw(programs[2],targets[2],targets[1][0])
draw(programs[3],targets[3],targets[2][0])
draw(programs[4],targets[2],targets[3][0])
draw(programs[5],targets[3],targets[2][0])
draw(programs[6],targets[2],targets[3][0],targets[1][0])
draw(programs[7],targets[4],targets[2][0])
draw(programs[8],targets[5],targets[4][0],targets[0][0],b'uColor')
Finish()
actual=np.zeros((24,32,4),np.uint8)
ReadPixels(0,0,32,24,0x1908,0x1401,actual.ctypes.data); check()
expected=np.frombuffer((ASSETS/'reference-output.rgba').read_bytes(),np.uint8).reshape(actual.shape)
delta=np.abs(actual.astype(np.int16)-expected.astype(np.int16))
assert delta.max()<=4 and delta.mean()<=0.85, (int(delta.max()),float(delta.mean()))

# Contrôle négatif : des dimensions x2 sans les convolutions ne passent pas.
mutant=program('#version 100\nprecision highp float; void main(){gl_FragColor=vec4(0.5);}')
draw(mutant,targets[4],targets[2][0])
draw(programs[8],targets[5],targets[4][0],targets[0][0],b'uColor')
Finish(); ReadPixels(0,0,32,24,0x1908,0x1401,actual.ctypes.data)
bad=np.abs(actual.astype(np.int16)-expected.astype(np.int16))
assert bad.max()>4 and bad.mean()>0.85
print(json.dumps({'renderer':GetString(0x1F01).decode(),'version':GetString(0x1F02).decode(),
                 'referenceMaximumByteError':int(delta.max()),'referenceMeanByteError':float(delta.mean()),
                 'disabledNetworkRejected':True,'mutantMaximumByteError':int(bad.max())}))
egl.eglMakeCurrent(display,None,None,None); egl.eglTerminate(display)
