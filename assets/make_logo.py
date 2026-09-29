# Genera los logos de Hardline (assets/*.svg).
#
#   pip install fonttools
#   curl -LO https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/BarlowCondensed-Bold.ttf
#   curl -LO https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/BarlowCondensed-Medium.ttf
#   python assets/make_logo.py <carpeta con los .ttf> assets
#
# El texto se convierte a trazados (Barlow Condensed, licencia OFL), así que
# los SVG se ven igual en cualquier sistema sin depender de fuentes instaladas.
# social-preview.png se obtiene renderizando social-preview.svg a 1280x640.
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import os, sys
S = sys.argv[1]; OUT = sys.argv[2]

def text_path(fontfile, text, size, x, baseline, tracking=0.0):
    f = TTFont(fontfile)
    gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f['head'].unitsPerEm
    sc = size / upm
    hmtx = f['hmtx']
    d = []; cx = x
    for ch in text:
        g = cmap[ord(ch)]
        pen = SVGPathPen(gs)
        tp = TransformPen(pen, (sc, 0, 0, -sc, cx, baseline))
        gs[g].draw(tp)
        d.append(pen.getCommands())
        cx += hmtx[g][0] * sc + tracking * size
    return ' '.join(d), cx - tracking * size - x

BOLD = f'{S}/BarlowCondensed-Bold.ttf'; MED = f'{S}/BarlowCondensed-Medium.ttf'
ACC = '#FF5A1F'

# --- Marca: ruido -> línea firme. viewBox 0 0 128 128
def mark(x0=0, y0=0, s=1.0, bg=True, noise='#5B6472'):
    t = lambda px, py: f'{x0 + px*s:.2f},{y0 + py*s:.2f}'
    parts = []
    if bg:
        parts.append(f'<rect x="{x0}" y="{y0}" width="{128*s}" height="{128*s}" rx="{28*s}" fill="#0E1116" stroke="#2A313C" stroke-width="{2*s:.2f}"/>')
    # tramo irregular (picos decrecientes: stutter / explosiones)
    pts = [(18,64),(26,64),(30,38),(35,86),(40,46),(45,78),(50,54),(54,70),(58,60),(62,66),(66,64)]
    parts.append(f'<polyline points="{" ".join(t(*p) for p in pts)}" fill="none" stroke="{noise}" stroke-width="{6*s:.2f}" stroke-linecap="round" stroke-linejoin="round"/>')
    # línea firme
    parts.append(f'<line x1="{x0+66*s:.2f}" y1="{y0+64*s:.2f}" x2="{x0+104*s:.2f}" y2="{y0+64*s:.2f}" stroke="{ACC}" stroke-width="{10*s:.2f}" stroke-linecap="round"/>')
    parts.append(f'<circle cx="{x0+104*s:.2f}" cy="{y0+64*s:.2f}" r="{9*s:.2f}" fill="{ACC}"/>')
    return '\n  '.join(parts)

def lockup(fg, sub, noise):
    # icono 128 a la izquierda, texto a la derecha. Alto 128.
    word, ww = text_path(BOLD, 'HARDLINE', 84, 152, 84, tracking=0.04)
    tag, tw = text_path(MED, 'WARZONE  ·  WINDOWS  ·  AMD  ·  AUDIO', 21, 154, 116, tracking=0.12)
    W = int(max(152 + ww, 154 + tw) + 8)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} 128" width="{W}" height="128" role="img" aria-label="Hardline">
  <title>Hardline</title>
  {mark()}
  <path d="{word}" fill="{fg}"/>
  <path d="{tag}" fill="{sub}"/>
</svg>
'''

open(f'{OUT}/logo-dark.svg','w').write(lockup('#F2F4F7', '#8A93A3', '#5B6472'))   # para tema oscuro
open(f'{OUT}/logo-light.svg','w').write(lockup('#0E1116', '#5B6472', '#5B6472'))  # para tema claro
open(f'{OUT}/icon.svg','w').write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128" role="img" aria-label="Hardline">
  <title>Hardline</title>
  {mark()}
</svg>
''')

# --- Social preview 1280x640
word, ww = text_path(BOLD, 'HARDLINE', 150, 0, 0, tracking=0.04)
tag, tw = text_path(MED, 'Optimizaciones reales para Warzone. Nada de placebo.', 40, 0, 0, tracking=0.01)
chips = 'WINDOWS  ·  RYZEN  ·  RADEON  ·  RED  ·  AUDIO DE PASOS'
chp, cw = text_path(MED, chips, 26, 0, 0, tracking=0.14)
iconS = 1.6; block = 128*iconS + 40 + ww
x0 = (1280 - block)/2
wx = x0 + 128*iconS + 40
word, _ = text_path(BOLD, 'HARDLINE', 150, wx, 300, tracking=0.04)
tag, _ = text_path(MED, 'Optimizaciones reales para Warzone. Nada de placebo.', 40, (1280-tw)/2, 415, tracking=0.01)
chp, _ = text_path(MED, chips, 26, (1280-cw)/2, 478, tracking=0.14)
# línea de fondo: ruido -> firme a lo ancho
import random
random.seed(7)
pts=[(0,600)]; x=0
amp=26
while x < 560:
    x += random.randint(14,26); amp*=0.93
    pts.append((x, 600 + (amp if len(pts)%2 else -amp)))
bgline = ' '.join(f'{px:.0f},{py:.0f}' for px,py in pts)
open(f'{OUT}/social-preview.svg','w').write(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640">
  <rect width="1280" height="640" fill="#0E1116"/>
  <polyline points="{bgline}" fill="none" stroke="#2A313C" stroke-width="4" stroke-linejoin="round"/>
  <line x1="{pts[-1][0]}" y1="600" x2="1280" y2="600" stroke="{ACC}" stroke-opacity="0.55" stroke-width="4"/>
  {mark(x0, 300-128*iconS/2-50, iconS, bg=False, noise='#5B6472')}
  <path d="{word}" fill="#F2F4F7"/>
  <path d="{tag}" fill="#C4CAD4"/>
  <path d="{chp}" fill="#8A93A3"/>
</svg>
''')
print('ok')
