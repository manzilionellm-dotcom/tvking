"""Histogrammes de présentation SurfaceFlinger des seules couches du paquet."""
import hashlib,re

def parse(raw,package):
    output=[]
    for block in re.split(r'(?m)^\s*layerName\s*=\s*',raw)[1:]:
        name=block.splitlines()[0].strip()
        pkg=re.search(r'(?m)^\s*packageName\s*=\s*([^\n]*)',block)
        exact=bool(pkg and pkg[1].strip()==package)
        label=bool(re.search(r'(?<![\w.])'+re.escape(package)+r'(?![\w.])',name))
        if not (exact or label) or (pkg and pkg[1].strip() and not exact):continue
        item=dict(layer_digest=hashlib.sha256(name.encode()).hexdigest()[:16],surface_view='SurfaceView' in name,
            attribution='packageName' if exact else 'nom_couche_qualifie')
        for k in ('totalFrames','droppedFrames','lateAcquireFrames','badDesiredPresentFrames','averageFPS'):
            value=re.search(r'(?m)^\s*'+k+r'\s*=\s*([.\d]+)',block)
            if value:item[k]=float(value[1])
        distribution=re.search(r'(?im)^\s*present2present histogram is as below:\s*\n([^\n]+)',block)
        if distribution:item['present2present_buckets_ms']={int(t):int(n) for t,n in re.findall(r'(\d+)ms=(\d+)',distribution[1]) if int(n)>0}
        if item.get('totalFrames',0)>0:output.append(item)
    return output
