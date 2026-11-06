#!/usr/bin/env python3
"""FIX114 H: an `ldid -S` stand-in for a thin arm64 Mach-O dylib: writes an
ad-hoc code signature (no entitlements) where ldid cannot run.

The signature is the standard ad-hoc one (what `codesign -s -` and `ldid -S`
write): a SuperBlob with a SHA-256 CodeDirectory (version 0x20400, flags
CS_ADHOC only: not "linker-signed"), an empty requirement set and an empty
CMS wrapper. The CodeDirectory hashes every 4 KiB page of the file up to the
signature, and slot -2 holds the requirement set's hash.

The dylib needs 16 free bytes after its load commands for LC_CODE_SIGNATURE
(link with -Wl,-headerpad,0x400); a dylib that is already signed (ldid or
the linker) has its signature replaced in place.

usage: tools/adhoc_sign.py [-S] <dylib> [--identifier ID]
       tools/adhoc_sign.py --verify <dylib>"""
import hashlib, os, struct, sys

MH_MAGIC_64 = 0xfeedfacf
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1d
CSMAGIC_EMBEDDED_SIGNATURE = 0xfade0cc0
CSMAGIC_CODEDIRECTORY = 0xfade0c02
CSMAGIC_REQUIREMENTS = 0xfade0c01
CSMAGIC_BLOBWRAPPER = 0xfade0b01
CSSLOT_CODEDIRECTORY, CSSLOT_REQUIREMENTS, CSSLOT_SIGNATURESLOT = 0, 2, 0x10000
CS_ADHOC = 0x2
CS_HASHTYPE_SHA256 = 2
PAGE = 4096


def align(v, a):
    return (v + a - 1) // a * a


class MachO:
    def __init__(self, data):
        self.data = bytearray(data)
        magic, cputype, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from('<IiiIIIII', self.data, 0)
        if magic != MH_MAGIC_64:
            raise SystemExit('not a thin 64-bit little-endian Mach-O')
        self.ncmds, self.sizeofcmds, self.filetype = ncmds, sizeofcmds, filetype
        self.cmds = []
        off = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from('<II', self.data, off)
            self.cmds.append((cmd, off, size))
            off += size

    def segment(self, name):
        for cmd, off, size in self.cmds:
            if cmd == LC_SEGMENT_64 and self.data[off + 8:off + 24].rstrip(b'\0').decode() == name:
                return off
        return None

    def segment_fields(self, off):
        # segname[16], vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags
        return list(struct.unpack_from('<QQQQiiII', self.data, off + 24))

    def first_section_offset(self):
        first = None
        for cmd, off, size in self.cmds:
            if cmd != LC_SEGMENT_64:
                continue
            nsects = struct.unpack_from('<I', self.data, off + 64)[0]
            for i in range(nsects):
                s = off + 72 + i * 80
                sect_size, sect_off = struct.unpack_from('<QI', self.data, s + 40)
                if sect_off and sect_size and (first is None or sect_off < first):
                    first = sect_off
        return first

    def code_signature(self):
        for cmd, off, size in self.cmds:
            if cmd == LC_CODE_SIGNATURE:
                return off
        return None


def requirements_blob():
    return struct.pack('>III', CSMAGIC_REQUIREMENTS, 12, 0)


def code_directory(data, code_limit, identifier, exec_base, exec_limit, exec_flags, special):
    """special: hashes of slots -1, -2, ... (in that order)."""
    nspecial = len(special)
    ncode = (code_limit + PAGE - 1) // PAGE
    ident = identifier.encode() + b'\0'
    header = 88
    hash_offset = header + len(ident) + nspecial * 32
    length = hash_offset + ncode * 32
    out = bytearray()
    out += struct.pack('>IIIIIIIII', CSMAGIC_CODEDIRECTORY, length, 0x20400, CS_ADHOC, hash_offset, header,
                       nspecial, ncode, code_limit)
    out += struct.pack('>BBBBI', 32, CS_HASHTYPE_SHA256, 0, 12, 0)   # hashSize, hashType, platform, pageSize 2^12, spare2
    out += struct.pack('>III', 0, 0, 0)                               # scatterOffset, teamOffset, spare3
    out += struct.pack('>QQQQ', 0, exec_base, exec_limit, exec_flags) # codeLimit64, execSeg base / limit / flags
    assert len(out) == header
    out += ident
    for h in reversed(special):                                        # slot -n first ... slot -1 last
        out += h
    for i in range(ncode):
        out += hashlib.sha256(bytes(data[i * PAGE:min((i + 1) * PAGE, code_limit)])).digest()
    assert len(out) == length
    return bytes(out)


def superblob(blobs):
    count = len(blobs)
    offset = 12 + 8 * count
    index, body = b'', b''
    for slot, blob in blobs:
        index += struct.pack('>II', slot, offset + len(body))
        body += blob
    total = 12 + 8 * count + len(body)
    return struct.pack('>III', CSMAGIC_EMBEDDED_SIGNATURE, total, count) + index + body


def sign(path, identifier=None):
    m = MachO(open(path, 'rb').read())
    identifier = identifier or os.path.basename(path)
    linkedit = m.segment('__LINKEDIT')
    text = m.segment('__TEXT')
    if linkedit is None or text is None:
        raise SystemExit('no __TEXT / __LINKEDIT segment')
    cs = m.code_signature()
    seg = m.segment_fields(linkedit)
    if cs is not None:
        # replace the existing signature (it is the last thing in __LINKEDIT)
        dataoff, _ = struct.unpack_from('<II', m.data, cs + 8)
        del m.data[dataoff:]
    else:
        if seg[2] + seg[3] != len(m.data):
            raise SystemExit('__LINKEDIT does not end the file')
        end = 32 + m.sizeofcmds
        first = m.first_section_offset()
        if first is None or first - end < 16 or any(m.data[end:end + 16]):
            raise SystemExit('no room for LC_CODE_SIGNATURE after the load commands (link with -Wl,-headerpad,0x400)')
        cs = end
        struct.pack_into('<IIII', m.data, cs, LC_CODE_SIGNATURE, 16, 0, 0)
        m.ncmds += 1
        m.sizeofcmds += 16
        struct.pack_into('<II', m.data, 16, m.ncmds, m.sizeofcmds)
    vmaddr, fileoff = seg[0], seg[2]
    dataoff = align(len(m.data), 16)
    m.data += b'\0' * (dataoff - len(m.data))
    text_fields = m.segment_fields(text)
    exec_base, exec_limit = text_fields[2], text_fields[3]
    exec_flags = 1 if m.filetype == 2 else 0          # CS_EXECSEG_MAIN_BINARY for executables only
    req = requirements_blob()
    special = [b'\0' * 32, hashlib.sha256(req).digest()]  # slot -1 Info.plist (none), slot -2 requirements
    # The size is known before the hashes: lay out with zero hashes, then fix the
    # load commands (they are hashed) and build the real one.
    cd_len = 88 + len(identifier.encode()) + 1 + len(special) * 32 + ((dataoff + PAGE - 1) // PAGE) * 32
    wrapper = struct.pack('>II', CSMAGIC_BLOBWRAPPER, 8)
    size = 12 + 8 * 3 + cd_len + len(req) + len(wrapper)
    datasize = align(size, 16)
    struct.pack_into('<II', m.data, cs + 8, dataoff, datasize)
    new_filesize = dataoff + datasize - fileoff
    struct.pack_into('<QQQQ', m.data, linkedit + 24, vmaddr, align(new_filesize, 0x4000), fileoff, new_filesize)
    cd = code_directory(m.data, dataoff, identifier, exec_base, exec_limit, exec_flags, special)
    assert len(cd) == cd_len
    blob = superblob([(CSSLOT_CODEDIRECTORY, cd), (CSSLOT_REQUIREMENTS, req), (CSSLOT_SIGNATURESLOT, wrapper)])
    assert len(blob) == size
    m.data += blob + b'\0' * (datasize - size)
    open(path, 'wb').write(bytes(m.data))
    return verify(path)


def verify(path):
    """Re-reads the file and checks the signature against its contents; returns the cdhash."""
    data = open(path, 'rb').read()
    m = MachO(data)
    cs = m.code_signature()
    if cs is None:
        raise SystemExit('unsigned')
    dataoff, datasize = struct.unpack_from('<II', data, cs + 8)
    linkedit = m.segment_fields(m.segment('__LINKEDIT'))
    assert dataoff + datasize == len(data) == linkedit[2] + linkedit[3], 'signature must end __LINKEDIT and the file'
    assert linkedit[1] >= linkedit[3] and linkedit[1] % 0x4000 == 0
    magic, total, count = struct.unpack_from('>III', data, dataoff)
    assert magic == CSMAGIC_EMBEDDED_SIGNATURE and total <= datasize
    blobs = {}
    for i in range(count):
        slot, off = struct.unpack_from('>II', data, dataoff + 12 + 8 * i)
        bmagic, blen = struct.unpack_from('>II', data, dataoff + off)
        blobs[slot] = data[dataoff + off:dataoff + off + blen]
    cd = blobs[CSSLOT_CODEDIRECTORY]
    (cmagic, clen, version, flags, hash_off, ident_off, nspecial, ncode, limit) = struct.unpack_from('>IIIIIIIII', cd, 0)
    hsize, htype, _, pshift = struct.unpack_from('>BBBB', cd, 36)
    assert cmagic == CSMAGIC_CODEDIRECTORY and version == 0x20400 and flags == CS_ADHOC and htype == CS_HASHTYPE_SHA256
    assert hsize == 32 and pshift == 12 and limit == dataoff and ncode == (limit + PAGE - 1) // PAGE
    for i in range(ncode):
        want = cd[hash_off + 32 * i:hash_off + 32 * (i + 1)]
        got = hashlib.sha256(data[i * PAGE:min((i + 1) * PAGE, limit)]).digest()
        assert want == got, 'page %d hash' % i
    req = blobs[CSSLOT_REQUIREMENTS]
    assert cd[hash_off - 64:hash_off - 32] == hashlib.sha256(req).digest(), 'requirements slot'
    assert cd[hash_off - 32:hash_off] == b'\0' * 32
    return hashlib.sha256(cd).hexdigest()[:40]


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if a != '-S']
    if not args:
        raise SystemExit(__doc__)
    if args[0] == '--verify':
        print('ok, cdhash', verify(args[1]))
    else:
        ident = None
        if '--identifier' in args:
            i = args.index('--identifier'); ident = args[i + 1]; del args[i:i + 2]
        print('signed (ad-hoc), cdhash', sign(args[0], ident))
