"""Build an offline map and POI catalogue, plus roads from the installed game.
The website assets are fetched with a bounded worker pool and cached locally.
"""
from pathlib import Path
import concurrent.futures, urllib.request, json, re, math, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import argparse, time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'KnoxNavigator/42/media'
CACHE = ROOT / 'tools/cache'
REMOTE = 'https://tiles.projectzomboidmap.com/maps/b42.20.2-r1/'
LEVEL = 15

def fetch(relative):
    dest = CACHE / relative
    if dest.exists():
        return dest.read_bytes()
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            req = urllib.request.Request(REMOTE + relative, headers={'User-Agent':'KnoxNavigator-local-build/0.1'})
            with urllib.request.urlopen(req, timeout=45) as response:
                data = response.read()
            dest.write_bytes(data)
            return data
        except Exception:
            if attempt == 3: raise
            time.sleep(1 + attempt)

def array_literal(source, name):
    start = source.index(name + '=[') + len(name) + 1
    depth, quote, escape = 0, None, False
    for i in range(start, len(source)):
        c = source[i]
        if quote:
            if escape: escape = False
            elif c == '\\': escape = True
            elif c == quote: quote = None
        elif c in '\"\'`': quote = c
        elif c == '[': depth += 1
        elif c == ']':
            depth -= 1
            if depth == 0:
                literal = source[start:i+1]
                literal = re.sub(r'([{,])([A-Za-z_]+):', r'\1"\2":', literal)
                return json.loads(literal)
    raise ValueError('Unterminated catalogue')

def catalogue():
    source = (ROOT/'site-reference.js').read_text(encoding='utf-8-sig')
    pois = array_literal(source, 'ai')
    # No code from the website is evaluated.
    destination = OUT/'data/KnoxNavigator/pois.tsv'
    destination.write_text('\n'.join('\t'.join(str(p.get(k,'' )).replace('\t',' ').replace('\n',' ') for k in ['name','x','y','town']) for p in pois),encoding='utf-8')
    print('POIs:',len(pois),'Gift Shop:',sum(p['name']=='Gift Shop' for p in pois),flush=True)
    return pois

def roads(game):
    step = 4
    xml = game/'media/maps/Muldraugh, KY/worldmap.xml'
    tree = ET.parse(xml)
    cells = tree.getroot().findall('cell')
    maxx = max(int(c.get('x')) for c in cells)*300+300
    maxy = max(int(c.get('y')) for c in cells)*300+300
    width, height = math.ceil(maxx/step)+1, math.ceil(maxy/step)+1
    mask = Image.new('1',(width,height),0)
    painter = ImageDraw.Draw(mask)
    for cell in cells:
        ox, oy = int(cell.get('x'))*300, int(cell.get('y'))*300
        for feat in cell.findall('feature'):
            props = {p.get('name'):p.get('value') for p in feat.findall('./properties/property')}
            if props.get('highway') not in ('primary','secondary','tertiary'): continue
            for coords in feat.findall('./geometry/coordinates'):
                points=[((ox+float(p.get('x')))/step,(oy+float(p.get('y')))/step) for p in coords.findall('point')]
                if len(points)>=3: painter.polygon(points,fill=1)
    # Named road centrelines also cover small gaps at cell boundaries.
    for xml in (game/'media/maps').glob('*/streets.xml'):
        for street in ET.parse(xml).getroot().findall('street'):
            points=[(float(p.get('x'))/step,float(p.get('y'))/step) for p in street.findall('./points/point')]
            if len(points)>1:
                painter.line(points,fill=1,width=max(1,round(float(street.get('width','6'))/step)))
    # Encode per-row runs: compact, safe text data for B42's mod reader.
    pixels=mask.load(); count=0; lines=[f'{step}\t{width}\t{height}']
    for y in range(height):
        runs=[]; x=0
        while x<width:
            if not pixels[x,y]: x+=1; continue
            start=x
            while x<width and pixels[x,y]: x+=1
            runs.extend((start,x-1)); count+=x-start
        if runs: lines.append(str(y)+'\t'+'\t'.join(map(str,runs)))
    (OUT/'data/KnoxNavigator/roads.tsv').write_text('\n'.join(lines),encoding='utf-8')
    mask.save(ROOT/'tools/road-mask.png')
    print('Road cells:',count,'grid:',width,height,flush=True)

def imagery():
    meta=json.loads(fetch('base/map_info.json'))
    dzi=ET.fromstring(fetch('base/layer0.dzi'))
    tile=int(dzi.get('TileSize')); fmt=dzi.get('Format')
    scale=2**(math.ceil(math.log2(max(meta['w'],meta['h'])))-LEVEL)
    w,h=math.ceil(meta['w']/scale),math.ceil(meta['h']/scale)
    manifest=json.loads(fetch('base/tiles_manifest.json'))
    layer=manifest['layers'].get('0',{})
    levels=layer.get('levels',{})
    available=levels.get(str(LEVEL),{}) if isinstance(levels,dict) else levels[LEVEL]
    coords=[]
    for x in range(math.ceil(w/tile)):
        ranges=available.get(str(x),[]) if isinstance(available,dict) else []
        for y in range(math.ceil(h/tile)):
            if not available or any(ranges[i]<=y<=ranges[i+1] for i in range(0,len(ranges),2)):
                coords.append((x,y))
    folder=OUT/'textures/KnoxNavigator/iso'; folder.mkdir(exist_ok=True)
    def download(pos):
        x,y=pos; dest=folder/f'{x}_{y}.png'
        if not dest.exists():
            data=fetch(f'base/layer0_files/{LEVEL}/{x}_{y}.{fmt}')
            from io import BytesIO
            image=Image.open(BytesIO(data)).convert('RGB')
            image.save(dest,optimize=True)
        return pos
    print('Map level:',LEVEL,'scale:',scale,'tiles:',len(coords),flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for n,_ in enumerate(pool.map(download,coords),1):
            if n%25==0: print('Map tiles:',n,'/',len(coords),flush=True)
    meta.update(level=LEVEL,scale=scale,tile=tile,iw=w,ih=h,version='B42.20.2-r1')
    (OUT/'data/KnoxNavigator/map.json').write_text(json.dumps(meta),encoding='utf-8')
    # Bake an affine inverse of the isometric imagery into top-down textures.
    # Work in small blocks; never allocate a several-hundred-megapixel atlas.
    top=OUT/'textures/KnoxNavigator/top'; top.mkdir(exist_ok=True)
    block=512; ppm=0.5; top_tile=int(block*ppm)
    sqr=meta['sqr']/scale; x0=meta['x0']/scale; y0=meta['y0']/scale
    cache={}; valid=set(coords)
    def source_region(left,upper,right,lower):
        region=Image.new('RGB',(right-left,lower-upper),(14,19,18))
        for tx in range(math.floor(left/tile),math.floor((right-1)/tile)+1):
            for ty in range(math.floor(upper/tile),math.floor((lower-1)/tile)+1):
                if (tx,ty) not in valid: continue
                if (tx,ty) not in cache:
                    if len(cache)>40: cache.clear()
                    with Image.open(folder/f'{tx}_{ty}.png') as im: cache[tx,ty]=im.copy()
                region.paste(cache[tx,ty],(tx*tile-left,ty*tile-upper))
        return region
    # Site cells are 256 squares; ignore the void outside cell_rects.
    bounds=[]
    for cx,cy,cw,ch in meta['cell_rects']:
        bounds.append((cx*256,cy*256,(cx+cw)*256,(cy+ch)*256))
    num=0
    for bx in range(math.ceil(max(b[2] for b in bounds)/block)):
        for by in range(math.ceil(max(b[3] for b in bounds)/block)):
            wx,wy=bx*block,by*block
            if not any(wx<b[2] and wx+block>b[0] and wy<b[3] and wy+block>b[1] for b in bounds): continue
            dest=top/f'{bx}_{by}.png'
            if dest.exists(): continue
            pts=[(x0+(xx-yy)*sqr/2,y0+(xx+yy)*sqr/4) for xx,yy in [(wx,wy),(wx+block,wy),(wx,wy+block),(wx+block,wy+block)]]
            left=math.floor(min(p[0] for p in pts))-2; upper=math.floor(min(p[1] for p in pts))-2
            right=math.ceil(max(p[0] for p in pts))+2; lower=math.ceil(max(p[1] for p in pts))+2
            region=source_region(left,upper,right,lower)
            coefficients=(sqr/(2*ppm),-sqr/(2*ppm),x0+(wx-wy)*sqr/2-left,sqr/(4*ppm),sqr/(4*ppm),y0+(wx+wy)*sqr/4-upper)
            result=region.transform((top_tile,top_tile),Image.Transform.AFFINE,coefficients,Image.Resampling.BICUBIC)
            result.save(dest,optimize=True); num+=1
            if num%100==0: print('Top-down tiles:',num,flush=True)
    lua='KnoxNavigator = KnoxNavigator or {}\nKnoxNavigator.MapMeta = {\n'
    for key in ['scale','tile','iw','ih','sqr','x0','y0']:
        lua+=f'    {key} = {meta[key]},\n'
    lua+=f'    block = {block}, topTile = {top_tile}, version = "{meta["version"]}"\n}}\n'
    (OUT/'lua/shared/KnoxNavigator/MapMeta.lua').write_text(lua,encoding='utf-8')
    print('Offline map ready.',flush=True)

def overviews():
    texture_root=OUT/'textures/KnoxNavigator'
    meta=json.loads((OUT/'data/KnoxNavigator/map.json').read_text())
    for view,tile in [('iso',meta['tile']),('top',256)]:
        files=list((texture_root/view).glob('*.png'))
        coordinates=[tuple(map(int,p.stem.split('_'))) for p in files]
        w=(max(p[0] for p in coordinates)+1)*tile
        h=(max(p[1] for p in coordinates)+1)*tile
        image=Image.new('RGB',(math.ceil(w/16),math.ceil(h/16)),(14,19,18))
        for path,(x,y) in zip(files,coordinates):
            with Image.open(path) as original:
                small=original.resize((math.ceil(original.width/16),math.ceil(original.height/16)),Image.Resampling.LANCZOS)
                image.paste(small,(x*tile//16,y*tile//16))
        image.save(texture_root/(view+'_overview.png'))
        print('Overview:',view,image.size,flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=Path('D:/steam/steamapps/common/ProjectZomboid'));parser.add_argument('--skip-map',action='store_true')
    args=parser.parse_args();catalogue();roads(args.game)
    if not args.skip_map: imagery();overviews()
