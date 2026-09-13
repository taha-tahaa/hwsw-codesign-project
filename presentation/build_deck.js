// Build the HW/SW Co-design final project deck.
//   node build_deck.js
//
// Palette is taken from the project itself: flame graphs colour hot paths
// orange, so ORANGE = baseline / slow / hot and TEAL = optimized / fast.
// That pairing is used consistently on every before-after element, so the
// audience learns the code once and reads every later chart instantly.

const pptxgen = require("pptxgenjs");

const INK = "1B2430";   // deep graphite - dark slides
const INK2 = "2B3A4A";  // lifted graphite - cards on dark
const PAPER = "FFFFFF";
const TINT = "F3F6F8";  // card fill on light slides
const HOT = "E8833A";   // flame-graph orange: baseline / before / hot
const COOL = "2D9B8A";  // teal: optimized / after / fast
const MUTED = "6B7785";
const RULE = "DBE2E8";
const WARN = "B3543F";

const TITLE_FONT = "Cambria";
const BODY = "Calibri";
const MONO = "Courier New";

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.author = "Taha Taha, Lana Bakre";
pres.title = "HW/SW Co-design - Final Project";

const L = 0.6;              // left margin
const R = 12.73;            // right edge
const W = R - L;            // 12.13 usable width

let slideNo = 0;

function chrome(s, speaker, dark) {
  slideNo += 1;
  if (slideNo === 1) return;
  s.addText(speaker, {
    x: L, y: 6.93, w: 5, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, color: dark ? "8A97A6" : MUTED,
  });
  s.addText(String(slideNo), {
    x: R - 1, y: 6.93, w: 1, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, color: dark ? "8A97A6" : MUTED, align: "right",
  });
}

// Light content slide with a small coloured kicker above the title.
function head(s, kicker, title, kickerColor, kickerW) {
  s.addText(kicker.toUpperCase(), {
    x: L, y: 0.5, w: kickerW || W, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, bold: true, charSpacing: 1.6,
    color: kickerColor || HOT,
  });
  s.addText(title, {
    x: L, y: 0.76, w: W, h: 0.64, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 29, bold: true, color: INK,
  });
}

function card(s, x, y, w, h, fill) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.06,
    fill: { color: fill || TINT }, line: { color: RULE, width: 0.75 },
  });
}

function darkCard(s, x, y, w, h) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.06,
    fill: { color: INK2 }, line: { color: "3C4E61", width: 0.75 },
  });
}

// Numbered pill used for the O1..O5 optimization labels.
function pill(s, x, y, label, color) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w: 0.52, h: 0.3, rectRadius: 0.5,
    fill: { color }, line: { color, width: 0 },
  });
  s.addText(label, {
    x, y, w: 0.52, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, bold: true, color: "FFFFFF", align: "center",
    valign: "middle",
  });
}

function arrow(s, x, y, w, color) {
  s.addShape(pres.ShapeType.line, {
    x, y, w, h: 0,
    line: { color: color || MUTED, width: 1.75, endArrowType: "triangle" },
  });
}

function bigStat(s, x, y, w, value, label, color) {
  s.addText(value, {
    x, y, w, h: 0.72, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 40, bold: true, color, align: "center",
  });
  s.addText(label, {
    x, y: y + 0.72, w, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, color: MUTED, align: "center",
  });
}

function bullets(s, x, y, w, h, items, size) {
  s.addText(
    items.map((t, i) => ({
      text: t,
      options: { bullet: true, breakLine: i !== items.length - 1 },
    })),
    {
      x, y, w, h, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: size || 14, color: INK,
      paraSpaceAfter: 6, lineSpacing: 19,
    }
  );
}

/* ------------------------------------------------------------------ 1 */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addText("HW/SW CO-DESIGN  ·  00460882", {
    x: L, y: 1.5, w: W, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, charSpacing: 2, color: HOT,
  });
  s.addText("Making Python Fast,\nThen Making It Hardware", {
    x: L, y: 1.95, w: 8.6, h: 1.9, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 42, bold: true, color: "FFFFFF",
    lineSpacing: 46,
  });
  s.addText("Profiling two pyperformance benchmarks, optimizing them without changing a single output byte, and proposing an accelerator for each.", {
    x: L, y: 4.0, w: 8.4, h: 0.7, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "AFBECD", lineSpacing: 20,
  });
  s.addText("Taha Taha   ·   Lana Bakre", {
    x: L, y: 5.1, w: 8, h: 0.35, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 16, bold: true, color: "FFFFFF",
  });
  s.addText("Final project  ·  Technion", {
    x: L, y: 5.45, w: 8, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: "8A97A6",
  });

  darkCard(s, 9.5, 1.95, 3.25, 3.5);
  s.addText("RESULTS", {
    x: 9.75, y: 2.15, w: 2.75, h: 0.25, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, bold: true, charSpacing: 1.5, color: "8A97A6",
  });
  s.addText("pyflate", {
    x: 9.75, y: 2.5, w: 2.75, h: 0.28, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: "AFBECD",
  });
  s.addText("2.38×", {
    x: 9.75, y: 2.76, w: 2.75, h: 0.6, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 34, bold: true, color: COOL,
  });
  s.addText("raytrace", {
    x: 9.75, y: 3.55, w: 2.75, h: 0.28, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: "AFBECD",
  });
  s.addText("2.55×", {
    x: 9.75, y: 3.81, w: 2.75, h: 0.6, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 34, bold: true, color: COOL,
  });
  s.addText("Output byte-identical.\nRequirement was 7%.", {
    x: 9.75, y: 4.6, w: 2.75, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, color: "8A97A6", lineSpacing: 15,
  });
  chrome(s, "", true);
  s.addNotes("Taha. 0:20. Introduce both presenters and the one-line result. Do not explain anything yet.");
}

/* ------------------------------------------------------------------ 2 */
{
  const s = pres.addSlide();
  head(s, "the task", "Two benchmarks, chosen to disagree with each other");
  s.addText("The brief asked for 2 of 13 approved pyperformance benchmarks, ≥7% faster each. We picked a pair that stress opposite parts of the machine — because that is what lets one project motivate both accelerator paradigms from the course.", {
    x: L, y: 1.5, w: W, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: INK, lineSpacing: 19,
  });

  card(s, L, 2.3, 5.9, 3.3);
  s.addText("pyflate", {
    x: L + 0.3, y: 2.5, w: 5.3, h: 0.4, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 22, bold: true, color: INK,
  });
  s.addText("pure-Python bzip2 decompressor", {
    x: L + 0.3, y: 2.88, w: 5.3, h: 0.28, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED,
  });
  bullets(s, L + 0.3, 3.3, 5.3, 1.9, [
    "integer, control-flow, irregular memory",
    "variable-length Huffman codes",
    "bits consumed per symbol: 1 to 20",
    "→ data-dependent rate → DATAFLOW",
  ], 13);

  card(s, 6.83, 2.3, 5.9, 3.3);
  s.addText("raytrace", {
    x: 7.13, y: 2.5, w: 5.3, h: 0.4, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 22, bold: true, color: INK,
  });
  s.addText("pure-Python recursive ray tracer", {
    x: 7.13, y: 2.88, w: 5.3, h: 0.28, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED,
  });
  bullets(s, 7.13, 3.3, 5.3, 1.9, [
    "floating point, allocation bound",
    "every test the same fixed shape",
    "fixed operand count, fixed latency",
    "→ fixed cadence → SYSTOLIC ARRAY",
  ], 13);

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 5.85, w: W, h: 0.72, rectRadius: 0.06,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("A systolic array has no control circuitry — it consumes one input every cycle whether or not one is ready. That is exactly why it cannot decode Huffman codes, and exactly why it suits ray–sphere intersection.", {
    x: L + 0.3, y: 5.97, w: W - 0.6, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: "E8EDF2", italic: true,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:20. The key move: the two benchmarks were chosen for contrast, not convenience. End on the bottom strip - it sets up both hardware sections.");
}

/* ------------------------------------------------------------------ 3 */
{
  const s = pres.addSlide();
  head(s, "method", "No single tool answers both questions", COOL);
  s.addText("Lecture 4 makes the point directly: a flame graph shows you WHERE, performance counters show you WHY. We used three views, because each one lies in a different direction.", {
    x: L, y: 1.5, w: W, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: INK, lineSpacing: 19,
  });

  const cols = [
    ["perf record", "WHERE", "cycle-weighted, per Python function\n(needs CPython's -X perf trampoline)", HOT],
    ["cProfile", "HOW MANY", "call counts, which perf cannot give\n— but it charges per call, not per cycle", "7A6FA8"],
    ["perf stat", "WHY", "IPC, cache misses, branch misses\n— the mechanism behind the speedup", COOL],
  ];
  cols.forEach((c, i) => {
    const x = L + i * 4.16;
    card(s, x, 2.2, 3.8, 2.5);
    s.addShape(pres.ShapeType.ellipse, {
      x: x + 0.3, y: 2.45, w: 0.42, h: 0.42,
      fill: { color: c[3] }, line: { color: c[3], width: 0 },
    });
    s.addText(String(i + 1), {
      x: x + 0.3, y: 2.45, w: 0.42, h: 0.42, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 13, bold: true, color: "FFFFFF",
      align: "center", valign: "middle",
    });
    s.addText(c[0], {
      x: x + 0.85, y: 2.47, w: 2.8, h: 0.3, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 14, bold: true, color: INK,
    });
    s.addText(c[1], {
      x: x + 0.3, y: 3.05, w: 3.2, h: 0.34, isTextBox: true, margin: 0,
      fontFace: TITLE_FONT, fontSize: 19, bold: true, color: c[3],
    });
    s.addText(c[2], {
      x: x + 0.3, y: 3.45, w: 3.2, h: 1.0, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
    });
  });

  card(s, L, 5.0, W, 1.55, "FDF3EC");
  s.addText("The two profilers disagreed — and that was the useful part.", {
    x: L + 0.3, y: 5.15, w: W - 0.6, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("cProfile ranks move_to_front at about 8%. perf puts it at 19.28% — second overall. Instrumentation charges per CALL; sampling charges per CYCLE. move_to_front is a function that is simply slow inside, so the call-count profiler under-reports it. We rewrote our analysis around perf.", {
    x: L + 0.3, y: 5.48, w: W - 0.6, h: 0.95, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:10. This is a teaching slide. The disagreement between the two profilers is the point - do not rush the bottom box.");
}

/* ------------------------------------------------------------------ 4 */
{
  const s = pres.addSlide();
  head(s, "method", "The command in the brief does not do what it looks like", WARN);
  s.addText("Project.pdf suggests:", {
    x: L, y: 1.48, w: 4, h: 0.28, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: MUTED,
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 1.78, w: W, h: 0.5, rectRadius: 0.05,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("perf record -F 999 -g -- python3-dbg -m pyperformance run --bench <name>", {
    x: L + 0.25, y: 1.88, w: W - 0.5, h: 0.32, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 14, color: "8FE3D2",
  });

  card(s, L, 2.55, 5.9, 2.35);
  s.addText("Trap 1  ·  you profile the wrong process", {
    x: L + 0.3, y: 2.72, w: 5.3, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: WARN,
  });
  s.addText("pyperformance builds a virtualenv and re-execs the benchmark in a CHILD process, using an interpreter that is not python3-dbg unless you pass --python. perf then samples process machinery.", {
    x: L + 0.3, y: 3.1, w: 5.3, h: 1.0, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: INK, lineSpacing: 16,
  });
  s.addText("Fix: tools/profile_target.py runs the workload in-process.", {
    x: L + 0.3, y: 4.3, w: 5.3, h: 0.45, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, bold: true, color: COOL,
  });

  card(s, 6.83, 2.55, 5.9, 2.35);
  s.addText("Trap 2  ·  no Python names in the graph", {
    x: 7.13, y: 2.72, w: 5.3, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: WARN,
  });
  s.addText("Python function names need CPython's perf trampoline, -X perf, which exists only in 3.12+. naranja7 runs 3.12.3 so it works; the course QEMU guest runs 3.10, where perf shows only _PyEval_EvalFrameDefault.", {
    x: 7.13, y: 3.1, w: 5.3, h: 1.0, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: INK, lineSpacing: 16,
  });
  s.addText("Fix: detect the version; always emit cProfile as a fallback.", {
    x: 7.13, y: 4.3, w: 5.3, h: 0.45, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, bold: true, color: COOL,
  });

  card(s, L, 5.1, W, 1.4, "FDF3EC");
  s.addText("And one that cost us an afternoon", {
    x: L + 0.3, y: 5.24, w: W - 0.6, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: INK,
  });
  s.addText("The trampoline writes /tmp/perf-<pid>.map, and perf script needs that file to resolve py:: frames. A diagnostic of ours deleted /tmp between record and script — the flame graph still rendered, it had just silently become interpreter soup. Record and collapse in one pass.", {
    x: L + 0.3, y: 5.55, w: W - 0.6, h: 0.8, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: INK, lineSpacing: 17,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:10. Staff wrote that command, so be matter-of-fact, not smug. Frame it as something we hit and fixed.");
}

/* ------------------------------------------------------------------ 5 */
{
  const s = pres.addSlide();
  head(s, "benchmark 1  ·  pyflate", "A bzip2 decompressor written entirely in Python");
  s.addText("67,562 compressed bytes in, 399,360 bytes out. The benchmark carries its own MD5, and we used it as the correctness oracle for the whole project.", {
    x: L, y: 1.5, w: 7.6, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: INK, lineSpacing: 19,
  });

  const stages = [
    ["Huffman\ndecode", "variable-length\nprefix codes", HOT],
    ["Move-to-\nfront", "alphabet reordered\nafter every symbol", HOT],
    ["Inverse\nBWT", "pointer chase\nend = T[end]", "7A6FA8"],
    ["RLE\nexpand", "runs of ≥ 4\nidentical bytes", MUTED],
  ];
  stages.forEach((st, i) => {
    const x = L + i * 3.12;
    card(s, x, 2.35, 2.75, 1.75);
    s.addText(st[0], {
      x: x + 0.2, y: 2.55, w: 2.35, h: 0.65, isTextBox: true, margin: 0,
      fontFace: TITLE_FONT, fontSize: 17, bold: true, color: st[2],
      lineSpacing: 20,
    });
    s.addText(st[1], {
      x: x + 0.2, y: 3.25, w: 2.35, h: 0.7, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, color: MUTED, lineSpacing: 15,
    });
    if (i < 3) arrow(s, x + 2.8, 3.2, 0.26);
  });

  s.addText("Why a benchmark would implement bzip2 in Python at all", {
    x: L, y: 4.45, w: W, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("It is deliberate. Calling libbz2 would measure C, not the interpreter. Every import is stdlib — hashlib, struct, os. So this benchmark measures Python executing bit manipulation and table lookups, which is precisely what makes it interesting to optimize and to accelerate.", {
    x: L, y: 4.8, w: W, h: 0.75, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  s.addText("This also rules out an easy cheat: swapping in libbz2 would have scored a huge speedup while measuring nothing and teaching nothing. We did not do it.", {
    x: L, y: 5.7, w: W, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, italic: true, color: COOL, lineSpacing: 18,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 0:50. Keep it short - this is orientation. The last line pre-empts an obvious question.");
}

/* ------------------------------------------------------------------ 6 */
{
  const s = pres.addSlide();
  head(s, "benchmark 1  ·  analysis", "Where the time actually goes");
  s.addText("perf, cycle-weighted, with Python function names resolved. Measured on naranja7.", {
    x: L, y: 1.5, w: 7.4, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: MUTED,
  });

  const rows = [
    ["decode_huffman_block", 21.25],
    ["move_to_front", 19.28],
    ["HuffmanTable.find_next_symbol", 13.22],
    ["RBitfield.readbits", 8.49],
    ["bwt_transform", 8.45],
    ["RBitfield.snoopbits", 8.17],
    ["bwt_reverse", 5.51],
    ["BitfieldBase._mask", 5.49],
  ];
  const barX = 4.6, barMax = 3.9;
  rows.forEach((r, i) => {
    const y = 1.95 + i * 0.46;
    s.addText(r[0], {
      x: L, y, w: 3.9, h: 0.34, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 11, color: INK, valign: "middle",
    });
    s.addShape(pres.ShapeType.rect, {
      x: barX, y: y + 0.07, w: (r[1] / 22) * barMax, h: 0.2,
      fill: { color: HOT }, line: { color: HOT, width: 0 },
    });
    s.addText(r[1].toFixed(2) + "%", {
      x: barX + barMax + 0.12, y, w: 0.85, h: 0.34, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, bold: true, color: INK, valign: "middle",
    });
  });

  card(s, 9.7, 1.95, 3.03, 3.7);
  s.addText("GROUPED BY STAGE", {
    x: 9.95, y: 2.12, w: 2.55, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, bold: true, charSpacing: 1.2, color: MUTED,
  });
  const grp = [["Huffman decode", "37.4%"], ["Move-to-front", "19.3%"],
               ["Inverse BWT", "14.0%"], ["decode loop body", "21.3%"]];
  grp.forEach((g, i) => {
    const y = 2.5 + i * 0.75;
    s.addText(g[1], {
      x: 9.95, y, w: 2.55, h: 0.42, isTextBox: true, margin: 0,
      fontFace: TITLE_FONT, fontSize: 22, bold: true, color: INK,
    });
    s.addText(g[0], {
      x: 9.95, y: y + 0.4, w: 2.55, h: 0.26, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, color: MUTED,
    });
  });

  s.addText("3,185,453 Python function calls to decompress 400 KB.  That is the number to keep in your head for the next slide.", {
    x: L, y: 5.85, w: W, h: 0.4, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:10. Read the top three. Flag that move_to_front is second - that is the perf-vs-cProfile disagreement showing up. End on the call count.");
}

/* ------------------------------------------------------------------ 7 */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addText("BENCHMARK 1  ·  THE TURNING POINT", {
    x: L, y: 0.5, w: W, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, bold: true, charSpacing: 1.6, color: HOT,
  });
  s.addText("The obvious diagnosis was wrong", {
    x: L, y: 0.78, w: W, h: 0.7, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF",
  });
  s.addText("find_next_symbol() walks a sorted table linearly, so everyone's first conclusion is \"the scan is too deep\". We almost optimized the wrong thing.", {
    x: L, y: 1.58, w: 11.5, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "AFBECD", lineSpacing: 19,
  });

  darkCard(s, L, 2.35, 3.85, 1.85);
  s.addText("148,271", {
    x: L + 0.25, y: 2.6, w: 3.35, h: 0.62, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 34, bold: true, color: "FFFFFF",
  });
  s.addText("calls to find_next_symbol", {
    x: L + 0.25, y: 3.25, w: 3.35, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: "AFBECD",
  });

  darkCard(s, 4.75, 2.35, 3.85, 1.85);
  s.addText("341,601", {
    x: 5.0, y: 2.6, w: 3.35, h: 0.62, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 34, bold: true, color: "FFFFFF",
  });
  s.addText("calls to snoopbits", {
    x: 5.0, y: 3.25, w: 3.35, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: "AFBECD",
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: 8.9, y: 2.35, w: 3.83, h: 1.85, rectRadius: 0.06,
    fill: { color: HOT }, line: { color: HOT, width: 0 },
  });
  s.addText("2.3", {
    x: 9.15, y: 2.55, w: 3.35, h: 0.72, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 42, bold: true, color: "1B2430",
  });
  s.addText("probes per symbol — not ~250", {
    x: 9.15, y: 3.3, w: 3.35, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, bold: true, color: "3A2412",
  });

  s.addText("Why: move-to-front keeps the hot symbols on short codes, so the scan almost always exits after two probes.", {
    x: L, y: 4.45, w: 11.9, h: 0.4, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "E8EDF2",
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 5.05, w: W, h: 1.45, rectRadius: 0.06,
    fill: { color: "2B3A4A" }, line: { color: COOL, width: 1.5 },
  });
  s.addText("So the cost was never scan depth. Decoding ONE symbol cost about seven Python function calls: find_next_symbol, ~2.3 snoopbits, a readbits, and several _mask. The fix had to remove CALLS, not iterations — the opposite of what the benchmark's own source comment suggests.", {
    x: L + 0.3, y: 5.22, w: W - 0.6, h: 1.1, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "FFFFFF", lineSpacing: 20,
  });
  chrome(s, "Taha", true);
  s.addNotes("Taha. 1:30. THE most important slide in the pyflate half. Pause after '2.3, not 250'. If short on time elsewhere, protect this slide.");
}

/* ------------------------------------------------------------------ 8 */
{
  const s = pres.addSlide();
  head(s, "benchmark 1  ·  optimization", "Five changes, all removing interpreter work");
  s.addText("Not one of these changes the algorithm. bzip2 is still bzip2; the decoded bytes are identical.", {
    x: L, y: 1.5, w: W, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: MUTED,
  });

  const opts = [
    ["O1", "Canonical Huffman decode", "The codes were already canonical, so limit/base/perm tables decode a symbol arithmetically — no table walk, no per-candidate object access.", COOL],
    ["O2", "Inlined bit reader", "Whole file read once; the bit cursor lives in local variables inside the hot loop. Decoding a symbol now makes zero function calls.", COOL],
    ["O3", "Inverse BWT", "256-bin histogram + prefix sum replaces sorted(L) and 256 find() scans; output written into a preallocated bytearray.", MUTED],
    ["O4", "Move-to-front", "list.pop + list.insert is one C-level memmove, replacing three slices and two concatenations per symbol.", MUTED],
    ["O5", "Output assembly", "One bytearray instead of ~767,000 one-byte bytes objects joined at the end.", MUTED],
  ];
  opts.forEach((o, i) => {
    const y = 1.92 + i * 0.90;
    pill(s, L, y + 0.05, o[0], o[3]);
    s.addText(o[1], {
      x: L + 0.72, y, w: 3.5, h: 0.32, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 14, bold: true, color: INK,
    });
    s.addText(o[2], {
      x: L + 0.72, y: 0.3 + y, w: 11.3, h: 0.58, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
    });
  });

  s.addText("O1 and O2 cannot be separated in measurement: the canonical decoder is what makes inlining possible, and the inlining is what turns it into wall-clock time.", {
    x: L, y: 6.42, w: W, h: 0.45, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, italic: true, color: COOL,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:10. Do not read all five. Spend the time on O1 and O2 and say the rest are bookkeeping. The honesty note at the bottom matters - say it.");
}

/* ------------------------------------------------------------------ 9 */
{
  const s = pres.addSlide();
  head(s, "benchmark 1  ·  result", "2.38× faster — and the counters say why", COOL);

  bigStat(s, L, 1.5, 2.6, "733 ms", "baseline", HOT);
  arrow(s, 3.35, 1.85, 0.55, MUTED);
  bigStat(s, 4.0, 1.5, 2.6, "309 ms", "optimized", COOL);
  s.addShape(pres.ShapeType.roundRect, {
    x: 7.0, y: 1.45, w: 2.6, h: 1.05, rectRadius: 0.06,
    fill: { color: COOL }, line: { color: COOL, width: 0 },
  });
  s.addText("2.38×", {
    x: 7.0, y: 1.52, w: 2.6, h: 0.6, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF", align: "center",
  });
  s.addText("57.9% cut  ·  t = 620", {
    x: 7.0, y: 2.1, w: 2.6, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, color: "D6F0EA", align: "center",
  });
  s.addText("pyperf --rigorous\n±1–2% error bars\nidle, pinned machine", {
    x: 9.95, y: 1.5, w: 2.8, h: 1.0, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 17,
  });

  const hdr = ["", "baseline", "optimized", "ratio"];
  const data = [
    ["instructions", "24.81 G", "10.74 G", "2.31× fewer"],
    ["IPC", "2.73", "2.85", "unchanged"],
    ["cache-misses", "1.95 M", "187 K", "10.4× fewer"],
    ["branch-misses", "19.4 M", "3.58 M", "5.4× fewer"],
  ];
  const cw = [3.3, 2.5, 2.5, 2.6];
  let cx = L;
  hdr.forEach((h, i) => {
    s.addText(h, {
      x: cx, y: 2.95, w: cw[i], h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, bold: true, color: MUTED,
    });
    cx += cw[i];
  });
  data.forEach((row, r) => {
    const y = 3.3 + r * 0.42;
    if (row[0] === "IPC") {
      s.addShape(pres.ShapeType.rect, {
        x: L - 0.1, y: y - 0.04, w: 11.1, h: 0.4,
        fill: { color: "FDF3EC" }, line: { color: "FDF3EC", width: 0 },
      });
    }
    let x = L;
    row.forEach((c, i) => {
      s.addText(c, {
        x, y, w: cw[i], h: 0.34, isTextBox: true, margin: 0,
        fontFace: i === 0 ? MONO : BODY, fontSize: 12,
        bold: row[0] === "IPC", color: i === 3 ? COOL : INK, valign: "middle",
      });
      x += cw[i];
    });
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 5.25, w: W, h: 1.3, rectRadius: 0.06,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("IPC barely moved. The machine did not get smarter — it was asked to do less.", {
    x: L + 0.3, y: 5.4, w: W - 0.6, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 15, bold: true, color: HOT,
  });
  s.addText("Instructions retired fell 2.31× against a 2.38× speedup. Those two numbers matching is the hardware-level proof that the win came from deleting interpreter work — frames, argument tuples, temporary objects — exactly as the call-count analysis predicted. Nothing here was won by being clever with the microarchitecture.", {
    x: L + 0.3, y: 5.75, w: W - 0.6, h: 0.7, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: "E8EDF2", lineSpacing: 17,
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 1:20. Land the IPC row. This is the strongest single piece of evidence in the whole project - instructions fell in near-exact proportion to the runtime.");
}

/* ------------------------------------------------------------------ 10 */
{
  const s = pres.addSlide();
  head(s, "benchmark 1  ·  hardware", "A dataflow decoder: 20 comparators, one encoder");

  s.addText("In software, canonical decoding is a short serial loop — one iteration per extra code length. In hardware all 20 candidate lengths are evaluated at once:", {
    x: L, y: 1.45, w: 7.15, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 2.08, w: 7.15, h: 1.5, rectRadius: 0.05,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("for L in 1..20  (in parallel):\n    code_L = window[19 -: L]\n    hit_L  = code_L <= limit[L]\nsel = lowest L with hit_L      // priority encoder\nsym = perm[code_sel - base[sel]]", {
    x: L + 0.25, y: 2.2, w: 6.65, h: 1.3, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 11.5, color: "8FE3D2", lineSpacing: 15,
  });
  s.addText("Huffman codes are prefix-free, so the SHORTEST accepting length is the unique correct one. That is what makes a priority encoder exact — no backtracking. One symbol per cycle, independent of code length.", {
    x: L, y: 3.72, w: 7.15, h: 0.8, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: INK, lineSpacing: 17,
  });

  const blocks = [
    ["bit_window", "64-bit, variable retire"],
    ["huffman_decoder", "1 symbol / cycle"],
    ["mtf_unit", "256-entry 1-cycle shift"],
    ["bwt_reverse_engine", "on-chip SRAM chase"],
  ];
  blocks.forEach((b, i) => {
    const y = 1.5 + i * 1.08;
    card(s, 8.2, y, 4.53, 0.88);
    s.addText(b[0], {
      x: 8.45, y: y + 0.1, w: 4.0, h: 0.3, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 12, bold: true, color: INK,
    });
    s.addText(b[1], {
      x: 8.45, y: y + 0.42, w: 4.0, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, color: MUTED,
    });
    if (i < 3) {
      s.addShape(pres.ShapeType.line, {
        x: 10.45, y: y + 0.88, w: 0, h: 0.2,
        line: { color: MUTED, width: 1.75, endArrowType: "triangle" },
      });
    }
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 4.7, w: 7.15, h: 1.85, rectRadius: 0.06,
    fill: { color: TINT }, line: { color: RULE, width: 0.75 },
  });
  s.addText("Verified, not asserted", {
    x: L + 0.28, y: 4.85, w: 6.6, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: INK,
  });
  bullets(s, L + 0.28, 5.18, 6.6, 1.25, [
    "Golden model: the RTL decision function, reimplemented in Python, decoded all 148,271 real symbols — MD5 matches",
    "tb_huffman_decoder checks the symbol AND the retired bit count",
    "Simulated under Icarus Verilog 12.0 on naranja7",
  ], 11.5);
  chrome(s, "Taha");
  s.addNotes("Taha. 1:20. The one idea: a serial loop becomes 20 parallel comparators. Say WHY the priority encoder is exact - prefix-free codes. Then hand over to Lana.");
}

/* ------------------------------------------------------------------ 11 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  raytrace", "A recursive ray tracer, 100×100, eight objects");

  s.addText("One large sphere, six small spheres, a checkerboard plane, two point lights. Lambert diffuse plus a specular reflection, recursing to depth 3.", {
    x: L, y: 1.5, w: 7.3, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: INK, lineSpacing: 19,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 2.2, w: 7.3, h: 2.6, rectRadius: 0.05,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("per pixel:", {
    x: L + 0.3, y: 2.35, w: 3, h: 0.28, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, color: "8A97A6",
  });
  s.addText("build primary ray          → normalized()  [sqrt]\ntest against all 8 objects → nearest hit\nshade it:\n    1 reflection ray       → recurse\n    2 lights × shadow rays → 8 objects each", {
    x: L + 0.3, y: 2.68, w: 6.7, h: 1.9, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, color: "8FE3D2", lineSpacing: 20,
  });

  card(s, 8.0, 2.2, 4.73, 2.6);
  s.addText("18", {
    x: 8.25, y: 2.38, w: 4.2, h: 0.82, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 44, bold: true, color: HOT,
  });
  s.addText("intersection tests per pixel", {
    x: 8.25, y: 3.24, w: 4.2, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: INK,
  });
  s.addText("Not 8. The extra ones are shadow rays and reflection rays — 179,457 calls for 10,000 pixels. Intersection is THE kernel, and that is what we later put in hardware.", {
    x: 8.25, y: 3.6, w: 4.2, h: 1.05, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
  });

  s.addText("Why this one, next to a decompressor", {
    x: L, y: 5.1, w: W, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("pyflate is integer and control-flow bound. This is floating point and allocation bound. Same interpreter, opposite bottleneck — and, as we will show, opposite accelerator.", {
    x: L, y: 5.45, w: W, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 0:50. Your opening - re-establish yourself. The 18-per-pixel number is the hook; it justifies the hardware choice later.");
}

/* ------------------------------------------------------------------ 12 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  analysis", "Half the runtime is in three-float wrappers");

  const rows = [
    ["Point.__sub__", 17.25, true],
    ["Vector.dot", 15.68, true],
    ["Sphere.intersectionTime", 11.76, false],
    ["Scene._lightIsVisible", 7.80, false],
    ["Vector.scale", 6.59, true],
    ["Scene.rayColour", 4.95, false],
    ["Vector.__init__", 4.72, true],
    ["Vector.normalized", 3.21, true],
  ];
  const barX = 4.6, barMax = 3.6;
  rows.forEach((r, i) => {
    const y = 1.55 + i * 0.46;
    s.addText(r[0], {
      x: L, y, w: 3.9, h: 0.34, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 11, color: INK, valign: "middle",
    });
    s.addShape(pres.ShapeType.rect, {
      x: barX, y: y + 0.07, w: (r[1] / 18) * barMax, h: 0.2,
      fill: { color: r[2] ? HOT : "C3CBD3" },
      line: { color: r[2] ? HOT : "C3CBD3", width: 0 },
    });
    s.addText(r[1].toFixed(2) + "%", {
      x: barX + barMax + 0.12, y, w: 0.85, h: 0.34, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, bold: true, color: INK, valign: "middle",
    });
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: 9.5, y: 1.55, w: 3.23, h: 2.2, rectRadius: 0.06,
    fill: { color: HOT }, line: { color: HOT, width: 0 },
  });
  s.addText("47.45%", {
    x: 9.75, y: 1.8, w: 2.75, h: 0.72, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 36, bold: true, color: "1B2430",
  });
  s.addText("of runtime is in Vector/Point operator wrappers (orange bars), not in the ray tracing algorithm", {
    x: 9.75, y: 2.55, w: 2.75, h: 1.05, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11.5, color: "3A2412", lineSpacing: 15,
  });

  card(s, 9.5, 3.95, 3.23, 1.7);
  s.addText("509,871", {
    x: 9.75, y: 4.1, w: 2.75, h: 0.5, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 24, bold: true, color: INK,
  });
  s.addText("calls to Vector.dot — every one of them starts with a mustBeVector() type assertion", {
    x: 9.75, y: 4.6, w: 2.75, h: 0.9, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, color: MUTED, lineSpacing: 15,
  });

  s.addText("The leaves of this flame graph are type checks and operator dispatch — not floating-point work. 307 function calls per pixel.", {
    x: L, y: 5.88, w: W, h: 0.52, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:10. Point at the orange bars as a group - that is the 47%. The dynamic type checks cost more than the arithmetic they guard.");
}

/* ------------------------------------------------------------------ 13 */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addText("BENCHMARK 2  ·  THE FINDING", {
    x: L, y: 0.5, w: W, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, bold: true, charSpacing: 1.6, color: HOT,
  });
  s.addText("One line, in the wrong place, cost 49%", {
    x: L, y: 0.78, w: W, h: 0.7, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF",
  });

  s.addText("BEFORE", {
    x: L, y: 1.6, w: 5.8, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, bold: true, charSpacing: 1.4, color: HOT,
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 1.88, w: 5.85, h: 1.5, rectRadius: 0.05,
    fill: { color: "2B3A4A" }, line: { color: HOT, width: 1.25 },
  });
  s.addText("for (o, s) in self.objects:\n    t = o.intersectionTime(\n            Ray(p, l - p))   ← inside", {
    x: L + 0.25, y: 2.02, w: 5.35, h: 1.2, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, color: "FFD9B8", lineSpacing: 19,
  });

  s.addText("AFTER", {
    x: 6.9, y: 1.6, w: 5.8, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, bold: true, charSpacing: 1.4, color: COOL,
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: 6.9, y: 1.88, w: 5.83, h: 1.5, rectRadius: 0.05,
    fill: { color: "2B3A4A" }, line: { color: COOL, width: 1.25 },
  });
  s.addText("shadowRay = Ray(p, l - p)   ← hoisted\nfor (o, s) in self.objects:\n    t = o.intersectionTime(shadowRay)", {
    x: 7.15, y: 2.02, w: 5.33, h: 1.2, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, color: "A9EDDD", lineSpacing: 19,
  });

  s.addText("Ray(p, l - p) does not depend on o. Its constructor calls normalized() → magnitude() → sqrt(). So the same shadow ray, square root included, was rebuilt 8 times per light per shading point.", {
    x: L, y: 3.6, w: 12.0, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "E8EDF2", lineSpacing: 19,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 4.4, w: 5.85, h: 2.0, rectRadius: 0.06,
    fill: { color: "2B3A4A" }, line: { color: "3C4E61", width: 0.75 },
  });
  s.addText("+49%", {
    x: L + 0.3, y: 4.6, w: 5.2, h: 0.65, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 36, bold: true, color: HOT,
  });
  s.addText("slower when we revert just this one hoist. A three-line change, with no cleverness in it at all.", {
    x: L + 0.3, y: 5.3, w: 5.2, h: 0.85, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: "AFBECD", lineSpacing: 18,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: 6.9, y: 4.4, w: 5.83, h: 2.0, rectRadius: 0.06,
    fill: { color: "2B3A4A" }, line: { color: COOL, width: 1.5 },
  });
  s.addText("The lesson", {
    x: 7.2, y: 4.58, w: 5.2, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: COOL,
  });
  s.addText("This is a plain bug, not a subtle trade-off — and reading the code at normal speed does not reveal it. Profiling did. That is the whole argument for measuring before optimizing.", {
    x: 7.2, y: 4.92, w: 5.2, h: 1.25, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: "E8EDF2", lineSpacing: 18,
  });
  chrome(s, "Lana", true);
  s.addNotes("Lana. 1:20. Your strongest slide. Let the before/after sit for a beat before saying 49%. Protect this slide if running late.");
}

/* ------------------------------------------------------------------ 14 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  optimization", "What we changed — and what each change was worth");

  s.addText("We measured each one by ABLATION: take the finished build and revert exactly one optimization. Marginal costs do not sum to the total, because the optimizations interact — so this is a ranking, not a decomposition.", {
    x: L, y: 1.45, w: W, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });

  const abl = [
    ["O3 / O5", "Inlined intersection, cached radius²", 51, COOL],
    ["O1", "Shadow-ray hoist (previous slide)", 49, COOL],
    ["O2", "Running minimum, no per-ray list", 7, "C3CBD3"],
  ];
  abl.forEach((a, i) => {
    const y = 2.15 + i * 0.95;
    card(s, L, y, 8.1, 0.8);
    s.addText(a[0], {
      x: L + 0.25, y: y + 0.12, w: 1.1, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 13, bold: true, color: INK,
    });
    s.addText(a[1], {
      x: L + 1.45, y: y + 0.12, w: 4.3, h: 0.55, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED,
    });
    s.addShape(pres.ShapeType.rect, {
      x: L + 5.85, y: y + 0.28, w: (a[2] / 55) * 1.5, h: 0.24,
      fill: { color: a[3] }, line: { color: a[3], width: 0 },
    });
    s.addText("+" + a[2] + "%", {
      x: L + 7.4, y: y + 0.12, w: 0.65, h: 0.55, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 14, bold: true, color: INK, align: "right",
    });
  });

  card(s, 9.0, 2.15, 3.73, 2.75, "FDF3EC");
  s.addText("The counter-intuitive one", {
    x: 9.25, y: 2.32, w: 3.25, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: INK,
  });
  s.addText("Removing ~200,000 allocations per frame — the thing you instinctively reach for — was worth only 7%.\n\nThe type-check and call overhead cost seven times more than the garbage did.", {
    x: 9.25, y: 2.68, w: 3.25, h: 2.0, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: INK, lineSpacing: 17,
  });

  s.addText("Everything preserves the baseline's floating-point operand ORDER and GROUPING — FP addition is not associative, and that is what keeps the image bit-identical.", {
    x: L, y: 5.25, w: W, h: 0.45, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: COOL, lineSpacing: 18,
  });
  s.addText("Also deliberately NOT fixed: CheckerboardSurface.baseColourAt() calls v.scale() and discards the result, so checkSize never takes effect. It is a real bug in the original — but fixing it would change the image, and the brief requires identical output. We flagged it in the report instead of silently preserving it.", {
    x: L, y: 5.75, w: W, h: 0.75, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 17,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:20. Explain ablation in one sentence. The 7% allocation result is the teaching moment - intuition was measurably wrong.");
}

/* ------------------------------------------------------------------ 15 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  result", "2.55× faster — and a trap in reading counters", COOL);

  bigStat(s, L, 1.45, 2.6, "554 ms", "baseline", HOT);
  arrow(s, 3.35, 1.8, 0.55, MUTED);
  bigStat(s, 4.0, 1.45, 2.6, "217 ms", "optimized", COOL);
  s.addShape(pres.ShapeType.roundRect, {
    x: 7.0, y: 1.4, w: 2.6, h: 1.05, rectRadius: 0.06,
    fill: { color: COOL }, line: { color: COOL, width: 0 },
  });
  s.addText("2.55×", {
    x: 7.0, y: 1.47, w: 2.6, h: 0.6, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF", align: "center",
  });
  s.addText("60.8% cut  ·  t = 671", {
    x: 7.0, y: 2.05, w: 2.6, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, color: "D6F0EA", align: "center",
  });
  s.addText("IPC 2.44 → 2.52\ninstructions 2.57× fewer\nSame story as pyflate.", {
    x: 9.95, y: 1.45, w: 2.8, h: 1.0, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 17,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 2.75, w: W, h: 3.6, rectRadius: 0.06,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("One row looks like a regression — and is not", {
    x: L + 0.35, y: 2.95, w: 11.4, h: 0.35, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 16, bold: true, color: HOT,
  });

  const m = [
    ["cache-miss RATE", "1.20%", "1.40%", "WORSE"],
    ["cache REFERENCES", "10.7 M", "3.48 M", "3.08× fewer"],
    ["cache MISSES", "129 K", "48.6 K", "2.65× fewer"],
  ];
  const mw = [3.5, 2.4, 2.4, 3.0];
  m.forEach((row, r) => {
    const y = 3.5 + r * 0.48;
    let x = L + 0.35;
    row.forEach((c, i) => {
      s.addText(c, {
        x, y, w: mw[i], h: 0.35, isTextBox: true, margin: 0,
        fontFace: i === 0 ? MONO : BODY, fontSize: 12.5,
        color: i === 3 ? (r === 0 ? HOT : COOL) : "E8EDF2",
        bold: i === 3, valign: "middle",
      });
      x += mw[i];
    });
  });

  s.addText("The optimized code makes 3.08× fewer cache REFERENCES, because it no longer allocates and chases a swarm of short-lived Vector objects. The references that remain are the genuinely cold ones — so the ratio of misses to references rises even though the machine stalls far less often.", {
    x: L + 0.35, y: 5.0, w: 11.4, h: 0.75, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: "AFBECD", lineSpacing: 17,
  });
  s.addText("This is the same trap the course's own perf tutorial sets with row-major vs column-major traversal. A rate is not a performance metric; misses per unit of work is.", {
    x: L + 0.35, y: 5.78, w: 11.4, h: 0.52, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, italic: true, color: "FFFFFF",
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:20. Tie it explicitly to tutorial 2 - row vs column major. Staff will recognize their own example and it shows we connected the material.");
}

/* ------------------------------------------------------------------ 16 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  hardware", "A weight-stationary systolic array");

  s.addText("Every intersection test is the same fixed shape — 3 subtractions, 6 multiplies, 4 adds, one square root. Fixed operand count, fixed latency, no data-dependent control. That is exactly what a systolic array wants.", {
    x: L, y: 1.45, w: W, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });

  for (let i = 0; i < 4; i++) {
    const x = L + i * 1.62;
    s.addShape(pres.ShapeType.roundRect, {
      x, y: 2.2, w: 1.42, h: 1.15, rectRadius: 0.05,
      fill: { color: i === 3 ? "C3CBD3" : INK2 },
      line: { color: "3C4E61", width: 0.75 },
    });
    s.addText(i === 3 ? "PE7" : "PE" + i, {
      x, y: 2.32, w: 1.42, h: 0.28, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 12, bold: true,
      color: i === 3 ? INK : "FFFFFF", align: "center",
    });
    s.addText(i === 3 ? "···" : "cx cy\ncz r²", {
      x, y: 2.62, w: 1.42, h: 0.6, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 10, color: i === 3 ? MUTED : "AFBECD",
      align: "center", lineSpacing: 13,
    });
  }
  s.addText("sphere parameters preloaded once per frame  ·  rays stream through", {
    x: L, y: 3.42, w: 6.5, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, italic: true, color: MUTED,
  });

  s.addShape(pres.ShapeType.line, {
    x: 6.9, y: 2.75, w: 0.45, h: 0,
    line: { color: MUTED, width: 1.75, endArrowType: "triangle" },
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: 7.45, y: 2.2, w: 2.4, h: 1.15, rectRadius: 0.05,
    fill: { color: HOT }, line: { color: HOT, width: 0 },
  });
  s.addText("fp32_sqrt", {
    x: 7.45, y: 2.42, w: 2.4, h: 0.3, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, bold: true, color: "1B2430", align: "center",
  });
  s.addText("24 stages · SHARED", {
    x: 7.45, y: 2.74, w: 2.4, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10.5, color: "3A2412", align: "center",
  });
  s.addShape(pres.ShapeType.line, {
    x: 9.95, y: 2.75, w: 0.4, h: 0,
    line: { color: MUTED, width: 1.75, endArrowType: "triangle" },
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: 10.45, y: 2.2, w: 2.28, h: 1.15, rectRadius: 0.05,
    fill: { color: COOL }, line: { color: COOL, width: 0 },
  });
  s.addText("nearest hit", {
    x: 10.45, y: 2.42, w: 2.28, h: 0.3, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, bold: true, color: "FFFFFF", align: "center",
  });
  s.addText("keeps the tie-break", {
    x: 10.45, y: 2.74, w: 2.28, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10.5, color: "D6F0EA", align: "center",
  });

  card(s, L, 3.95, 5.9, 2.5);
  s.addText("This is the TPU trick", {
    x: L + 0.28, y: 4.12, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("Sphere parameters are weight-stationary: preloaded into the PEs once per frame while rays stream past — structurally the same as the TPU preloading weights and streaming activations. We took the pattern straight from the Accelerator Design Patterns lecture.", {
    x: L + 0.28, y: 4.48, w: 5.3, h: 1.8, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: INK, lineSpacing: 17,
  });

  card(s, 6.83, 3.95, 5.9, 2.5, "FDF3EC");
  s.addText("Amdahl, stated honestly", {
    x: 7.11, y: 4.12, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("Intersection is 36.02% of the OPTIMIZED runtime. So even an infinitely fast intersection unit caps the whole-frame speedup at 1.56×. We report that instead of the ~10,000× kernel ratio, which would be meaningless. A real product would have to move shading onto the accelerator too — which is the path GPUs actually took.", {
    x: 7.11, y: 4.48, w: 5.3, h: 1.8, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: INK, lineSpacing: 17,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:20. Two things to land: weight-stationary = the TPU pattern, and the Amdahl bound. The honesty about 1.56x will earn more credit than a big number would.");
}

/* ------------------------------------------------------------------ 17 */
{
  const s = pres.addSlide();
  head(s, "benchmark 2  ·  hardware", "The square root is the real design decision");

  s.addText("Not the multipliers. fp32_sqrt is 24 pipeline stages — by far the largest block — so whether it is shared or replicated sets both the throughput and roughly half the array area.", {
    x: L, y: 1.45, w: W, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13.5, color: INK, lineSpacing: 18,
  });

  card(s, L, 2.15, 5.9, 2.15);
  s.addText("Shared  (what we built)", {
    x: L + 0.3, y: 2.32, w: 5.3, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 15, bold: true, color: COOL,
  });
  s.addText("1 sqrt unit  ·  1 ray / 8 cycles", {
    x: L + 0.3, y: 2.7, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 13, color: INK,
  });
  s.addText("Smallest area. The sqrt sets the throughput: 8 spheres must drain through one pipeline before the next ray enters.", {
    x: L + 0.3, y: 3.05, w: 5.3, h: 1.05, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
  });

  card(s, 6.83, 2.15, 5.9, 2.15);
  s.addText("Replicated  (also buildable)", {
    x: 7.13, y: 2.32, w: 5.3, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 15, bold: true, color: HOT,
  });
  s.addText("8 sqrt units  ·  1 ray / 1 cycle", {
    x: 7.13, y: 2.7, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 13, color: INK,
  });
  s.addText("8× the throughput for roughly double the total array area. The design is parameterized, so both points on the curve are real.", {
    x: 7.13, y: 3.05, w: 5.3, h: 1.05, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
  });

  s.addText("A second knob: accuracy against area", {
    x: L, y: 4.5, w: W, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("Our root truncates rather than rounds. Measured against math.sqrt over 6,008 samples: 1.16 ulp worst case. A 25th stage plus a rounding incrementer brings that to 0.69 ulp. We kept truncation, because 1 ulp of a distance cannot move an 8-bit colour channel — but it does mean this accelerator is NOT bit-exact, unlike the pyflate one.", {
    x: L, y: 4.85, w: W, h: 0.95, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  s.addText("And one place where precision is not negotiable: bfloat16 would halve the multiplier area, but 8 mantissa bits cannot survive the cancellation in (cc − v·v). We rejected it.", {
    x: L, y: 5.95, w: W, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, italic: true, color: COOL, lineSpacing: 17,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:00. The brief asks for performance/area/power trade-offs - this slide IS that requirement. If late, state the shared-vs-replicated trade and skip the ulp numbers.");
}

/* ------------------------------------------------------------------ 18 */
{
  const s = pres.addSlide();
  head(s, "verification", "We simulated the RTL — and it was wrong", WARN);

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 1.45, w: W, h: 1.85, rectRadius: 0.06,
    fill: { color: INK }, line: { color: WARN, width: 1.5 },
  });
  s.addText("tb_ray_sphere failed on its second test vector", {
    x: L + 0.35, y: 1.62, w: 11.4, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 15, bold: true, color: HOT,
  });
  s.addText("2 + 3  →  6.5          9 − 4  →  2.5", {
    x: L + 0.35, y: 2.0, w: 5.5, h: 0.35, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 15, color: "FFD9B8",
  });
  s.addText("fp32_add had two coupled off-by-one errors: the carry path normalized the leading one to bit 26 while the leading-zero path normalized it to bit 27 — and the mantissa slice matched neither convention. The module had been written carefully and reviewed. It was still flatly wrong.", {
    x: L + 0.35, y: 2.42, w: 11.4, h: 0.8, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: "E8EDF2", lineSpacing: 17,
  });

  s.addText("Three hand-picked vectors were enough to MISS it, so we added 400 randomized ones — a quarter of them near-cancelling subtractions, the case that exercises the long normalize path where the bug lived.", {
    x: L, y: 3.45, w: W, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });

  const checks = [
    "correctness gate — both benchmarks byte / bit-identical",
    "golden model — all 148,271 real Huffman symbols",
    "sqrt model — 6,008 samples, 1.16 ulp",
    "tb_huffman_decoder — symbol and retired bit count",
    "tb_bit_window — 12 irregular retires, 1 to 20 bits",
    "bzip2_accel_top — elaborates",
    "tb_ray_sphere — single PE, bit-exact",
    "tb_ray_array — nearest hit across 8 spheres",
    "tb_fp_random — 400 vectors, bit-exact",
  ];
  checks.forEach((c, i) => {
    const col = i % 2;
    const row = Math.floor(i / 2);
    const x = L + col * 6.1;
    const y = 4.1 + row * 0.42;
    s.addShape(pres.ShapeType.ellipse, {
      x, y: y + 0.06, w: 0.2, h: 0.2,
      fill: { color: COOL }, line: { color: COOL, width: 0 },
    });
    s.addText(c, {
      x: x + 0.3, y, w: 5.7, h: 0.32, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11.5, color: INK, valign: "middle",
    });
  });

  s.addText("9 / 9 green  ·  ./tools/regress.sh", {
    x: 6.7, y: 6.2, w: 6.03, h: 0.35, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: COOL,
  });
  chrome(s, "Lana");
  s.addNotes("Lana. 1:00. Do not hide this - a found bug is evidence the verification works. Say plainly: we wrote it carefully, reviewed it, and it was wrong on vector two.");
}

/* ------------------------------------------------------------------ 19 */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addText("SYNTHESIS", {
    x: L, y: 0.5, w: W, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, bold: true, charSpacing: 1.6, color: HOT,
  });
  s.addText("Two benchmarks, two paradigms", {
    x: L, y: 0.78, w: W, h: 0.7, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF",
  });
  s.addText("This is why we chose the pair we did. The same project motivates both of the dominant accelerator patterns from the course — and, more importantly, shows why each one is wrong for the other workload.", {
    x: L, y: 1.55, w: 11.7, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "AFBECD", lineSpacing: 19,
  });

  const rows = [
    ["", "pyflate", "raytrace"],
    ["Bound by", "integer, control flow, memory", "floating point, allocation"],
    ["Data rate", "VARIABLE — 1 to 20 bits/symbol", "FIXED — same shape every test"],
    ["Pattern", "DATAFLOW, valid/ready", "SYSTOLIC, weight-stationary"],
    ["Key idea", "20 comparators + priority encoder", "preload spheres, stream rays"],
    ["Bit-exact?", "yes", "no — truncating sqrt, 1.16 ulp"],
  ];
  const cw2 = [2.6, 4.6, 4.9];
  rows.forEach((row, r) => {
    const y = 2.25 + r * 0.64;
    if (r === 0) {
      let x = L;
      row.forEach((c, i) => {
        s.addText(c, {
          x, y, w: cw2[i], h: 0.34, isTextBox: true, margin: 0,
          fontFace: BODY, fontSize: 14, bold: true,
          color: i === 1 ? HOT : (i === 2 ? COOL : "8A97A6"),
        });
        x += cw2[i];
      });
      return;
    }
    let x = L;
    row.forEach((c, i) => {
      s.addText(c, {
        x, y, w: cw2[i], h: 0.5, isTextBox: true, margin: 0,
        fontFace: BODY, fontSize: 12.5,
        color: i === 0 ? "8A97A6" : "E8EDF2",
        bold: i === 0, valign: "middle",
      });
      x += cw2[i];
    });
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 5.85, w: W, h: 0.85, rectRadius: 0.06,
    fill: { color: "2B3A4A" }, line: { color: HOT, width: 1.5 },
  });
  s.addText("A systolic array has no control circuitry. Feed it a variable-rate bitstream and it mis-aligns immediately — garbage in, garbage out. That single sentence is why these are two different machines.", {
    x: L + 0.3, y: 6.0, w: W - 0.6, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13.5, color: "FFFFFF", lineSpacing: 18,
  });
  chrome(s, "Taha + Lana", true);
  s.addNotes("Both. 0:40. Taha reads the pyflate column, Lana the raytrace column, then one of you reads the bottom strip. Rehearse the handoff.");
}

/* ------------------------------------------------------------------ 20 */
{
  const s = pres.addSlide();
  head(s, "limitations", "What we did not finish", WARN);
  s.addText("Stating this plainly is deliberate. Every claim in our reports is one we can defend; these are the ones we cannot.", {
    x: L, y: 1.5, w: W, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: MUTED,
  });

  const lim = [
    ["bzip2_accel_top is an integration sketch", "The T[] counting-sort engine that bwt_reverse_engine depends on is specified in the source but NOT implemented, so t_we is tied low. The individual blocks are simulated and correct; the assembled top elaborates but would not decompress a file. What is missing is about n + 512 cycles of work: a 256-counter histogram, a prefix sum, and a second pass over L[]."],
    ["Amdahl caps both accelerators", "raytrace intersection is 36% of the optimized runtime → 1.56× ceiling on a whole frame. For pyflate, a 67 KB input behind PCIe would be dominated by the round trip — which is why this belongs on-die, not on a discrete card."],
    ["A latent divergence we left alone", "build_decode_tables does not skip zero-length symbols while the baseline does. We instrumented the real workload: all 6 Huffman tables have minimum length 2, so it never triggers. Latent, not active."],
  ];
  lim.forEach((l, i) => {
    const y = 1.95 + i * 1.55;
    s.addShape(pres.ShapeType.ellipse, {
      x: L, y: y + 0.03, w: 0.28, h: 0.28,
      fill: { color: WARN }, line: { color: WARN, width: 0 },
    });
    s.addText(String(i + 1), {
      x: L, y: y + 0.03, w: 0.28, h: 0.28, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 11, bold: true, color: "FFFFFF",
      align: "center", valign: "middle",
    });
    s.addText(l[0], {
      x: L + 0.45, y, w: 11.6, h: 0.32, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 14, bold: true, color: INK,
    });
    s.addText(l[1], {
      x: L + 0.45, y: y + 0.35, w: 11.6, h: 1.1, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
    });
  });
  chrome(s, "Taha");
  s.addNotes("Taha. 0:25. Move briskly - do not dwell. Volunteering limitations pre-empts the question and reads as confidence, not weakness.");
}

/* ------------------------------------------------------------------ 21 */
{
  const s = pres.addSlide();
  s.background = { color: INK };
  s.addText("SUMMARY", {
    x: L, y: 0.75, w: W, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 11, bold: true, charSpacing: 1.6, color: HOT,
  });
  s.addText("Requirement was 7% on two benchmarks", {
    x: L, y: 1.05, w: W, h: 0.7, isTextBox: true, margin: 0,
    fontFace: TITLE_FONT, fontSize: 32, bold: true, color: "FFFFFF",
  });

  [["pyflate", "733.3 ms", "308.7 ms", "57.9%", "2.38×", "t = 620.51"],
   ["raytrace", "554.5 ms", "217.1 ms", "60.8%", "2.55×", "t = 670.87"]].forEach((r, i) => {
    const y = 2.0 + i * 1.15;
    darkCard(s, L, y, W, 0.95);
    const cw3 = [2.0, 1.9, 1.9, 1.7, 1.7, 1.8];
    let x = L + 0.3;
    r.forEach((c, j) => {
      s.addText(c, {
        x, y: y + 0.22, w: cw3[j], h: 0.5, isTextBox: true, margin: 0,
        fontFace: j === 0 ? TITLE_FONT : BODY,
        fontSize: j === 0 ? 18 : (j === 4 ? 20 : 14),
        bold: j === 0 || j === 3 || j === 4,
        color: j === 1 ? HOT : (j === 2 || j === 3 || j === 4 ? COOL : "E8EDF2"),
        valign: "middle",
      });
      x += cw3[j];
    });
  });

  s.addText("Both clear the bar by roughly 8×, both statistically significant, and both with output identical to the original — byte for byte for pyflate, pixel for pixel for raytrace.", {
    x: L, y: 4.45, w: 11.7, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, color: "AFBECD", lineSpacing: 19,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 5.15, w: W, h: 1.35, rectRadius: 0.06,
    fill: { color: "2B3A4A" }, line: { color: COOL, width: 1.5 },
  });
  s.addText("What we would want you to take away", {
    x: L + 0.35, y: 5.3, w: 11.4, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, bold: true, color: COOL,
  });
  s.addText("In both benchmarks the obvious diagnosis was wrong, and the counters — not intuition — settled it. IPC stayed flat while instructions retired fell in proportion to the runtime. We did not make the machine faster; we stopped asking it to do work that was never needed.", {
    x: L + 0.35, y: 5.62, w: 11.4, h: 0.75, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13.5, color: "FFFFFF", lineSpacing: 18,
  });
  chrome(s, "Lana", true);
  s.addNotes("Lana. 0:15. Short. Then: 'Happy to take questions, and we have the code running if you would like to see anything.'");
}

/* ---------------------------------------------------------- BACKUPS */
function backupSlide(title, kicker) {
  const s = pres.addSlide();
  head(s, kicker, title, MUTED, 7.5);
  s.addText("BACKUP — not presented", {
    x: R - 3.0, y: 0.5, w: 3.0, h: 0.26, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 10, bold: true, color: WARN, align: "right",
  });
  return s;
}

{
  const s = backupSlide("Canonical Huffman: why limit/base/perm works", "backup B1");
  s.addText("populate_huffman_symbols() already assigns canonical MSB-first codes — codes handed out in increasing order, shifted left whenever the length grows. That structure is what the linear scan ignores.", {
    x: L, y: 1.5, w: W, h: 0.55, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 13, color: INK, lineSpacing: 18,
  });
  s.addShape(pres.ShapeType.roundRect, {
    x: L, y: 2.15, w: 6.6, h: 2.0, rectRadius: 0.05,
    fill: { color: INK }, line: { color: INK, width: 0 },
  });
  s.addText("zvec = next min_len bits\nwhile zvec > limit[zn]:\n    zn += 1\n    zvec = (zvec << 1) | next_bit\nsym = perm[zvec - base[zn]]", {
    x: L + 0.25, y: 2.3, w: 6.1, h: 1.7, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 12, color: "8FE3D2", lineSpacing: 18,
  });
  card(s, 7.4, 2.15, 5.33, 2.0);
  s.addText("Worked example (6 symbols)", {
    x: 7.65, y: 2.3, w: 4.8, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12, bold: true, color: INK,
  });
  s.addText("lengths [2,2,2,3,4,4]\nsym 0→00  1→01  2→10\nsym 3→110  4→1110  5→1111\nlimit[2]=2 base[2]=0\nlimit[3]=6 base[3]=3\nlimit[4]=15 base[4]=10", {
    x: 7.65, y: 2.62, w: 4.8, h: 1.4, isTextBox: true, margin: 0,
    fontFace: MONO, fontSize: 10.5, color: MUTED, lineSpacing: 14,
  });
  s.addText("These are the exact vectors in tb_huffman_decoder.v. The testbench checks both the decoded symbol and the number of bits retired — a decoder that returns the right symbol while consuming the wrong number of bits destroys the rest of the stream.", {
    x: L, y: 4.35, w: W, h: 0.6, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: INK, lineSpacing: 17,
  });
  chrome(s, "backup");
  s.addNotes("If asked how canonical decoding works, or how the hardware table is built.");
}

{
  const s = backupSlide("Host/software interface and the three rules", "backup B2");
  const rules = [
    ["Rule 1", "Do not expect users to change their code", "Python still calls bz2.decompress(). Nothing above the library moves."],
    ["Rule 2", "If software must change, confine it to the library", "Only the decompressor gains a fast path: map buffers, push the Huffman tables through the CSR window, write CTRL.START, sleep on the interrupt."],
    ["Rule 3", "Never break the user's code", "START returns UNSUPPORTED for a randomised block or one larger than the on-chip SRAM, and the driver falls back to software. Our optimized Python mirrors this: a gzip input falls back to the baseline decoder."],
  ];
  rules.forEach((r, i) => {
    const y = 1.5 + i * 1.5;
    card(s, L, y, W, 1.3);
    s.addText(r[0], {
      x: L + 0.3, y: y + 0.15, w: 1.2, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 13, bold: true, color: HOT,
    });
    s.addText(r[1], {
      x: L + 1.55, y: y + 0.15, w: 10.2, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 13.5, bold: true, color: INK,
    });
    s.addText(r[2], {
      x: L + 1.55, y: y + 0.5, w: 10.2, h: 0.7, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
    });
  });
  s.addText("Security: the accelerator is a DMA master behind the IOMMU, with per-device page tables, so it can only touch the buffers the driver mapped for that request.", {
    x: L, y: 6.12, w: W, h: 0.52, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, italic: true, color: COOL,
  });
  chrome(s, "backup");
  s.addNotes("If asked about the HW/SW interface, the driver, or security.");
}

{
  const s = backupSlide("Measurement environment", "backup B3");
  const env = [
    ["host", "naranja7.cslcs.technion.ac.il — the server assigned to ece882-031"],
    ["cpu", "2 × Intel Xeon E5-2630 v3 @ 2.40 GHz, 32 threads"],
    ["os", "Ubuntu 24.04.4 LTS, kernel 6.8.0-124"],
    ["python", "CPython 3.12.3  ·  pyperf 2.10.0  ·  perf 6.8.12"],
    ["simulator", "Icarus Verilog 12.0 (installed without root via dpkg -x)"],
    ["method", "pyperf --rigorous, taskset -c 8, load average 0.16 before the run"],
    ["counters", "perf_event_paranoid = -1 — full hardware counter access"],
  ];
  env.forEach((e, i) => {
    const y = 1.55 + i * 0.62;
    s.addText(e[0], {
      x: L, y, w: 1.8, h: 0.35, isTextBox: true, margin: 0,
      fontFace: MONO, fontSize: 12, bold: true, color: HOT, valign: "middle",
    });
    s.addText(e[1], {
      x: L + 1.9, y, w: 10.2, h: 0.35, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12.5, color: INK, valign: "middle",
    });
  });
  s.addText("Error bars of 1–2% come from the machine being genuinely idle and the process pinned. Every table in both reports regenerates with ./script_pyflate.sh and ./script_raytrace.sh.", {
    x: L, y: 6.05, w: W, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, italic: true, color: MUTED, lineSpacing: 17,
  });
  chrome(s, "backup");
  s.addNotes("If asked where the numbers came from, or about measurement noise.");
}

{
  const s = backupSlide("Things we tried and rejected", "backup B4");
  const rej = [
    ["A full 2^20-entry Huffman LUT", "Would decode in one step, but bzip2 allows 6 tables of length ≤ 20 — about 6M entries to BUILD per block, for a block that decodes 148k symbols. Table construction costs more than it saves."],
    ["numpy for the inverse BWT", "An added dependency for a stage the ablation shows is worth ~2%."],
    ["A BVH for raytrace", "The first thing a graphics person proposes. With 8 objects, traversal overhead exceeds the 8 intersection tests it would save."],
    ["bfloat16 in the raytrace datapath", "Halves multiplier area, but 8 mantissa bits cannot survive the catastrophic cancellation in (cc − v·v)."],
    ["Swapping in libbz2 / a C extension", "Would post a huge speedup while measuring nothing. The benchmark exists to measure the interpreter."],
  ];
  rej.forEach((r, i) => {
    const y = 1.5 + i * 1.05;
    s.addText("✗", {
      x: L, y, w: 0.35, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 15, bold: true, color: WARN,
    });
    s.addText(r[0], {
      x: L + 0.4, y, w: 11.6, h: 0.3, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 13.5, bold: true, color: INK,
    });
    s.addText(r[1], {
      x: L + 0.4, y: y + 0.32, w: 11.6, h: 0.62, isTextBox: true, margin: 0,
      fontFace: BODY, fontSize: 12, color: MUTED, lineSpacing: 16,
    });
  });
  chrome(s, "backup");
  s.addNotes("If asked 'did you consider X'. Most likely question of the whole session.");
}

{
  const s = backupSlide("How we tested beyond the benchmark", "backup B5");
  card(s, L, 1.5, 5.9, 2.4);
  s.addText("pyflate — 14 extra streams", {
    x: L + 0.3, y: 1.68, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  bullets(s, L + 0.3, 2.05, 5.3, 1.7, [
    "empty, 1 byte, 1 KB of zeros",
    "highly repetitive, 64 KB random",
    "text, and a 900 KB MULTI-BLOCK file",
    "at compression levels 1 and 9",
    "all round-trip correctly",
  ], 12);

  card(s, 6.83, 1.5, 5.9, 2.4);
  s.addText("raytrace — 7 resolutions", {
    x: 7.13, y: 1.68, w: 5.3, h: 0.3, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  bullets(s, 7.13, 2.05, 5.3, 1.7, [
    "2×2, 3×7, 16×16, 50×50",
    "100×100, 101×37, 128×96",
    "bit-identical at every one",
    "the default is not a special case",
  ], 12);

  s.addText("Two API divergences we found and disclosed", {
    x: L, y: 4.15, w: W, h: 0.32, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 14, bold: true, color: INK,
  });
  s.addText("Removing the type assertions (O3) means Vector − Point and Vector.dot(Point) now compute silently where the baseline raised TypeError. Both are invalid usage the renderer never produces — but they are a behaviour change, so we documented them rather than leaving them to be discovered.", {
    x: L, y: 4.5, w: W, h: 0.7, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, color: MUTED, lineSpacing: 17,
  });
  s.addText("The correctness gate runs before any timing is reported. tools/verify.py compares all 399,360 decompressed bytes and the full 30,000-byte framebuffer.", {
    x: L, y: 5.35, w: W, h: 0.5, isTextBox: true, margin: 0,
    fontFace: BODY, fontSize: 12.5, italic: true, color: COOL, lineSpacing: 17,
  });
  chrome(s, "backup");
  s.addNotes("If asked whether the optimization generalizes, or only works on the one benchmark file.");
}

pres.writeFile({ fileName: "HWSW_CoDesign_Final_Taha_Lana.pptx" })
  .then((f) => console.log("wrote " + f + "  (" + slideNo + " slides)"));
