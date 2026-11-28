"""Produire hors acquisition un film FFV1 à partir des luminances 8 bits mesurées."""
import csv
from fractions import Fraction
from pathlib import Path
import sys
import av
import numpy as np

p=Path(sys.argv[1]); rows=csv.DictReader((p/'luminance.csv').open()); t0=None; previous=-1
with av.open(str(p/'film-mire-echantillonne.mkv'),'w') as dest:
    stream=dest.add_stream('ffv1',rate=25);stream.width=300;stream.height=20;stream.pix_fmt='gray';stream.time_base=Fraction(1,1000);stream.codec_context.time_base=Fraction(1,1000)
    for row in rows:
        end=float(row['end_s']);t0=end if t0 is None else t0
        stamp=round((end-t0)*1000)
        if stamp<=previous:raise ValueError('PTS successifs non distincts')
        previous=stamp
        strip=np.tile(np.repeat(np.frombuffer(bytes.fromhex(row['luma_hex']),dtype=np.uint8),10),(20,1))
        frame=av.VideoFrame.from_ndarray(strip,format='gray');frame.pts=stamp;frame.time_base=Fraction(1,1000)
        for packet in stream.encode(frame):dest.mux(packet)
    for packet in stream.encode():dest.mux(packet)
