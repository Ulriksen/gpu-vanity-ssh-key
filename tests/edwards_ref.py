"""From-scratch, deliberately simple (not optimized) Edwards25519 reference,
used to (a) derive the base point's exact coordinates and (b) serve as the
oracle for property-based point-arithmetic tests. Validated at the bottom
against the `cryptography` library's real ed25519 key derivation.
"""
import hashlib

p = 2**255 - 19
d = 37095705934669439343138083508754565189542113879843219016388785533085940283555
d2 = 16295367250680780974490674513165176452449235426866156013048779062215315747161

assert (2 * d) % p == d2, "sanity check on constants pulled from libsodium source comments"

def inv(x):
    return pow(x, p - 2, p)

sqrt_m1 = pow(2, (p - 1) // 4, p)
assert (sqrt_m1 * sqrt_m1) % p == p - 1, "sqrt(-1) sanity check"


def modsqrt(a):
    """p % 8 == 5 square root algorithm. Returns None if a is not a QR."""
    a %= p
    if a == 0:
        return 0
    cand = pow(a, (p + 3) // 8, p)
    if (cand * cand) % p == a:
        return cand
    cand2 = (cand * sqrt_m1) % p
    if (cand2 * cand2) % p == a:
        return cand2
    return None


# -x^2 + y^2 = 1 + d x^2 y^2  (a = -1)  =>  x^2 = (y^2 - 1) * inv(1 + d*y^2)
def recover_x(y, sign):
    num = (y * y - 1) % p
    den = (1 + d * y * y) % p
    x2 = (num * inv(den)) % p
    x = modsqrt(x2)
    assert x is not None, "y is not on the curve"
    if x == 0 and sign:
        raise ValueError("no valid x for sign=1 when x2=0")
    if (x % 2) != sign:
        x = p - x
    return x


By = (4 * inv(5)) % p
Bx = recover_x(By, 0)
print("Bx =", Bx)
print("By =", By)

# curve equation self-check
assert (-(Bx * Bx) + By * By) % p == (1 + d * Bx * Bx * By * By) % p


def point_add(P, Q):
    x1, y1 = P
    x2, y2 = Q
    denom_x = (1 + d * x1 * x2 * y1 * y2) % p
    denom_y = (1 - d * x1 * x2 * y1 * y2) % p
    x3 = ((x1 * y2 + y1 * x2) % p) * inv(denom_x) % p
    y3 = ((y1 * y2 + x1 * x2) % p) * inv(denom_y) % p
    return (x3, y3)


def point_double(P):
    return point_add(P, P)


def scalar_mult(k, P):
    R = (0, 1)  # identity
    Q = P
    while k > 0:
        if k & 1:
            R = point_add(R, Q)
        Q = point_double(Q)
        k >>= 1
    return R


def encode_point(P):
    x, y = P
    out = bytearray(y.to_bytes(32, "little"))
    out[31] = (out[31] & 0x7F) | ((x & 1) << 7)
    return bytes(out)


def clamp(scalar_bytes):
    s = bytearray(scalar_bytes)
    s[0] &= 248
    s[31] &= 127
    s[31] |= 64
    return int.from_bytes(bytes(s), "little")


def derive_pubkey_from_seed(seed: bytes) -> bytes:
    h = hashlib.sha512(seed).digest()
    a = clamp(h[:32])
    A = scalar_mult(a, (Bx, By))
    return encode_point(A)


if __name__ == "__main__":
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    import os

    for trial in range(20):
        seed = os.urandom(32)
        priv = Ed25519PrivateKey.from_private_bytes(seed)
        expected = priv.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        got = derive_pubkey_from_seed(seed)
        status = "OK" if got == expected else "MISMATCH"
        print(trial, status, got.hex(), expected.hex())
        assert got == expected
    print("all trials matched `cryptography` library output")
