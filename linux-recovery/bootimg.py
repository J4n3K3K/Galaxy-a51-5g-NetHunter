#!/usr/bin/env python3
"""Minimal Android boot image (header v0-v2) and DT table tool.

  bootimg.py unpack <boot.img> <outdir>
  bootimg.py pack <info.json> <out.img> kernel=<f> ramdisk=<f> [dtb=<f>]
  bootimg.py dtimg <out> <a.dtb> [<b.dtb> ...]

unpack writes info.json with the header fields, pack reads it back.
"""
import struct, sys, os, json, hashlib

HDR = '<8s10I16s512s32s1024s'  # v0 fields up to extra_cmdline

def align(n, p): return (n + p - 1) // p * p

def unpack(img, out):
    d = open(img, 'rb').read()
    assert d[:8] == b'ANDROID!', 'not a boot image'
    (magic, ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, ver, osver,
     name, cmd, idv, xcmd) = struct.unpack_from(HDR, d, 0)
    off = struct.calcsize(HDR)
    info = dict(kernel_addr=kaddr, ramdisk_addr=raddr, second_addr=saddr,
                tags_addr=tags, page_size=page, header_version=ver, os_version=osver,
                name=name.rstrip(b'\0').decode(errors='replace'),
                cmdline=(cmd.rstrip(b'\0') + xcmd.rstrip(b'\0')).decode(errors='replace'))
    rsz_ = osz = 0; dsz = 0
    if ver >= 1:
        rsz_, roff, hsz = struct.unpack_from('<IQI', d, off); off += 16
        info.update(recovery_dtbo_size=rsz_, header_size=hsz)
    if ver >= 2:
        dsz, daddr = struct.unpack_from('<IQ', d, off)
        info.update(dtb_addr=daddr)
    os.makedirs(out, exist_ok=True)
    p = page; pos = p
    for nm, sz in (('kernel', ksz), ('ramdisk', rsz), ('second', ssz),
                   ('recovery_dtbo', rsz_), ('dtb', dsz)):
        if sz:
            open(os.path.join(out, nm), 'wb').write(d[pos:pos + sz])
        info[nm + '_size'] = sz
        pos += align(sz, p)
    info['trailer'] = d[pos:pos + 64].rstrip(b'\0').decode(errors='replace')
    json.dump(info, open(os.path.join(out, 'info.json'), 'w'), indent=1)
    print(json.dumps(info, indent=1))

def pack(info_path, out, **files):
    info = json.load(open(info_path))
    ver, p = info['header_version'], info['page_size']
    blobs = {k: open(v, 'rb').read() if v else b'' for k, v in files.items()}
    k, r = blobs.get('kernel', b''), blobs.get('ramdisk', b'')
    s, rd, dt = blobs.get('second', b''), blobs.get('recovery_dtbo', b''), blobs.get('dtb', b'')
    cmd = info['cmdline'].encode()
    sha = hashlib.sha1()
    for b in (k, r, s) + ((rd,) if ver >= 1 else ()) + ((dt,) if ver >= 2 else ()):
        sha.update(b); sha.update(struct.pack('<I', len(b)))
    hdr = struct.pack(HDR, b'ANDROID!', len(k), info['kernel_addr'], len(r),
                      info['ramdisk_addr'], len(s), info['second_addr'],
                      info['tags_addr'], p, ver, info['os_version'],
                      info['name'].encode(), cmd[:512], sha.digest().ljust(32, b'\0'),
                      cmd[512:])
    if ver >= 1:
        roff = align(len(hdr) + 16 + (12 if ver >= 2 else 0), p) + align(len(k), p) \
            + align(len(r), p) + align(len(s), p) if rd else 0
        hdr += struct.pack('<IQI', len(rd), roff, len(hdr) + 16 + (12 if ver >= 2 else 0))
    if ver >= 2:
        hdr += struct.pack('<IQ', len(dt), info['dtb_addr'])
    o = hdr.ljust(p, b'\0')
    for b in (k, r, s) + ((rd,) if ver >= 1 else ()) + ((dt,) if ver >= 2 else ()):
        o += b.ljust(align(len(b), p), b'\0')
    if info.get('trailer'):
        o += info['trailer'].encode()
    open(out, 'wb').write(o)
    print('wrote', out, len(o))

def dtimg(out, dtbs):
    """Samsung/AOSP DT table (magic d7b7ab1e), one entry per dtb.

    Entry ids match the A51 recovery image the layout was taken from.
    """
    hdr_size, entry_size, page = 32, 32, 2048
    blobs = [open(f, 'rb').read() for f in dtbs]
    off = hdr_size + entry_size * len(blobs)
    entries = b''
    for b in blobs:
        entries += struct.pack('>8I', len(b), off, 0, 0, 0, 0xff, 0, 0)
        off += len(b)
    total = off
    hdr = struct.pack('>8I', 0xd7b7ab1e, total, hdr_size, entry_size,
                      len(blobs), hdr_size, page, 0)
    open(out, 'wb').write(hdr + entries + b''.join(blobs))
    print('wrote', out, total)

if __name__ == '__main__':
    if sys.argv[1] == 'unpack':
        unpack(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'dtimg':
        dtimg(sys.argv[2], sys.argv[3:])
    else:
        args = dict(a.split('=', 1) for a in sys.argv[4:])
        pack(sys.argv[2], sys.argv[3], **args)
