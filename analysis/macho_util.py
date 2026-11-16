#!/usr/bin/env python3
"""OneApp Mach-O 只读解析工具：段映射、CString、CFString、selref/classref、间接符号。"""
import struct

PATH = 'recovered/ios-444.28.0/Payload/OneApp.app/OneApp'

def _load(path=PATH):
    data = open(path, 'rb').read()
    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    segs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        if cmd == 0x19:
            segname = data[off+8:off+24].rstrip(b'\x00').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, off+24)
            segs.append((segname, vmaddr, vmsize, fileoff, filesize))
        off += cmdsize
    return data, segs

DATA, SEGS = _load()

def v2o(vmaddr):
    for name, vmaddr0, vmsize, fileoff, filesize in SEGS:
        if vmaddr0 <= vmaddr < vmaddr0 + vmsize:
            d = vmaddr - vmaddr0
            if d < filesize:
                return fileoff + d
            return None
    return None

def read(vmaddr, n):
    o = v2o(vmaddr)
    if o is None:
        return None
    return DATA[o:o+n]

def read_cstring(vmaddr, maxlen=400):
    o = v2o(vmaddr)
    if o is None:
        return None
    end = DATA.find(b'\x00', o, o+maxlen)
    if end < 0:
        end = o + maxlen
    return DATA[o:end].decode('utf-8', 'replace')

def read_u64(vmaddr):
    b = read(vmaddr, 8)
    return struct.unpack('<Q', b)[0] if b else None

def read_cfstring(vmaddr):
    """标准 0x20 字节 __NSCFConstantString 结构：isa, flags, ptr, len"""
    b = read(vmaddr, 0x20)
    if not b or len(b) < 0x20:
        return None
    isa, flags, ptr, ln = struct.unpack('<QQQQ', b)
    if ptr and ln and ln < 4096:
        o = v2o(ptr)
        if o is not None:
            return DATA[o:o+ln].decode('utf-8', 'replace')
    return None

def describe(vmaddr):
    """尝试判断地址内容类型并返回 (类型, 值)。"""
    b = read(vmaddr, 0x20)
    if b is None:
        return ('out-of-range', None)
    if b[:1] == b'\x00':
        # 可能是结构体（如 CFString）或空；尝试 CFString 解析
        s = read_cfstring(vmaddr)
        if s is not None:
            return ('cfstring', s)
        return ('zero/data', b.hex())
    # 尝试直接 cstring
    s = read_cstring(vmaddr)
    if s:
        return ('cstring', s)
    return ('data', b.hex())

def read_selref(vmaddr):
    """selref/classref 单元格：解引用一次得到符号名字符串地址"""
    ptr = read_u64(vmaddr)
    if ptr is None:
        return None
    return read_cstring(ptr)

def stub_target(stub_vmaddr):
    """解析 __stubs 项：adrp x16, A; ldr x16, [x16, off] -> 返回 GOT 条目地址"""
    b = read(stub_vmaddr, 16)
    if not b:
        return None
    ins = [struct.unpack('<I', b[i:i+4])[0] for i in range(0, 16, 4)]
    def decode_adrp(ins, pc):
        immhi = (ins >> 5) & 0x7ffff
        immlo = (ins >> 29) & 0x3
        imm = (immhi << 2) | immlo
        if imm & (1 << 20):
            imm -= 1 << 21
        return (pc & ~0xfff) + (imm << 12)
    def decode_ldr_imm12(ins):
        # ldr x16, [x16, #off] : 1111_1001_01 imm12 Rn Rt
        return ((ins >> 10) & 0xfff) << 3
    got = None
    for i, ins in enumerate(ins):
        pc = stub_vmaddr + i * 4
        if (ins & 0x9f000000) == 0x90000000:  # adrp
            got = decode_adrp(ins, pc)
        elif (ins & 0xffc00000) == 0xf9400000 and got is not None:  # ldr Xt,[Xn,#imm]
            got += decode_ldr_imm12(ins)
            return got
    return None

if __name__ == '__main__':
    import sys, json
    for a in sys.argv[1:]:
        v = int(a, 0)
        print(hex(v), describe(v))
