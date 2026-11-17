# corewait-gui show OUT [--top N] [--fn SYMBOL] [--k K] [--hashes H]: the show tables in an imkit window; `corewait show
# OUT --gui` starts it with the same arguments. Close the window to exit. Needs a GPU, and -I ../mojo-imkit/src at build.
from std.collections import List
from std.os import getenv
from max.gpu.host import DeviceContext
from imkit.draw import UW, UH
from imkit.font import Font
from imkit.layer import Layer
from imkit.theme import amarbaro
from imkit.ui import Ui
from imkit.window import Window
from corewait import NC, Analysis, analyze, cause_cycles, cause_of, cname, energy_line, fail, hexs, hot, parse, pct, select, summary

comptime HALF = UW // 2
comptime FW = Float32(UW)
comptime FH = Float32(UH)
comptime FHALF = Float32(HALF)


def main() raises:
    var o = parse()
    if o.cmd != "show" or len(o.pos) < 1:
        fail("usage", "corewait-gui show OUT [--top N] [--fn SYMBOL] [--k K] [--hashes H]")
    gui(analyze(o.pos[0], o.k), o.pos[0], o.func, o.top, o.hashes)


def gui(an: Analysis, path: String, func: String, top: Int, hashes: Int) raises:
    """The show tables in an imkit window: the run line and energy, the cause shares as bars, the hottest rows. Close to exit."""
    var sel = select(an, func)
    var by_cause = cause_cycles(an, sel)
    var total = by_cause[NC]
    if total == 0:
        fail("show", "no samples in the selected functions" + (" (--fn " + func + ")" if func.byte_length() > 0 else String("")))
    # every string is built here: the frame loop allocates nothing between begin() and finish()
    var head = List[String]()
    head.append(summary(an))
    var el = energy_line(an, hashes)
    if el.byte_length() > 0:
        head.append(el)
    var names = List[String]()
    var shares = List[String]()
    for c in range(NC):
        names.append(cname(c))
        shares.append(pct(by_cause[c], total))
    var cells = List[String]()  # per hot row: addr, cyc%, cycles, cause, instruction
    var cause = List[Int]()
    for ri in hot(an, sel, top):
        ref r = an.ins[ri]
        var ci = cause_of(an, ri)
        cells.append(hexs(r.addr))
        cells.append(pct(r.cyc, total))
        cells.append(String(r.cyc))
        cells.append(cname(ci))
        cells.append(String(r.text[byte=0:min(60, r.text.byte_length())]))
        cause.append(ci)
    var u = Ui(Font(getenv("IMKIT_FONT", "/usr/share/fonts/TTF/Roboto-Medium.ttf"), [13, 16, 22]))
    u.set_theme(amarbaro())
    var ctx = DeviceContext()
    var layer = Layer(ctx, u)
    var win = Window("corewait " + path, UW, UH, UW, UH, app_id="corewait")
    var bg = List[UInt32](length=UW * UH, fill=u.theme.panel)
    var colors = List[UInt32]()  # by cause: mem, fe, dep, branch, busy
    for c in [u.theme.warn, u.theme.accent, u.theme.bad, u.theme.good, u.theme.muted]:
        colors.append(c)
    var bw = Float32(HALF - 56 - 70)  # bar: label 64, percent after it
    var cx = Float32(HALF + 24)
    while True:
        var inp = win.poll()
        if inp.quit:
            break
        u.begin(inp)
        u.panel(16, 16, FW - 16, 128, "corewait show")
        for i in range(len(head)):
            _ = u.text(32, Float32(56 + 22 * i), head[i], 0, u.theme.text)
        u.panel(16, 144, FHALF - 8, FH - 16, "cause share")
        for c in range(NC):
            var y0 = u.y
            u.bar(names[c], Float32(by_cause[c]) / Float32(total), colors[c], bw)
            _ = u.text(u.x + bw + 8, y0, shares[c], 0, u.theme.text)
        u.panel(FHALF + 8, 144, FW - 16, FH - 16, "hottest rows")
        u.clip(FHALF + 8, 144, FW - 24, FH - 16)  # a branch row names a long symbol (364 px vs 252): cut 8 px inside the border
        _ = u.text(cx, 184, "addr", 0, u.theme.muted)
        _ = u.text(cx + 80, 184, "cyc%", 0, u.theme.muted)
        _ = u.text(cx + 150, 184, "cycles", 0, u.theme.muted)
        _ = u.text(cx + 260, 184, "cause", 0, u.theme.muted)
        _ = u.text(cx + 340, 184, "instruction", 0, u.theme.muted)
        for i in range(min(len(cause), 22)):  # 22 rows fit the panel
            var y = 206 + 22 * Float32(i)
            _ = u.text(cx, y, cells[5 * i], 0, u.theme.text)
            _ = u.text(cx + 80, y, cells[5 * i + 1], 0, u.theme.text)
            _ = u.text(cx + 150, y, cells[5 * i + 2], 0, u.theme.text)
            _ = u.text(cx + 260, y, cells[5 * i + 3], 0, colors[cause[i]])
            _ = u.text(cx + 340, y, cells[5 * i + 4], 0, u.theme.text)
        u.unclip()
        u.finish()
        layer.render(u)
        win.present(Int(bg.unsafe_ptr()), Int(layer.pixels.unsafe_ptr()))


