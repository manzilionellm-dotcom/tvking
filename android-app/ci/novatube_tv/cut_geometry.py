"""Read fixture geometry and the fingerprint of the complete composited screenshot."""
import hashlib
from statistics import median


def edge(row, kind):
    consecutive = 0
    for x, (red, green, blue) in enumerate(row):
        if kind == 'green':
            match = green > 188 and red < 85 and blue < 85
        else:
            match = red > 188 and green > 188 and blue < 85
        consecutive = consecutive + 1 if match else 0
        if consecutive == 14:
            return x - 13
    return None


def digest_and_geometry(image):
    rgb = image.convert('RGB')
    width, height = rgb.size
    metrics = {'width':width, 'height':height, 'rgb_sha256':hashlib.sha256(rgb.tobytes()).hexdigest()}
    greens = []
    yellows = []
    for reference_y in (74,90,95,106,118):
        y = round(reference_y*height/1080)
        row = list(rgb.crop((0,y,width,y+1)).getdata())
        green, yellow = edge(row,'green'), edge(row,'yellow')
        if green is not None and yellow is not None and yellow > green:
            greens.append(green)
            yellows.append(yellow)
    if len(greens)<3:
        return dict(metrics, framing='unknown')
    green, yellow = round(median(greens)), round(median(yellows))
    scale = ((green/320 + yellow/640)/2)
    metrics.update(green_x=green, yellow_x=yellow)
    black_starts=[]
    for refx in (510,515,530):
        x = min(width-1,round(refx*scale))
        col = list(rgb.crop((x,0,x+1,height)).getdata())
        count = 0
        for y,pixel in enumerate(col):
            count=count+1 if y>height*.17 and max(pixel)<40 else 0
            if count==20:
                black_starts.append(y-19)
                break
    if len(black_starts)<2:
        return dict(metrics,framing='unknown')
    top=round(median(black_starts))
    metrics['black_y']=top
    sx=scale*1920/width
    sy=top*1080/(410*height)
    if abs(sx-1)<.04 and abs(sy-1)<.045 and abs(green-yellow/2)<width*.014:
        state='full'
    elif sx>1.12 and sy>1.12 and abs(sx-sy)<.08*max(sx,sy):
        state='enlarged'
    else:
        state='other'
    return dict(metrics,framing=state,scale_x=round(sx,4),scale_y=round(sy,4))
