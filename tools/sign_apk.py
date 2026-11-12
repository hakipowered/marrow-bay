#!/usr/bin/env python3
"""Sign an aligned, unsigned APK with APK Signature Scheme v2.

Godot exports the APK unsigned (package/signed=false) because this build
machine has no Android SDK. This script adds the v2 signature that Android
needs to install it (minSdk 24, so v1 JAR signing is not required).

  python3 tools/sign_apk.py <in.apk> <out.apk> <key.pem> [cert.der]

If key.pem doesn't exist, a new RSA key and a self-signed certificate are
made and saved next to it. Keep using the same key: Android only installs an
update over an existing install when the signature matches.
"""
import hashlib, os, struct, sys, datetime
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding

CHUNK = 1 << 20
V2_BLOCK_ID = 0x7109871A
SIG_RSA_PKCS1_SHA256 = 0x0103
MAGIC = b"APK Sig Block 42"


def lp(b: bytes) -> bytes:
    return struct.pack("<I", len(b)) + b


def load_or_make_key(key_path: str, cert_path: str):
    if os.path.exists(key_path) and os.path.exists(cert_path):
        key = serialization.load_pem_private_key(open(key_path, "rb").read(), None)
        cert = x509.load_der_x509_certificate(open(cert_path, "rb").read())
        return key, cert
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "RaGoon City Debug")])
    now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now).not_valid_after(now + datetime.timedelta(days=365 * 30))
            .sign(key, hashes.SHA256()))
    os.makedirs(os.path.dirname(os.path.abspath(key_path)), exist_ok=True)
    with open(key_path, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                  serialization.NoEncryption()))
    os.chmod(key_path, 0o600)
    with open(cert_path, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.DER))
    return key, cert


def find_eocd(data: bytes) -> int:
    i = data.rfind(b"PK\x05\x06", max(0, len(data) - 65557))
    if i < 0:
        sys.exit("not a zip: no end of central directory")
    return i


def chunk_digest(sections) -> bytes:
    digests = []
    for sec in sections:
        for off in range(0, len(sec), CHUNK):
            c = sec[off:off + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(digests)) + b"".join(digests)).digest()


def sign(src: str, dst: str, key_path: str, cert_path: str) -> None:
    data = open(src, "rb").read()
    eocd_off = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd_off + 12:eocd_off + 20])
    if data[cd_off - 16:cd_off] == MAGIC:
        sys.exit("APK already has a signing block")
    entries = memoryview(data)[:cd_off]
    cdir = memoryview(data)[cd_off:cd_off + cd_size]
    eocd = bytearray(data[eocd_off:])
    # The digest is computed with the EOCD pointing at the signing block,
    # which will start where the central directory starts now.
    digest = chunk_digest([entries, cdir, bytes(eocd)])

    key, cert = load_or_make_key(key_path, cert_path)
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER,
                                           serialization.PublicFormat.SubjectPublicKeyInfo)
    signed_data = (lp(lp(struct.pack("<I", SIG_RSA_PKCS1_SHA256) + lp(digest)))
                   + lp(lp(cert_der))
                   + lp(b""))
    signature = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    signer = lp(signed_data) + lp(lp(struct.pack("<I", SIG_RSA_PKCS1_SHA256) + lp(signature))) + lp(pub_der)
    v2_value = lp(lp(signer))

    pair = struct.pack("<I", V2_BLOCK_ID) + v2_value
    pairs = struct.pack("<Q", len(pair)) + pair
    block_size = len(pairs) + 8 + 16
    block = struct.pack("<Q", block_size) + pairs + struct.pack("<Q", block_size) + MAGIC

    new_eocd = bytearray(eocd)
    struct.pack_into("<I", new_eocd, 16, cd_off + len(block))
    with open(dst, "wb") as f:
        f.write(entries)
        f.write(block)
        f.write(cdir)
        f.write(new_eocd)


def verify(path: str) -> bool:
    """Re-derive the digest from a signed APK and check it against the block."""
    data = open(path, "rb").read()
    eocd_off = find_eocd(data)
    cd_size, cd_off = struct.unpack("<II", data[eocd_off + 12:eocd_off + 20])
    if data[cd_off - 16:cd_off] != MAGIC:
        return False
    size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
    start = cd_off - size - 8
    pairs = data[start + 8:cd_off - 24]
    p = 0
    v2 = None
    while p < len(pairs):
        n = struct.unpack("<Q", pairs[p:p + 8])[0]
        bid = struct.unpack("<I", pairs[p + 8:p + 12])[0]
        if bid == V2_BLOCK_ID:
            v2 = pairs[p + 12:p + 8 + n]
        p += 8 + n
    if v2 is None:
        return False

    def rd(b, o):
        n = struct.unpack("<I", b[o:o + 4])[0]
        return b[o + 4:o + 4 + n], o + 4 + n

    signers, _ = rd(v2, 0)
    signer, _ = rd(signers, 0)
    sd, o = rd(signer, 0)
    sigs, o = rd(signer, o)
    pub, o = rd(signer, o)
    digs, _ = rd(sd, 0)
    d0, _ = rd(digs, 0)
    want, _ = rd(d0, 4)
    s0, _ = rd(sigs, 0)
    sig, _ = rd(s0, 4)
    serialization.load_der_public_key(pub).verify(sig, sd, padding.PKCS1v15(), hashes.SHA256())
    eocd = bytearray(data[eocd_off:])
    struct.pack_into("<I", eocd, 16, start)
    got = chunk_digest([memoryview(data)[:start], memoryview(data)[cd_off:cd_off + cd_size], bytes(eocd)])
    return got == want


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    src, dst, key_path = sys.argv[1:4]
    cert_path = sys.argv[4] if len(sys.argv) > 4 else os.path.splitext(key_path)[0] + "_cert.der"
    sign(src, dst, key_path, cert_path)
    print("signed:", dst, "verified" if verify(dst) else "VERIFY FAILED")
