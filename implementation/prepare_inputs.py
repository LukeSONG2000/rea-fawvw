#!/usr/bin/env python3
"""从保留的原始 IPA 按需恢复构建输入；默认只解出 6 个 SDK。"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
IPA = ROOT / 'packages/com.fawvw.aftermarket_444.28.0_cn_iphone_dumpipa.com.ipa'
DEST = ROOT / 'recovered/ios-444.28.0'
APP = DEST / 'Payload/OneApp.app'
FRAMEWORKS = ['CarNetLib', 'AEXML', 'AnyDate', 'EVReflectionCore', 'XMLDictionary', 'TrustKit']
ORIGINAL_SHA256 = '450f0978f4eab1804c0abfef83dfd1c4a2106a9d4eb386567d3593556ba1acea'


def ensure_inputs(full=False):
    marker = DEST / 'input-manifest.json'
    complete = all((APP / f'Frameworks/{name}.framework/{name}').is_file() for name in FRAMEWORKS)
    previous = json.loads(marker.read_text()) if marker.exists() else {}
    if complete and (not full or previous.get('mode') == 'full'):
        return
    if not IPA.is_file():
        raise SystemExit('缺少原始 IPA。请从私有仓库 research-baseline Release 恢复到 packages/。')
    with IPA.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else None
    if digest is None:
        h = hashlib.sha256()
        with IPA.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(chunk)
        digest = h.hexdigest()
    if digest != ORIGINAL_SHA256:
        raise SystemExit('原始 IPA 校验失败，未恢复任何文件。')
    prefixes = [f'Payload/OneApp.app/Frameworks/{name}.framework/' for name in FRAMEWORKS]
    DEST.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(IPA) as archive:
        for entry in archive.infolist():
            if not entry.filename.startswith('Payload/OneApp.app/'):
                continue
            if not full and not any(entry.filename.startswith(prefix) for prefix in prefixes):
                continue
            relative = PurePosixPath(entry.filename)
            if relative.is_absolute() or '..' in relative.parts:
                raise SystemExit('安装包中存在不安全路径，停止恢复。')
            target = DEST.joinpath(*relative.parts)
            if not target.resolve().is_relative_to(DEST.resolve()):
                raise SystemExit('输入目录中存在越界链接，停止恢复。')
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
            mode = (entry.external_attr >> 16) & 0o777
            target.chmod(mode or 0o644)
            count += 1
    marker.write_text(json.dumps({'mode': 'full' if full else 'minimal', 'sourceSHA256': digest,
                                  'frameworks': FRAMEWORKS, 'filesExtracted': count}, indent=2) + '\n')
    print(f'原始输入已恢复：{"完整研究包" if full else "6 个构建 SDK"}，{count} 个文件。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full', action='store_true', help='恢复完整 OneApp.app，用于原宿主研究及过渡版构建')
    args = parser.parse_args()
    ensure_inputs(full=args.full)
