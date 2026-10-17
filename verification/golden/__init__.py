"""Seam for the integer golden model.

The golden model is written once, in this repo, and every RTL result is
compared to it bit for bit (including requantization rounding and
saturation). Its arithmetic is specified by the target spec (#3), not by the
harness. Until then every entry point raises ``NotImplementedError``.

Plug-in contract: the scoreboard imports this package and calls the functions
below with plain Python ints and lists of ints, and compares the result to the
DUT outputs with ``==`` (no tolerance). Keep it free of any simulator, PDK or
array-size assumption; array size is a parameter passed in by the caller.
"""


def matmul_int8(a, b, *, rows, cols):
    """Integer matrix product of INT8 operands. Specified by #3."""
    raise NotImplementedError("specified by #3")


def requantize(acc, *, scale, shift, zero_point):
    """Requantize accumulators to INT8 with the spec's rounding and
    saturation. Specified by #3."""
    raise NotImplementedError("specified by #3")
