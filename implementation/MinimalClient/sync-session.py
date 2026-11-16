#!/usr/bin/env python3
"""一键同步官方会话到 MinimalClient（滚动延期工具）。

流程：设备上官方 App(com.fawvw.aftermarket) 的探针持续把最新 identity token
捕获到其沙盒 Library/Application Support/P0Probe/sdk-client-identity.token；
本脚本拉取该文件并写入 PoC(com.lukev.minimalclient) 偏好 imported.idToken。

用法：python3 sync-session.py [设备UDID]
前置：官方 App 至少运行过一次且登录状态有效；设备解锁。
"""
import subprocess, sys, plistlib, tempfile, pathlib

UDID = sys.argv[1] if len(sys.argv) > 1 else '00008150-001E34E93A12401C'
HOST_APP = 'com.fawvw.aftermarket'
POC_APP = 'com.lukev.minimalclient'

def sh(*cmd):
    r = subprocess.run(list(cmd), capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f'命令失败: {" ".join(cmd)}\n{r.stderr.strip()[-300:]}')
    return r.stdout

tmp = tempfile.mkdtemp()
sh('xcrun', 'devicectl', 'device', 'copy', 'from', '--device', UDID,
   '--domain-type', 'appDataContainer', '--domain-identifier', HOST_APP,
   '--source', 'Library/Application Support/P0Probe', '--destination', tmp)
token = (pathlib.Path(tmp) / 'P0Probe' / 'sdk-client-identity.token').read_bytes()
assert token.count(b'.') == 2 and len(token) > 400, '捕获文件不是有效 JWT'
prefs = plistlib.dumps({'imported.idToken': token.decode()})
pref_file = pathlib.Path(tmp) / 'mc-prefs.plist'
pref_file.write_bytes(prefs)
sh('xcrun', 'devicectl', 'device', 'copy', 'to', '--device', UDID,
   '--domain-type', 'appDataContainer', '--domain-identifier', POC_APP,
   '--source', str(pref_file),
   '--destination', 'Library/Preferences/com.lukev.minimalclient.plist')
import base64, json, datetime
p = token.decode().split('.')[1].replace('-', '+').replace('_', '/')
claims = json.loads(base64.b64decode(p + '=' * (-len(p) % 4)))
exp = datetime.datetime.fromtimestamp(claims['exp'])
typ = claims.get('typ')
print(f'同步完成：identity token({typ}) len={len(token)} 有效期至 {exp:%Y-%m-%d}')
if typ != 'identity':
    print('⚠️ 警告：捕获的不是 identity 类型，请确认官方 App 重新登录过')
