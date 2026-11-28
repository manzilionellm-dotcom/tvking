"""Ne transmet que des nombres et des empreintes des captures privées."""
import json,hashlib,sys
from pathlib import Path
import numpy as np
from PIL import Image
root,out=map(Path,sys.argv[1:])
res={}
for page in ('accueil','direct','lecteur','reglages'):
    series={}
    for side in ('temoin1','lab','temoin2'):
        path=root/side/(page+'.png')
        if not path.exists():continue
        with Image.open(path) as img:
            rgb=np.asarray(img.convert('RGB'))
        if rgb.shape!=(720,1280,3) or np.unique(rgb[::4,::4].reshape(-1,3),axis=0).shape[0]<8:
            raise ValueError('Image vide ou taille invalide pour '+page)
        series[side]=rgb
    row={'n':len(series),'sha256_rgb':{k:hashlib.sha256(i.tobytes()).hexdigest() for k,i in series.items()}}
    if len(series)==3:
        a,b,c=[series[k] for k in ('temoin1','lab','temoin2')]
        aa=np.any(a!=c,axis=2);ab=np.any(a!=b,axis=2);bc=np.any(b!=c,axis=2)
        row.update(total=aa.size,temoin_repetition_pixels_differents=int(aa.sum()),temoin1_lab=int(ab.sum()),lab_temoin2=int(bc.sum()),different_hors_variation_observee_temoin=int(((~aa)&ab).sum()))
    res[page]=row
out.write_text(json.dumps(res,indent=2))
if any(v['n']!=3 for v in res.values()):raise SystemExit('Rendus appariés incomplets')
