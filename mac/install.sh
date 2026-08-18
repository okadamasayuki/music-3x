#!/bin/zsh
# 改善メモの受け口(improvement_server.py)を、ログイン時に自動で
# 立ち上がるように launchd へ登録する。一度実行すればよい。
#
#   導入:   ./install.sh
#   取り外し: ./install.sh --uninstall
#   旧方式:  ./install.sh --terminal (要望ごとに Terminal で claude を立ち上げる)
#
# ログは ~/Library/Logs/music3x-improvements.log に出る。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LABEL="com.okadamasayuki.music3x-improvements"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/music3x-improvements.log"
# 本体の写し先。リポジトリはデスクトップの中にあって launchd からは
# 読めない(macOS の保護)ので、保護の外へ写したものを動かす。
# improvement_server.py を書き換えたら、もう一度 install.sh を実行すること。
RUN_DIR="$HOME/.music3x-improvements"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "取り外しました: $LABEL"
  exit 0
fi

# 旧方式(要望ごとに Terminal で claude を立ち上げる)を選んだときだけ環境変数を立てる
TERMINAL_MODE=""
if [[ "${1:-}" == "--terminal" ]]; then
  TERMINAL_MODE="
	<key>EnvironmentVariables</key>
	<dict>
		<key>MUSIC3X_OPEN_TERMINAL</key>
		<string>1</string>
	</dict>"
fi

mkdir -p "$HOME/Library/LaunchAgents" "$RUN_DIR"
cp "$SCRIPT_DIR/improvement_server.py" "$RUN_DIR/improvement_server.py"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/python3</string>
		<string>$RUN_DIR/improvement_server.py</string>
		<string>$REPO_DIR</string>
	</array>
	<key>RunAtLoad</key>
	<true/>$TERMINAL_MODE
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
PLIST

# すでに動いていれば入れ替える
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 1
if curl -s --max-time 3 "http://localhost:8917/ping" | grep -q '"ok": true'; then
  echo "受け口が動いています: http://$(scutil --get LocalHostName).local:8917"
else
  echo "登録はしましたが応答がありません。ログを確認してください: $LOG"
  exit 1
fi
