from pathlib import Path
import plistlib,subprocess,shutil,zipfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output'
APP=OUT/'signed/Payload/OneApp.app'
IDENTITY='F4B7D9363FDD39D2AF1F8F8E231D6E80853E4532'
PROFILE=Path('/Users/lukesong/Library/Developer/Xcode/UserData/Provisioning Profiles/60e16239-d416-4900-9903-86890bc23da1.mobileprovision')
if APP.exists(): raise SystemExit('签名目录已存在，请检查后选择新的输出目录')
with zipfile.ZipFile(OUT/'FAWVW-444.28.0-CarControlOnly-dev-unsigned.ipa') as z:z.extractall(APP.parents[1])
# The IPA extraction API does not restore executable permission bits.
for p in APP.rglob('*'):
 if p.is_file():
  with p.open('rb') as f:magic=f.read(4)
  if magic in [bytes.fromhex(x) for x in ['cffaedfe','cefaedfe','cafebabe','bebafeca']]:p.chmod(0o755)
profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(PROFILE)]))
# Nested extensions need their own provisioning. This artifact is scoped to the phone app.
for folder in ['PlugIns','Watch']:
 p=APP/folder
 if p.exists():shutil.rmtree(p)
# Decrypted images use development signing, without obsolete store-install metadata.
for metadata in list(APP.rglob('SC_Info')):
 if metadata.is_dir():shutil.rmtree(metadata)
shutil.copy2(PROFILE,APP/'embedded.mobileprovision')
binary_path=APP/'OneApp'
binary=bytearray(binary_path.read_bytes())
# Runtime backtrace identified AppLaunchDelegate's local bundle identity gate.
position=0xe3f8
assert binary[position:position+4]==bytes.fromhex('40010036')
binary[position:position+4]=bytes.fromhex('1f2003d5')
proxy_check=0x18af8cc
assert binary[proxy_check:proxy_check+4]==bytes.fromhex('a7a4a995')
binary[proxy_check:proxy_check+4]=bytes.fromhex('000080d2')
binary_path.write_bytes(binary)
info=plistlib.loads((APP/'Info.plist').read_bytes())
info['CFBundleIdentifier']='com.lukev.aftermarket'
info['CFBundleDisplayName']='一汽大众·车控'
(APP/'Info.plist').write_bytes(plistlib.dumps(info))
bid=info['CFBundleIdentifier'];team=profile['TeamIdentifier'][0]
ent=profile['Entitlements'].copy();ent['application-identifier']=team+'.'+bid;ent['keychain-access-groups']=[team+'.'+bid]
entpath=OUT/'development-entitlements.plist';entpath.write_bytes(plistlib.dumps(ent))
for p in sorted(APP.rglob('*'),key=lambda p:len(p.parts),reverse=True):
 if p.is_file():
  with p.open('rb') as f:magic=f.read(4)
  if magic in [bytes.fromhex(x) for x in ['cffaedfe','cefaedfe','cafebabe','bebafeca']] and p!=APP/info['CFBundleExecutable']:
   subprocess.run(['codesign','--force','--sign',IDENTITY,'--timestamp=none',str(p)],check=True)
for p in sorted(APP.rglob('*.framework'),key=lambda p:len(p.parts),reverse=True):
 subprocess.run(['codesign','--force','--sign',IDENTITY,'--timestamp=none',str(p)],check=True)
subprocess.run(['codesign','--force','--sign',IDENTITY,'--timestamp=none','--entitlements',str(entpath),str(APP)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
print(APP)
