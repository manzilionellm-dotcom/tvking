"""Lecture optique en alphabet MK : reconnaissance indépendante du code de référence."""
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

ALPHABET = '0123456789ABCDEFKM:'

def normalized(im):
    bounds = im.getbbox()
    if not bounds:
        raise ValueError('Glyphe vide')
    return im.crop(bounds).resize((32,48),Image.Resampling.LANCZOS)

def alphabet(font_path):
    font = ImageFont.truetype(str(font_path),96)
    refs = {}
    for char in ALPHABET:
        image = Image.new('L',(160,160))
        ImageDraw.Draw(image).text((8,8),char,font=font,fill=255)
        refs[char] = normalized(image.point(lambda x: 255 if x>=128 else 0))
    return refs

def decode(crop, refs):
    grey = crop.convert('L')
    lo,hi = grey.getextrema()
    mask = grey.point(lambda x: 255 if x>(lo+hi)/2 else 0)
    xs = sorted(set(x for x in range(mask.width) if mask.crop((x,0,x+1,mask.height)).getbbox()))
    boundaries=[]
    for x in xs:
        if not boundaries or x>boundaries[-1][-1]+1:
            boundaries.append([x])
        else:
            boundaries[-1].append(x)
    text=''
    for run in boundaries:
        glyph = normalized(mask.crop((run[0],0,run[-1]+1,mask.height)))
        scores = {char:ImageStat.Stat(ImageChops.difference(ref,glyph)).mean[0] for char,ref in refs.items()}
        text+=min(scores,key=scores.get)
    return text
