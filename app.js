"use strict";

const audio = document.getElementById("audio");
const audioFileInput = document.getElementById("audio-file");
const subtitleFileInput = document.getElementById("subtitle-file");
const audioFileName = document.getElementById("audio-file-name");
const subtitleFileName = document.getElementById("subtitle-file-name");
const audioDrop = document.getElementById("audio-drop");
const subtitleDrop = document.getElementById("subtitle-drop");
const subtitleText = document.getElementById("subtitle-text");
const seekBar = document.getElementById("seek-bar");
const currentTimeEl = document.getElementById("current-time");
const durationEl = document.getElementById("duration");
const playPauseBtn = document.getElementById("play-pause");
const back10Btn = document.getElementById("back-10");
const forward10Btn = document.getElementById("forward-10");
const speedButtons = document.querySelectorAll(".speed-btn");
const preservePitchCheckbox = document.getElementById("preserve-pitch");
const volumeSlider = document.getElementById("volume");

let cues = []; // { start, end, text } 秒単位、start 昇順
let currentAudioUrl = null;
let seeking = false;

// ---------- 字幕パーサー ----------

// "01:02:03,456" / "02:03.456" → 秒
function parseTimestamp(ts) {
  const m = ts.trim().match(/^(?:(\d+):)?(\d+):(\d+)[.,](\d{1,3})$/);
  if (!m) return null;
  const h = m[1] ? parseInt(m[1], 10) : 0;
  const min = parseInt(m[2], 10);
  const s = parseInt(m[3], 10);
  const ms = parseInt(m[4].padEnd(3, "0"), 10);
  return h * 3600 + min * 60 + s + ms / 1000;
}

// SRT と VTT の両方をブロック単位で処理できる共通パーサー
function parseSubtitles(content) {
  const result = [];
  const normalized = content.replace(/\r\n?/g, "\n").replace(/^﻿/, "");
  const blocks = normalized.split(/\n\n+/);

  for (const block of blocks) {
    const lines = block.split("\n").filter((l) => l.trim() !== "");
    if (lines.length === 0) continue;

    // タイムコード行("-->" を含む行)を探す
    const timeLineIndex = lines.findIndex((l) => l.includes("-->"));
    if (timeLineIndex === -1) continue; // WEBVTT ヘッダーや NOTE ブロックなど

    const [startRaw, endRaw] = lines[timeLineIndex].split("-->");
    if (endRaw === undefined) continue;
    const start = parseTimestamp(startRaw);
    // VTT はタイムコード後に位置指定が付くことがあるので最初のトークンだけ使う
    const end = parseTimestamp(endRaw.trim().split(/\s+/)[0]);
    if (start === null || end === null) continue;

    const text = lines
      .slice(timeLineIndex + 1)
      .join("\n")
      .replace(/<[^>]+>/g, "") // <i> などの装飾タグを除去
      .trim();
    if (text) result.push({ start, end, text });
  }

  result.sort((a, b) => a.start - b.start);
  return result;
}

// ---------- ファイル読み込み ----------

function loadAudioFile(file) {
  if (currentAudioUrl) URL.revokeObjectURL(currentAudioUrl);
  currentAudioUrl = URL.createObjectURL(file);
  audio.src = currentAudioUrl;
  audioFileName.textContent = file.name;
  audioDrop.classList.add("loaded");
  playPauseBtn.disabled = false;
  playPauseBtn.textContent = "▶";
  seekBar.value = 0;
  applySpeed(getActiveSpeed());
}

function loadSubtitleFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    cues = parseSubtitles(reader.result);
    subtitleFileName.textContent = `${file.name}(${cues.length} 件)`;
    subtitleDrop.classList.add("loaded");
    if (cues.length === 0) {
      subtitleText.textContent = "字幕を読み込めませんでした(形式を確認してください)";
      subtitleText.classList.remove("active");
    } else {
      updateSubtitle(audio.currentTime, true);
    }
  };
  reader.readAsText(file);
}

audioFileInput.addEventListener("change", () => {
  if (audioFileInput.files[0]) loadAudioFile(audioFileInput.files[0]);
});

subtitleFileInput.addEventListener("change", () => {
  if (subtitleFileInput.files[0]) loadSubtitleFile(subtitleFileInput.files[0]);
});

// ドラッグ&ドロップ
function setupDrop(el, handler) {
  el.addEventListener("dragover", (e) => {
    e.preventDefault();
    el.classList.add("dragover");
  });
  el.addEventListener("dragleave", () => el.classList.remove("dragover"));
  el.addEventListener("drop", (e) => {
    e.preventDefault();
    el.classList.remove("dragover");
    const file = e.dataTransfer.files[0];
    if (file) handler(file);
  });
}
setupDrop(audioDrop, loadAudioFile);
setupDrop(subtitleDrop, loadSubtitleFile);

// ---------- 再生コントロール ----------

function togglePlay() {
  if (!audio.src) return;
  if (audio.paused) {
    audio.play();
  } else {
    audio.pause();
  }
}

playPauseBtn.addEventListener("click", togglePlay);
audio.addEventListener("play", () => (playPauseBtn.textContent = "⏸"));
audio.addEventListener("pause", () => (playPauseBtn.textContent = "▶"));
audio.addEventListener("ended", () => (playPauseBtn.textContent = "▶"));

back10Btn.addEventListener("click", () => skip(-10));
forward10Btn.addEventListener("click", () => skip(10));

function skip(seconds) {
  if (!audio.src) return;
  audio.currentTime = Math.min(
    Math.max(0, audio.currentTime + seconds),
    audio.duration || Infinity
  );
}

// ---------- 速度切替 ----------

function getActiveSpeed() {
  const active = document.querySelector(".speed-btn.active");
  return active ? parseFloat(active.dataset.speed) : 1;
}

function applySpeed(speed) {
  audio.playbackRate = speed;
  // 倍速でも声の高さを保つ(ブラウザ実装差のためベンダープレフィックスも設定)
  const preserve = preservePitchCheckbox.checked;
  audio.preservesPitch = preserve;
  if ("mozPreservesPitch" in audio) audio.mozPreservesPitch = preserve;
  if ("webkitPreservesPitch" in audio) audio.webkitPreservesPitch = preserve;
}

speedButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    speedButtons.forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    applySpeed(parseFloat(btn.dataset.speed));
  });
});

preservePitchCheckbox.addEventListener("change", () => applySpeed(getActiveSpeed()));

// ---------- シーク・時間表示 ----------

function formatTime(seconds) {
  if (!isFinite(seconds)) return "0:00";
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
}

audio.addEventListener("loadedmetadata", () => {
  durationEl.textContent = formatTime(audio.duration);
  seekBar.max = audio.duration;
});

audio.addEventListener("timeupdate", () => {
  if (!seeking) seekBar.value = audio.currentTime;
  currentTimeEl.textContent = formatTime(audio.currentTime);
  updateSubtitle(audio.currentTime);
});

seekBar.addEventListener("input", () => {
  seeking = true;
  currentTimeEl.textContent = formatTime(parseFloat(seekBar.value));
});

seekBar.addEventListener("change", () => {
  audio.currentTime = parseFloat(seekBar.value);
  seeking = false;
  updateSubtitle(audio.currentTime, true);
});

volumeSlider.addEventListener("input", () => {
  audio.volume = parseFloat(volumeSlider.value);
});

// ---------- 字幕の同期表示 ----------

let lastCueIndex = -1;

function updateSubtitle(time, force = false) {
  if (cues.length === 0) return;

  // 直前のキューがまだ有効なら何もしない(timeupdate は高頻度で呼ばれるため)
  if (!force && lastCueIndex >= 0) {
    const c = cues[lastCueIndex];
    if (time >= c.start && time <= c.end) return;
  }

  // 二分探索で現在時刻を含むキューを探す
  let lo = 0;
  let hi = cues.length - 1;
  let found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (cues[mid].start > time) {
      hi = mid - 1;
    } else {
      if (time <= cues[mid].end) found = mid;
      lo = mid + 1;
    }
  }

  if (found !== lastCueIndex || force) {
    lastCueIndex = found;
    if (found >= 0) {
      subtitleText.textContent = cues[found].text;
      subtitleText.classList.add("active");
    } else {
      subtitleText.textContent = "";
      subtitleText.classList.remove("active");
    }
  }
}

// ---------- キーボードショートカット ----------

document.addEventListener("keydown", (e) => {
  if (e.target.tagName === "INPUT" && e.target.type !== "range") return;
  switch (e.key) {
    case " ":
      e.preventDefault();
      togglePlay();
      break;
    case "ArrowLeft":
      skip(-10);
      break;
    case "ArrowRight":
      skip(10);
      break;
    case "1":
    case "2":
    case "3":
    case "4": {
      const btn = document.querySelector(`.speed-btn[data-speed="${e.key}"]`);
      if (btn) btn.click();
      break;
    }
  }
});
