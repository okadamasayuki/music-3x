#!/usr/bin/env python3
"""iPhone の改善メモの受け口。

アプリの「改善」タブで項目をスワイプすると、ここへ HTTP で届く。
届いた要望は受信箱(~/.music3x-improvements/inbox.jsonl)へ記録するだけにし、
実装は、受信箱を見張っている常駐の Claude Code セッションが引き受ける。

以前は要望ごとに Terminal で新しい claude を立ち上げていたが、
セッションごとにモデルの確認や許可のやり直しが要るうえ、push や
スマホへの入れ直しまでは面倒を見ず、同時に動くと衝突もするのでやめた。
その形に戻したいときは install.sh --terminal で入れ直す。

導入は install.sh を一度実行するだけ。ログイン時に自動で立ち上がる。
"""

import json
import os
import shlex
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8917
# リポジトリの場所。常駐時は install.sh が引数で渡す。
#
# このファイル自身から辿らないのは、リポジトリが「デスクトップ」の中にあり、
# launchd から動かした python3 には保護されて読めないため。install.sh が
# 本体を保護の外(~/.music3x-improvements)へ写して、そちらを動かす。
# リポジトリを読むのは Terminal の中の claude なので、そちらは困らない。
REPO = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
# 要望の控えと、Terminal に渡すファイルの置き場
WORK_DIR = Path.home() / ".music3x-improvements"

# claude の実行ファイル。launchd から動くと PATH が細いので、自分で探す。
CLAUDE_CANDIDATES = [
    Path.home() / ".local/bin/claude",
    Path("/opt/homebrew/bin/claude"),
    Path("/usr/local/bin/claude"),
]


def find_claude() -> str:
    for path in CLAUDE_CANDIDATES:
        if path.exists():
            return str(path)
    # 見つからなくても、Terminal はログインシェルなので PATH に望みを残す
    return "claude"


def build_prompt(text: str, created_at: str) -> str:
    return (
        "iPhone の改善メモから届いた、このアプリへの改善要望です。"
        "リポジトリの中身を確かめて実装してください。\n"
        "\n"
        f"要望: {text}\n"
        "\n"
        f"(書き留めた日時: {created_at or '不明'})\n"
    )


def launch_claude(text: str, created_at: str) -> None:
    """要望を包んだ .command を Terminal で開く。新しいウィンドウで claude が走る。"""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    prompt_path = WORK_DIR / f"req-{stamp}.txt"
    prompt_path.write_text(build_prompt(text, created_at), encoding="utf-8")

    command_path = WORK_DIR / f"req-{stamp}.command"
    command_path.write_text(
        "#!/bin/zsh\n"
        f"cd {shlex.quote(str(REPO))} || exit 1\n"
        f'exec {shlex.quote(find_claude())} "$(cat {shlex.quote(str(prompt_path))})"\n',
        encoding="utf-8",
    )
    command_path.chmod(0o755)
    subprocess.run(["/usr/bin/open", "-a", "Terminal", str(command_path)], check=True)


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path == "/ping":
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"ok": False})

    def do_POST(self):
        if self.path != "/implement":
            self._reply(404, {"ok": False})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._reply(400, {"ok": False, "error": "bad json"})
            return

        text = str(body.get("text", "")).strip()
        if not text:
            self._reply(400, {"ok": False, "error": "empty text"})
            return
        created_at = str(body.get("createdAt", ""))

        # 何が届いたかの控え。実装がうまくいかなかったときに見返す。
        with (WORK_DIR / "inbox.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(
                {"receivedAt": time.strftime("%Y-%m-%dT%H:%M:%S"), **body},
                ensure_ascii=False,
            ) + "\n")

        # 動作確認用。ヘッダを付けると記録だけで、その先は何もしない。
        if self.headers.get("X-Dry-Run"):
            self._reply(200, {"ok": True, "dryRun": True})
            return

        # ふだんは受信箱への記録だけ。見張り役のセッションが拾って実装する。
        # Terminal で新しい claude を立ち上げる古い形は、選んだときだけ。
        if os.environ.get("MUSIC3X_OPEN_TERMINAL"):
            try:
                launch_claude(text, created_at)
            except Exception as error:  # noqa: BLE001 — 失敗の中身をそのまま返す
                self._reply(500, {"ok": False, "error": str(error)})
                return
        self._reply(200, {"ok": True})

    def _reply(self, status: int, payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    WORK_DIR.mkdir(exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"improvement server: repo={REPO} port={PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
