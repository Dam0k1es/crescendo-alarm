#!/usr/bin/env python3
"""docs/TODO.md T-213 (F-1): fail if an APK's signing block carries AGP's
dependency-metadata block (ID 0x504b4453, "DEPENDENCY_INFO_BLOCK").

The Android Gradle Plugin writes the resolved dependency list into the APK
Signing Block, encrypted with a key only Google holds, unless the app's
`android { dependenciesInfo { includeInApk = false } }` turns it off. F-Droid
rejects or warns about it: nobody but Google can read what it contains, so a
reproducible-build check cannot verify it either. `android/app/build.gradle.kts`
turns it off; this script proves that the built APK actually agrees, because
a Gradle setting that silently stops applying (renamed DSL, a second build
type, a plugin that re-enables it) would otherwise go unnoticed.

Usage: python3 scripts/check_apk_dependency_block.py <app.apk> [<app.apk> ...]
       python3 scripts/check_apk_dependency_block.py --self-test

`--self-test` needs no APK: it builds synthetic ZIP files with and without a
signing block (and with and without the forbidden ID inside it) and checks
both the parser and the exit code, the same way
`scripts/check_proprietary_native_deps.py --self-test` does.

Format (https://source.android.com/docs/security/features/apksigning/v2):
the APK Signing Block sits directly before the ZIP central directory and
ends with a uint64 size followed by the 16-byte magic "APK Sig Block 42".
Its body is a sequence of uint64-length-prefixed (uint32 id, value) pairs.
"""
import struct
import sys

DEPENDENCY_INFO_BLOCK_ID = 0x504B4453
_MAGIC = b"APK Sig Block 42"
_EOCD_SIGNATURE = b"PK\x05\x06"
_EOCD_MIN_SIZE = 22


class ApkFormatError(Exception):
    pass


def _central_directory_offset(data: bytes) -> int:
    # The EOCD record is at the end, followed by a comment of at most 65535
    # bytes; search backwards for its signature.
    search_from = max(0, len(data) - _EOCD_MIN_SIZE - 0xFFFF)
    eocd = data.rfind(_EOCD_SIGNATURE, search_from)
    if eocd < 0 or eocd + _EOCD_MIN_SIZE > len(data):
        raise ApkFormatError("no ZIP end-of-central-directory record found")
    (cd_offset,) = struct.unpack_from("<I", data, eocd + 16)
    if cd_offset > eocd:
        raise ApkFormatError("central directory offset points past the EOCD")
    return cd_offset


def signing_block_ids(data: bytes) -> list[int] | None:
    """The IDs of every pair in the APK Signing Block, or None when the file
    has no signing block at all (an unsigned ZIP)."""
    cd_offset = _central_directory_offset(data)
    if cd_offset < 24 or data[cd_offset - 16:cd_offset] != _MAGIC:
        return None
    (block_size,) = struct.unpack_from("<Q", data, cd_offset - 24)
    block_start = cd_offset - block_size - 8
    if block_start < 0:
        raise ApkFormatError("signing block size exceeds the file")
    (leading_size,) = struct.unpack_from("<Q", data, block_start)
    if leading_size != block_size:
        raise ApkFormatError("signing block's two size fields disagree")

    ids = []
    pos = block_start + 8
    pairs_end = cd_offset - 24
    while pos < pairs_end:
        if pos + 12 > pairs_end:
            raise ApkFormatError("truncated signing block pair")
        (pair_len,) = struct.unpack_from("<Q", data, pos)
        if pair_len < 4 or pos + 8 + pair_len > pairs_end:
            raise ApkFormatError("signing block pair length out of range")
        (pair_id,) = struct.unpack_from("<I", data, pos + 8)
        ids.append(pair_id)
        pos += 8 + pair_len
    return ids


def check(path: str) -> int:
    with open(path, "rb") as f:
        data = f.read()
    try:
        ids = signing_block_ids(data)
    except ApkFormatError as e:
        print(f"{path}: cannot parse ({e.__class__.__name__}: {e.args[0]})")
        return 2
    if ids is None:
        print(f"{path}: no APK Signing Block (unsigned?) - "
              "nothing to check, treated as a failure")
        return 2
    listed = ", ".join(f"0x{i:08x}" for i in ids)
    if DEPENDENCY_INFO_BLOCK_ID in ids:
        print(f"{path}: FAIL - the signing block contains the dependency-"
              f"metadata block 0x{DEPENDENCY_INFO_BLOCK_ID:08x} "
              f"(blocks: {listed}). Set android.dependenciesInfo."
              "includeInApk = false in android/app/build.gradle.kts.")
        return 1
    print(f"{path}: OK - no dependency-metadata block (blocks: {listed})")
    return 0


def main(paths: list[str]) -> int:
    if not paths:
        print(__doc__)
        return 2
    return max(check(p) for p in paths)


def _synthetic_apk(pair_ids: list[int] | None) -> bytes:
    """A small, valid ZIP with an APK Signing Block holding one pair per id
    inserted before its central directory (or none at all for None)."""
    import io
    import zipfile

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("AndroidManifest.xml", b"<manifest/>")
        z.writestr("classes.dex", b"dex\n035\0")
    data = buf.getvalue()
    if pair_ids is None:
        return data

    cd_offset = _central_directory_offset(data)
    pairs = b""
    for pair_id in pair_ids:
        value = b"\x00" * 7
        pairs += struct.pack("<QI", 4 + len(value), pair_id) + value
    block_size = len(pairs) + 8 + 16  # pairs + trailing size + magic
    block = (struct.pack("<Q", block_size) + pairs
             + struct.pack("<Q", block_size) + _MAGIC)

    eocd = data.rfind(_EOCD_SIGNATURE)
    patched_eocd = (data[eocd:eocd + 16]
                    + struct.pack("<I", cd_offset + len(block))
                    + data[eocd + 20:])
    return data[:cd_offset] + block + data[cd_offset:eocd] + patched_eocd


def self_test() -> int:
    import os
    import tempfile

    failed = False
    v2 = 0x7109871A  # APK Signature Scheme v2
    v3 = 0xF05368C0  # APK Signature Scheme v3
    padding = 0x42726577  # verity padding

    def expect(label: str, got, want) -> None:
        nonlocal failed
        if got != want:
            print(f"SELF-TEST FAIL: {label}: expected {want!r}, got {got!r}")
            failed = True

    # Parser: reads every pair id, in order, and tells "no block" apart.
    expect("ids of a v2+v3 block", signing_block_ids(_synthetic_apk([v2, v3])),
           [v2, v3])
    expect("ids including the dependency block",
           signing_block_ids(_synthetic_apk([v2, DEPENDENCY_INFO_BLOCK_ID,
                                             padding])),
           [v2, DEPENDENCY_INFO_BLOCK_ID, padding])
    expect("unsigned zip", signing_block_ids(_synthetic_apk(None)), None)

    # A corrupted size must be reported, not silently read as "clean".
    corrupt = bytearray(_synthetic_apk([v2]))
    cd = _central_directory_offset(bytes(corrupt))
    struct.pack_into("<Q", corrupt, cd - 24, 10_000)
    try:
        signing_block_ids(bytes(corrupt))
        print("SELF-TEST FAIL: a corrupted block size was not reported")
        failed = True
    except ApkFormatError:
        pass

    # check(): exit codes from file to verdict.
    cases = [
        ("clean signed APK", _synthetic_apk([v2, v3, padding]), 0),
        ("APK with the dependency block",
         _synthetic_apk([v2, DEPENDENCY_INFO_BLOCK_ID]), 1),
        ("dependency block as the only pair",
         _synthetic_apk([DEPENDENCY_INFO_BLOCK_ID]), 1),
        ("unsigned zip", _synthetic_apk(None), 2),
        ("corrupt block", bytes(corrupt), 2),
    ]
    tmpdir = tempfile.mkdtemp()
    for label, data, want in cases:
        path = os.path.join(tmpdir, label.replace(" ", "_") + ".apk")
        with open(path, "wb") as f:
            f.write(data)
        expect(f"check({label})", check(path), want)

    if failed:
        print("SELF-TEST: FAILED")
        return 1
    print("SELF-TEST: all cases passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    sys.exit(main(sys.argv[1:]))
