# Adds click-by-click entrance animations and a fade transition to the deck built by build.js.
# anim.json: {slide number: [click, ...]}. A click is either
#   - a list of objectNames (a card: its background, circle and tag zoom in, the text fades in after), or
#   - {"seq": [step, ...]}, step = {"n": [names], "fx": "fade"|"wipe"|"zoom", "dir": "l"|"r"|"u"|"d",
#                                 "at": start in ms after the click, "dur": ms}
# Wipe "dir" is where the wipe starts: "l" = from the left (for a left-to-right arrow), "u" = from the top.
import json, re, sys, zipfile

src, dst = sys.argv[1], sys.argv[2]
anim = json.load(open("anim.json"))
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)

CARD_FIRST = ("_bg", "_c", "_n", "_tag")
WIPE = {"l": (8, "wipe(left)"), "r": (2, "wipe(right)"), "u": (1, "wipe(up)"), "d": (4, "wipe(down)")}


def as_steps(click):
    if isinstance(click, dict):
        return click["seq"]
    first = [n for n in click if n.endswith(CARD_FIRST)]
    rest = [n for n in click if n not in first]
    steps = [{"n": first, "fx": "zoom", "at": 0, "dur": 350}] if first else []
    if rest:
        steps.append({"n": rest, "fx": "fade", "at": 200 if first else 0, "dur": 400})
    return steps


def timing(clicks):
    ctr = [2]

    def nid():
        ctr[0] += 1
        return ctr[0]

    def effect(spid, step, node):
        fx, dur = step.get("fx", "fade"), step.get("dur", 400)
        tgt = f'<p:tgtEl><p:spTgt spid="{spid}"/></p:tgtEl>'
        eid, sid = nid(), nid()
        vis = (f'<p:set><p:cBhvr><p:cTn id="{sid}" dur="1" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst></p:cTn>'
               f'{tgt}<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr>'
               f'<p:to><p:strVal val="visible"/></p:to></p:set>')
        if fx == "wipe":
            sub, flt = WIPE[step.get("dir", "l")]
            preset, body = 22, vis + (f'<p:animEffect transition="in" filter="{flt}"><p:cBhvr><p:cTn id="{nid()}" dur="{dur}"/>'
                                     f'{tgt}</p:cBhvr></p:animEffect>')
        elif fx == "zoom":
            sub, preset = 16, 53
            grow = "".join(
                f'<p:anim calcmode="lin" valueType="num"><p:cBhvr><p:cTn id="{nid()}" dur="{dur}" fill="hold"/>{tgt}'
                f'<p:attrNameLst><p:attrName>ppt_{a}</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst>'
                f'<p:tav tm="0"><p:val><p:strVal val="0"/></p:val></p:tav>'
                f'<p:tav tm="100000"><p:val><p:strVal val="#ppt_{a}"/></p:val></p:tav></p:tavLst></p:anim>'
                for a in ("w", "h"))
            body = vis + grow + (f'<p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="{nid()}" dur="{dur}"/>'
                                 f'{tgt}</p:cBhvr></p:animEffect>')
        else:
            sub, preset = 0, 10
            body = vis + (f'<p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="{nid()}" dur="{dur}"/>'
                          f'{tgt}</p:cBhvr></p:animEffect>')
        return (f'<p:par><p:cTn id="{eid}" presetID="{preset}" presetClass="entr" presetSubtype="{sub}" fill="hold" '
                f'grpId="0" nodeType="{node}"><p:stCondLst><p:cond delay="0"/></p:stCondLst>'
                f'<p:childTnLst>{body}</p:childTnLst></p:cTn></p:par>')

    out = []
    for steps in clicks:
        outer = nid()
        pars = []
        for k, step in enumerate(sorted(steps, key=lambda st: st.get("at", 0))):
            pid = nid()
            effs = [effect(spid, step, ("clickEffect" if k == 0 else "afterEffect") if j == 0 else "withEffect")
                    for j, spid in enumerate(step["ids"])]
            pars.append(f'<p:par><p:cTn id="{pid}" fill="hold"><p:stCondLst><p:cond delay="{step.get("at", 0)}"/>'
                        f'</p:stCondLst><p:childTnLst>{"".join(effs)}</p:childTnLst></p:cTn></p:par>')
        out.append(f'<p:par><p:cTn id="{outer}" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst>'
                   f'<p:childTnLst>{"".join(pars)}</p:childTnLst></p:cTn></p:par>')
    bld = "".join(f'<p:bldP spid="{i}" grpId="0"/>' for steps in clicks for st in steps for i in st["ids"])
    return ('<p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" restart="never" nodeType="tmRoot"><p:childTnLst>'
            '<p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>'
            + "".join(out) +
            '</p:childTnLst></p:cTn><p:prevCondLst><p:cond evt="onPrev" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>'
            '<p:nextCondLst><p:cond evt="onNext" delay="0"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>'
            f'</p:childTnLst></p:cTn></p:par></p:tnLst><p:bldLst>{bld}</p:bldLst></p:timing>')


nsteps = 0
for item in zin.infolist():
    data = zin.read(item.filename)
    m = re.fullmatch(r"ppt/slides/slide(\d+)\.xml", item.filename)
    if m:
        xml = data.decode("utf-8")
        ids = {name: i for i, name in re.findall(r'<p:cNvPr id="(\d+)" name="([^"]*)"', xml)}
        clicks = []
        for click in anim.get(m.group(1), []):
            steps = [dict(st) for st in as_steps(click) if st["n"]]
            for st in steps:
                missing = [n for n in st["n"] if n not in ids]
                if missing:
                    sys.exit(f"slide {m.group(1)}: no shape named {missing}")
                st["ids"] = [ids[n] for n in st["n"]]
            clicks.append(steps)
        nsteps += len(clicks)
        extra = '<p:transition spd="med"><p:fade/></p:transition>'
        if clicks:
            extra += timing(clicks)
        xml = re.sub(r"<p:transition.*?</p:transition>|<p:timing>.*?</p:timing>", "", xml, flags=re.S)
        anchor = "<p:extLst>" if "<p:extLst>" in xml.split("</p:clrMapOvr>")[-1] else "</p:sld>"
        head, sep, tail = xml.rpartition(anchor)
        xml = head + extra + sep + tail
        data = xml.encode("utf-8")
    zout.writestr(item, data)
zout.close()
print("animated", nsteps, "clicks")
