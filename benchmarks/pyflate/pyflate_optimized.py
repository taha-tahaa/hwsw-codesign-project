#!/usr/bin/env python
"""
Optimized bzip2 decoder for the pyperformance 'pyflate' benchmark.

Derived from Paul Sladen's pure-Python pyflate (2006-2007), the source used by
pyperformance's bm_pyflate.  Same DFSG-compatible licensing as the original.

The decompressed output is byte-identical to the baseline; this is enforced by
the MD5 gate in tools/verify.py and by the benchmark's own checksum.

Optimizations, in the order they were applied (see report_pyflate.txt for the
measured effect of each):

  O1  Canonical Huffman decoding.  The baseline HuffmanTable.find_next_symbol()
      walks the (bits, code)-sorted symbol table linearly, calling
      field.snoopbits() every time the code length changes.  The codes are
      already canonical MSB-first, so limit/base/perm tables decode a symbol in
      O(codelen - minLen) cheap integer steps with no per-candidate comparison.

  O2  Inlined bit reader.  The baseline allocates an RBitfield and calls
      readbits()/snoopbits()/needbits()/_mask()/_more()/_read() per access -
      six-deep call chains for a handful of integer ops.  Here the whole input
      is read once into a bytes object and the bit cursor (bitbuf, bitcnt, pos)
      lives in local variables inside the hot loop, so decoding a symbol costs
      no Python function calls at all.

  O3  Inverse BWT.  bwt_transform() built the character histogram with
      sorted(L) plus 256 bytes.find() scans; a direct 256-bin histogram with a
      prefix sum is O(n) instead.  The pointer-chase loop writes into a
      preallocated bytearray by index rather than append()-ing to a list.

  O4  Move-to-front.  move_to_front() rebuilt the list from three slices per
      call (~93k calls).  list.pop()/list.insert() do the same work as one
      C-level memmove.  The alphabet is kept as ints, not 1-byte bytes objects.

  O5  Output assembly.  Symbols accumulate into a bytearray instead of a list
      of ~767k one-byte bytes objects joined at the end, and the final RLE pass
      indexes the block directly instead of slicing per byte.

Scope: the bzip2 path exercised by the benchmark is what has been optimized.
A gzip input transparently falls back to the unmodified baseline decoder, so
this module is a drop-in replacement and never breaks a working input - the
"don't break the user's code" rule from the accelerator-design lecture.
"""

import hashlib
import os

MASKS = [(1 << i) - 1 for i in range(65)]


# ---------------------------------------------------------------------------
# O1: canonical Huffman decode tables
# ---------------------------------------------------------------------------

def build_decode_tables(lengths):
    """Build (limit, base, perm, minLen) for a canonical MSB-first code.

    `lengths[s]` is the code length of symbol s.  This reproduces exactly the
    code assignment that the baseline's populate_huffman_symbols() performs:
    symbols sorted by (bits, code), codes handed out in increasing order with a
    left shift whenever the length grows.
    """
    min_len = min(lengths)
    max_len = max(lengths)

    # perm: symbols ordered by (length, symbol) - the baseline's sort order.
    perm = []
    for l in range(min_len, max_len + 1):
        for sym, sl in enumerate(lengths):
            if sl == l:
                perm.append(sym)

    # base/limit per the canonical decoding recurrence.
    size = max_len + 2
    base = [0] * size
    limit = [0] * size

    for sl in lengths:
        base[sl + 1] += 1
    for i in range(1, size):
        base[i] += base[i - 1]

    vec = 0
    for l in range(min_len, max_len + 1):
        vec += base[l + 1] - base[l]
        limit[l] = vec - 1
        vec <<= 1
    for l in range(min_len + 1, max_len + 1):
        base[l] = ((limit[l - 1] + 1) << 1) - base[l]

    return limit, base, perm, min_len, max_len


# ---------------------------------------------------------------------------
# O3: inverse Burrows-Wheeler transform
# ---------------------------------------------------------------------------

def bwt_reverse(L, end):
    n = len(L)
    if not n:
        return b''

    # Direct histogram + prefix sum, replacing sorted(L) and 256 find() scans.
    counts = [0] * 256
    for c in L:
        counts[c] += 1
    base = [0] * 256
    total = 0
    for i in range(256):
        base[i] = total
        total += counts[i]

    T = [0] * n
    for i, symbol in enumerate(L):
        T[base[symbol]] = i
        base[symbol] += 1

    # Pointer chase into a preallocated buffer (no per-byte append).
    out = bytearray(n)
    for i in range(n):
        end = T[end]
        out[i] = L[end]
    return bytes(out)


# ---------------------------------------------------------------------------
# bzip2 block decoding
# ---------------------------------------------------------------------------

class _Reader(object):
    """Minimal MSB-first bit reader for the cold path (headers, tables).

    The hot symbol loop does not use this - it inlines the same arithmetic on
    local variables.  State is exchanged through .pos/.bitbuf/.bitcnt so the
    two can hand off mid-stream.
    """

    __slots__ = ('data', 'pos', 'bitbuf', 'bitcnt')

    def __init__(self, data):
        # Pad so a refill near EOF can never index past the end.  The format's
        # end-of-stream marker is reached first, so padding is never decoded.
        self.data = data + b'\x00' * 8
        self.pos = 0
        self.bitbuf = 0
        self.bitcnt = 0

    def readbits(self, n):
        bitbuf = self.bitbuf
        bitcnt = self.bitcnt
        pos = self.pos
        data = self.data
        while bitcnt < n:
            bitbuf = (bitbuf << 8) | data[pos]
            pos += 1
            bitcnt += 8
        bitcnt -= n
        r = (bitbuf >> bitcnt) & MASKS[n]
        self.bitbuf = bitbuf & MASKS[bitcnt]
        self.bitcnt = bitcnt
        self.pos = pos
        return r

    def align(self):
        self.readbits(self.bitcnt & 0x7)


def compute_used(b):
    huffman_used_map = b.readbits(16)
    used = []
    for i in range(15, -1, -1):
        if huffman_used_map & (1 << i):
            bitmap = b.readbits(16)
            for j in range(15, -1, -1):
                used.append(bool(bitmap & (1 << j)))
        else:
            used.extend([False] * 16)
    return used


def compute_selectors_list(b, huffman_groups):
    selectors_used = b.readbits(15)
    mtf = list(range(huffman_groups))
    selectors_list = []
    for _ in range(selectors_used):
        c = 0
        while b.readbits(1):
            c += 1
            if c >= huffman_groups:
                raise Exception("Bzip2 chosen selector greater than number of "
                                "groups (max 6)")
        # O4: pop/insert instead of rebuilding the list from three slices.
        if c:
            mtf.insert(0, mtf.pop(c))
        selectors_list.append(mtf[0])
    return selectors_list


def compute_tables(b, huffman_groups, symbols_in_use):
    tables = []
    for _ in range(huffman_groups):
        length = b.readbits(5)
        lengths = []
        for _ in range(symbols_in_use):
            if not 0 <= length <= 20:
                raise Exception("Bzip2 Huffman length code outside range 0..20")
            while b.readbits(1):
                length -= (b.readbits(1) * 2) - 1
            lengths.append(length)
        tables.append(build_decode_tables(lengths))
    return tables


def decode_huffman_block(b, out):
    randomised = b.readbits(1)
    if randomised:
        raise Exception("Bzip2 randomised support not implemented")
    pointer = b.readbits(24)
    used = compute_used(b)

    huffman_groups = b.readbits(3)
    if not 2 <= huffman_groups <= 6:
        raise Exception("Bzip2: Number of Huffman groups not in range 2..6")

    selectors_list = compute_selectors_list(b, huffman_groups)
    symbols_in_use = sum(used) + 2
    tables = compute_tables(b, huffman_groups, symbols_in_use)

    # O4: alphabet as ints rather than 1-byte bytes objects.
    favourites = [i for i, x in enumerate(used) if x]

    # ---- O2: hoist bit-cursor state and everything else into locals -------
    data = b.data
    pos = b.pos
    bitbuf = b.bitbuf
    bitcnt = b.bitcnt
    masks = MASKS

    buffer = bytearray()          # O5
    eob = symbols_in_use - 1
    selector_pointer = 0
    decoded = 0
    repeat = repeat_power = 0
    limit = base = perm = None
    min_len = 0

    while True:
        decoded -= 1
        if decoded <= 0:
            decoded = 50          # Huffman table switch interval
            if selector_pointer <= len(selectors_list):
                limit, base, perm, min_len, _max_len = \
                    tables[selectors_list[selector_pointer]]
                selector_pointer += 1

        # ---- O1 + O2: inline canonical symbol decode, zero function calls --
        while bitcnt < 24:
            bitbuf = (bitbuf << 8) | data[pos]
            pos += 1
            bitcnt += 8

        zn = min_len
        bitcnt -= zn
        zvec = (bitbuf >> bitcnt) & masks[zn]
        bitbuf &= masks[bitcnt]
        while zvec > limit[zn]:
            bitcnt -= 1
            zvec = (zvec << 1) | ((bitbuf >> bitcnt) & 1)
            bitbuf &= masks[bitcnt]
            zn += 1
        r = perm[zvec - base[zn]]

        if r <= 1:
            # RUNA / RUNB
            if repeat == 0:
                repeat_power = 1
            repeat += repeat_power << r
            repeat_power <<= 1
            continue
        elif repeat > 0:
            buffer += bytes((favourites[0],)) * repeat
            repeat = 0
        if r == eob:
            break
        else:
            j = r - 1
            o = favourites[j]
            if j:
                favourites.insert(0, favourites.pop(j))   # O4
            buffer.append(o)                              # O5

    # Hand the bit cursor back to the object for the block footer.
    b.pos = pos
    b.bitbuf = bitbuf
    b.bitcnt = bitcnt

    nt = bwt_reverse(bytes(buffer), pointer)

    # ---- O5: final RLE pass over indices, not per-byte slices -------------
    n = len(nt)
    limit4 = n - 4
    i = 0
    while i < n:
        b0 = nt[i]
        if i < limit4 and nt[i + 1] == b0 and nt[i + 2] == b0 and nt[i + 3] == b0:
            out += bytes((b0,)) * (nt[i + 4] + 4)
            i += 5
        else:
            out.append(b0)
            i += 1


def bzip2_main(b):
    method = b.readbits(8)
    if method != ord('h'):
        raise Exception(
            "Unknown (not type 'h'uffman Bzip2) compression method")

    blocksize = b.readbits(8)
    if not (ord('1') <= blocksize <= ord('9')):
        raise Exception("Unknown (not size '0'-'9') Bzip2 blocksize")

    out = bytearray()
    while True:
        blocktype = b.readbits(48)
        b.readbits(32)   # crc
        if blocktype == 0x314159265359:      # (pi)
            decode_huffman_block(b, out)
        elif blocktype == 0x177245385090:    # sqrt(pi)
            b.align()
            break
        else:
            raise Exception("Illegal Bzip2 blocktype")
    return bytes(out)


def decompress(data):
    """Decompress a gzip or bzip2 byte string.

    bzip2 uses the optimized path above.  gzip falls back to the unmodified
    baseline decoder so no previously working input stops working.
    """
    b = _Reader(data)
    magic = b.readbits(16)
    if magic == 0x425a:      # BZip2
        return bzip2_main(b)
    elif magic == 0x1f8b:    # GZip - fall back, not the benchmarked path
        import io
        import importlib.util
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'pyflate_baseline.py')
        spec = importlib.util.spec_from_file_location('pyflate_baseline', path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        fp = io.BytesIO(data)
        field = mod.RBitfield(fp)
        field.readbits(16)
        return mod.gzip_main(field)
    raise Exception("Unknown file magic %x, not a gzip/bzip2 file" % magic)


def bench_pyflake(loops, filename):
    import pyperf
    range_it = range(loops)

    # The file read stays INSIDE the timed region, exactly as in the baseline,
    # so that replacing the baseline's per-byte f.read(1) with a single bulk
    # read is credited as an optimization rather than hidden outside the timer.
    t0 = pyperf.perf_counter()
    for _ in range_it:
        with open(filename, 'rb') as fp:
            data = fp.read()
        out = decompress(data)
    dt = pyperf.perf_counter() - t0

    if hashlib.md5(out).hexdigest() != "afa004a630fe072901b1d9628b960974":
        raise Exception("MD5 checksum mismatch")
    return dt


if __name__ == '__main__':
    import pyperf
    runner = pyperf.Runner()
    runner.metadata['description'] = "Pyflate benchmark (optimized)"
    filename = os.path.join(os.path.dirname(__file__),
                            "data", "interpreter.tar.bz2")
    runner.bench_time_func('pyflate', bench_pyflake, filename)
