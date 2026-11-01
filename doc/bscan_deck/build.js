// Boundary-scan deck for the Croc DFT presentation. Animations are added afterwards by
// animate.py, which looks shapes up by objectName (the ANIM table below).
const pptxgen = require("pptxgenjs");
const fs = require("fs");

const THEME = {
  name: "Croc DFT",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1B2B2E", lt1: "FFFFFF", dk2: "12343B", lt2: "E0F2F1",
    accent1: "00897B", accent2: "93005F", accent3: "E39B2D", accent4: "1565B0",
    accent5: "6B7B7E", accent6: "B2DFDB", hlink: "00897B", folHlink: "93005F",
  },
};
const HEX = THEME.colors;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";            // 13.333 x 7.5 in
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
pres.title = "Boundary scan on Croc";
const C = pres.SchemeColor;
const TEAL = C.accent1, PURP = C.accent2, AMBER = C.accent3, GREY = C.accent5, DARK = C.text2, MINT = C.background2;

pres.defineSlideMaster({
  title: "TITLE_DARK",
  background: { color: DARK },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.3, w: 11.7, h: 1.3, fontSize: 44, bold: true, color: C.background1, fontFace: THEME.headFontFace, valign: "bottom", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.75, w: 11.7, h: 0.9, fontSize: 20, color: C.accent6, valign: "top", align: "left", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.35, w: 12.1, h: 0.85, fontSize: 34, bold: true, color: DARK, fontFace: THEME.headFontFace, valign: "middle", align: "left", margin: 0 }, text: "" } },
  ],
  slideNumber: { x: 12.3, y: 7.0, w: 0.6, h: 0.3, fontSize: 10, color: GREY, align: "right" },
});

const ANIM = {};   // slide number -> list of click groups (lists of objectNames)
let sn = 0;
function addSlide(master) { sn++; ANIM[sn] = []; return pres.addSlide({ masterName: master, sectionTitle: "Boundary scan" }); }
function click(...names) { ANIM[sn].push(names); }
// steps: [{n: [names], fx: "fade"|"wipe"|"zoom", dir: "l"|"r"|"u"|"d", at: ms, dur: ms}] (see animate.py)
function clickSeq(steps) { ANIM[sn].push({ seq: steps.filter((st) => st.n.length) }); }

function box(s, name, x, y, w, h, fill, opts = {}) {
  s.addShape(opts.round === false ? pres.shapes.RECTANGLE : pres.shapes.ROUNDED_RECTANGLE,
    { x, y, w, h, fill: { color: fill }, line: opts.line || { type: "none" }, rectRadius: opts.round === false ? undefined : 0.08, objectName: name });
}
function txt(s, name, text, x, y, w, h, o = {}) {
  s.addText(text, Object.assign({ x, y, w, h, isTextBox: true, margin: 0, fontSize: 14, color: C.text1, valign: "top", objectName: name }, o));
}
function num(s, name, n, x, y, d = 0.5, fill = TEAL) {
  s.addShape(pres.shapes.OVAL, { x, y, w: d, h: d, fill: { color: fill }, line: { type: "none" }, objectName: name + "_c" });
  s.addText(String(n), { x, y, w: d, h: d, isTextBox: true, margin: 0, align: "center", valign: "middle", fontSize: 18, bold: true, color: C.background1, objectName: name + "_n" });
  return [name + "_c", name + "_n"];
}
function hline(s, name, x1, x2, y, color, width, o = {}) {
  s.addShape(pres.shapes.LINE, { x: Math.min(x1, x2), y, w: Math.abs(x2 - x1), h: 0, flipH: x2 < x1,
    line: { color, width, dashType: o.dash || "solid", endArrowType: o.arrow === false ? undefined : "triangle", beginArrowType: o.both ? "triangle" : undefined }, objectName: name });
}
function vline(s, name, x, y1, y2, color, width, o = {}) {
  s.addShape(pres.shapes.LINE, { x, y: Math.min(y1, y2), w: 0, h: Math.abs(y2 - y1), flipV: y2 < y1,
    line: { color, width, dashType: o.dash || "solid", endArrowType: o.arrow === false ? undefined : "triangle" }, objectName: name });
}

// ---------------------------------------------------------------- 1. Title
pres.addSection({ title: "Boundary scan" });
let s = addSlide("TITLE_DARK");
s.addText("Boundary Scan on Croc", { placeholder: "title" });
s.addText("Reading and driving every signal pin over five JTAG wires", { placeholder: "body" });
// motif: a short scan chain of cells
for (let i = 0; i < 8; i++) {
  s.addShape(pres.shapes.RECTANGLE, { x: 0.8 + i * 0.75, y: 5.6, w: 0.35, h: 0.35, fill: { color: C.accent6 }, line: { color: TEAL, width: 1.5 }, objectName: "motif_cell" + i });
  if (i < 7) hline(s, "motif_link" + i, 1.15 + i * 0.75, 1.55 + i * 0.75, 5.775, TEAL, 1.5, { dash: "dash" });
}
txt(s, "motif_tdi", "TDI", 0.8, 6.05, 0.6, 0.3, { fontSize: 12, color: C.accent6 });
txt(s, "motif_tdo", "TDO", 6.05, 6.05, 0.6, 0.3, { fontSize: 12, color: C.accent6 });
s.addNotes("Boundary scan is the part of our DFT work that sits at the edge of the chip, between the pads and the core. This section shows what it is, where it sits in Croc, what each instruction is for, and how we verified it.");

// ---------------------------------------------------------------- 2. Why
s = addSlide("CONTENT");
s.addText("Why we need access at the pins", { placeholder: "title" });
const why = [
  ["Is it the chip or the board?", "UART prints nothing on the first board. A bad solder joint, a wrong pin map and a broken core all look the same from the outside."],
  ["Pins we cannot probe", "48 signal pins on a fine-pitch package. There is no room for a probe on each one, and a probe only sees, it cannot drive."],
  ["A core we cannot fully trust", "Thomy (IIS, IHP130): synthesis flipped the reset values of array-assigned control signals. The team needed scan access to force the right values."],
];
why.forEach(([h, b], i) => {
  const y = 1.55 + i * 1.75;
  box(s, `why${i}_bg`, 0.6, y, 7.0, 1.5, MINT);
  const n = num(s, `why${i}`, i + 1, 0.85, y + 0.3);
  txt(s, `why${i}_h`, h, 1.6, y + 0.2, 5.8, 0.4, { fontSize: 18, bold: true, color: DARK });
  txt(s, `why${i}_b`, b, 1.6, y + 0.62, 5.8, 0.8, { fontSize: 14 });
  click(`why${i}_bg`, ...n, `why${i}_h`, `why${i}_b`);
});
box(s, "why_ans", 8.0, 1.55, 4.7, 5.0, DARK);
txt(s, "why_ans_h", "Boundary scan", 8.35, 1.85, 4.0, 0.5, { fontSize: 22, bold: true, color: C.accent6, fontFace: THEME.headFontFace });
txt(s, "why_ans_b", [
  { text: "A scan cell sits between every signal pad and the core. From 5 JTAG pins we can:", options: { breakLine: true, paraSpaceAfter: 10 } },
  { text: "read every pin while the chip runs", options: { bullet: true, breakLine: true, paraSpaceAfter: 6 } },
  { text: "drive every output pin ourselves", options: { bullet: true, breakLine: true, paraSpaceAfter: 6 } },
  { text: "feed the core any input pattern", options: { bullet: true, breakLine: true, paraSpaceAfter: 6 } },
  { text: "do all of it without firmware", options: { bullet: true } },
], 8.35, 2.5, 4.0, 3.8, { fontSize: 16, color: C.background1 });
click("why_ans", "why_ans_h", "why_ans_b");
s.addNotes("Three situations we will face after tape-out. First, when something does not work on the board we must separate chip faults from board faults. Second, we cannot probe 48 pins, and a probe cannot drive anything. Third, the Thomy chip from IIS showed that silicon can come back in a state we did not intend: synthesis in IHP130 flipped the init values of control signals assigned through an array, and they needed scan access to set them. Boundary scan answers the pin-level part of all three: from the five JTAG pins we can observe and control every signal pin, without any firmware.");

// ---------------------------------------------------------------- 3. Where
s = addSlide("CONTENT");
s.addText("Where it sits in Croc", { placeholder: "title" });
const imgH = 5.65, imgW = imgH * 2000 / 1530;
s.addImage({ path: "croc_chip_postdft.png", x: 0.5, y: 1.4, w: imgW, h: imgH, altText: "Croc chip after DFT: boundary-scan cells between every signal pad and the core, chained from the Bndscan TAP", objectName: "where_img" });
const where = [
  ["40 cells", "uart_rx, testmode, uart_tx, status, unused0–3, gpio0–31. Bit 0 (uart_rx) is shifted out first."],
  ["No cell on", "clk, rst_n, ref_clk and the five JTAG pins themselves."],
  ["Own TAP", "First in the JTAG chain: TDI → Bndscan TAP → OBI-JTAG TAP → debug TAP → TDO."],
  ["4-bit IR", "0 BYPASS, 1 SAMPLE/PRELOAD, 2 EXTEST, 3 INTEST. Unused opcodes select BYPASS."],
];
where.forEach(([h, b], i) => {
  const x = 8.15, y = 1.45 + i * 1.4;
  const n = num(s, `where${i}`, i + 1, x, y + 0.05, 0.45);
  txt(s, `where${i}_h`, h, x + 0.6, y, 4.0, 0.4, { fontSize: 18, bold: true, color: DARK });
  txt(s, `where${i}_b`, b, x + 0.6, y + 0.42, 4.1, 0.9, { fontSize: 14 });
  click(...n, `where${i}_h`, `where${i}_b`);
});
s.addNotes("The teal squares around the edge are the 40 boundary-scan cells, one per signal pin except the clocks, reset and JTAG pins. They form one shift register, driven by its own TAP, which is the first TAP after TDI. The other two TAPs, for crossbar isolation and for debug, follow it in the same chain. The instruction register is 4 bits wide; we implement the four standard instructions and every unused opcode falls back to BYPASS.");

// ---------------------------------------------------------------- 4. One cell
s = addSlide("CONTENT");
s.addText("One cell, three steps", { placeholder: "title" });
box(s, "cell_pad", 0.7, 2.6, 1.6, 1.3, "F1DDE9");
txt(s, "cell_pad_t", "Pad", 0.7, 2.6, 1.6, 1.3, { align: "center", valign: "middle", fontSize: 20, bold: true, color: PURP });
box(s, "cell_core", 11.1, 2.6, 1.6, 1.3, DARK);
txt(s, "cell_core_t", "Core", 11.1, 2.6, 1.6, 1.3, { align: "center", valign: "middle", fontSize: 20, bold: true, color: C.background1 });
box(s, "cell_bg", 3.3, 1.65, 7.0, 3.1, MINT, { line: { color: TEAL, width: 1.5 } });
txt(s, "cell_lbl", "Boundary-scan cell", 7.4, 1.75, 2.7, 0.35, { fontSize: 14, bold: true, color: TEAL, align: "right" });
box(s, "cell_sff", 4.0, 3.0, 1.9, 0.9, TEAL);
txt(s, "cell_sff_t", "Shift FF", 4.0, 3.0, 1.9, 0.9, { align: "center", valign: "middle", fontSize: 16, bold: true, color: C.background1 });
box(s, "cell_uff", 6.6, 3.0, 1.9, 0.9, TEAL);
txt(s, "cell_uff_t", "Update FF", 6.6, 3.0, 1.9, 0.9, { align: "center", valign: "middle", fontSize: 16, bold: true, color: C.background1 });
box(s, "cell_mux", 9.0, 2.6, 0.75, 1.5, GREY);
txt(s, "cell_mux_t", "MUX", 9.0, 2.6, 0.75, 1.5, { align: "center", valign: "middle", fontSize: 12, bold: true, color: C.background1 });
txt(s, "cell_mode", "mode (from IR)", 8.55, 4.2, 1.7, 0.3, { fontSize: 11, color: GREY, align: "center" });
// base wiring (thin grey)
hline(s, "w_func", 2.3, 9.0, 2.8, GREY, 1.5);
txt(s, "w_func_t", "functional path", 5.2, 2.42, 2.0, 0.3, { fontSize: 11, color: GREY, align: "center" });
hline(s, "w_cap", 2.3, 4.0, 3.45, GREY, 1.25, { dash: "dash" });
vline(s, "w_tdi", 4.95, 1.25, 3.0, GREY, 1.25, { dash: "dash" });
vline(s, "w_tdo", 4.95, 3.9, 5.05, GREY, 1.25, { dash: "dash" });
hline(s, "w_upd1", 5.9, 6.6, 3.45, GREY, 1.25, { dash: "dash" });
hline(s, "w_upd2", 8.5, 9.0, 3.45, GREY, 1.25, { dash: "dash" });
hline(s, "w_core", 9.75, 11.1, 3.25, GREY, 1.5);
txt(s, "w_tdi_t", "TDI (from previous cell)", 5.1, 1.2, 2.6, 0.3, { fontSize: 11, color: GREY });
txt(s, "w_tdo_t", "TDO (to next cell)", 5.1, 4.8, 2.4, 0.3, { fontSize: 11, color: GREY });
// highlighted paths, one per click
hline(s, "h_cap", 2.3, 4.0, 3.45, AMBER, 4);
vline(s, "h_tdi", 4.95, 1.25, 3.0, AMBER, 4);
vline(s, "h_tdo", 4.95, 3.9, 5.05, AMBER, 4);
hline(s, "h_upd1", 5.9, 6.6, 3.45, AMBER, 4);
hline(s, "h_upd2", 8.5, 9.0, 3.45, AMBER, 4);
hline(s, "h_core", 9.75, 11.1, 3.25, AMBER, 4);
const steps = [
  ["Capture", "The pin value (or the core output) is copied into the shift FF."],
  ["Shift", "One bit per TCK: a new pattern goes in at TDI while the captured values come out at TDO."],
  ["Update", "The shifted-in value moves to the update FF and, in EXTEST/INTEST, drives the pin or the core."],
];
const hi = [["h_cap"], ["h_tdi", "h_tdo"], ["h_upd1", "h_upd2", "h_core"]];
steps.forEach(([h, b], i) => {
  const x = 0.7 + i * 4.05, y = 5.45;
  box(s, `step${i}_bg`, x, y, 3.8, 1.5, MINT);
  const n = num(s, `step${i}`, i + 1, x + 0.2, y + 0.2, 0.45, AMBER);
  txt(s, `step${i}_h`, h, x + 0.8, y + 0.2, 2.8, 0.4, { fontSize: 18, bold: true, color: DARK });
  txt(s, `step${i}_b`, b, x + 0.8, y + 0.62, 2.85, 0.85, { fontSize: 13 });
  const card = [{ n: [`step${i}_bg`, ...n], fx: "zoom", dur: 350 }, { n: [`step${i}_h`, `step${i}_b`], fx: "fade", dur: 400 }];
  const draw = [[{ n: ["h_cap"], fx: "wipe", dir: "l", dur: 600 }],
               [{ n: ["h_tdi"], fx: "wipe", dir: "u", dur: 500 }, { n: ["h_tdo"], fx: "wipe", dir: "u", dur: 500 }],
               [{ n: ["h_upd1"], fx: "wipe", dir: "l", dur: 350 }, { n: ["h_upd2"], fx: "wipe", dir: "l", dur: 300 }, { n: ["h_core"], fx: "wipe", dir: "l", dur: 450 }]][i];
  let t = 0; const seq = [];
  draw.forEach((st) => { seq.push(Object.assign({ at: t }, st)); t += st.dur; });
  card.forEach((st, k) => seq.push(Object.assign({ at: t + 150 + k * 200 }, st)));
  clickSeq(seq);
});
s.addNotes("Each cell has a shift flip-flop and an update flip-flop. Capture copies what is on the pin into the shift flip-flop. Shift moves the whole chain one bit per TCK, so we read the captured values out at TDO while the next pattern goes in at TDI. Update copies the new pattern into the update flip-flops at once, and the mux, controlled by the instruction, decides whether the pin or the core sees the functional value or the scanned value. In normal operation the functional path is untouched.");

// ---------------------------------------------------------------- 5-6. Instructions
// One panel per instruction: an input-pin row and an output-pin row, so it is clear per direction
// what the cell does. Behaviour follows bndscan_jtag_wrapper.sv:
//   SAMPLE/PRELOAD: pins work normally; input cells capture the pin, output cells the core output
//   EXTEST: output pins driven by the cells; input cells capture the pin, the core still sees it
//   INTEST: core inputs driven by the cells (pin ignored); output cells capture, the core still drives the pin
const RED = "C62828", CELL_GREY = "D5DCDD", PIN = "F1DDE9";
function instrPanel(s, id, px, py, P) {
  const pw = 6.0, ph = 5.6, names = [], R = { base: [], a1: [], a2: [], b2: [], b1: [], label: [], jtag: [], text: [] };
  let role = "base";
  const add = (n) => { names.push(n); R[role].push(n); return n; };
  box(s, add(`${id}_bg`), px, py, pw, ph, MINT);
  txt(s, add(`${id}_h`), P.head, px + 0.25, py + 0.18, pw - 0.5, 0.42, { fontSize: 20, bold: true, color: DARK });
  txt(s, add(`${id}_tag`), P.tag, px + 0.25, py + 0.62, pw - 0.5, 0.32, { fontSize: 14, color: GREY, italic: true });
  const pinX = px + 0.3, pinW = 1.15, cellX = px + 2.25, cellW = 0.95, coreX = px + 4.35, coreW = 1.35, bh = 0.6;
  const r1 = py + 1.35, r2 = py + 2.45, c1 = r1 + bh / 2, c2 = r2 + bh / 2;
  [[r1, "Input pin"], [r2, "Output pin"]].forEach(([ry, t], k) => {
    box(s, add(`${id}_pin${k}`), pinX, ry, pinW, bh, PIN);
    txt(s, add(`${id}_pint${k}`), t, pinX, ry, pinW, bh, { align: "center", valign: "middle", fontSize: 13, bold: true, color: PURP });
  });
  box(s, add(`${id}_core`), coreX, r1, coreW, r2 + bh - r1, DARK);
  txt(s, add(`${id}_coret`), "Core", coreX, r1, coreW, r2 + bh - r1, { align: "center", valign: "middle", fontSize: 16, bold: true, color: C.background1 });
  const cellStyle = { drive: [C.accent6, TEAL], record: [C.background1, AMBER], pass: [CELL_GREY, GREY] };
  const cellLabels = [];
  [[r1, P.cell[0]], [r2, P.cell[1]]].forEach(([ry, [mode, label]], k) => {
    role = "base";
    const [fill, col] = cellStyle[mode];
    box(s, add(`${id}_cell${k}`), cellX, ry, cellW, bh, fill, { line: { color: col, width: 2 } });
    txt(s, add(`${id}_cellt${k}`), "cell", cellX, ry, cellW, bh, { align: "center", valign: "middle", fontSize: 13, bold: true, color: DARK });
    const ly = k === 0 ? ry - 0.4 : ry + bh + 0.11;
    role = "label";
    txt(s, add(`${id}_cl${k}`), label, cellX - 0.6, ly, cellW + 1.2, 0.3, { align: "center", fontSize: 12, bold: true, color: col });
  });
  // arrows: A1 pin->cell, A2 cell->core (row 1); B2 core->cell, B1 cell->pin (row 2)
  const col = { pass: GREY, drive: TEAL, record: AMBER };
  role = "base";
  const seg = (n, x1, x2, y, kind) => {
    role = n;
    if (kind === "cut") {
      hline(s, add(`${id}_${n}`), x1, x2, y, CELL_GREY, 2, { dash: "dash", arrow: false });
      txt(s, add(`${id}_${n}x`), "✕", (x1 + x2) / 2 - 0.15, y - 0.2, 0.3, 0.4, { align: "center", valign: "middle", fontSize: 20, bold: true, color: RED });
    } else hline(s, add(`${id}_${n}`), x1, x2, y, col[kind], 3);
  };
  seg("a1", pinX + pinW, cellX, c1, P.arrows[0]);
  seg("a2", cellX + cellW, coreX, c1, P.arrows[1]);
  seg("b2", coreX, cellX + cellW, c2, P.arrows[2]);
  seg("b1", cellX, pinX + pinW, c2, P.arrows[3]);
  // JTAG strip
  role = "jtag";
  const jy = py + 3.5;
  box(s, add(`${id}_jbg`), px + 0.25, jy, pw - 0.5, 0.42, C.background1, { line: { color: CELL_GREY, width: 1 } });
  txt(s, add(`${id}_j`), [{ text: "JTAG  ", options: { bold: true, color: PURP } }, { text: P.jtag, options: { color: DARK } }],
      px + 0.4, jy, pw - 0.8, 0.42, { fontSize: 13, valign: "middle" });
  role = "text";
  txt(s, add(`${id}_w`), P.what, px + 0.25, py + 4.05, pw - 0.5, 0.85, { fontSize: 14 });
  txt(s, add(`${id}_u`), [{ text: "Use it for: ", options: { bold: true, color: TEAL } }, { text: P.use, options: { italic: true, color: DARK } }],
      px + 0.25, py + 4.9, pw - 0.5, 0.6, { fontSize: 14 });
  // build-up: blocks, then each signal along its direction, then what the cells do, JTAG, text
  const arrowStep = (n, dir) => {
    const line = R[n].filter((x) => !x.endsWith("x")), cross = R[n].filter((x) => x.endsWith("x"));
    return P.arrows[["a1", "a2", "b2", "b1"].indexOf(n)] === "cut"
      ? [{ n: line, fx: "fade", dur: 300 }, { n: cross, fx: "zoom", dur: 300 }]
      : [{ n: line, fx: "wipe", dir, dur: 450 }];
  };
  const seq = [{ n: R.base, fx: "fade", dur: 400, at: 0 }];
  let t = 450;
  [["a1", "l"], ["a2", "l"]].forEach(([n, d]) => arrowStep(n, d).forEach((st) => { seq.push(Object.assign({ at: t }, st)); t += st.dur; }));
  let t2 = 450;
  [["b2", "r"], ["b1", "r"]].forEach(([n, d]) => arrowStep(n, d).forEach((st) => { seq.push(Object.assign({ at: t2 }, st)); t2 += st.dur; }));
  t = Math.max(t, t2) + 100;
  seq.push({ n: R.label, fx: "zoom", dur: 350, at: t }); t += 450;
  seq.push({ n: R.jtag, fx: "wipe", dir: "l", dur: 500, at: t }); t += 550;
  seq.push({ n: R.text, fx: "fade", dur: 500, at: t });
  return seq;
}
function instrKey(s, name) {
  txt(s, name, [
    { text: "teal", options: { color: TEAL, bold: true } }, { text: " = the cell drives    " },
    { text: "amber", options: { color: AMBER, bold: true } }, { text: " = the cell records it    " },
    { text: "grey", options: { color: GREY, bold: true } }, { text: " = normal path    " },
    { text: "✕", options: { color: RED, bold: true } }, { text: " = cut" },
  ], 0.6, 7.03, 10.0, 0.3, { fontSize: 11, color: GREY });
}

// slide 5: BYPASS and SAMPLE / PRELOAD
s = addSlide("CONTENT");
s.addText("Watching: BYPASS and SAMPLE / PRELOAD", { placeholder: "title" });
clickSeq(instrPanel(s, "byp", 0.6, 1.35, {
  head: "BYPASS", tag: "Boundary scan steps aside",
  cell: [["pass", "transparent"], ["pass", "transparent"]], arrows: ["pass", "pass", "pass", "pass"],
  jtag: "TDI → one 1-bit register → TDO",
  what: "Every pin works normally and the cells are transparent. Between TDI and TDO there is only one bit, so the other JTAG blocks in the chain are reached with one extra shift.",
  use: "normal operation (the default after reset) and talking to the other JTAG blocks." }));
const smp = instrPanel(s, "smp", 6.75, 1.35, {
  head: "SAMPLE / PRELOAD", tag: "Look at every pin while the chip runs",
  cell: [["record", "records the pin"], ["record", "records the core output"]], arrows: ["pass", "pass", "pass", "pass"],
  jtag: "the snapshot shifts out at TDO",
  what: "SAMPLE: the chip keeps running. Each input cell records its pin, each output cell records what the core drives, and the snapshot is shifted out.",
  use: "watching the pins live while firmware runs." });
clickSeq(smp);
// PRELOAD: same instruction, the values shifted in wait in the cells
const pre = [];
[[1.35 + 1.35, 0], [1.35 + 2.45, 1]].forEach(([ry, k]) => {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 6.75 + 2.25 - 0.08, y: ry - 0.08, w: 0.95 + 0.16, h: 0.6 + 0.16, rectRadius: 0.08,
    fill: { type: "none" }, line: { color: TEAL, width: 2, dashType: "dash" }, objectName: `pre_ring${k}` });
  pre.push(`pre_ring${k}`);
});
box(s, "pre_jbg", 6.75 + 0.25, 1.35 + 3.5, 5.5, 0.42, C.background1, { line: { color: TEAL, width: 1.5 } });
txt(s, "pre_j", [{ text: "JTAG  ", options: { bold: true, color: PURP } }, { text: "PRELOAD: new values shift in and wait in the cells", options: { color: DARK } }],
    6.75 + 0.4, 1.35 + 3.5, 5.2, 0.42, { fontSize: 13, valign: "middle" });
box(s, "pre_wbg", 6.75 + 0.15, 1.35 + 4.0, 5.7, 1.5, MINT);
txt(s, "pre_w", "PRELOAD: values shifted in are stored in the cells but not applied yet, so EXTEST or INTEST starts from safe, known values instead of random ones.",
    6.75 + 0.25, 1.35 + 4.05, 5.5, 0.85, { fontSize: 14 });
txt(s, "pre_u", [{ text: "Use it for: ", options: { bold: true, color: TEAL } }, { text: "loading safe values before taking control of the pins or the core.", options: { italic: true, color: DARK } }],
    6.75 + 0.25, 1.35 + 4.9, 5.5, 0.6, { fontSize: 14 });
clickSeq([{ n: pre, fx: "zoom", dur: 400, at: 0 },
          { n: ["pre_jbg", "pre_j"], fx: "wipe", dir: "l", dur: 500, at: 500 },
          { n: ["pre_wbg", "pre_w", "pre_u"], fx: "fade", dur: 500, at: 1050 }]);
instrKey(s, "ins_key1");
s.addNotes("Click 1, BYPASS: boundary scan is out of the way. All pins and the core work normally, and the only thing between TDI and TDO is a single bit, so reaching the other TAPs behind it costs one extra shift. This is the state after reset. Click 2, SAMPLE: the chip still runs normally, nothing is changed on any pin. On Capture, every input cell records the value on its pin and every output cell records what the core is driving; Shift moves that snapshot out at TDO. Click 3, PRELOAD: it is the same instruction, used the other way round. The values we shift in are stored in the cells on Update but not applied, so when we then switch to EXTEST or INTEST, the pins or the core start from values we chose.");

// slide 6: EXTEST and INTEST
s = addSlide("CONTENT");
s.addText("Taking control: EXTEST and INTEST", { placeholder: "title" });
clickSeq(instrPanel(s, "ext", 0.6, 1.35, {
  head: "EXTEST", tag: "Take over the output pins to test the board",
  cell: [["record", "records the pin"], ["drive", "drives the pin"]], arrows: ["pass", "pass", "record", "drive"],
  jtag: "shifted-in values drive the pins; recorded inputs shift out",
  what: "The cells drive every output pin; the core's output stops at its cell. Input cells record what the board drives, and the core still sees its inputs.",
  use: "board test: walk a 1 across the outputs and read it back to find shorts, opens or a wrong pin map." }));
clickSeq(instrPanel(s, "int", 6.75, 1.35, {
  head: "INTEST", tag: "Take over the core's inputs to test the core",
  cell: [["drive", "drives the core"], ["record", "records the core output"]], arrows: ["cut", "drive", "pass", "pass"],
  jtag: "shifted-in values drive the core; its answers shift out",
  what: "The cells drive the core's inputs; the real input pins are ignored. Output cells record the core's answer, and the core keeps driving its pins.",
  use: "testing the core with known inputs, whatever the board around it does." }));
instrKey(s, "ins_key2");
s.addNotes("Click 1, EXTEST: now boundary scan takes control of the outputs. Every output pin is driven by its cell, so the core cannot disturb the board test; what the core wanted to drive is still recorded in the cell. Input cells record what arrives on the input pins, and in our design the core still sees those inputs. Typical use: walk a single 1 across the output pins and read the input pins back to find shorts, opens or a wrong pin map. Click 2, INTEST: the mirror image. The cells drive the core's inputs and the real input pins are ignored, so the core sees exactly the pattern we shifted in. The output cells record the core's answer, and in our design the core keeps driving its output pins. Typical use: test the core with known inputs even if the board is broken; our testbench does this with a program that echoes inputs to outputs.");

// ---------------------------------------------------------------- 6. Examples
s = addSlide("CONTENT");
s.addText("How it helps: four examples", { placeholder: "title" });
const ex = [
  ["UART prints nothing", "SAMPLE", "Sample uart_tx while the firmware runs. If the cell toggles, the core works and the fault is on the board. If it is stuck, look at the core. EXTEST can then toggle the pin directly for the scope."],
  ["GPIO short on the board", "EXTEST", "Walk a single 1 across the GPIO outputs and read the pins back through the input cells. A short shows the 1 on two pins; an open never shows it at all."],
  ["Core needs known inputs", "PRELOAD+INTEST", "Like Thomy's scan fix, but at the chip boundary: force testmode or the GPIO inputs to known values from JTAG, whatever the board drives."],
  ["Is the core alive?", "INTEST", "Our test: the core echoes gpio[23:16] onto gpio[15:8]. Under INTEST the echo returns the BSR pattern, not the pin values, so the core works with nothing on the pins."],
];
ex.forEach(([h, tag, b], i) => {
  const x = 0.6 + (i % 2) * 6.15, y = 1.5 + Math.floor(i / 2) * 2.75, w = 5.95, hgt = 2.5;
  box(s, `ex${i}_bg`, x, y, w, hgt, MINT);
  const n = num(s, `ex${i}`, i + 1, x + 0.25, y + 0.25, 0.5, PURP);
  txt(s, `ex${i}_h`, h, x + 0.95, y + 0.25, 3.0, 0.5, { fontSize: 18, bold: true, color: DARK, valign: "middle" });
  box(s, `ex${i}_tag`, x + w - 1.85, y + 0.3, 1.6, 0.4, TEAL);
  txt(s, `ex${i}_tt`, tag, x + w - 1.85, y + 0.3, 1.6, 0.4, { fontSize: 12, bold: true, color: C.background1, align: "center", valign: "middle" });
  txt(s, `ex${i}_b`, b, x + 0.95, y + 0.9, w - 1.2, 1.5, { fontSize: 14 });
  click(`ex${i}_bg`, ...n, `ex${i}_h`, `ex${i}_tag`, `ex${i}_tt`, `ex${i}_b`);
});
s.addNotes("Four concrete cases. One: the classic bring-up problem, UART silent. SAMPLE tells us in one scan whether the core is driving the pin. Two: board shorts and opens, found with a walking one under EXTEST, with no firmware and no probes. Three: the Thomy lesson. Boundary scan cannot reach internal registers, but it does give us control over every input the core sees from outside, for example testmode. Four: this is exactly what our testbench does, the core echoes GPIO inputs to outputs, and under INTEST it echoes the pattern we scanned in, which proves the core path works independently of the pins.");

// ---------------------------------------------------------------- 7. Verification
s = addSlide("CONTENT");
s.addText("Verification at the pins", { placeholder: "title" });
txt(s, "ver_sub", "tb_croc_chip +bscan_test: the testbench drives only the chip pins and JTAG, like a tester", 0.6, 1.25, 12.0, 0.35, { fontSize: 14, color: GREY, italic: true });
const partA = ["Chain length per instruction: BYPASS 5 bits, SAMPLE / EXTEST / INTEST 44", "Unused opcodes select BYPASS",
  "SAMPLE: walking 1/0 on all 32 GPIO pins is captured", "SAMPLE: shifting all 1s leaves the outputs alone",
  "EXTEST: walking 1/0 on uart_tx, status, unused0–3", "EXTEST: input pads are not driven, still captured",
  "TMS reset, TRST and BYPASS give the pins back to the core"];
const partB = ["SAMPLE sees the core's outputs on gpio[15:8]", "EXTEST: the BSR overrides the core on gpio[15:8]",
  "INTEST: the core reads the BSR, not the pins (echo shows the BSR pattern)", "BYPASS: the core drives and reads the pins again"];
[[partA, "Part A: pins only, core idle", 0.6, 6.4], [partB, "Part B: core running test_bscan.c", 7.2, 5.5]].forEach(([items, head, x, w], k) => {
  const names = [];
  box(s, `ver${k}_bg`, x, 1.8, w, 4.6, MINT); names.push(`ver${k}_bg`);
  txt(s, `ver${k}_h`, head, x + 0.25, 1.95, w - 0.5, 0.4, { fontSize: 18, bold: true, color: DARK }); names.push(`ver${k}_h`);
  txt(s, `ver${k}_l`, items.map((t, j) => ({ text: t, options: { bullet: true, breakLine: j < items.length - 1, paraSpaceAfter: 6 } })),
    x + 0.25, 2.5, w - 0.5, 3.8, { fontSize: 16 }); names.push(`ver${k}_l`);
  click(...names);
});
box(s, "ver_res", 0.6, 6.55, 12.1, 0.6, DARK);
txt(s, "ver_res_t", [{ text: "Result: ", options: { bold: true, color: C.accent6 } }, { text: "all 34 checks pass", options: { color: C.accent6, bold: true } },
  { text: "   ·   RTL simulation, QuestaSim", options: { color: C.background1 } }], 0.85, 6.55, 11.6, 0.6, { fontSize: 16, valign: "middle" });
click("ver_res", "ver_res_t");
s.addNotes("We verified boundary scan from the outside only: the testbench drives the JTAG pins and the chip pins, exactly as a tester would. Part A runs with the core idle and checks the chain lengths, every instruction, and that a TAP reset or TRST always gives the pins back to the core. Part B runs a small program on the core so we can see SAMPLE, EXTEST and INTEST interact with real core activity. All 34 checks pass (QuestaSim, 31 October).");

// ---------------------------------------------------------------- 8. Takeaways
s = addSlide("TITLE_DARK");
s.addText("Takeaways", { placeholder: "title" });
s.addText("40 cells and one TAP buy control over the whole chip boundary", { placeholder: "body" });
const tk = [["Chip or board?", "SAMPLE and EXTEST answer it without firmware"], ["Every pin", "readable and drivable from 5 JTAG pins"], ["Core in isolation", "INTEST tests it with nothing on the pins"]];
tk.forEach(([h, b], i) => {
  const x = 0.8 + i * 4.0;
  txt(s, `tk${i}_h`, h, x, 5.0, 3.7, 0.5, { fontSize: 22, bold: true, color: C.accent6, fontFace: THEME.headFontFace });
  txt(s, `tk${i}_b`, b, x, 5.55, 3.6, 0.8, { fontSize: 16, color: C.background1 });
  click(`tk${i}_h`, `tk${i}_b`);
});
s.addNotes("To sum up: for the cost of 40 scan cells and one small TAP, we can tell chip faults from board faults, observe and drive every signal pin, and test the core on its own. Area numbers are in the evaluation slide.");

(async () => {
  await pres.writeFile({ fileName: "bs_raw.pptx" });
  const { applyTheme } = require(process.env.SKILL + "/scripts/apply_theme.js");
  await applyTheme("bs_raw.pptx", THEME);
  fs.writeFileSync("anim.json", JSON.stringify(ANIM));
  console.log("written");
})();
