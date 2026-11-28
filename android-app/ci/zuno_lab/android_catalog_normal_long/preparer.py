"""Ajoute au parcours de l'APK signé un pilote externe de 30 minutes."""
from pathlib import Path
path=Path('android-app/ci/zuno_lab/android_catalog_normal/normal.py')
src=path.read_text()
def edit(old,new):
 global src
 if src.count(old)!=1:raise ValueError('Relire le pilote normal avant la campagne longue')
 src=src.replace(old,new)
if "if applied.get('kind')=='source'" not in src:
 edit("if applied.get('id',0)>prior and srcs.get('get_live_streams'):", "if applied.get('kind')=='source' and applied.get('id',0)>prior and srcs.get('get_live_streams'):")
if "note('ack',order_id=" not in src:
 edit("note('ack',elapsed_s=", "note('ack',order_id=applied['id'],kind=applied['kind'],elapsed_s=")
edit("srcs={}","srcs={}\ncatalog_locked=False")
old="   if act=='get_live_streams': buf="
edit(old, """   if catalog_locked and act in ('get_live_categories','get_live_streams'):
    srcs['blocked_catalog']=srcs.get('blocked_catalog',0)+1
    note('catalog_reload_rejected',kind=act)
    self.send_response(503);self.send_header('Content-Length','0');self.end_headers();return
"""+old)
# Distinguer le nom de la liste affiché sur l'accueil des chaînes et catégories de la fixture.
edit("any(x.startswith(('cat ','lab ')) for x in labels)", "any(x.startswith('cat ') or (x.startswith('lab ') and x!='lab 30000') for x in labels)")
a=src.index(' for n in [22,20,23,166,167,4]*4:')
b=src.index('finally:',a)
src=src[:a]+Path(__file__).with_name('campagne.py.src').read_text()+src[b:]
compile(src,str(path),'exec')
path.write_text(src)
