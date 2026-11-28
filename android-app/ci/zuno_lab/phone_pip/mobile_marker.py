"""Détection d'un grand code optique horizontal dans la fenêtre Android visée."""
import numpy as np
from PIL import Image


def decode(values):
    bits=values>=190
    if not np.all((values<=60)|bits) or not np.array_equal(bits[:7],[1,0,1,1,0,1,0]) or not bits[29]:
        return None
    payload=bits[8:28]
    if int(payload.sum())%2!=int(bits[28]):return None
    number=sum(int(bit)<<i for i,bit in enumerate(payload))
    return ('B' if bits[7] else 'A',number) if number<3000 else None


def find_marker(image):
    """Le 2e carreau noir donne le pas. Vérifier le préambule, la parité et trois lignes."""
    ratio=min(1,960/image.width)
    frame=np.asarray(image.convert('L').resize((round(image.width*ratio),max(1,round(image.height*ratio))),Image.Resampling.BILINEAR))
    h,w=frame.shape
    nominal=min(w,h*16/9)/60
    # Un code d'aperçu dans la colonne droite doit échouer sur l'écran complet.
    # La recherche sur le PiP passe exclusivement son rectangle à cette fonction.
    for y in range(2,h-2,max(1,round(nominal/5))):
        line=frame[y]
        dark=line<=105
        transitions=np.flatnonzero(dark[1:]!=dark[:-1])+1
        if len(transitions)<3:continue
        left=transitions[:-1];right=transitions[1:]
        widths=right-left
        possible=np.flatnonzero(dark[left] & (widths>=.71*nominal) & (widths<=1.12*nominal))
        for i in possible:
            for ds in (0,-.25,.25,-.5,.5,-.75,.75,-.125,.125,-.375,.375,-.625,.625,-.875,.875):
                step=widths[i]+ds
                if not .74*nominal<=step<=1.08*nominal:continue
                x0=left[i]-step/2
                indices=np.rint(x0+step*np.arange(30)).astype(int)
                if indices[0]<0 or indices[-1]>=w:continue
                # Le cadre d'image déduit doit entrer dans la fenêtre capturée (en
                # tolérant un arrondi à chaque bord). Exclut une bande centrée
                # fortuitement dans une portion trop petite de la sortie.
                vw=step*60;vx=x0-vw*496/1920
                if vx < -.08*w or vx+vw>1.08*w:continue
                value=decode(line[indices])
                if value and all(decode(frame[yy,indices])==value for yy in (y-1,y+1)):
                    return (*value, [round(x0/ratio),round(y/ratio),round(float(step)/ratio,3)])
    return None
