# One click-driven slide on the VAD debug / observability / controllability registers (DEMO vs NORMAL),
# same style as isol_pptx.py. Follows the register map in rtl/user_domain/vad_csr_wrapper.sv.
# No addresses or Croc-specific sizes on the slide.
# usage: python vad_obs_pptx.py out.pptx
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

def wire2(name, x1, y1, x2, y2, color, lw=3):
    c = wire(name, x1, y1, x2, y2, color, lw)
    etree.SubElement(c.line._get_or_add_ln(), qn("a:headEnd"), {"type": "triangle", "w": "med", "len": "med"})
    return c

slide = prs.slides.add_slide(prs.slide_layouts[6])
title("VAD: debug, observability and controllability registers")
box("Subtitle", 40, 66, 1200, 34, lines=[(
    "Before: software could only switch the VAD on, set the thresholds and get yes / no back. "
    "Now it can see inside every step and drive it.", 18, GREY)],
    align=PP_ALIGN.LEFT, margin=0)

# ---- datapath (the original VAD), grey = what NORMAL already has
BY, BH = 130, 96
BLK = [("Mic", "Microphone\n(I2S)", 40, 120),
       ("FB", "Frame buffer\n2 SRAM banks, ping-pong", 190, 290),
       ("DSP", "DSP core\nenergy + zero crossings", 510, 230),
       ("DEC", "Decision\nvs thresholds", 770, 190),
       ("WK", "Wake-up\nspeech / no speech", 990, 250)]
G = {}
for key, text, x, w in BLK:
    head, sub = text.split("\n")
    G[key] = (x, w)
    box(f"Block {key}", x, BY, w, BH, fill=PALE, line=DARK, lw=1.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
        lines=[(head, 19, DARK, True), (sub, 14, GREY)])
for (a, _, xa, wa, ), (b, _, xb, _) in zip([(k, t, x, w) for k, t, x, w in BLK][:-1], [(k, t, x, w) for k, t, x, w in BLK][1:]):
    wire(f"Flow {a}-{b}", xa + wa, BY + BH / 2, xb, BY + BH / 2, DARK, 2.5)

BUSY = 528
box("Bus", 40, BUSY, 1200, 48, fill=DARK, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
    lines=[("Software over the bus (register interface)", 19, "FFFFFF", True)])
# NORMAL links: enable + thresholds in, one wake-up bit out
wire("Normal thresholds", 920, BUSY, 920, BY + BH, GREY, 2.5)
box("Normal thr label", 926, 330, 62, 60, lines=[("enable,", 13, GREY), ("thresholds", 13, GREY)], align=PP_ALIGN.LEFT, margin=0)
box("Normal note", 990, BY + BH + 8, 180, 44, lines=[("Before: only this yes / no", 13, GREY), ("came out of the VAD", 13, GREY)],
    align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=0)

# ---- the three added register groups, one per click
CY, CH = 280, 198
def card(c, num, x, w, head, color, rows, tags, tag_size=12):
    shapes = [box(f"Card {num}", x, CY, w, CH, fill="FFFFFF", line=color, lw=2.5, shape=MSO_SHAPE.ROUNDED_RECTANGLE),
              box(f"Card {num} head", x, CY, w, 36, fill=color, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                  lines=[(head, 17, "FFFFFF", True)], margin=0)]
    b = box(f"Card {num} body", x + 12, CY + 44, w - 24, CH - 78, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, margin=0)
    for k, (lab, txt) in enumerate(rows):
        p = b.text_frame.paragraphs[0] if k == 0 else b.text_frame.add_paragraph()
        p.space_after = Pt(3); p.alignment = PP_ALIGN.LEFT
        for t, col, bold in ((lab + ": ", color, True), (txt, DARK, False)):
            r = p.add_run(); r.text = t
            r.font.size, r.font.bold, r.font.name = fs(14), bold, SANS
            r.font.color.rgb = RGBColor.from_string(col)
    shapes.append(b)
    tx = x + 12
    for t, tc in tags:
        tw = 14 + 0.68 * tag_size * len(t)
        shapes.append(box(f"Card {num} tag {t}", tx, CY + CH - 30, tw, 22, fill=tc, shape=MSO_SHAPE.ROUNDED_RECTANGLE,
                          lines=[(t, tag_size, "FFFFFF", True)], margin=0))
        tx += tw + 6
    for s in shapes: ev(c, 0, s)
    return shapes

OBS, CTL, DBG = "1E5A8C", PURPLE, "5D4037"
clicks = [[] for _ in range(4)]

c = clicks[0]   # frame memory access
fx, fw = G["FB"]
card(c, 1, 170, 320, "Frame memory access", TEAL,
     [("Control", "pause the microphone, write your own audio frame and run the core on it."),
      ("Observe", "read back the audio that was really stored.")],
     [("Controllability", CTL), ("Observability", OBS)])
ev(c, 0, wire2("Link FB", fx + fw / 2, BY + BH, fx + fw / 2, CY, TEAL))
ev(c, 0, wire2("Link FB bus", fx + fw / 2, CY + CH, fx + fw / 2, BUSY, TEAL))

c = clicks[1]   # last frame result + EVAL
card(c, 2, 510, 390, "Last frame result + evaluate", PURPLE,
     [("Observe", "see the energy and zero-crossing values the core computed, not just yes / no."),
      ("Control", "write your own values and run only the decision, to test the thresholds without audio.")],
     [("Observability", OBS), ("Controllability", CTL)])
dx, dw = G["DSP"]; ex, ew = G["DEC"]
ev(c, 0, wire("Link DSP", dx + dw / 2, BY + BH, dx + dw / 2, CY, PURPLE, 3))
ev(c, 0, wire("Link DEC", ex + 50, CY, ex + 50, BY + BH, PURPLE, 3))
ev(c, 0, wire2("Link res bus", 705, CY + CH, 705, BUSY, PURPLE))

c = clicks[2]   # status + interrupt
card(c, 3, 988, 252, "Status + interrupt", AMBER,
     [("Speech flag", "held until software clears it, so no detection is missed."),
      ("Buffer", "which bank fills, which is processed, how full the frame is."),
      ("Interrupt", "software switches it on, fires it on demand to test it, and clears it.")],
     [("Observability", OBS), ("Controllability", CTL)], tag_size=10)
wx, ww = G["WK"]
ev(c, 0, wire("Link WK", wx + ww - 40, BY + BH, wx + ww - 40, CY, AMBER, 3))
ev(c, 0, wire2("Link st bus", wx + ww / 2, CY + CH, wx + ww / 2, BUSY, AMBER))

c = clicks[3]   # why registers and not the scan chain
ev(c, 0, caption("Result",
    "Same chip, only these registers cut off vs. reachable: test coverage from the pins 17 % \u2192 28 %, DSP core 5 % \u2192 24 %.\n"
    "One bus access (2 cycles) while the chip runs, instead of stopping it and shifting every flip-flop (~300 shifts)."))

attach_timing(slide, clicks)
slide.notes_slide.notes_text_frame.text = (
    "Start: the original VAD. Software writes enable and the two thresholds and only gets the wake-up bit back, "
    "so a wrong decision cannot be traced to the microphone data, the energy / ZCR computation or the thresholds. "
    "Click 1: frame memory access. Software takes the frame SRAMs (audio is dropped meanwhile), writes or reads "
    "samples with auto-increment and kicks the core on a chosen bank: a known stimulus in, the stored audio out. "
    "Click 2: the core keeps the energy and zero-crossing count of the last frame in registers; software can read "
    "them, or write values and run only the comparator (EVAL), which sets the speech flag like a real frame. "
    "Click 3: the core's speech output is a one-cycle pulse per frame; the sticky flag holds it until software writes 1 "
    "to clear it. Status also shows which ping-pong bank the microphone fills and which the core reads, the next sample "
    "slot of the writer (does audio arrive, how full is the frame) and a read-pending bit for SRAM debug reads. "
    "Interrupt: before, the line was the raw one-cycle decision pulse, which software could not mask, acknowledge or catch while busy. Now it is the sticky flag AND an enable bit (held until cleared), software can fire it on demand with the IRQ_TRIG command (no audio, works outside debug mode) and read the line back in the status register, so the whole path flag, enable, line, CPU can be tested. "
    "Click 4, first line: TetraMAX pins-only ATPG on the same DEMO netlist with the same limits, once as built and once with OBI address bit 6 tied to 0 so these registers are unreachable: 28.3 % vs 17.0 % fault coverage, DSP core 23.5 % vs 5.0 %. Of the 2858 faults only detected with the registers, 1433 were not observed and 792 not controlled without them. Second line: measured in gate-level simulation on the synthesized netlists: an OBI "
    "write of a threshold takes 2 cycles; the same through the scan chain needs one full recirculating pass "
    "(299 flops in NORMAL, 560 in DEMO) with the clock in test mode, and the SRAM contents are not reachable by scan.")

prs.save(sys.argv[1])
print("saved", sys.argv[1])
