#!/usr/bin/env python3
"""Signs a content upload for the download worker (download/worker.js).

The worker only knows the PUBLIC half of an Ed25519 key (CONTENT_UPLOAD_PUBKEY
in worker.js); the private half stays in the project's private folder, so no
upload secret ever has to be copied around. A signature only lets you write
web:/pack:/packs:/packmeta: keys (the browser version and content packs),
never the APK.

  tools/web/upload_auth.py <METHOD> <key> <content-length>
      prints curl header args:  -H x-upload-ts:... -H x-upload-sig:...
  tools/web/upload_auth.py --new-key
      makes a new key pair (only if the old one is lost) and prints the
      public key to paste into worker.js.

Key file: $CONTENT_UPLOAD_KEY or /mnt/project-files/.signing/content_upload_ed25519.pem
The signed message is "<METHOD>\\n<key>\\n<unix seconds>\\n<content-length>";
the worker accepts it for 10 minutes.
"""
import base64, os, sys, time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

KEY = os.environ.get("CONTENT_UPLOAD_KEY", "/mnt/project-files/.signing/content_upload_ed25519.pem")

def public_b64(priv):
    raw = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return base64.b64encode(raw).decode()

if sys.argv[1:2] == ["--new-key"]:
    if os.path.exists(KEY):
        sys.exit(f"{KEY} exists; delete it first if you really want a new key")
    priv = Ed25519PrivateKey.generate()
    fd = os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.write(fd, priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    os.close(fd)
    print(public_b64(priv))
    sys.exit()

if sys.argv[1:2] == ["--public"]:
    print(public_b64(serialization.load_pem_private_key(open(KEY, "rb").read(), None)))
    sys.exit()

method, key, length = sys.argv[1], sys.argv[2], sys.argv[3]
priv = serialization.load_pem_private_key(open(KEY, "rb").read(), None)
ts = str(int(time.time()))
sig = base64.b64encode(priv.sign(f"{method.upper()}\n{key}\n{ts}\n{int(length)}".encode())).decode()
print(f"-H x-upload-ts:{ts} -H x-upload-sig:{sig}")
