from pathlib import Path
import hashlib,json,struct,subprocess,zipfile,sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'implementation'))
from prepare_inputs import ensure_inputs
ensure_inputs(full=True)
APP = ROOT / 'recovered/ios-444.28.0/Payload/OneApp.app'
OUT = ROOT / 'output'
LIB = OUT / 'CarControlOnly.dylib'
subprocess.run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-miphoneos-version-min=15.0','-fobjc-arc','-dynamiclib','-framework','UIKit','-framework','Foundation','-install_name','@executable_path/Frameworks/CarControlOnly.dylib',str(Path(__file__).with_name('CarControlOnly.m')),str(Path(__file__).with_name('VehiclePage.m')),'-o',str(LIB)],check=True)
binary = bytearray((APP / 'OneApp').read_bytes())
assert binary[:4] == bytes.fromhex('cffaedfe')
count, size = struct.unpack_from('<II',binary,16)
offset = 32
first_section = len(binary)
for _ in range(count):
    command, length = struct.unpack_from('<II',binary,offset)
    if command == 0x19:
        for index in range(struct.unpack_from('<I',binary,offset+64)[0]):
            section_offset = struct.unpack_from('<I',binary,offset+72+index*80+48)[0]
            if section_offset:
                first_section = min(first_section,section_offset)
    offset += length
name = b'@executable_path/Frameworks/CarControlOnly.dylib\0'
length = (24 + len(name) + 7) & ~7
command = struct.pack('<IIIIII',0xc,length,24,0,0x10000,0x10000) + name
command += bytes(length-len(command))
end = 32 + size
assert end + length <= first_section
assert not any(binary[end:end+length])
binary[end:end+length] = command
struct.pack_into('<II',binary,16,count+1,size+length)
patched = OUT / 'OneApp.patched'
patched.write_bytes(binary)
ipa = OUT / 'FAWVW-444.28.0-CarControlOnly-dev-unsigned.ipa'
with zipfile.ZipFile(ipa,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=1) as archive:
    for path in sorted(APP.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(APP)
        if '_CodeSignature' in relative.parts:
            continue
        destination = 'Payload/OneApp.app/' + relative.as_posix()
        if relative.as_posix() == 'OneApp':
            info = zipfile.ZipInfo(destination)
            info.external_attr = 0o100755 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info,binary)
        else:
            archive.write(path,destination)
    archive.write(LIB,'Payload/OneApp.app/Frameworks/CarControlOnly.dylib')
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
report = {'ipa':ipa.name,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'bytes':ipa.stat().st_size,'status':'unsigned-development-build','verification':['dylib compilation','Mach-O header padding and LC_LOAD_DYLIB injection','ZIP CRC verification'],'runtime_verified':False}
(OUT/'build-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
