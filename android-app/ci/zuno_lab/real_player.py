"""Tourner deux touches Android sur des chaînes entièrement synthétiques, sans son système."""
import argparse,csv,json,time
from functools import partial
from pathlib import Path
from PIL import Image
from optical_film import Recorder,clocked_key
from optical_witness import open_fixture,motion,event,observe_ui
from real_film import export,safe_ui

def run(out,assets):
    out.mkdir(parents=True)
    (out/'LIRE.txt').write_text(
        "Film muet de la sortie Android, 960×540. Chaque image conserve son horodatage d’origine. "
        "Les touches sont injectées par ADB, leurs bornes figurent dans touches.json.\n"
        "Les hachures bleu-gris désignent une zone masquée. Les autres pixels de mire ont été comparés "
        "à la source locale approuvée ; leurs couleurs peuvent avoir été quantifiées. Une image portant "
        "« Intervalle masque » ne renseigne pas sur l’écran réellement affiché à cet instant. "
        "Un panneau reconnu conserve ses libellés et la roue vérifiée sur son fond uni.\n")
    def photograph(image,words,nodes,size):
        if image is None:return
        labels={w for w,*_ in words}
        if len(labels&{'live','movies','series','server','settings','films','serveur','direct'})>=3:
            name='accueil'
        elif 'mire' in labels and 'a' in labels and 'b' in labels:
            name='direct'
        else:return
        p=out/(name+'-expurge.png')
        if not p.exists():
            masked=safe_ui(image,name)
            if masked:masked.save(p)
    safe_rows=[];actions=[]
    # Les événements de configuration contiennent seulement des mots admis.
    # Les pièces de remise proviennent exclusivement du dossier public ci-dessous.
    audit=out.parent/'parametrage-prive';audit.mkdir()
    open_fixture(audit,observer=photograph)
    seen=motion(audit,'initial','A',20,safe_rows)
    if seen is None:raise RuntimeError('Mire A mobile initiale non prouvée')
    rec=Recorder(out/'film',exporter=partial(export,assets=assets));rec.start()
    try:
        time.sleep(4)
        for target,code in (('B','KEYCODE_CHANNEL_DOWN'),('A','KEYCODE_CHANNEL_UP')):
            row={'destination':target,'action':code,'mode':'injection ADB','etat':'demande'};actions.append(row)
            (out/'touches.json').write_text(json.dumps(actions,indent=2))
            low,high=clocked_key(code);row.update(debut_elapsed_s=low,fin_elapsed_s=high,etat='envoyee')
            visible=motion(audit,'vers-'+target,target,13,safe_rows)
            row['mouvement_sonde_live']=visible is not None
            (out/'touches.json').write_text(json.dumps(actions,indent=2))
            time.sleep(2)
    finally:
        good=rec.finish()
        (out/'touches.json').write_text(json.dumps(actions,indent=2))
    # Observer le BON compteur après chaque touche dans le film lui-même.
    frames=[]
    for path in sorted((out/'film').glob('images-*.csv')):
        with path.open() as f:frames.extend(csv.DictReader(f))
    checked=[]
    for i,act in enumerate(actions):
        after=act.get('fin_elapsed_s')
        until=(actions[i+1].get('debut_elapsed_s') if i+1<len(actions) else float('inf'))
        if after is None:continue
        options=[r for r in frames if r['elapsed_android'] and after<=float(r['elapsed_android'])<until]
        prev=None;moving=False
        for r in options:
            if r['scene']!='mire-verifiee' or r['chaine']!=act['destination']:
                prev=None;continue
            n=int(r['compteur'])
            if prev and 0<(n-prev[0])%3000<300 and float(r['elapsed_android'])-prev[1]<=.5:moving=True;break
            prev=(n,float(r['elapsed_android']))
        checked.append({'touche':act['action'],'destination':act['destination'],'mouvement_confirme_film':moving})
    (out/'resultat.json').write_text(json.dumps({'actions':checked,'capture_complete':good,
        'support':'sortie Android 1920×1080, film 960×540, sans audio, fichier de test uniquement',
        'lecture':'Les PTS sont conservés ; chaque image masquée est signalée. Deux captures de navigation existent seulement après contrôle OCR.'},indent=2))
    if not good or len(checked)!=2 or any(not r['mouvement_confirme_film'] for r in checked):
        raise SystemExit('Film partiel, garder les observations et les intervalles masqués.')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('out',type=Path);p.add_argument('assets',type=Path);a=p.parse_args();run(a.out,a.assets)
