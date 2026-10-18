"""Integer golden model (spec/npu.md sections 3 and 4).

Plain Python ``int`` only: no floats, no numpy, no simulator, PDK or
array-size assumption. Every RTL result is compared to these functions with
``==``. Matrices are lists of rows of ints.
"""

K_MAX = 256
INT8_MIN, INT8_MAX = -128, 127
MULT_MAX = 0xFFFF
SHIFT_MAX = 47


def _check_int8(v, what):
    if not INT8_MIN <= v <= INT8_MAX:
        raise ValueError(f"{what} {v} outside INT8")


def gemm_acc(a, b, bias):
    """acc[m][n] = bias[n] + sum_k a[m][k] * b[k][n], exact (spec 3.1).

    Returns the biased sum ``t``. ``a`` is M x K, ``b`` is K x N, ``bias`` has
    N entries in [-2**30, 2**30).
    """
    m, k = len(a), len(b)
    n = len(bias)
    if m < 1 or n < 1 or not 1 <= k <= K_MAX:
        raise ValueError(f"bad shape M={m} K={k} N={n} (1 <= K <= {K_MAX})")
    for row in a:
        if len(row) != k:
            raise ValueError("a is not M x K")
        for v in row:
            _check_int8(v, "a element")
    for row in b:
        if len(row) != n:
            raise ValueError("b is not K x N")
        for v in row:
            _check_int8(v, "b element")
    for v in bias:
        if not -(1 << 30) <= v < (1 << 30):
            raise ValueError(f"bias {v} outside [-2^30, 2^30)")
    cols = list(zip(*b))
    return [
        [bias[j] + sum(x * y for x, y in zip(row, cols[j])) for j in range(n)]
        for row in a
    ]


def _requantize_one(t, mult, shift, relu):
    p = t * mult
    r = (p + (1 << (shift - 1))) >> shift if shift > 0 else p
    if relu:
        r = max(r, 0)
    return min(max(r, INT8_MIN), INT8_MAX)


def requantize(t, mult, shift, relu):
    """Elementwise requantization of INT32 ``t`` (spec 3.2).

    ``t`` is an int or an arbitrarily nested list of ints; the result has the
    same shape. Round-half-up, then ReLU, then saturate to INT8.
    """
    if not 0 <= mult <= MULT_MAX:
        raise ValueError(f"mult {mult} outside 0..{MULT_MAX}")
    if not 0 <= shift <= SHIFT_MAX:
        raise ValueError(f"shift {shift} outside 0..{SHIFT_MAX}")
    relu = bool(relu)

    def walk(x):
        if isinstance(x, (list, tuple)):
            return [walk(e) for e in x]
        if not -(1 << 31) <= x < (1 << 31):
            raise ValueError(f"t {x} outside INT32")
        return _requantize_one(x, mult, shift, relu)

    return walk(t)


def gemm_int8(a, b, bias, mult, shift, relu):
    """(acc, out) for one GEMM; ``acc`` is the biased INT32 sum."""
    acc = gemm_acc(a, b, bias)
    return acc, requantize(acc, mult, shift, relu)


def _conv_dims(h, w, kh, kw, stride, pad):
    return (h + 2 * pad - kh) // stride + 1, (w + 2 * pad - kw) // stride + 1


def im2col(x, kh, kw, stride, pad):
    """x is int8[H][W][C]; returns int8[OH*OW][KH*KW*C] (spec 4)."""
    h, w, c = len(x), len(x[0]), len(x[0][0])
    oh, ow = _conv_dims(h, w, kh, kw, stride, pad)
    a = []
    for r in range(oh):
        for q in range(ow):
            row = []
            for i in range(kh):
                for j in range(kw):
                    y, xx = r * stride + i - pad, q * stride + j - pad
                    if 0 <= y < h and 0 <= xx < w:
                        row.extend(x[y][xx])
                    else:
                        row.extend([0] * c)
            a.append(row)
    return a


def reshape_weights(w):
    """int8[KH][KW][C][F] -> int8[K][F] with k = (i*KW + j)*C + c."""
    return [list(fs) for wi in w for wj in wi for fs in wj]


def conv2d_int8(x, w, bias, stride, pad, mult, shift, relu):
    """Convolution as GEMM over im2col (spec 4). Rows are m = oh*OW + ow."""
    kh, kw = len(w), len(w[0])
    return gemm_int8(im2col(x, kh, kw, stride, pad), reshape_weights(w),
                     bias, mult, shift, relu)


def conv2d_direct(x, w, bias, stride, pad, mult, shift, relu):
    """Nested-loop reference convolution; independent of im2col."""
    h, wd, c = len(x), len(x[0]), len(x[0][0])
    kh, kw, f = len(w), len(w[0]), len(w[0][0][0])
    oh, ow = _conv_dims(h, wd, kh, kw, stride, pad)
    acc = []
    for r in range(oh):
        for q in range(ow):
            row = []
            for o in range(f):
                s = bias[o]
                for i in range(kh):
                    for j in range(kw):
                        y, xx = r * stride + i - pad, q * stride + j - pad
                        if 0 <= y < h and 0 <= xx < wd:
                            for ch in range(c):
                                s += x[y][xx][ch] * w[i][j][ch][o]
                row.append(s)
            acc.append(row)
    return acc, requantize(acc, mult, shift, relu)


def _pack(vectors, n, what):
    """K consecutive k-vectors of ``n`` bytes (spec 5.2), little endian."""
    out = bytearray()
    for vec in vectors:
        if len(vec) > n:
            raise ValueError(f"{what}: vector longer than ARRAY_N={n}")
        for v in vec:
            _check_int8(v, what)
        out += bytes(v & 0xFF for v in vec) + bytes(n - len(vec))
    return bytes(out)


def pack_a(a_tile, n):
    """a_tile is int8[M<=n][K]; k-vector k has byte i = a_tile[i][k]."""
    k = len(a_tile[0])
    return _pack([[row[kk] for row in a_tile] for kk in range(k)], n, "pack_a")


def pack_b(b_tile, n):
    """b_tile is int8[K][N<=n]; k-vector k has byte j = b_tile[k][j]."""
    return _pack(b_tile, n, "pack_b")
