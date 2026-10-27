"""Add level-17 offline imagery without replacing the low-zoom overview."""
from pathlib import Path
import runpy,json,math,concurrent.futures,xml.etree.ElementTree as ET
from io import BytesIO
from PIL import Image
BASE=runpy.run_path(str(Path(__file__).with_name('build_data.py')))
ROOT,OUT,fetch=BASE['ROOT'],BASE['OUT'],BASE['fetch']
LEVEL=17
meta=json.loads(fetch('base/map_info.json'))
dzi=ET.fromstring(fetch('base/layer0.dzi'))
tile=int(dzi.get('TileSize'));fmt=dzi.get('Format')
scale=2**(math.ceil(math.log2(max(meta['w'],meta['h'])))-LEVEL)
factor=128/scale
w,h=math.ceil(meta['w']/scale),math.ceil(meta['h']/scale)
manifest=json.loads(fetch('base/tiles_manifest.json'))
levels=manifest['layers']['0']['levels']
available=levels.get(str(LEVEL),{}) if isinstance(levels,dict) else levels[LEVEL]
coords=[]
for x in range(math.ceil(w/tile)):
    ranges=available.get(str(x),[])
    for y in range(math.ceil(h/tile)):
        if any(ranges[i]<=y<=ranges[i+1] for i in range(0,len(ranges),2)):coords.append((x,y))
iso=OUT/'textures/KnoxNavigator/iso_high';iso.mkdir(exist_ok=True)
def download(pos):
    x,y=pos;dest=iso/f'{x}_{y}.png'
    if not dest.exists():
        data=fetch(f'base/layer0_files/{LEVEL}/{x}_{y}.{fmt}')
        with Image.open(BytesIO(data)) as original:
            original.convert('RGB').save(dest,compress_level=3)
    return pos
print('High-detail tiles:',len(coords),'linear detail increase:',factor,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for n,_ in enumerate(pool.map(download,coords),1):
        if n%50==0:print('High-detail download:',n,'/',len(coords),flush=True)
top=OUT/'textures/KnoxNavigator/top_high';top.mkdir(exist_ok=True)
block=512;ppm=2;top_tile=block*ppm
sqr=meta['sqr']/scale;x0=meta['x0']/scale;y0=meta['y0']/scale
cache={};valid=set(coords)
def region(left,upper,right,lower):
    image=Image.new('RGB',(right-left,lower-upper),(14,19,18))
    for tx in range(math.floor(left/tile),math.floor((right-1)/tile)+1):
        for ty in range(math.floor(upper/tile),math.floor((lower-1)/tile)+1):
            if (tx,ty) not in valid:continue
            if (tx,ty) not in cache:
                if len(cache)>24:cache.clear()
                with Image.open(iso/f'{tx}_{ty}.png') as original:cache[tx,ty]=original.copy()
            image.paste(cache[tx,ty],(tx*tile-left,ty*tile-upper))
    return image
blocks=[tuple(map(int,p.stem.split('_'))) for p in (OUT/'textures/KnoxNavigator/top').glob('*.png')]
for n,(bx,by) in enumerate(blocks,1):
    dest=top/f'{bx}_{by}.png'
    if dest.exists():continue
    wx,wy=bx*block,by*block
    pts=[(x0+(xx-yy)*sqr/2,y0+(xx+yy)*sqr/4) for xx,yy in [(wx,wy),(wx+block,wy),(wx,wy+block),(wx+block,wy+block)]]
    left=math.floor(min(p[0] for p in pts))-2;upper=math.floor(min(p[1] for p in pts))-2
    right=math.ceil(max(p[0] for p in pts))+2;lower=math.ceil(max(p[1] for p in pts))+2
    source=region(left,upper,right,lower)
    coeff=(sqr/(2*ppm),-sqr/(2*ppm),x0+(wx-wy)*sqr/2-left,sqr/(4*ppm),sqr/(4*ppm),y0+(wx+wy)*sqr/4-upper)
    result=source.transform((top_tile,top_tile),Image.Transform.AFFINE,coeff,Image.Resampling.BICUBIC)
    result.save(dest,compress_level=3)
    if n%50==0:print('High-detail top view:',n,'/',len(blocks),flush=True)
metadata=OUT/'lua/shared/KnoxNavigator/MapMeta.lua'
source=metadata.read_text(encoding='utf-8')
if 'highFactor' not in source:
    source+=f'KnoxNavigator.MapMeta.highFactor = {factor}\nKnoxNavigator.MapMeta.highTile = {tile}\nKnoxNavigator.MapMeta.highTopTile = {top_tile}\n'
    metadata.write_text(source,encoding='utf-8')
print('High-detail map complete.',flush=True)
