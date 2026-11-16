#!/usr/bin/env python3
"""MinimalClient 构建：编译 → 组装 .app（依赖白名单）→ 深度签名 → IPA。

用法：
  python3 build.py            # 构建并签名到 output/minimalclient/
  python3 build.py --ipa      # 额外打出 output/FAWVW-MinimalClient-PoC-dev.ipa

可重现性：不依赖 Xcode 工程文件；输入只有本目录 src/ 与 recovered/ 的只读 framework。
签名资产与 implementation/CarControlOnly/sign-development.py 相同（wildcard 团队证书）。
"""
from pathlib import Path
import subprocess, shutil, plistlib, sys, zipfile, hashlib, json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = HERE / 'src'
FWROOT = ROOT / 'recovered/ios-444.28.0/Payload/OneApp.app/Frameworks'
OUT = ROOT / 'output/minimalclient'
APPDIR = OUT / 'Payload/MinimalClient.app'
IDENTITY = 'F4B7D9363FDD39D2AF1F8F8E231D6E80853E4532'
PROFILE = Path('/Users/lukesong/Library/Developer/Xcode/UserData/Provisioning Profiles/60e16239-d416-4900-9903-86890bc23da1.mobileprovision')

# P0 依赖白名单（analysis/rea-carnet-sdk-evidence.json + EVReflectionCore→XMLDictionary 递归闭包）
FRAMEWORKS = ['CarNetLib', 'AEXML', 'AnyDate', 'EVReflectionCore', 'XMLDictionary', 'TrustKit']

def run(cmd, **kw):
    print('$', ' '.join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True, **kw)

def main():
    make_ipa = '--ipa' in sys.argv
    if OUT.exists():
        shutil.rmtree(OUT)  # 构建目录可安全重建；recovered/ 输入不动
    (APPDIR / 'Frameworks').mkdir(parents=True)

    # 1. 编译（arm64 真机；SDK framework 为真机构建，模拟器 slice 不存在）
    sources = sorted(str(p) for p in SRC.glob('*.m'))
    exe = APPDIR / 'MinimalClient'
    run(['xcrun', '--sdk', 'iphoneos', 'clang', '-arch', 'arm64',
         '-miphoneos-version-min=15.0', '-fobjc-arc', '-fmodules',
         '-framework', 'UIKit', '-framework', 'Foundation',
         '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
         *sources, '-o', exe])

    # 2. 依赖白名单 framework（拷贝，不修改 recovered）
    for fw in FRAMEWORKS:
        src = FWROOT / f'{fw}.framework'
        dst = APPDIR / 'Frameworks' / f'{fw}.framework'
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns('_CodeSignature'))

    # 3. Info.plist / 描述文件
    shutil.copy2(SRC / 'Info.plist', APPDIR / 'Info.plist')
    shutil.copy2(PROFILE, APPDIR / 'embedded.mobileprovision')

    # 4. entitlements：wildcard profile 允许任意 Bundle ID，keychain 组对齐团队
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', PROFILE]))
    team = profile['TeamIdentifier'][0]
    bid = plistlib.loads((APPDIR / 'Info.plist').read_bytes())['CFBundleIdentifier']
    ent = profile['Entitlements'].copy()
    ent['application-identifier'] = f'{team}.{bid}'
    ent['keychain-access-groups'] = [f'{team}.{bid}']
    entpath = OUT / 'entitlements.plist'
    entpath.write_bytes(plistlib.dumps(ent))

    # 5. 深度签名（先内层 Mach-O，再 framework，最后 .app 整体）
    exe.chmod(0o755)
    for p in sorted(APPDIR.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if p.is_file() and not p.is_dir():
            with p.open('rb') as f:
                magic = f.read(4)
            if magic in [bytes.fromhex(x) for x in ('cffaedfe', 'cefaedfe', 'cafebabe', 'bebafeca')]:
                run(['codesign', '--force', '--sign', IDENTITY, '--timestamp=none', p])
    for fw in sorted(APPDIR.glob('Frameworks/*.framework'), key=lambda p: len(p.parts), reverse=True):
        run(['codesign', '--force', '--sign', IDENTITY, '--timestamp=none', fw])
    run(['codesign', '--force', '--sign', IDENTITY, '--timestamp=none',
         '--entitlements', entpath, APPDIR])
    run(['codesign', '--verify', '--deep', '--strict', '--verbose=1', APPDIR])

    report = {
        'bundle_id': bid,
        'app': str(APPDIR),
        'frameworks': FRAMEWORKS,
        'app_size_bytes': sum(p.stat().st_size for p in APPDIR.rglob('*') if p.is_file()),
        'verified': 'codesign --deep --strict 通过',
    }

    # 6. 可选 IPA
    if make_ipa:
        ipa = ROOT / 'output/FAWVW-MinimalClient-PoC-dev.ipa'
        with zipfile.ZipFile(ipa, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for p in sorted(APPDIR.rglob('*')):
                if p.is_file():
                    name = 'Payload/MinimalClient.app/' + p.relative_to(APPDIR).as_posix()
                    info = zipfile.ZipInfo(name)
                    info.external_attr = (0o100755 if p == exe else 0o100644) << 16
                    z.writestr(info, p.read_bytes())
        report['ipa'] = ipa.name
        report['ipa_sha256'] = hashlib.sha256(ipa.read_bytes()).hexdigest()

    print(json.dumps(report, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()
