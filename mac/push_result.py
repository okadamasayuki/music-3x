#!/usr/bin/env python3
"""対応結果のまとめを iPhone の改善タブ「対応済み」欄へ書き込む。

使い方: python3 push_result.py "要望の要約" "原因と対応内容のまとめ"

端末の Documents/improve_results.json を取ってきて追記し、書き戻す。
取ってから書くのは、端末側での削除を尊重するため。上書きだけだと、
消したはずの知らせがまた現れる。iPhone が Mac から見えないときは失敗する
(そのときは知らせを諦めるだけで、実装や push には関わりない)。
"""
import json
import os
import subprocess
import sys
import time
import uuid

DEVICE = "0FBCC7AE-2007-5EA8-9EDF-869A24A76401"
APPID = "com.okadamasayuki.music3x"
ENV = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
TMP = "/tmp/music3x_improve_results.json"


def dctl(*args):
    return subprocess.run(["xcrun", "devicectl", *args], env=ENV, capture_output=True)


title, summary = sys.argv[1], sys.argv[2]
dctl("device", "copy", "from", "--device", DEVICE,
     "--source", "Documents/improve_results.json", "--destination", TMP,
     "--domain-type", "appDataContainer", "--domain-identifier", APPID)
try:
    results = json.load(open(TMP))
except Exception:  # noqa: BLE001 — 端末にまだ無ければ空から始める
    results = []

# 端末(Swift)の JSONDecoder が読める形式にする:
# id は UUID の大文字表記、日付は 2001 年からの参照秒。
swift_epoch = time.time() - 978307200.0
results.append({
    "id": str(uuid.uuid4()).upper(),
    "title": title,
    "summary": summary,
    "completedAt": swift_epoch,
})
json.dump(results, open(TMP, "w"), ensure_ascii=False)
r = dctl("device", "copy", "to", "--device", DEVICE,
         "--source", TMP, "--destination", "Documents/improve_results.json",
         "--domain-type", "appDataContainer", "--domain-identifier", APPID)
print("pushed" if r.returncode == 0 else f"FAILED: {r.stderr.decode()[:200]}")
