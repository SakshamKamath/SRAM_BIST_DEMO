"""Area plots: Original Croc (NORMAL) vs our design (DFT).

  area_composition.png  stacked bar per design; each memory's BIST is counted in that memory
  area_overhead.png     added area per block, with the overhead relative to that block
usage: python area_plot.py <out_dir>
"""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from area_data import NAND2_UM2, VAD_MACRO_UM2, normal_tot, normal_parts, dft_tot, dft_parts

OUT = sys.argv[1] if len(sys.argv) > 1 else "."

SURFACE, INK, INK2, GRID, NEUTRAL = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df", "#8a8984"
# Validated categorical order (light mode), one slot per block, never cycled
BLOCKS = ["SRAM bank 0", "SRAM bank 1", "CVE2 core", "Peripherals & others",
          "User domain (VAD)", "OBI cuts (+ JTAG isolation & access)", "Boundary scan"]
COLORS = dict(zip(BLOCKS, ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6"]))
WHITE_TEXT = {"#2a78d6", "#008300", "#6250d6"}

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 13,
    "axes.edgecolor": INK2, "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK,
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
})


def kge(um2):
    return um2 / NAND2_UM2 / 1e3


def part(parts, cat, key):
    return sum(a for m, a in parts[cat] if key in m)


bist = {k: part(dft_parts, "March MBIST", key) for k, key in
        (("bank0", "gen_sram_bank[0]"), ("bank1", "gen_sram_bank[1]"),
         ("vad0", "u_bank_0"), ("vad1", "u_bank_1"))}


def blocks(tot, with_bist):
    """Block totals; the BIST controllers are counted in the memory they test."""
    return {
        "SRAM bank 0": tot["SRAM Bank 1"] + (bist["bank0"] if with_bist else 0),
        "SRAM bank 1": tot["SRAM Bank 2"] + (bist["bank1"] if with_bist else 0),
        "CVE2 core": tot["CVE2 Core"],
        "Peripherals & others": tot["Peripherals & Others"],
        "User domain (VAD)": tot["User domain (VAD)"] + (bist["vad0"] + bist["vad1"] if with_bist else 0),
        "OBI cuts (+ JTAG isolation & access)": tot["OBI cuts / JTAG isolation"],
        "Boundary scan": tot["Boundary scan"],
    }


orig = blocks(normal_tot, False)
ours = blocks(dft_tot, True)
ORIG_TOTAL, OURS_TOTAL = sum(orig.values()), sum(ours.values())
assert abs(OURS_TOTAL - sum(dft_tot.values())) < 1


def style_axis(ax):
    ax.xaxis.grid(True, color=GRID, lw=0.8)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)


# ---------------------------------------------------------------- Figure 1
def composition():
    rows = [("Original Croc", orig), ("Our design", ours)]
    fig, ax = plt.subplots(figsize=(15, 5.4))
    bar_h = 0.52
    for y, (_, b) in zip((1, 0), rows):
        left = 0.0
        for name in BLOCKS:
            w = b[name]
            if w <= 0:
                continue
            col = COLORS[name]
            ax.barh(y, w, left=left, height=bar_h, color=col, edgecolor=SURFACE, linewidth=2)
            if w >= 55e3:
                ax.text(left + w / 2, y, f"{kge(w):.1f}\nkGE", ha="center", va="center", fontsize=13,
                        fontweight="bold", linespacing=1.3, color="white" if col in WHITE_TEXT else INK)
            else:
                ax.annotate(f"{name}: {kge(w):.1f} kGE", xy=(left + w / 2, y - bar_h / 2),
                            xytext=(left + w / 2, y - bar_h / 2 - 0.15), ha="center", va="top",
                            fontsize=11, fontweight="bold", color=INK,
                            arrowprops=dict(arrowstyle="-", color=INK2, lw=1))
            left += w
        ax.text(left + 8e3, y, f"{kge(left):.1f} kGE", ha="left", va="center", fontsize=14,
                color=INK, fontweight="bold")
    ax.set_yticks([1, 0], [r[0] for r in rows], fontsize=15, fontweight="bold")
    ax.set_xlim(0, 1.05e6)
    ax.set_ylim(-0.62, 1.45)
    ticks = [i * 0.2e6 for i in range(6)]
    ax.set_xticks(ticks, [f"{t / 1e6:.1f}" for t in ticks])
    ax.set_xlabel("Area (×10⁶ µm²)", color=INK2)
    style_axis(ax)
    d = OURS_TOTAL - ORIG_TOTAL
    ax.set_title(f"Area composition:  +{kge(d):.1f} kGE  (+{d / ORIG_TOTAL * 100:.1f} %)",
                 fontsize=19, fontweight="bold", color=INK, pad=14)
    handles = [plt.Rectangle((0, 0), 1, 1, color=COLORS[n]) for n in BLOCKS]
    ax.legend(handles, BLOCKS, loc="upper left", bbox_to_anchor=(1.01, 1.0), frameon=True,
              edgecolor=GRID, fontsize=12.5)
    fig.tight_layout()
    fig.savefig(f"{OUT}/area_composition.png", dpi=200)
    fig.savefig(f"{OUT}/area_composition.svg")


# ---------------------------------------------------------------- Figure 2
def overhead():
    xbar_orig = part(normal_parts, "Peripherals & Others", "obi_xbar$")
    interconnect_orig = normal_tot["OBI cuts / JTAG isolation"] + xbar_orig
    bank_if = {k: dft_tot[c] - normal_tot[c] for k, c in (("bank0", "SRAM Bank 1"), ("bank1", "SRAM Bank 2"))}
    vad_rest = dft_tot["User domain (VAD)"] - normal_tot["User domain (VAD)"]
    core_periph = (dft_tot["CVE2 Core"] + dft_tot["Peripherals & Others"]
                   - normal_tot["CVE2 Core"] - normal_tot["Peripherals & Others"])

    # (group, label, added µm², base µm² or None, base name, color)
    rows = [
        ("Memories: March MBIST", "Main SRAM bank 0  (256x64)", bist["bank0"] + bank_if["bank0"],
         normal_tot["SRAM Bank 1"], "of the bank", COLORS["SRAM bank 0"]),
        ("", "Main SRAM bank 1  (256x64)", bist["bank1"] + bank_if["bank1"],
         normal_tot["SRAM Bank 2"], "of the bank", COLORS["SRAM bank 1"]),
        ("", "VAD frame SRAM 0  (512x32)", bist["vad0"], VAD_MACRO_UM2, "of the SRAM", COLORS["User domain (VAD)"]),
        ("", "VAD frame SRAM 1  (512x32)", bist["vad1"], VAD_MACRO_UM2, "of the SRAM", COLORS["User domain (VAD)"]),
        ("Interconnect", "OBI JTAG isolation + sub access",
         dft_tot["OBI cuts / JTAG isolation"] - normal_tot["OBI cuts / JTAG isolation"],
         interconnect_orig, "of crossbar + cuts", COLORS["OBI cuts (+ JTAG isolation & access)"]),
        ("Chip IO", "Boundary scan  (40 cells)", dft_tot["Boundary scan"], ORIG_TOTAL, "of the chip",
         COLORS["Boundary scan"]),
        ("Other changes", "VAD: SRAM debug + observability regs", vad_rest, None, "", COLORS["User domain (VAD)"]),
        ("", "Core + peripherals", core_periph, None, "", NEUTRAL),
    ]
    total = sum(r[2] for r in rows)
    assert abs(total - (OURS_TOTAL - ORIG_TOTAL)) < 1

    # y positions, with a gap before each group
    ys, y = [], 0.0
    for g, *_ in rows:
        if g and ys:
            y += 0.55
        ys.append(-y)
        y += 1

    fig, ax = plt.subplots(figsize=(14, 7.2))
    vals = [kge(r[2]) for r in rows]
    ax.barh(ys, vals, height=0.66, color=[r[5] for r in rows], edgecolor=SURFACE, linewidth=2)
    for yy, v, (g, label, a, base, bname, _) in zip(ys, vals, rows):
        txt = f"+{v:.2f} kGE" if v < 1.5 else f"+{v:.1f} kGE"
        if base:
            txt += f"   ·   +{a / base * 100:.1f} % {bname}"
        if v > 8:     # long bar: label inside, so it is not cut off at the right edge
            ax.text(v - 0.15, yy, txt, va="center", ha="right", fontsize=12.5, color="white", fontweight="bold")
        else:
            ax.text(v + 0.15, yy, txt, va="center", ha="left", fontsize=12.5, color=INK)
        if g:
            ax.text(-0.02, yy + 0.62, g, transform=ax.get_yaxis_transform(), ha="right", va="center",
                    fontsize=12.5, fontweight="bold", color=INK2)
    ax.set_yticks(ys, [r[1] for r in rows], fontsize=12.5)
    ax.set_ylim(min(ys) - 0.7, 1.0)
    ax.set_xlim(0, 13.5)
    ax.set_xlabel("Area added vs Original Croc (kGE)", color=INK2)
    style_axis(ax)
    ax.set_title(f"Area overhead per block:  +{kge(total):.1f} kGE in total  "
                 f"(+{total / ORIG_TOTAL * 100:.1f} % of the chip)",
                 fontsize=18, fontweight="bold", color=INK, loc="left", pad=14)
    fig.tight_layout(rect=(0.03, 0, 1, 1))
    fig.savefig(f"{OUT}/area_overhead.png", dpi=200)
    fig.savefig(f"{OUT}/area_overhead.svg")


composition()
overhead()
print("written to", OUT)
