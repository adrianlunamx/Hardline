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

# --- Marca: monograma H (desde 1.12.0). Dos astas y, en vez de travesaño, la
# "línea dura" naranja que sale por la derecha y acaba en un punto.
# viewBox 0 0 128 128. Mismo dibujo que assets/brand/concepts/04-monograma.svg.
# glow: resplandor naranja (lockups y vista previa; el icono pequeño va sin él).
def mark(x0=0, y0=0, s=1.0, bg=True, glow=False, uid='hl'):
    X = lambda v: f'{x0 + v*s:.2f}'
    Y = lambda v: f'{y0 + v*s:.2f}'
    S = lambda v: f'{v*s:.2f}'
    parts = [f'<defs><linearGradient id="{uid}g" gradientUnits="userSpaceOnUse" x1="{X(25.6)}" y1="0" x2="{X(106)}" y2="0">'
             f'<stop offset="0" stop-color="{ACC}"/><stop offset="1" stop-color="#FF9A3D"/></linearGradient>'
             + (f'<filter id="{uid}f" x="-40%" y="-80%" width="180%" height="260%"><feGaussianBlur stdDeviation="{S(3.2)}" result="b"/>'
                f'<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>' if glow else '')
             + '</defs>']
    if bg:
        parts.append(f'<rect x="{x0}" y="{y0}" width="{S(128)}" height="{S(128)}" rx="{S(28)}" fill="#0E1116" stroke="#2A313C" stroke-width="{S(2)}"/>')
    parts.append(f'<rect x="{X(25.6)}" y="{Y(27.2)}" width="{S(16.53)}" height="{S(73.6)}" rx="{S(4.8)}" fill="#EEF1F6"/>')
    parts.append(f'<rect x="{X(73.07)}" y="{Y(27.2)}" width="{S(16.53)}" height="{S(73.6)}" rx="{S(4.8)}" fill="#EEF1F6"/>')
    f = f' filter="url(#{uid}f)"' if glow else ''
    parts.append(f'<g{f}><rect x="{X(25.6)}" y="{Y(56)}" width="{S(80)}" height="{S(16)}" rx="{S(8)}" fill="url(#{uid}g)"/>'
                 f'<circle cx="{X(106.13)}" cy="{Y(64)}" r="{S(10.67)}" fill="{ACC}"/></g>')
    parts.append(f'<circle cx="{X(106.13)}" cy="{Y(64)}" r="{S(4)}" fill="#0E1116"/>')
    return '\n  '.join(parts)

def lockup(fg, sub):
    # icono 128 a la izquierda, texto a la derecha. Alto 128.
    word, ww = text_path(BOLD, 'HARDLINE', 84, 152, 84, tracking=0.04)
    tag, tw = text_path(MED, 'WARZONE  ·  WINDOWS  ·  AMD  ·  AUDIO', 21, 154, 116, tracking=0.12)
    W = int(max(152 + ww, 154 + tw) + 8)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} 128" width="{W}" height="128" role="img" aria-label="Hardline">
  <title>Hardline</title>
  {mark(glow=True)}
  <path d="{word}" fill="{fg}"/>
  <path d="{tag}" fill="{sub}"/>
</svg>
'''

open(f'{OUT}/logo-dark.svg','w').write(lockup('#F2F4F7', '#8A93A3'))   # para tema oscuro
open(f'{OUT}/logo-light.svg','w').write(lockup('#0E1116', '#5B6472'))  # para tema claro
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
  {mark(x0, 300-128*iconS/2-50, iconS, glow=True)}
  <path d="{word}" fill="#F2F4F7"/>
  <path d="{tag}" fill="#C4CAD4"/>
  <path d="{chp}" fill="#8A93A3"/>
</svg>
''')
print('ok')
