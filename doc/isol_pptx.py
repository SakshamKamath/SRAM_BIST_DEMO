# Click-driven PowerPoint slides for the JTAG interconnect (crossbar) isolation, same style as
# march_pptx.py. Follows rtl/SEM_PROJ_RTL/integrate_optimised_redundancy/obi_jtag_* and the
# +obi_jtag_test checks in rtl/test/tb_croc_chip.sv.
#   slide 1: how isolation helps debugging (cards, one per click)
#   slide 2: animation: isolate, daisy chain, shift / update / capture a request and a response, map, release
#   slide 3: scan cells bit by bit: shift, update, step, capture, shift out
#   slide 4: how req / gnt work during isolation (one step = one transaction)
#   slide 5: sub access: JTAG reads / writes a real subordinate (JtagSubAccess = 1)
#   slide 6: verification results and cost
#   slides 7-8: area plots from doc/area_composition.png and doc/area_overhead.png
#   slide 9: proposal, memory bank repair
# Slides avoid Croc addresses and sizes: managers / subordinates are numbered generically.
# usage: python isol_pptx.py out.pptx [image dir]
import sys
from lxml import etree
from pptx import Presentation
from pptx.oxml.ns import qn
from pptx.util import Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

TEAL, PURPLE, AMBER, DARK, RED, GREEN = "00897B", "93005F", "E39B2D", "12343B", "C62828", "2E7D32"
GREY, LIGHT, BLUE, PALE = "9E9E9E", "E0F2F1", "1E5A8C", "F5F5F5"
SANS, MONO = "Calibri", "Consolas"
FADE = 250

prs = Presentation()
prs.slide_width, prs.slide_height = Emu(9144000), Emu(5143500)   # 10" x 5.625"
px = lambda v: Emu(int(v * 9144000 / 1280))                       # design grid: 1280 x 720
fs = lambda v: Pt(v * 0.5625)
slide = None
IMG_DIR = sys.argv[2] if len(sys.argv) > 2 else "/home/sem26h3/Documents/SEM_PROJ/DEMO/doc"

def box(name, x, y, w, h, fill=None, line=None, lw=1.5, lines=(), shape=MSO_SHAPE.RECTANGLE,
        align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, margin=4, dash=False):
    s = slide.shapes.add_shape(shape, px(x), px(y), px(w), px(h))
    s.name = name
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        s.adjustments[0] = min(0.15, 10 / min(w, h))
    st = s._element.find(qn("p:style"))
    if st is not None: s._element.remove(st)   # no theme shadow/effects
    if fill: s.fill.solid(); s.fill.fore_color.rgb = RGBColor.from_string(fill)
    else: s.fill.background()
    if line:
        s.line.color.rgb = RGBColor.from_string(line); s.line.width = Pt(lw)
        if dash: s.line.dash_style = 4   # dash
    else: s.line.fill.background()
    tf = s.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    for side in ("left", "right", "top", "bottom"):
        setattr(tf, f"margin_{side}", px(margin))
    for k, ln in enumerate(lines):
        text, size, color = ln[:3]
        bold = ln[3] if len(ln) > 3 else False
        font = ln[4] if len(ln) > 4 else SANS
        p = tf.paragraphs[0] if k == 0 else tf.add_paragraph()
        p.alignment = align
        r = p.add_run(); r.text = text
        r.font.size, r.font.bold, r.font.name = fs(size), bold, font
        r.font.color.rgb = RGBColor.from_string(color)
    return s

def wire(name, x1, y1, x2, y2, color=DARK, lw=2.5, arrow=True, dash=False):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, px(x1), px(y1), px(x2), px(y2))
    c.name = name
    st = c._element.find(qn("p:style"))
    if st is not None: c._element.remove(st)
    c.line.color.rgb = RGBColor.from_string(color); c.line.width = Pt(lw)
    if dash: c.line.dash_style = 4
    if arrow:
        ln = c.line._get_or_add_ln()
        etree.SubElement(ln, qn("a:tailEnd"), {"type": "triangle", "w": "med", "len": "med"})
    return c

def title(text):
    box("Title", 40, 14, 1200, 50, lines=[(text, 32, DARK, True)], align=PP_ALIGN.LEFT, margin=0)

def caption(name, text):
    return box(name, 0, 628, 1280, 92, fill=DARK, lines=[(s, 22, "FFFFFF") for s in text.split("\n")],
               align=PP_ALIGN.LEFT, margin=40)

def ev(c, t, shp, kind="in"):
    c.append((t, shp, kind))

def attach_timing(sl, clicks):
    ids = [2]
    def nid():
        ids[0] += 1; return ids[0]
    grp = {}                                  # (spid, kind) -> grpId
    def effect(spid, kind, node):
        g = grp.setdefault((spid, kind), 0 if kind == "in" else 1)
        eid, a, b = nid(), nid(), nid()
        tgt = f'<p:tgtEl><p:spTgt spid="{spid}"/></p:tgtEl>'
        vis = lambda cid, d, v: (f'<p:set><p:cBhvr><p:cTn id="{cid}" dur="1" fill="hold"><p:stCondLst><p:cond delay="{d}"/></p:stCondLst></p:cTn>'
                                 f'{tgt}<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>'
                                 f'<p:to><p:strVal val="{v}"/></p:to></p:set>')
        fade = lambda cid, d: (f'<p:animEffect transition="{d}" filter="fade"><p:cBhvr><p:cTn id="{cid}" dur="{FADE}"/>{tgt}</p:cBhvr></p:animEffect>')
        body = vis(a, 0, "visible") + fade(b, "in") if kind == "in" else fade(a, "out") + vis(b, FADE - 1, "hidden")
        cls = "entr" if kind == "in" else "exit"
        return (f'<p:par><p:cTn id="{eid}" presetID="10" presetClass="{cls}" presetSubtype="0" fill="hold" grpId="{g}" nodeType="{node}">'
                f'<p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>{body}</p:childTnLst></p:cTn></p:par>')

    seq = []
    for c in clicks:
        times = sorted({t for t, _, _ in c})
        outer = nid()
        inner = []
        for gi, t in enumerate(times):
            pid = nid()
            effs = [effect(s.shape_id, k, ("clickEffect" if gi == 0 else "afterEffect") if j == 0 else "withEffect")
                    for j, (_, s, k) in enumerate([x for x in c if x[0] == t])]
            inner.append(f'<p:par><p:cTn id="{pid}" fill="hold"><p:stCondLst><p:cond delay="{t}"/></p:stCondLst>'
                         f'<p:childTnLst>{"".join(effs)}</p:childTnLst></p:cTn></p:par>')
        seq.append(f'<p:par><p:cTn id="{outer}" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst>'
                   f'<p:childTnLst>{"".join(inner)}</p:childTnLst></p:cTn></p:par>')
    bld = "".join(f'<p:bldP spid="{s}" grpId="{g}" animBg="1"/>' for (s, _), g in grp.items())
    NS = 'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
    timing = (f'<p:timing {NS}><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst>'
              '<p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>'
              + "".join(seq) +
              '</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>'
              '<p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>'
              f'</p:childTnLst></p:cTn></p:par></p:tnLst><p:bldLst>{bld}</p:bldLst></p:timing>')
    sl._element.append(etree.fromstring(timing))

def chip(name, x, y, text, color):
    return box(name, x, y, 230, 28, fill=color, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[(text, 15, "FFFFFF", True)], margin=0)

# =====================================================================================
# Slide 1: how isolation helps debugging
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("How crossbar isolation helps debugging")
box("Subtitle", 40, 66, 1200, 34, lines=[(
    "JTAG instructions wrap the OBI crossbar in scan registers (4 manager-side cuts, 5 subordinate-side cuts, "
    "a loadable address map); sub access also reads and writes the subordinates.", 18, GREY)],
    align=PP_ALIGN.LEFT, margin=0)
CARDS = [
    ("1", "Is it the crossbar?",
     "Send a real transfer through the crossbar from JTAG: req + payload in at any manager, "
     "rvalid + response back from the subordinate side. No core, software or memory has to work.",
     "Separates a decode / arbitration / response-routing bug in the crossbar from a fault outside it.",
     ("Verified: 8 transfers", GREEN)),
    ("2", "Freeze and look",
     "Entering isolation stalls every manager (no gnt, no rvalid) and keeps req away from every "
     "subordinate. Capture snapshots payload + valid at all 9 boundaries.",
     "After a hang: which request was waiting at each port. Transfers in flight are dropped on entry.",
     ("Not yet tested in sim", AMBER)),
    ("3", "What-if address map",
     "Load a different address map from JTAG, then re-run the routing test.",
     "Checks a suspected decode bug, or a remap (e.g. swap two memory ranges), without new silicon. Only while isolated.",
     ("Verified: banks swapped", GREEN)),
    ("4", "Clean exit",
     "BYPASS (or TAP reset) puts the cuts and crossbar back on the system clock, clears the cuts "
     "and restores the hard-wired map.",
     "The debug session leaves no trace: the core boots and runs afterwards.",
     ("Verified: read-back + program run", GREEN)),
]
cclicks = []
for k, (num, head, do, tells, (tag, tagc)) in enumerate(CARDS):
    x, y = 40 + (k % 2) * 610, 112 + (k // 2) * 252
    c = []; cclicks.append(c)
    shapes = [
        box(f"Card {num}", x, y, 590, 236, fill="FFFFFF", line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE),
        box(f"Card {num} num", x + 18, y + 16, 44, 44, fill=TEAL, shape=MSO_SHAPE.OVAL,
            lines=[(num, 22, "FFFFFF", True)], margin=0),
        box(f"Card {num} head", x + 76, y + 16, 300, 44, lines=[(head, 24, DARK, True)], align=PP_ALIGN.LEFT, margin=0),
        chip(f"Card {num} tag", x + 344, y + 24, tag, tagc),
        box(f"Card {num} do", x + 18, y + 70, 554, 84, lines=[("What you do", 15, TEAL, True), (do, 17, DARK)],
            align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=0),
        box(f"Card {num} tells", x + 18, y + 156, 554, 74, lines=[("What it tells you", 15, PURPLE, True), (tells, 17, DARK)],
            align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=0),
    ]
    for s in shapes: ev(c, 0, s)
attach_timing(slide, cclicks)
slide.notes_slide.notes_text_frame.text = (
    "4 clicks, one card each. Card 1: each cut register cell holds the payload plus one valid bit (req on the A "
    "channel, rvalid on the R channel); Update drives it for one TCK cycle (a step) and the subordinate-side cuts "
    "grant during every step. Card 2 (freeze and look) follows from the RTL: with isol_en the cuts drive gnt/rvalid "
    "= 0 to managers and req = 0 to subordinates and Capture loads the cut inputs, but it was not exercised in "
    "simulation, and the cut full flags are cleared on entry. Card 3: the JTAG address map is used only while XcnctIsolation is selected; outside "
    "isolation the register follows the hard-wired CrocAddrMap, so it cannot repair a chip at run time.")

# =====================================================================================
# Slide 2: animation with the scan chain: isolate, shift, update, capture, read out, map, release
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("Crossbar isolation in action")

MGRS = ["Manager 0", "Manager 1", "Manager 2", "Manager 3"]
SUBS = ["Sub 0", "Sub 1", "Sub 2", "Sub 3", "Sub 4"]
MX, MW, MH = 40, 170, 74
my = lambda i: 140 + i * 112
CMX, CW = 222, 30                      # manager-side cut strips
XX, XW, XY, XH = 300, 420, 120, 470    # crossbar
CSX = 732                              # subordinate-side cut strips
SX, SW, SH = 774, 180, 66
sy = lambda j: 132 + j * 94
PX, PW = 980, 270                      # panel
MAPX, MAPW, MAPY, MAPH = 300, 380, 76, 36
mcut = lambda i: (CMX, my(i) - 4, CW, MH + 8)
scut = lambda j: (CSX, sy(j) - 4, CW, SH + 8)
MCX, SCX_ = CMX + CW / 2, CSX + CW / 2     # chain runs through the middle of the cut strips

box("Xbar", XX, XY, XW, XH, fill="F4F8FB", line=BLUE, lw=2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Crossbar", 24, BLUE, True), ("routes each request by its address", 16, BLUE)],
    anchor=MSO_ANCHOR.BOTTOM, margin=14)
for i, m in enumerate(MGRS):
    box(f"Mgr {i}", MX, my(i), MW, MH, fill="EDE7F6", line=PURPLE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        lines=[(m, 19, DARK, True)], margin=4)
    box(f"Mgr cut {i}", *mcut(i), fill="FFFFFF", line=TEAL, lw=1.5)
    wire(f"Mgr {i} link", MX + MW, my(i) + MH / 2, CMX, my(i) + MH / 2, GREY, 1.5, arrow=False)
    wire(f"Mgr {i} xlink", CMX + CW, my(i) + MH / 2, XX, my(i) + MH / 2, GREY, 1.5, arrow=False)
for j, s in enumerate(SUBS):
    box(f"Sub {j}", SX, sy(j), SW, SH, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        lines=[(s, 18, DARK, True)], margin=4)
    box(f"Sub cut {j}", *scut(j), fill="FFFFFF", line=TEAL, lw=1.5)
    wire(f"Sub {j} xlink", XX + XW, sy(j) + SH / 2, CSX, sy(j) + SH / 2, GREY, 1.5, arrow=False)
    wire(f"Sub {j} link", CSX + CW, sy(j) + SH / 2, SX, sy(j) + SH / 2, GREY, 1.5, arrow=False)
box("Map", MAPX, MAPY, MAPW, MAPH, fill=PALE, line=GREY, lw=1.5,
    lines=[("Address map: built in", 15, DARK, True)], margin=2)

def panel(name, mode, driver, color):
    return box(name, PX, 120, PW, 470, fill="FFFFFF", line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[("Mode", 15, GREY, True), (mode, 24, color, True), ("", 8, DARK),
                      ("Crossbar driven by", 15, GREY, True), (driver, 20, DARK, True)],
               align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=16)
def route(name, i, j, color=AMBER, lw=4):
    return wire(name, CMX + CW, my(i) + MH / 2, CSX, sy(j) + SH / 2, color, lw)
def back(name, j, i, color=GREEN, lw=4):
    return wire(name, CSX, sy(j) + SH / 2, CMX + CW, my(i) + MH / 2, color, lw)
def fill_cut(name, geo, color):
    return box(name, *geo, fill=color, line=TEAL, lw=1.5)
def tag(name, x, y, text, color, w=170):
    return box(name, x, y, w, 26, fill="FFFFFF", line=color, lw=1.2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[(text, 14, color, True)], margin=0)
def mtag(name, i, text, color):      # under a manager
    return tag(name, MX + 10, my(i) + MH + 2, text, color, 150)
def stag(name, j, text, color):      # on a subordinate
    return tag(name, SX + 30, sy(j) + SH - 6, text, color, 130)

panel("Panel normal", "Normal", "the managers", PURPLE)

# ---- the daisy chain, in shift order: TDI -> map register -> manager cuts 0..3 -> subordinate cuts 4..0 -> TDO
BOT = 606
CHAIN = []        # ("seg", [(x, y), ...]) or ("reg", (x, y, w, h))
CHAIN.append(("seg", [(604, 50), (660, 50), (660, MAPY)]))
CHAIN.append(("reg", (MAPX, MAPY, MAPW, MAPH)))
CHAIN.append(("seg", [(MAPX, MAPY + MAPH / 2), (MCX, MAPY + MAPH / 2), (MCX, mcut(0)[1])]))
for i in range(4):
    CHAIN.append(("reg", mcut(i)))
    if i < 3:
        CHAIN.append(("seg", [(MCX, mcut(i)[1] + mcut(i)[3]), (MCX, mcut(i + 1)[1])]))
CHAIN.append(("seg", [(MCX, mcut(3)[1] + mcut(3)[3]), (MCX, BOT), (SCX_, BOT), (SCX_, scut(4)[1] + scut(4)[3])]))
for j in range(4, -1, -1):
    CHAIN.append(("reg", scut(j)))
    if j > 0:
        CHAIN.append(("seg", [(SCX_, scut(j)[1]), (SCX_, scut(j - 1)[1] + scut(j - 1)[3])]))
CHAIN.append(("seg", [(SCX_, scut(0)[1]), (SCX_, 94), (800, 94)]))
CH_TDO = len(CHAIN) - 1
CH_MAP = 1
CH_S4 = next(k for k, (t, g) in enumerate(CHAIN) if t == "reg" and g == scut(4))

def chain_draw(prefix, color, lw, dash, sel=None):
    """Lines (and register outlines) for the chain elements in sel; one list per element."""
    out = []
    for k, (t, g) in enumerate(CHAIN):
        if sel is not None and k not in sel:
            out.append([]); continue
        if t == "seg":
            pts = g
            out.append([wire(f"{prefix} {k}.{n}", *pts[n], *pts[n + 1], color, lw,
                             arrow=(n == len(pts) - 2), dash=dash) for n in range(len(pts) - 1)])
        else:
            out.append([box(f"{prefix} {k}", *g, fill=None, line=color, lw=lw + 1)])
    return out

def pulse(c, t0, first, last, prefix, dt=90):
    """Light the chain from element first to last, one element after the other, then fade it."""
    lit = chain_draw(prefix, AMBER, 4, False, set(range(first, last + 1)))
    k_end = t0
    for n, k in enumerate(range(first, last + 1)):
        for s in lit[k]: ev(c, t0 + n * dt, s)
        k_end = t0 + n * dt
    for k in range(first, last + 1):
        for s in lit[k]: ev(c, k_end + 400, s, "out")
    return k_end + 400

caption("Caption 0", "The crossbar connects managers (core, debug, …) to subordinates (memories, peripherals).\n"
                     "Each link has a cut register (teal). Click to follow a transaction.")
clicks = []
def click():
    clicks.append([]); return clicks[-1]

# 1: normal transaction
c = click()
r1 = route("Route normal", 2, 3, PURPLE)
ev(c, 0, r1)
ev(c, 0, caption("Caption 1", "Normal mode: manager 2 reads from subordinate 3 through the crossbar.\n"
                              "If this fails on silicon: is the bug in the manager, the crossbar or the memory?"))

# 2: isolate, the chain appears
c = click()
ev(c, 0, r1, "out")
iso_cuts = [fill_cut(f"Iso mgr cut {i}", mcut(i), LIGHT) for i in range(4)] + \
           [fill_cut(f"Iso sub cut {j}", scut(j), LIGHT) for j in range(5)]
for s in iso_cuts: ev(c, 0, s)
waits = [mtag(f"Wait {i}", i, "waits", RED) for i in range(4)]
for s in waits: ev(c, 300, s)
chain = [s for el in chain_draw("Chain", AMBER, 2, True) for s in el]
for k, s in enumerate(chain): ev(c, 500 + k * 25, s)
tdi = box("TDI", 540, 36, 62, 28, lines=[("TDI", 17, AMBER, True)], align=PP_ALIGN.RIGHT, margin=2)
tdo = box("TDO", 802, 80, 70, 28, lines=[("TDO", 17, AMBER, True)], align=PP_ALIGN.LEFT, margin=2)
ev(c, 500, tdi); ev(c, 500 + len(chain) * 25, tdo)
p_iso = panel("Panel iso", "Isolated", "JTAG", TEAL)
ev(c, 0, p_iso)
OPS = [("Shift-DR", "bits move along the chain"), ("Update-DR", "a cut drives the bus, 1 TCK"),
       ("Capture-DR", "cuts record what arrived")]
OPY = lambda n: 300 + n * 70
ops = [box(f"Op {n}", PX + 16, OPY(n), PW - 32, 60, fill=PALE, line="DDDDDD", lw=1, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
           lines=[(a, 17, DARK, True), (b, 13, GREY)], margin=2) for n, (a, b) in enumerate(OPS)]
ops.append(box("Op head", PX + 16, 268, PW - 32, 26, lines=[("JTAG step", 15, GREY, True)], align=PP_ALIGN.LEFT, margin=0))
for s in ops: ev(c, 300, s)
def op_on(n):
    a, b = OPS[n]
    return box(f"Op hl {n} {len(clicks)}", PX + 16, OPY(n), PW - 32, 60, fill="FFF3E0", line=AMBER, lw=2.5,
               shape=MSO_SHAPE.ROUNDED_RECTANGLE, lines=[(a, 17, AMBER, True), (b, 13, DARK, True)], margin=2)
ev(c, 0, caption("Caption 2", "Isolation instruction: managers wait, subordinates see nothing, the crossbar runs on the JTAG clock.\n"
                              "The address-map register and all cut registers are daisy-chained from TDI to TDO."))

# 3: Shift-DR, a request lands in manager 3's cut
c = click()
h = op_on(0); ev(c, 0, h)
t_end = pulse(c, 0, 0, CH_TDO, "Shift a")
inj = fill_cut("Inject m3", mcut(3), AMBER)
inj_t = tag("Inject tag", 24, my(3) + MH + 30, "request loaded", AMBER, 150)
ev(c, t_end, inj); ev(c, t_end, inj_t)
ev(c, 0, caption("Caption 3", "Shift-DR: a bit pattern moves through every register in the chain, one bit per TCK.\n"
                              "When it stops, manager 3's cut holds a request (valid + address + data); the others hold 0."))

# 4: Update-DR, the request is driven for one TCK
c = click()
ev(c, 0, h, "out")
h = op_on(1); ev(c, 0, h)
r2 = route("Route test", 3, 4)
ev(c, 400, r2)
ev(c, 0, caption("Caption 4", "Update-DR: manager 3's cut drives the request into the crossbar for exactly one TCK.\n"
                              "The crossbar routes it by its address toward subordinate 4."))

# 5: Capture-DR, subordinate 4's cut records it
c = click()
ev(c, 0, h, "out")
h = op_on(2); ev(c, 0, h)
got4 = fill_cut("Got s4", scut(4), GREEN)
got4_t = stag("Got s4 tag", 4, "captured", GREEN)
ev(c, 300, got4); ev(c, 300, got4_t)
zeros = [stag(f"Zero s{j}", j, "nothing", GREY) for j in range(4)]
for s in zeros: ev(c, 300, s)
ev(c, 0, caption("Caption 5", "Capture-DR: every subordinate-side cut records what reached it in that cycle.\n"
                              "Only subordinate 4's cut holds the request; the other cuts saw nothing."))

# 6: Shift-DR, read the result out at TDO
c = click()
ev(c, 0, h, "out")
for s in [r2] + zeros: ev(c, 0, s, "out")
h = op_on(0); ev(c, 0, h)
t_end = pulse(c, 0, CH_S4, CH_TDO, "Shift b", dt=140)
read_t = tag("Read tag", 872, 66, "Sub 4 got it ✓", GREEN, 100)
ev(c, t_end, read_t)
ev(c, 0, caption("Caption 6", "Shift-DR again: the captured bits come out at TDO (while the next pattern goes in at TDI).\n"
                              "JTAG reads: the request reached subordinate 4, the one its address belongs to."))

# 7: response, same three steps the other way
c = click()
ev(c, 0, h, "out")
for s in (inj, inj_t, got4, got4_t, read_t): ev(c, 0, s, "out")
hs = [op_on(0), op_on(1), op_on(2)]
rsp4 = fill_cut("Rsp s4", scut(4), AMBER)
rsp4_t = stag("Rsp s4 tag", 4, "response", AMBER)
ev(c, 0, hs[0]); ev(c, 300, rsp4); ev(c, 300, rsp4_t)
ev(c, 1100, hs[0], "out"); ev(c, 1100, hs[1])
rb = back("Route back", 4, 3)
ev(c, 1300, rb)
ev(c, 2200, hs[1], "out"); ev(c, 2200, hs[2])
gotm3 = fill_cut("Got m3", mcut(3), GREEN)
gotm3_t = tag("Got m3 tag", 24, my(3) + MH + 30, "response ✓", GREEN, 150)
ev(c, 2400, gotm3); ev(c, 2400, gotm3_t)
ev(c, 0, caption("Caption 7", "The response is tested the same way: shift it into subordinate 4's cut, update, then capture.\n"
                              "It returns only to manager 3's cut, the manager that asked. No core, software or memory involved."))

# 8: a different address map, shifted in from TDI
c = click()
ev(c, 0, hs[2], "out")
for s in (rsp4, rsp4_t, rb, gotm3, gotm3_t): ev(c, 0, s, "out")
h = op_on(0); ev(c, 0, h)
t_end = pulse(c, 0, 0, CH_MAP, "Shift c", dt=250)
map_j = box("Map jtag", MAPX, MAPY, MAPW, MAPH, fill="FFF3E0", line=AMBER, lw=2.5,
            lines=[("Address map: from JTAG (changed)", 15, AMBER, True)], margin=2)
ev(c, t_end, map_j)
inj2 = fill_cut("Inject m3 b", mcut(3), AMBER)
inj2_t = tag("Inject tag b", 24, my(3) + MH + 30, "same request", AMBER, 150)
ev(c, t_end, inj2); ev(c, t_end, inj2_t)
h2 = op_on(1)
ev(c, t_end + 700, h, "out"); ev(c, t_end + 700, h2)
r3 = route("Route new map", 3, 3)
ev(c, t_end + 900, r3)
got3 = fill_cut("Got s3", scut(3), GREEN)
got3_t = stag("Got s3 tag", 3, "captured ✓", GREEN)
h3 = op_on(2)
ev(c, t_end + 1600, h2, "out"); ev(c, t_end + 1600, h3)
ev(c, t_end + 1800, got3); ev(c, t_end + 1800, got3_t)
ev(c, 0, caption("Caption 8", "The address map is the first register in the chain. Shift in a changed map and the same request\n"
                              "now goes where the new map says: check a suspected decoding error without new silicon."))

# 9: release
c = click()
for s in [h3, map_j, inj2, inj2_t, r3, got3, got3_t, tdi, tdo] + iso_cuts + waits + chain + ops:
    ev(c, 0, s, "out")
ev(c, 0, panel("Panel exit", "Normal", "the managers", PURPLE))
r6 = route("Route after", 2, 3, PURPLE)
ev(c, 600, r6)
ev(c, 0, caption("Caption 9", "Leaving isolation (BYPASS) reopens the cuts and restores the built-in map.\n"
                              "The system runs as before; the test leaves nothing behind."))
attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    f"{len(clicks)} clicks. Croc mapping: managers 0-3 = user, debug, core data, core instruction; subordinates "
    "0-4 = error, peripherals, user/VAD, SRAM bank 0, SRAM bank 1. Isolation instruction = XcnctIsolation on the "
    "obi_jtag TAP: the cuts and the crossbar run on TCK, managers get no gnt/rvalid, subordinates no req. "
    "Chain (1284 bits TDI to TDO): address-map register, then the manager-side cuts, then the subordinate-side "
    "cuts; drawn simplified here. Each cut holds an A cell and an R cell, each payload plus one valid bit. "
    "In practice one scan does Capture + Shift + Update together: it reads the last step and loads the next. "
    "The JTAG register also holds a default index per manager (where unmapped addresses go), verified in "
    "simulation but left off the slide. tb_croc_chip +obi_jtag_test: 23 of 23 checks pass (18 isolation + 5 sub access, see the sub access slide).")

# =====================================================================================
# Slide: scan cell mechanics, bit by bit (shift, update, step, capture, shift out)
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("Scan cells: shift, update, capture")

SC_W, SC_G = 60, 8                         # cell width, gap
SC_ROWS = {"in": 198, "sh": 272, "up": 346}  # row tops, height 44
SC_H = 44
SC_CUTS = [("Manager-side cut", 150), ("Subordinate-side cut", 812)]   # frame x; frame w 298
SC_HEAD = ["valid", "p2", "p1", "p0"]
scx = lambda k: SC_CUTS[k // 4][1] + 18 + (k % 4) * (SC_W + SC_G)     # bit k = 0..7 along the chain
scy = lambda row: SC_ROWS[row]

# static structure
def sc_label(name, fx, row, lab):
    return box(name, fx + 14, scy(row) - 21, 270, 20, lines=[(lab, 12, GREY, True)], align=PP_ALIGN.LEFT, margin=0)
SC_LABS, SC_LABTXT = {}, {}                               # row labels, hidden while copy arrows cross them
box("SC xbar", 500, 150, 260, 255, fill="F4F8FB", line=BLUE, lw=2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Crossbar", 20, BLUE, True), ("routes by address", 14, BLUE)], anchor=MSO_ANCHOR.TOP, margin=8)
for name, fx in SC_CUTS:
    box(f"SC frame {name}", fx, 150, 298, 255, fill="FFFFFF", line=TEAL, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        lines=[(name, 15, TEAL, True)], anchor=MSO_ANCHOR.TOP, margin=4)
    for row, lab in (("in", "input (from the bus)"), ("sh", "shift stage (on the scan chain)"),
                     ("up", "update stage (drives the bus)")):
        SC_LABS.setdefault(row, []).append(sc_label(f"SC lab {name} {row}", fx, row, lab))
        SC_LABTXT.setdefault(row, []).append((fx, lab))
def relabel(row):
    """Fresh copies of a row's labels (a shape with an entrance effect starts hidden)."""
    return [sc_label(f"SC lab {fx} {row} b", fx, row, lab) for fx, lab in SC_LABTXT[row]]
for k in range(8):
    for row in SC_ROWS:
        box(f"SC cell {row} {k}", scx(k), scy(row), SC_W, SC_H, fill="FFFFFF", line=GREY, lw=1)
    box(f"SC head {k}", scx(k), 128, SC_W, 18, lines=[(SC_HEAD[k % 4], 11, GREY, True)], margin=0)

# bus wiring: manager -> cut, cut update -> crossbar -> other cut input, cut -> subordinate (held)
box("SC mgr", 20, 196, 118, 48, fill="EDE7F6", line=PURPLE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Manager", 14, DARK, True), ("stalled", 12, GREY)], margin=2)
wire("SC mgr link", 138, scy("in") + 22, 150, scy("in") + 22, GREY, 1.5)
wire("SC up link", 448, scy("up") + 22, 500, scy("up") + 22, GREY, 1.5)
wire("SC sub link", 760, scy("in") + 22, 812, scy("in") + 22, GREY, 1.5)
box("SC sub", 1120, 340, 150, 56, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Subordinate", 14, DARK, True), ("req held at 0", 12, GREY)], margin=2)
wire("SC sub out", 1110, 368, 1120, 368, GREY, 1.5)

# scan chain: TDI -> manager-side shift stage -> over the crossbar -> subordinate-side shift stage -> TDO
SCY = scy("sh") + 22
box("SC tdi", 20, SCY - 16, 110, 32, lines=[("TDI", 17, AMBER, True)], align=PP_ALIGN.LEFT, margin=4)
wire("SC tdi w", 70, SCY, 168, SCY, AMBER, 2.5)
wire("SC ch 1", 432, SCY, 474, SCY, AMBER, 2.5, arrow=False, dash=True)
wire("SC ch 2", 474, SCY, 474, 112, AMBER, 2.5, arrow=False, dash=True)
wire("SC ch 3", 474, 112, 788, 112, AMBER, 2.5, arrow=False, dash=True)
wire("SC ch 4", 788, 112, 788, SCY, AMBER, 2.5, arrow=False, dash=True)
wire("SC ch 5", 788, SCY, 830, SCY, AMBER, 2.5, dash=True)
box("SC ch lab", 520, 88, 220, 22, lines=[("scan chain", 13, AMBER, True)], margin=0)
wire("SC tdo w", 1094, SCY, 1150, SCY, AMBER, 2.5)
box("SC tdo", 1154, SCY - 16, 110, 32, lines=[("TDO", 17, AMBER, True)], align=PP_ALIGN.LEFT, margin=4)
box("SC tdo lab", 1120, SCY - 68, 150, 18, lines=[("read out", 11, GREY, True)], margin=0)
box("SC tdi lab", 14, SCY + 18, 130, 18, lines=[("still to shift in", 11, GREY, True)], margin=0)

# TAP operations legend (doubles as the "where are we" indicator)
OPS = [("Capture-DR", "input → shift stage", "all bits at once"),
       ("Shift-DR", "TDI → … → TDO", "one bit per TCK"),
       ("Update-DR", "shift → update stage", "all bits at once"),
       ("Step", "update stage drives", "the bus for 1 TCK")]
OPX = lambda i: 40 + i * 302
for i, (a, b, c_) in enumerate(OPS):
    box(f"SC op {i}", OPX(i), 470, 290, 108, fill=PALE, line="DDDDDD", lw=1, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        lines=[(a, 19, DARK, True), (b, 15, DARK), (c_, 14, GREY)], margin=4)
for i in range(3):
    wire(f"SC op arr {i}", OPX(i) + 290, 524, OPX(i + 1), 524, GREY, 1.5)
def op_hl(i):
    a, b, c_ = OPS[i]
    return box(f"SC op hl {i}", OPX(i), 470, 290, 108, fill="FFF3E0", line=AMBER, lw=3, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[(a, 19, AMBER, True), (b, 15, DARK, True), (c_, 14, DARK)], margin=4)

# value boxes; later boxes sit on top of earlier ones, so a new value simply fades in over the old
OLD_FILL, NEW_FILL, CAP_FILL = "FFFFFF", "FFF3E0", "E8F5E9"
def val(name, row, k, v, fill="FFFFFF", color=DARK, line=GREY, lw=1.6):
    return box(name, scx(k), scy(row), SC_W, SC_H, fill=fill, line=line, lw=lw, lines=[(str(v), 20, color, True, MONO)], margin=0)
def strbox(name, x, bits, color):
    s = "".join(str(b) for b in bits)
    s = (s[:4] + " " + s[4:]) if len(s) > 4 else s
    return box(name, x, SCY + 36 if x < 640 else SCY - 50, 130, 28, fill="FFFFFF", lines=[(s, 15, color, True, MONO)], margin=0)
def counter(name, text):
    return box(name, 1000, 20, 240, 40, fill="FFFFFF", lines=[(text, 18, AMBER, True)], align=PP_ALIGN.RIGHT, margin=0)

state = [0, 1, 1, 0, 1, 0, 0, 1]          # left over from an earlier capture
for k, v in enumerate(state):
    val(f"SC sh0 {k}", "sh", k, v, color=GREY)
    val(f"SC in0 {k}", "in", k, 0, color=GREY)
    val(f"SC up0 {k}", "up", k, 0, color=GREY)

caption("SC cap 0", "Every cut register is one scan cell: a shift stage on the JTAG chain and an update stage\n"
                    "that drives the bus. Here: two cuts with a valid bit and a 3-bit payload. Click to step through.")
clicks = []
def click():
    clicks.append([]); return clicks[-1]

TCK = 520                                   # ms per animated TCK cycle
def shift(c, target, t0, fill, color, tag):
    """Animate len(target) Shift-DR cycles; returns the shapes to clear later."""
    global state
    keep = []
    queue = list(target)
    out = []
    keep.append(strbox(f"SC q {tag} 0", 0, queue, AMBER)); ev(c, t0, keep[-1])
    keep.append(strbox(f"SC o {tag} 0", 1130, out, AMBER)); ev(c, t0, keep[-1])
    for f in range(len(target)):
        t = t0 + (f + 1) * TCK
        bit_in = queue.pop()                 # rightmost bit goes in first, ends up rightmost
        out.insert(0, state[-1])             # bits leave at TDO; shown in chain order
        state = [bit_in] + state[:-1]
        for k in range(8):
            new = k <= f                     # this cell already holds a bit from TDI
            ev(c, t, val(f"SC sh {tag} {f} {k}", "sh", k, state[k], fill if new else OLD_FILL,
                         color if new else GREY))
        keep.append(strbox(f"SC q {tag} {f + 1}", 0, queue, AMBER)); ev(c, t, keep[-1])
        keep.append(strbox(f"SC o {tag} {f + 1}", 1130, out, AMBER)); ev(c, t, keep[-1])
        keep.append(counter(f"SC tck {tag} {f}", f"TCK {f + 1} / {len(target)}")); ev(c, t, keep[-1])
    return keep

# 1: Shift-DR, a request goes into the manager-side cut
c = click()
hl1 = op_hl(1); ev(c, 0, hl1)
k1 = shift(c, [1, 1, 0, 1, 0, 0, 0, 0], 300, NEW_FILL, DARK, "a")
ev(c, 0, caption("SC cap 1", "Shift-DR: one bit moves one place per TCK, from TDI toward TDO. The manager-side cut gets\n"
                              "valid = 1 and a payload; the old contents leave at TDO. The bus sees none of this."))

# 2: Update-DR, shift stage copied to the update stage
c = click()
ev(c, 0, hl1, "out")
for s in k1: ev(c, 0, s, "out")
hl2 = op_hl(2); ev(c, 0, hl2)
arr_up = [wire(f"SC arr up {k}", scx(k) + SC_W / 2, scy("sh") + SC_H, scx(k) + SC_W / 2, scy("up"), AMBER, 2.5)
          for k in range(8)]
for s in SC_LABS["up"]: ev(c, 0, s, "out")
for s in arr_up: ev(c, 300, s)
for k in range(8):
    ev(c, 700, val(f"SC up1 {k}", "up", k, state[k], NEW_FILL, DARK, AMBER, 1.6))
ev(c, 0, caption("SC cap 2", "Update-DR copies every shift-stage bit into the update stage at the same moment.\n"
                              "Only now does the new request appear at the cut's output."))

# 3: step, one TCK: the update stage drives the bus, the crossbar routes it, the other cut sees it
c = click()
ev(c, 0, hl2, "out")
for s in arr_up: ev(c, 0, s, "out")
for s in relabel("up"): ev(c, 0, s)
hl3 = op_hl(3); ev(c, 0, hl3)
bus = [wire("SC bus 1", 448, scy("up") + 22, 500, scy("up") + 22, AMBER, 4),
       wire("SC bus 2", 500, scy("up") + 22, 760, scy("in") + 22, AMBER, 4),
       wire("SC bus 3", 760, scy("in") + 22, 830, scy("in") + 22, AMBER, 4)]
for k, s in enumerate(bus): ev(c, 300 + k * 350, s)
req_t = box("SC req tag", 520, 300, 220, 26, fill="FFFFFF", line=AMBER, lw=1.2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
            lines=[("req = 1 for one TCK", 14, AMBER, True)], margin=0)
ev(c, 300, req_t)
for k in range(4, 8):
    ev(c, 1400, val(f"SC in1 {k}", "in", k, state[k - 4], CAP_FILL, DARK, GREEN, 1.6))
for s in bus: ev(c, 2400, s, "out")
ev(c, 2400, req_t, "out")
req0 = box("SC req0 tag", 520, 300, 220, 26, fill="FFFFFF", line=GREY, lw=1.2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
           lines=[("next cycle: req = 0", 14, GREY, True)], margin=0)
ev(c, 2400, req0)
ev(c, 0, caption("SC cap 3", "The step: for exactly one TCK cycle the update stage drives req + payload. The crossbar routes it\n"
                              "and the subordinate-side cut samples what arrives. Then req drops, so it is sent only once."))

# 4: Capture-DR, inputs copied into the shift stage
c = click()
ev(c, 0, hl3, "out"); ev(c, 0, req0, "out")
hl0 = op_hl(0); ev(c, 0, hl0)
arr_cap = [wire(f"SC arr cap {k}", scx(k) + SC_W / 2, scy("in") + SC_H, scx(k) + SC_W / 2, scy("sh"), GREEN, 2.5)
           for k in range(8)]
for s in SC_LABS["sh"]: ev(c, 0, s, "out")
for s in arr_cap: ev(c, 300, s)
captured = [0, 0, 0, 0] + state[0:4]
state = captured
for k in range(8):
    ev(c, 700, val(f"SC sh2 {k}", "sh", k, state[k], CAP_FILL if k >= 4 else OLD_FILL, DARK, GREEN if k >= 4 else GREY,
                   1.6))
ev(c, 0, caption("SC cap 4", "Capture-DR copies every input into the shift stage at the same moment. The subordinate-side cut\n"
                              "now holds the request that crossed the crossbar; the idle manager side holds 0."))

# 5: Shift-DR, read out at TDO while the next pattern goes in
c = click()
ev(c, 0, hl0, "out")
for s in arr_cap: ev(c, 0, s, "out")
for s in relabel("sh"): ev(c, 0, s)
hl1b = op_hl(1); ev(c, 0, hl1b)
k5 = shift(c, [0, 0, 0, 0, 0, 0, 0, 0], 300, NEW_FILL, DARK, "b")
ev(c, 300 + 8 * TCK + 200, box("SC read tag", 1112, 150, 160, 50, fill="E8F5E9", line=GREEN, lw=1.5,
                                  shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                                  lines=[("sub-side cut: 1101", 13, GREEN, True), ("request arrived ✓", 13, GREEN, True)],
                                  margin=2))
ev(c, 0, caption("SC cap 5", "Shift-DR again: the captured bits leave at TDO, and the next pattern goes in at TDI\n"
                              "at the same time. One scan reads the last step and loads the next one."))
attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    f"{len(clicks)} clicks. Simplified: two cut registers, each a valid bit plus a 3-bit payload. In the RTL "
    "(spill_register_flushable_mod) the shift stage is {valid_q, a_data_q}, the update stage is b_data_q plus "
    "valid_upd_q, and the step is step_q, set by Update-DR for the next TCK cycle. Each OBI cut has an A cell "
    "(request: valid = req) and an R cell (response: valid = rvalid). Subordinate-side A cells never drive req to "
    "the real subordinate, manager-side R cells never drive rvalid to the real manager. The cells sample their "
    "inputs in the step cycle; Capture-DR keeps that sample (or loads the live inputs if no step happened since the "
    "last Update). In Croc the chain is 1284 bits from chip TDI to TDO: the address-map register and 9 cuts, so "
    "each scan takes about 1,300 TCK cycles.")

# =====================================================================================
# Slide: how req / gnt work during isolation (one cut on each side of the crossbar)
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("How req / gnt work during isolation")

AY, RY = 196, 340                 # A channel (left -> right) and R channel (right -> left)
REQ_Y, GNT_Y = AY - 12, AY + 12
GAP = {"L0": (180, 240), "L1": (400, 470), "X": (470, 790), "R1": (790, 860), "R0": (1020, 1080)}
gcx = lambda g: sum(GAP[g]) / 2

def hs_wires(name, y, segs, color, back=False, lw=3.5, dash=False):
    out = []
    for g in segs:
        x1, x2 = GAP[g]
        if back: x1, x2 = x2, x1
        out.append(wire(f"{name} {g}", x1, y, x2, y, color, lw, arrow=True, dash=dash))
    return out

def sig(name, g, row, text, color):
    y = {"req": REQ_Y - 30, "gnt": GNT_Y + 4, "rv": RY - 30}[row]
    return box(name, gcx(g) - 34, y, 68, 24, fill="FFFFFF", line=color, lw=1.2,
               shape=MSO_SHAPE.ROUNDED_RECTANGLE, lines=[(text, 12, color, True)], margin=0)

# static blocks
box("HS mgr", 30, 140, 150, 240, fill="EDE7F6", line=PURPLE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Manager", 21, DARK, True), ("core, debug, …", 14, GREY)])
box("HS sub", 1080, 140, 170, 240, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Subordinate", 21, DARK, True), ("memory, peripheral, …", 14, GREY)])
box("HS xbar", 470, 110, 320, 300, fill="F4F8FB", line=BLUE, lw=2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Crossbar", 21, BLUE, True)], anchor=MSO_ANCHOR.TOP, margin=8)
for nm, x in (("L", 240), ("R", 860)):
    box(f"HS cut {nm}", x, 140, 160, 240, fill="FFFFFF", line=TEAL, lw=1.5,
        lines=[("cut", 15, TEAL, True)], anchor=MSO_ANCHOR.TOP, margin=4)
# isolation look of the cuts: created before the cells so it sits behind them
iso_frames = [box(f"HS cut {nm} iso", x, 140, 160, 240, fill=LIGHT, line=TEAL, lw=3,
                  lines=[("cut (scan)", 15, TEAL, True)], anchor=MSO_ANCHOR.TOP, margin=4)
              for nm, x in (("L", 240), ("R", 860))]

def cell(name, x, y, head, body, fill="FFFFFF", line=GREY, size=14):
    return box(name, x + 12, y - 30, 136, 60, fill=fill, line=line, lw=1.2,
               lines=[(head, 12, GREY, True), (body, size, DARK, False, MONO)], margin=2)
for nm, x in (("L", 240), ("R", 860)):
    cell(f"HS {nm} A", x, AY, "A cell", "valid | payload")
    cell(f"HS {nm} R", x, RY, "R cell", "valid | payload")

# thin static wires for the three signals
for g in GAP:
    x1, x2 = GAP[g]
    for y in (REQ_Y, GNT_Y, RY):
        wire(f"HS base {g} {y}", x1, y, x2, y, "CFCFCF", 1.2, arrow=False)

box("HS fifo", 486, 362, 140, 34, fill="FFFFFF", line=GREY, lines=[("ID FIFO: empty", 13, DARK)], margin=0)
box("HS cnt", 640, 362, 134, 34, fill="FFFFFF", line=GREY, lines=[("in flight: 0", 13, DARK)], margin=0)
box("HS clk", 470, 72, 320, 30, fill=PALE, line=GREY, lines=[("cuts + crossbar clock: system clock", 14, DARK, True)], margin=0)

# timeline (appears with isolation)
COLS = ["Shift-DR", "Update-DR", "Step: 1 TCK", "Capture-DR", "Shift-DR"]
colx = lambda i: 240 + i * 204
tl = [box("TL lab tap", 30, 446, 200, 38, lines=[("JTAG TAP state", 15, DARK, True)], align=PP_ALIGN.RIGHT, margin=6),
      box("TL lab v", 30, 492, 200, 34, lines=[("req / rvalid into crossbar", 14, DARK)], align=PP_ALIGN.RIGHT, margin=6),
      box("TL lab g", 30, 534, 200, 34, lines=[("gnt into crossbar", 14, DARK)], align=PP_ALIGN.RIGHT, margin=6)]
for i, c in enumerate(COLS):
    tl.append(box(f"TL tap {i}", colx(i), 446, 196, 38, fill=PALE, lines=[(c, 15, DARK, True)], margin=0))
    tl.append(box(f"TL v {i}", colx(i), 492, 196, 34, fill="FFFFFF", line="DDDDDD", lw=0.75, lines=[("0", 14, GREY)], margin=0))
    tl.append(box(f"TL g {i}", colx(i), 534, 196, 34, fill="FFFFFF", line="DDDDDD", lw=0.75, lines=[("0", 14, GREY)], margin=0))

def hl(name, cols):
    x = colx(cols[0]); w = colx(cols[-1]) + 196 - x
    return box(name, x, 446, w, 38, fill="FFF3E0", line=AMBER, lw=2.5,
               lines=[("  ·  ".join(COLS[i] for i in cols), 15, AMBER, True)], margin=0)
def wave(name, row, i, text, color):
    y = 492 if row == "v" else 534
    return box(name, colx(i), y, 196, 34, fill=color, lines=[(text, 14, "FFFFFF", True)], margin=0)

caption("HS cap 0", "One transfer through the isolated crossbar, step by step.\n"
                    "Click to start in normal mode.")
clicks = []
def click():
    clicks.append([]); return clicks[-1]

# 1: normal mode
c = click()
n1 = (hs_wires("HS n req", REQ_Y, ["L0", "L1", "X", "R1", "R0"], PURPLE)
      + hs_wires("HS n gnt", GNT_Y, ["L0", "L1", "X", "R1", "R0"], PURPLE, back=True)
      + hs_wires("HS n rv", RY, ["L0", "L1", "X", "R1", "R0"], PURPLE, back=True)
      + [sig("HS n t req", "L0", "req", "req", PURPLE), sig("HS n t gnt", "L0", "gnt", "gnt", PURPLE),
         sig("HS n t rv", "L0", "rv", "rvalid", PURPLE), sig("HS n t req2", "R0", "req", "req", PURPLE),
         sig("HS n t gnt2", "R0", "gnt", "gnt", PURPLE), sig("HS n t rv2", "R0", "rv", "rvalid", PURPLE)])
for s in n1: ev(c, 0, s)
ev(c, 0, caption("HS cap 1", "Normal mode: each cut is a small pipeline register. It does its own req / gnt handshake\n"
                              "with the side before it and the side after it; responses (rvalid) flow back."))

# 2: enter isolation
c = click()
for s in n1: ev(c, 0, s, "out")
for s in iso_frames: ev(c, 0, s)
clk_t = box("HS clk tck", 470, 72, 320, 30, fill="FFF3E0", line=AMBER, lw=2,
            lines=[("cuts + crossbar clock: TCK (JTAG)", 14, AMBER, True)], margin=0)
ev(c, 0, clk_t)
iso_tags = [sig("HS i gnt", "L0", "gnt", "gnt = 0", RED), sig("HS i rv", "L0", "rv", "rvalid = 0", RED),
            sig("HS i req", "R0", "req", "req = 0", RED),
            box("HS i mgr", 30, 388, 150, 26, fill="FFFFFF", line=RED, lw=1.2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                lines=[("waits, req held", 13, RED, True)], margin=0),
            box("HS i sub", 1080, 388, 170, 26, fill="FFFFFF", line=GREY, lw=1.2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                lines=[("idle, never sees req", 13, GREY, True)], margin=0)]
for s in iso_tags: ev(c, 300, s)
for k, s in enumerate(tl): ev(c, 400, s)
ev(c, 0, caption("HS cap 2", "Isolation: cuts and crossbar move to the JTAG clock. Toward the real manager gnt and rvalid\n"
                              "are held at 0, toward the real subordinate req is held at 0. The manager simply waits."))

# 3: shift a request into the manager-side A cell
c = click()
h0 = hl("HS hl 0", [0])
ev(c, 0, h0)
la = cell("HS L A load", 240, AY, "A cell (loaded)", "  1   | request", fill="FFF3E0", line=AMBER, size=13)
ev(c, 300, la)
ev(c, 0, caption("HS cap 3", "Shift-DR: a request is loaded into the manager-side A cell: one valid bit\n"
                              "(it becomes req) plus the payload. Nothing is driven yet."))

# 4: update + one step cycle: req and gnt meet in the crossbar
c = click()
ev(c, 0, h0, "out")
h12 = hl("HS hl 12", [1, 2])
ev(c, 0, h12)
s4 = (hs_wires("HS s req", REQ_Y, ["L1", "X", "R1"], AMBER)
      + hs_wires("HS s gnt", GNT_Y, ["L1", "X", "R1"], GREEN, back=True))
for k, s in enumerate(s4): ev(c, 300 + (k % 3) * 200 + (600 if k >= 3 else 0), s)
s4t = [sig("HS s t req1", "L1", "req", "req = 1", AMBER), sig("HS s t req2", "R1", "req", "req = 1", AMBER),
       sig("HS s t gnt2", "R1", "gnt", "gnt = 1", GREEN), sig("HS s t gnt1", "L1", "gnt", "gnt = 1", GREEN)]
for k, s in enumerate(s4t): ev(c, 300 + k * 300, s)
w4 = [wave("HS w v1", "v", 2, "1  (req)", AMBER), wave("HS w g1", "g", 2, "1", GREEN)]
for s in w4: ev(c, 300, s)
fifo1 = box("HS fifo 1", 486, 362, 140, 34, fill="FFF3E0", line=AMBER, lw=2, lines=[("ID FIFO: manager", 13, DARK, True)], margin=0)
cnt1 = box("HS cnt 1", 640, 362, 134, 34, fill="FFF3E0", line=AMBER, lw=2, lines=[("in flight: 1", 13, DARK, True)], margin=0)
ev(c, 1500, fifo1); ev(c, 1500, cnt1)
ev(c, 0, caption("HS cap 4", "Update-DR, then exactly one TCK cycle (the step): the cell drives req, and the subordinate-side\n"
                              "cut grants every request in that cycle. req and gnt meet: the crossbar records one transfer."))

# 5: step ends, capture what arrived
c = click()
for s in [h12, la] + s4 + s4t + w4: ev(c, 0, s, "out")
h34 = hl("HS hl 34", [3, 4])
ev(c, 0, h34)
ev(c, 0, sig("HS c t req", "L1", "req", "req = 0", GREY))
ra = cell("HS R A got", 860, AY, "A cell (captured)", "  1   | request", fill="E8F5E9", line=GREEN, size=13)
ev(c, 400, ra)
ev(c, 0, caption("HS cap 5", "Next cycle req drops. It was granted in the same cycle, so no request is withdrawn ungranted\n"
                              "and the transfer happens once. Capture-DR stores what arrived; the next shift reads it out."))

# 6: response step
c = click()
for s in [h34, ra, fifo1, cnt1] + [x for x in slide.shapes if x.name == "HS c t req"]: ev(c, 0, s, "out")
h12b = hl("HS hl 12b", [0, 1, 2])
ev(c, 0, h12b)
rr = cell("HS R R load", 860, RY, "R cell (loaded)", "  1   | response", fill="FFF3E0", line=AMBER, size=13)
ev(c, 0, rr)
s6 = hs_wires("HS r rv", RY, ["R1", "X", "L1"], AMBER, back=True)
for k, s in enumerate(s6): ev(c, 500 + k * 250, s)
s6t = [sig("HS r t1", "R1", "rv", "rvalid = 1", AMBER), sig("HS r t2", "L1", "rv", "rvalid = 1", AMBER)]
ev(c, 500, s6t[0]); ev(c, 1000, s6t[1])
w6 = [wave("HS w v2", "v", 2, "1  (rvalid)", AMBER), wave("HS w g2", "g", 2, "1  (unused)", GREY)]
for s in w6: ev(c, 500, s)
fifo0 = box("HS fifo 0", 486, 362, 140, 34, fill="E8F5E9", line=GREEN, lw=2, lines=[("ID FIFO: empty", 13, DARK, True)], margin=0)
cnt0 = box("HS cnt 0", 640, 362, 134, 34, fill="E8F5E9", line=GREEN, lw=2, lines=[("in flight: 0", 13, DARK, True)], margin=0)
ev(c, 1200, fifo0); ev(c, 1200, cnt0)
lr = cell("HS L R got", 240, RY, "R cell (captured)", "  1   | response", fill="E8F5E9", line=GREEN, size=13)
ev(c, 1300, lr)
ev(c, 0, caption("HS cap 6", "A second step sends the response from the subordinate-side R cell. The crossbar looks up who\n"
                              "asked and returns it only to that manager's cut, where it is captured. Nothing is left in flight."))

# 7: why exactly one cycle
c = click()
for s in [h12b] + s6 + s6t + w6: ev(c, 0, s, "out")
why = box("HS why", 240, 446, 1012, 122, fill="FFFFFF", line=RED, lw=2.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
          lines=[("Why exactly one cycle?", 18, RED, True),
                 ("A scan takes as many TCK cycles as the chain is long. If req and gnt stayed high for all of them,", 15, DARK),
                 ("the crossbar would accept the same request on every cycle. One step = one transaction.", 15, DARK)],
          margin=10)
ev(c, 0, why)
ev(c, 0, caption("HS cap 7", "The real manager and subordinate never take part: every handshake happens between\n"
                              "two scan cells, inside the isolated crossbar."))
attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    f"{len(clicks)} clicks. Each cut register's scan cell holds the payload plus one valid bit (req on the A channel, "
    "rvalid on the R channel). Update-DR starts a step: for exactly one TCK cycle the cells drive their valid bit "
    "into the crossbar, and the subordinate-side cuts drive gnt = 1. The crossbar runs on the same TCK, so its "
    "arbiter, ID FIFO and in-flight counter see one handshake per step. The cells sample their inputs in the step "
    "cycle; Capture-DR keeps that sample. Toward the real managers gnt and rvalid stay 0, toward the real "
    "subordinates req stays 0, and the cut full flags are cleared on entry, so nothing is replayed on exit. "
    "gnt itself is not captured: it is proven by the response, which the crossbar only returns for a granted request.")

# Sub-access area (Yosys): obi_jtag_top block with JtagSubAccess = 1 (croc_dft_sub) minus = 0 (croc_dft_isol)
SUB_UM2 = 154227.2 - 141118.6
SUB_KGE = SUB_UM2 / 5.65 / 1e3

# =====================================================================================
# Slide: sub access, JTAG reads and writes a subordinate like a manager does
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("Sub access: JTAG reads and writes a subordinate")

BND = 690                                  # clock boundary x
AY2, RY2 = 220, 380                        # A cell / R cell rows (centres)
box("SA tck zone", 30, 84, BND - 40, 30, fill=LIGHT, lines=[("JTAG clock (TCK)", 15, TEAL, True)], margin=0)
box("SA sys zone", BND + 10, 84, 1250 - BND - 10, 30, fill="E3F2FD", lines=[("subordinate's own clock", 15, BLUE, True)], margin=0)
wire("SA boundary", BND, 84, BND, 560, GREY, 2, arrow=False, dash=True)
box("SA sync lbl", BND - 80, 530, 160, 30, fill="FFFFFF", lines=[("synchronisers", 13, GREY, True)], margin=0)

box("SA xbar", 40, 150, 200, 300, fill=PALE, line=GREY, lw=1.5, dash=True, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Crossbar", 20, GREY, True), ("isolated,", 14, GREY), ("not needed here", 14, GREY)])
box("SA cut", 300, 150, 300, 300, fill="FFFFFF", line=TEAL, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("subordinate-side cut", 15, TEAL, True)], anchor=MSO_ANCHOR.TOP, margin=6)
wire("SA xbar link A", 240, AY2, 320, AY2, "CFCFCF", 1.5)
wire("SA xbar link R", 320, RY2, 240, RY2, "CFCFCF", 1.5)

def sa_cell(name, y, head, body, fill="FFFFFF", line=GREY, color=DARK, lw=1.2):
    return box(name, 320, y - 40, 260, 80, fill=fill, line=line, lw=lw,
               lines=[(head, 13, GREY, True), (body, 16, color, True)], margin=3)
sa_cell("SA A cell", AY2, "A cell (request)", "valid = 0")
sa_cell("SA R cell", RY2, "R cell (reply)", "valid = 0")

box("SA eng", 760, 150, 200, 300, fill="FFFFFF", line=PURPLE, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("access engine", 17, PURPLE, True), ("one per cut", 13, GREY)], anchor=MSO_ANCHOR.TOP, margin=8)
box("SA mem", 1040, 150, 200, 300, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Subordinate", 20, DARK, True), ("e.g. a memory", 14, GREY)])
for nm, y in (("req", 210), ("gnt", 270), ("rv", 360)):
    wire(f"SA base {nm}", 960 if nm == "req" else 1040, y, 1040 if nm == "req" else 960, y, "CFCFCF", 1.2, arrow=False)
wire("SA base fire", 580, AY2, 760, AY2, "CFCFCF", 1.2, arrow=False)
wire("SA base done", 760, RY2, 580, RY2, "CFCFCF", 1.2, arrow=False)

# JTAG chain in / out
box("SA tdi", 300, 470, 90, 36, fill=DARK, lines=[("TDI", 15, "FFFFFF", True)], margin=0)
box("SA tdo", 510, 470, 90, 36, fill=DARK, lines=[("TDO", 15, "FFFFFF", True)], margin=0)

# JTAG step strip
STEPS = ["Shift-DR", "Update-DR", "wait a few TCK", "Capture-DR", "Shift-DR"]
SW = 150
def step_box(k, on):
    x = 40 + k * (SW + 8)
    return box(f"SA step {k} {'on' if on else 'off'}", x, 575, SW, 36, fill=AMBER if on else PALE,
               line=None if on else GREY, lw=1, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[(STEPS[k], 14, "FFFFFF" if on else GREY, True)], margin=0)
for k in range(len(STEPS)): step_box(k, False)
step_on = [step_box(k, True) for k in range(len(STEPS))]

caption("SA cap 0", "A second JTAG instruction, sub access: isolation as before, and each subordinate-side cut\n"
                    "can also run a real transfer to its subordinate, the same way a core would.")
clicks = []
def click():
    clicks.append([]); return clicks[-1]
cur = [None]
def step(c, k, t=0):
    if cur[0] is not None: ev(c, t, step_on[cur[0]], "out")
    if k is not None: ev(c, t, step_on[k])
    cur[0] = k

# 1: Shift-DR, request straight into the cut's A cell
c = click()
step(c, 0)
o1 = [wire("SA shift in", 345, 470, 345, AY2 + 40, AMBER, 4),
      sa_cell("SA A full", AY2, "A cell (request)", "valid = 1 · write", "FFF3E0", AMBER, DARK, 2.5)]
ev(c, 0, o1[0]); ev(c, 400, o1[1])
ev(c, 0, caption("SA cap 1", "Shift-DR: a write request (valid = 1, address, data) is shifted straight into the cut\n"
                             "in front of the subordinate. The crossbar is skipped."))

# 2: Update-DR, the engine is triggered across the clock boundary and issues req
c = click()
step(c, 1)
ev(c, 0, o1[0], "out")
fire = wire("SA fire", 580, AY2, 760, AY2, AMBER, 4); ev(c, 0, fire)
eng_req = box("SA eng req", 776, 206, 168, 40, fill="FFF3E0", line=AMBER, lines=[("send request", 15, DARK, True)], margin=0)
ev(c, 400, eng_req)
req = wire("SA req", 960, 210, 1040, 210, AMBER, 4); ev(c, 700, req)
lreq = box("SA req lbl", 962, 180, 76, 24, fill="FFFFFF", lines=[("req", 13, AMBER, True)], margin=0); ev(c, 700, lreq)
ev(c, 0, caption("SA cap 2", "Update-DR: the request crosses into the subordinate's clock. The engine raises req\n"
                             "and holds the address and data steady, exactly like a manager."))

# 3: handshake on the system clock: gnt, then rvalid + reply
c = click()
step(c, 2)
gnt = wire("SA gnt", 1040, 270, 960, 270, GREEN, 4); ev(c, 0, gnt)
lgnt = box("SA gnt lbl", 962, 240, 76, 24, fill="FFFFFF", lines=[("gnt", 13, GREEN, True)], margin=0); ev(c, 0, lgnt)
memw = box("SA mem w", 1056, 330, 168, 50, fill="E8F5E9", line=GREEN, lines=[("written ✓", 16, GREEN, True)], margin=0)
ev(c, 500, memw)
rv = wire("SA rv", 1040, 360, 960, 360, GREEN, 4); ev(c, 1000, rv)
lrv = box("SA rv lbl", 958, 330, 84, 24, fill="FFFFFF", lines=[("rvalid", 13, GREEN, True)], margin=0); ev(c, 1000, lrv)
eng_st = box("SA eng st", 776, 340, 168, 40, fill="E8F5E9", line=GREEN, lines=[("reply stored", 15, DARK, True)], margin=0)
ev(c, 1400, eng_st)
ev(c, 0, caption("SA cap 3", "The subordinate grants, does the write and answers with rvalid and a reply, all on its own\n"
                             "clock. JTAG just waits a few TCK cycles meanwhile."))

# 4: Capture-DR: done comes back, R cell records the reply
c = click()
step(c, 3)
for s in (fire, req, lreq, gnt, lgnt, rv, lrv): ev(c, 0, s, "out")
done = wire("SA done", 760, RY2, 580, RY2, GREEN, 4); ev(c, 0, done)
rfull = sa_cell("SA R full", RY2, "R cell (reply)", "valid = 1 · OK · same ID", "E8F5E9", GREEN, DARK, 2.5)
ev(c, 400, rfull)
ev(c, 0, caption("SA cap 4", "Capture-DR: the reply crosses back to TCK and the cut's R cell records it\n"
                             "(valid, error flag, ID and, for a read, the data)."))

# 5: Shift-DR: reply out at TDO
c = click()
step(c, 4)
ev(c, 0, done, "out")
sout = wire("SA shift out", 555, RY2 + 40, 555, 470, GREEN, 4); ev(c, 0, sout)
tdo1 = box("SA tdo w", 620, 466, 200, 44, fill="E8F5E9", line=GREEN, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
           lines=[("write accepted ✓", 15, GREEN, True)], margin=0)
ev(c, 400, tdo1)
ev(c, 0, caption("SA cap 5", "Shift-DR: the reply comes out at TDO while the next request goes in.\n"
                             "One transfer = two scans with a short wait in between."))

# 6: read back the same address
c = click()
step(c, None)
for s in (sout, tdo1, eng_req, eng_st, rfull) + tuple(o1[1:]): ev(c, 0, s, "out")
rd = sa_cell("SA A read", AY2, "A cell (request)", "valid = 1 · read", "FFF3E0", AMBER, DARK, 2.5); ev(c, 300, rd)
rrd = sa_cell("SA R read", RY2, "R cell (reply)", "valid = 1 · data", "E8F5E9", GREEN, DARK, 2.5); ev(c, 900, rrd)
tdo2 = box("SA tdo r", 620, 466, 200, 44, fill="E8F5E9", line=GREEN, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
           lines=[("read = written data ✓", 15, GREEN, True)], margin=0)
ev(c, 1300, tdo2)
ev(c, 0, caption("SA cap 6", "The same two scans with a read return the data just written. A request to the error\n"
                             "subordinate returns a bus error: JTAG sees exactly what a core would see."))

# 7: verified + cost
c = click()
ev(c, 0, chip("SA verified", 1010, 26, "Verified in simulation", GREEN))
ev(c, 0, box("SA cost", 860, 470, 380, 90, fill="FFFFFF", line=PURPLE, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
             lines=[(f"+{SUB_KGE:.1f} kGE", 26, PURPLE, True), ("on top of isolation: engines + synchronisers", 13, GREY)],
             margin=4))
ev(c, 0, caption("SA cap 7", "Memories and peripherals can be read and written over JTAG even if the core or the\n"
                             f"debug path is broken. Cost: +{SUB_KGE:.1f} kGE on top of isolation."))
attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    f"{len(clicks)} clicks. Instruction XcnctSubAccess on the obi_jtag TAP (JtagSubAccess = 1 in obi_xbar): the "
    "same isolation and scan chain as XcnctIsolation, plus one access engine (obi_cut_sub_access) per "
    "subordinate-side cut. A Shift-DR + Update-DR with the A cell valid bit set toggles a TCK flop; a 2-flop "
    "synchroniser carries the toggle into the subordinate's clock, where the engine raises req with the A cell "
    "payload (stable until the next Update), holds it until gnt, waits for rvalid and stores the reply. done is "
    "synchronised back to TCK; the next Capture-DR loads the reply into the cut's R cell and Shift-DR reads it out. "
    "The testbench waits 20 TCK in Run-Test/Idle between the two scans. tb_croc_chip +obi_jtag_test: write "
    "0x5AB1C0DE to SRAM bank 0, read it back, the error subordinate answers err = 1, each transaction reaches its "
    "subordinate exactly once, and after leaving isolation the value is read over the normal debug path "
    f"(5 extra checks, 23 in total). Area: +{SUB_KGE:.2f} kGE vs isolation only "
    f"({SUB_UM2:,.0f} um2: ~215 flops, ~15 synchronisers, reply muxes).")

# =====================================================================================
# Slide 4: verification and cost
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("Verification and cost")
box("Verif head", 40, 80, 700, 34, lines=[("tb_croc_chip +obi_jtag_test: 23 of 23 checks pass", 22, TEAL, True)],
    align=PP_ALIGN.LEFT, margin=0)
CHECKS = [
    ("Scan chain integrity", "a pattern comes out after exactly the chain length"),
    ("Requests (5)", "from every manager, each reaches only the decoded subordinate"),
    ("", "including an unmapped address → error subordinate"),
    ("Address map from JTAG (2)", "two ranges swapped: requests follow the new map"),
    ("Default index from JTAG", "unmapped address redirected away from the error subordinate"),
    ("Responses (8)", "rvalid + rdata return only to the requesting manager, rid = aid"),
    ("No leaks", "never gnt / rvalid to a manager or req to a subordinate"),
    ("Sub access (5)", "write + read-back of a memory, error subordinate, each exactly once"),
    ("After isolation (extra)", "sub-access write seen over debug, program runs"),
]
vclicks = [[], []]
for k, (a, b) in enumerate(CHECKS):
    y = 120 + k * 38
    ev(vclicks[0], 0, box(f"Check {k} a", 40, y, 260, 34, fill=PALE if k % 2 == 0 else "FFFFFF",
                          lines=[(("✓  " + a) if a else "", 16, GREEN if a else DARK, True)], align=PP_ALIGN.LEFT, margin=10))
    ev(vclicks[0], 0, box(f"Check {k} b", 300, y, 440, 34, fill=PALE if k % 2 == 0 else "FFFFFF",
                          lines=[(b, 15, DARK)], align=PP_ALIGN.LEFT, margin=10))
ev(vclicks[0], 0, box("Not tested", 40, 466, 700, 46, lines=[
    ("Not covered yet: snapshot of live traffic (card 2); transfers in flight on entry are dropped; "
     "a subordinate's own gnt is not observed (the cuts grant during every step).", 15, RED)],
    align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=0))
box("Cmd", 40, 524, 700, 70, fill=PALE, lines=[
    ("cd vsim", 15, DARK, False, MONO),
    ("./run_vsim.sh --tb tb_croc_chip --plusarg +obi_jtag_test \\", 15, DARK, False, MONO),
    ("              --run ../sw/bin/helloworld.hex", 15, DARK, False, MONO)],
    align=PP_ALIGN.LEFT, margin=12)
STATS = [("1 chain", "address map + all 9 cuts", "payload + 1 valid bit per cut register"),
         ("2 scans", "per step", "one to drive, one to capture; a transfer is 2 steps"),
         ("+10.7 kGE", "isolation + sub access vs the plain cuts", "isolation 8.4 (scan muxes, JTAG control, flops) + sub access 2.3"),
         ("+39 %", "of the original interconnect", "crossbar + cuts were 27.6 kGE; +7.2 % of the chip")]
for k, (big, small, note) in enumerate(STATS):
    y = 90 + k * 128
    ev(vclicks[1], 0, box(f"Stat {k}", 790, y, 450, 116, fill="FFFFFF", line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                          lines=[(big, 30, PURPLE if k >= 2 else TEAL, True), (small, 17, DARK, True), (note, 15, GREY)],
                          margin=8))
caption("Caption verif", "The crossbar can be tested, re-mapped, its subordinates read and written, all over the JTAG port.\n"
                         "Cost: +10.7 kGE over the original cuts: 8.4 for isolation, 2.3 for sub access.")
attach_timing(slide, vclicks)
slide.notes_slide.notes_text_frame.text = (
    "2 clicks: checks, then cost. 23 checks = 1 chain + 8 request routes + 8 responses + 1 leak monitor + 5 sub access. "
    "Area (Yosys, IHP 130 nm, 1 GE = NAND2X1 = 5.65 um2): obi_jtag_top block incl. JTAG wrapper and TAP "
    "141,119 um2 (25.0 kGE); NORMAL obi_xbar_multicut 93,812 um2 (16.6 kGE); difference 47,306 um2 = 8.4 kGE for isolation. "
    "Of that: extra flops ~1.5 kGE (mostly the 288-bit address-map shadow register), scan muxes ~4.6 kGE, "
    "JTAG control (TAP, IR, 288-bit address-map shift register, clock mux) 2.3 kGE. Dropping the JTAG-loadable "
    "address map would save roughly 2.5-3 kGE. Sub access (JtagSubAccess = 1): block 154,227 um2, +13,109 um2 = "
    "+2.3 kGE more (access engines, synchronisers, reply muxes); total +10.7 kGE.")

# =====================================================================================
# Slides 4-5: area plots (doc/area_*.png from area_plot.py)
# =====================================================================================
AREA = [
    ("area_composition.png", "Area: original Croc vs our design",
     "+17.9 kGE (+12.1 %). Each BIST controller is counted in the memory it tests; the core and\n"
     "peripherals are unchanged. Standard cells + SRAM macros, IO pads excluded. 1 GE = NAND2X1.",
     "Standard cells + SRAM macros, IO pads excluded. 1 GE = NAND2X1 = 5.65 um2. Each March BIST controller is "
     "counted in the memory it tests. Our design: the VAD 512x32 SRAM macros are black boxes in its Yosys run; "
     "their liberty area (2 x 79,720 um2, from the NORMAL technology library) is added. Original Croc: "
     "NORMAL/yosys/reports/croc_area.rpt; our design: yosys/reports/croc_dft_sub_area.rpt (JtagSubAccess = 1)."),
    ("area_overhead.png", "Area overhead per block",
     "Each memory pays about 1 kGE for its March BIST (6–7 % of that memory).\n"
     "Crossbar isolation + sub access is the largest single cost: +10.7 kGE, 39 % of the original interconnect.",
     "Main SRAM banks: BIST controller 0.93 kGE + 0.09 kGE interface logic in the bank wrapper. VAD frame SRAMs: "
     "BIST controller only, relative to the 512x32 macro. OBI isolation: scan cuts + JTAG control minus the plain "
     "cuts the original already had (60,415 um2); relative to the original crossbar + cuts (27.6 kGE). Of the "
     "10.7 kGE: isolation 8.4 (scan muxes ~4.6, JTAG control ~2.3, extra flops ~1.5, mostly the 288-bit address-map "
     "shadow register) and sub access 2.3 (access engines, synchronisers, reply muxes). VAD +1.9 kGE: SRAM debug access and observability registers in the VAD wrapper (the BIST uses the macro's own BIST port, so hooking it up costs no extra muxes). "
     "Core + peripherals: SoC control registers for MBIST (+0.3 kGE) and synthesis noise. Chip = Original Croc, "
     "148.8 kGE, standard cells + SRAM macros, IO pads excluded. 1 GE = NAND2X1 = 5.65 um2."),
]
from PIL import Image
for img, head, cap, notes in AREA:
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    title(head)
    path = f"{IMG_DIR}/{img}"
    w, h = Image.open(path).size
    bw, bh = 1200, 540                       # free area between title and caption
    if w / h > bw / bh: dw, dh = bw, bw * h / w
    else:               dw, dh = bh * w / h, bh
    pic = slide.shapes.add_picture(path, px(40 + (bw - dw) / 2), px(78 + (bh - dh) / 2), px(dw), px(dh))
    pic.name = head
    caption(f"Caption {img}", cap)
    slide.notes_slide.notes_text_frame.text = notes

# =====================================================================================
# Slide: proposal, memory bank repair with the same remap (not implemented)
# =====================================================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
title("Proposal: memory bank repair")
chip("Repair tag", 1010, 26, "Proposal · not implemented", AMBER)

box("RP core", 40, 230, 170, 120, fill="EDE7F6", line=PURPLE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Core", 22, DARK, True), ("runs the program", 14, GREY)])
box("RP xbar", 290, 130, 380, 330, fill="F4F8FB", line=BLUE, lw=2, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Crossbar decode", 21, BLUE, True)], anchor=MSO_ANCHOR.TOP, margin=10)
wire("RP core link", 210, 290, 290, 290, GREY, 2)
RLO, RHI = 215, 335                       # rows of the decode table
def drow(name, y, left, right, fill="FFFFFF", line=GREY, color=DARK):
    return box(name, 310, y, 340, 56, fill=fill, line=line, lw=1.5,
               lines=[(left, 15, GREY, True), (right, 17, color, True)], margin=4)
drow("RP row lo", RLO, "lower half of the RAM range", "→ bank A")
drow("RP row hi", RHI, "upper half of the RAM range", "→ bank B")

BA, BB, BE = 150, 270, 400
box("RP bank A", 780, BA, 200, 90, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Bank A", 21, DARK, True), ("memory", 14, GREY)])
box("RP bank B", 780, BB, 200, 90, fill="E3F2FD", line=BLUE, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Bank B", 21, DARK, True), ("memory", 14, GREY)])
box("RP err", 780, BE, 200, 70, fill=PALE, line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Error subordinate", 17, DARK, True), ("answers with a bus error", 13, GREY)])
box("RP bist", 1020, 150, 220, 210, fill="FFFFFF", line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("March BIST", 19, DARK, True), ("one per bank, run after reset", 14, GREY)],
    anchor=MSO_ANCHOR.TOP, margin=12)
box("RP reg", 290, 490, 380, 56, fill="FFFFFF", line=GREY, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("remap register:   bank A bad = 0   ·   bank B bad = 0", 15, DARK, True)], margin=4)
wire("RP reg link", 480, 490, 480, 460, GREY, 2)

caption("RP cap 0", "If BIST finds a broken memory bank, the same decode mechanism can steer around it.\n"
                    "Click to step through.")
clicks = []
def click():
    clicks.append([]); return clicks[-1]

# 1: normal decode
c = click()
n = [wire("RP n lo", 650, RLO + 28, 780, BA + 45, PURPLE, 3.5), wire("RP n hi", 650, RHI + 28, 780, BB + 45, PURPLE, 3.5)]
for s in n: ev(c, 0, s)
ev(c, 0, caption("RP cap 1", "Today the decode is fixed: the lower half of the RAM range goes to bank A,\n"
                             "the upper half to bank B."))

# 2: BIST finds bank A faulty
c = click()
ev(c, 0, box("RP bist res", 1036, 236, 188, 100, fill="FFFFFF", lines=[
    ("bank A:  FAIL", 17, RED, True, MONO), ("bank B:  pass", 17, GREEN, True, MONO)], align=PP_ALIGN.LEFT, margin=6))
ev(c, 500, box("RP bad A", 780, BA, 200, 90, fill="FFEBEE", line=RED, lw=3, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
               lines=[("Bank A  ✗", 21, RED, True), ("stuck cell found", 14, RED)]))
ev(c, 0, caption("RP cap 2", "After reset, March BIST tests every bank. Here bank A has a stuck cell:\n"
                             "without repair, any program using the RAM would fail."))

# 3: one register bit changes the decode
c = click()
for s in n: ev(c, 0, s, "out")
ev(c, 0, box("RP reg set", 290, 490, 380, 56, fill="FFF3E0", line=AMBER, lw=2.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
             lines=[("remap register:   bank A bad = 1   ·   bank B bad = 0", 15, DARK, True)], margin=4))
ev(c, 500, drow("RP row lo 2", RLO, "lower half of the RAM range", "→ bank B", "E8F5E9", GREEN, GREEN))
ev(c, 500, drow("RP row hi 2", RHI, "upper half of the RAM range", "→ error subordinate", "FFEBEE", RED, RED))
m = [wire("RP m lo", 650, RLO + 28, 780, BB + 45, GREEN, 3.5),
     wire("RP m hi", 650, RHI + 28, 780, BE + 35, RED, 3, dash=True)]
for s in m: ev(c, 1000, s)
ev(c, 0, caption("RP cap 3", "Boot code or the debugger sets one bit. The decode now sends the lower half to the good bank\n"
                             "and the upper half to the error subordinate. Set it before the program is loaded."))

# 4: what software sees
c = click()
ev(c, 0, box("RP sw", 40, 370, 200, 76, fill="E8F5E9", line=GREEN, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
             lines=[("same start address,", 14, GREEN, True), ("half the RAM ✓", 14, GREEN, True)], margin=4))
ev(c, 0, box("RP no alias", 990, 400, 260, 70, fill="FFFFFF", line=RED, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
             lines=[("stray access → bus error,", 14, RED, True), ("never silent corruption", 14, RED, True)], margin=4))
ev(c, 0, caption("RP cap 4", "Software keeps its start address and sees half the RAM. An access to the missing half\n"
                             "returns a bus error instead of silently overwriting good data. Cost: two register bits."))
attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    "Proposal, not implemented. Differences to the isolation map: the remap is active in normal operation, it is "
    "set from a register (soc_ctrl), not over JTAG isolation, and it only changes the target index of the two "
    "memory rules (two control bits: bank A bad, bank B bad). The missing half maps to the error subordinate rather "
    "than aliasing onto the good bank, so a stray access is reported instead of overwriting live data. Sequence: "
    "reset, run March BIST, read the status, set the remap, then load and start a program linked for half the RAM. "
    "Hardware cost is a two-bit register and a few muxes on the index fields, about 0.1 kGE. A finer-grained "
    "alternative uses the failing word addresses that the BIST already logs to replace single words with spare "
    "flip-flops, keeping the full RAM.")

prs.save(sys.argv[1])
print("saved", sys.argv[1])
