"""Per-category area from Yosys area reports (own area per module, summed by instance path)."""
import re

NAND2_UM2 = 5.65                 # 1 GE = area of NAND2X1
VAD_MACRO_UM2 = 79719.8976       # RM_IHPSG13_1P_512x32_c2_bm_bist, from NORMAL/technology liberty

CATS = [
    "SRAM Bank 1",
    "SRAM Bank 2",
    "CVE2 Core",
    "Peripherals & Others",
    "User domain (VAD)",
    "OBI cuts / JTAG isolation",
    "March MBIST",
    "Boundary scan",
]


def module_areas(full_rpt, logic_rpt):
    """{module_name: own area}; the top module uses the logic report (no IO pads)."""
    def parse(p):
        out = {}
        for m in re.finditer(r"Chip area for module '\\(.+?)': ([0-9.]+)", open(p).read()):
            out[m.group(1)] = float(m.group(2))
        return out
    full, logic = parse(full_rpt), parse(logic_rpt)
    full["croc_chip"] = logic["croc_chip"]
    return full


def category(mod):
    path = mod.split("$", 1)[1] if "$" in mod else mod
    if "u_bist_controller" in path:
        return "March MBIST"
    if path == "croc_chip" or "i_bndscan_jtag_top" in path:
        return "Boundary scan"            # bndscan_jtag_top is flattened into croc_chip
    if "gen_sram_bank[0]" in path:
        return "SRAM Bank 1"
    if "gen_sram_bank[1]" in path:
        return "SRAM Bank 2"
    if "i_core_wrap" in path:
        return "CVE2 Core"
    if "i_obi_jtag_top" in path or mod.startswith("obi_xbar_multicut"):
        return "OBI cuts / JTAG isolation"
    if ".i_user" in path:
        return "User domain (VAD)"
    return "Peripherals & Others"


def categorize(areas, extra=None):
    tot = {c: 0.0 for c in CATS}
    parts = {c: [] for c in CATS}
    for mod, a in areas.items():
        c = category(mod)
        tot[c] += a
        parts[c].append((mod, a))
    for c, a, name in (extra or []):
        tot[c] += a
        parts[c].append((name, a))
    return tot, parts


NORMAL = "/home/sem26h3/Documents/SEM_PROJ/NORMAL/yosys/reports/croc"
DFT = "/home/sem26h3/Documents/SEM_PROJ/DEMO/yosys/reports/croc_dft_sub"

normal_tot, normal_parts = categorize(module_areas(NORMAL + "_area.rpt", NORMAL + "_area_logic.rpt"))
# The VAD macros are black boxes in the DFT run (no liberty in DEMO/technology): add their area
dft_tot, dft_parts = categorize(module_areas(DFT + "_area.rpt", DFT + "_area_logic.rpt"),
                                extra=[("User domain (VAD)", 2 * VAD_MACRO_UM2,
                                        "2x RM_IHPSG13_1P_512x32 (from liberty)")])

if __name__ == "__main__":
    for name, tot, parts in (("NORMAL", normal_tot, normal_parts), ("DFT", dft_tot, dft_parts)):
        print(f"== {name}: total {sum(tot.values()):,.0f} um2 = {sum(tot.values())/NAND2_UM2/1e3:.1f} kGE")
        for c in CATS:
            print(f"  {c:28s} {tot[c]:12,.0f}  {tot[c]/NAND2_UM2/1e3:7.1f} kGE")
            if c in ("March MBIST", "OBI cuts / JTAG isolation", "Boundary scan"):
                for m, a in sorted(parts[c], key=lambda x: -x[1]):
                    print(f"      {a:12,.1f}  {m}")
