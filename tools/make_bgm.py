"""BGM と一部の効果音（伐採音）を合成して assets/audio に書き出す。

フリー素材に森の作業ゲーム向けの BGM が無かったため、このスクリプトで自作している（ライセンスはリポジトリと同じ扱い）。
  pip install numpy
  python tools/make_bgm.py      # ffmpeg があれば .ogg、無ければ .wav を出力

BGM: 96 BPM・ハ長調、I-vi-IV-V の進行。アコギ風のアルペジオ（Karplus-Strong）、マリンバ風メロディ、
     ベース、パッド、軽いパーカッション。ループの継ぎ目が切れないよう末尾の余韻を先頭に重ねている。
"""
import pathlib
import shutil
import subprocess
import wave

import numpy as np

SR = 32000
BPM = 96
BEAT = 60.0 / BPM
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "audio"
rng = np.random.default_rng(7)


def midi_hz(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


def pluck(freq: float, dur: float) -> np.ndarray:
    """Karplus-Strong のギター風の音。"""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    # 少し丸めた初期ノイズで柔らかい音にする
    buf = np.convolve(buf, np.ones(3) / 3, mode="same")
    out = np.empty(n)
    decay = 0.996
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = decay * 0.5 * (buf[j] + buf[(i + 1) % period])
    fade = np.minimum(1, np.linspace(0, dur, n)[::-1] / 0.05)
    return out * fade


def marimba(freq: float, dur: float) -> np.ndarray:
    t = np.arange(int(dur * SR)) / SR
    env = np.exp(-t * 6.0)
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t * 18)
    attack = np.minimum(1, t / 0.004)
    return tone * env * attack


def bass(freq: float, dur: float) -> np.ndarray:
    t = np.arange(int(dur * SR)) / SR
    env = np.exp(-t * 2.2) * np.minimum(1, t / 0.01)
    rel = np.minimum(1, (dur - t) / 0.06)
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    return tone * env * rel


def pad(freqs, dur: float) -> np.ndarray:
    t = np.arange(int(dur * SR)) / SR
    out = np.zeros_like(t)
    for f in freqs:
        for det in (-0.6, 0.6):
            ff = f + det
            out += np.sin(2 * np.pi * ff * t) + 0.3 * np.sin(2 * np.pi * ff * 2 * t) + 0.12 * np.sin(2 * np.pi * ff * 3 * t)
    env = np.minimum(1, t / 0.6) * np.minimum(1, (dur - t) / 0.6)
    return out * env / (len(freqs) * 2)


def kick() -> np.ndarray:
    t = np.arange(int(0.25 * SR)) / SR
    f = 110 * np.exp(-t * 25) + 45
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t * 14)


def shaker() -> np.ndarray:
    t = np.arange(int(0.08 * SR)) / SR
    noise = np.diff(rng.uniform(-1, 1, len(t) + 1))
    return noise * np.exp(-t * 60) * np.minimum(1, t / 0.006)


def add(track: np.ndarray, sig: np.ndarray, start: float, gain: float) -> None:
    i = int(start * SR)
    end = min(len(track), i + len(sig))
    track[i:end] += sig[: end - i] * gain


def make_bgm() -> np.ndarray:
    bars = 16
    loop_len = bars * 4 * BEAT
    tail = 2.0
    total = loop_len + tail
    left = np.zeros(int(total * SR))
    right = np.zeros(int(total * SR))

    # C, Am, F, G （各1小節）。コードトーンは MIDI 番号
    chords = [
        ([48, 52, 55, 60, 64], 36),
        ([45, 52, 57, 60, 64], 33),
        ([41, 48, 53, 57, 60], 29),
        ([43, 50, 55, 59, 62], 31),
    ]
    arp_pattern = [0, 2, 3, 4, 3, 2, 1, 2]
    # メロディ（ペンタトニック中心、8分音符単位、None は休符）
    melody = [
        [72, None, 74, 76, None, 79, 76, None],
        [76, None, 74, 72, None, 69, None, None],
        [69, None, 72, 74, None, 72, 69, 67],
        [67, None, 69, 71, 74, None, None, None],
        [72, 74, 76, None, 79, None, 81, 79],
        [76, None, 74, None, 72, 74, 76, None],
        [77, None, 76, 74, None, 72, 69, None],
        [71, None, 72, 74, None, None, None, None],
    ]

    for bar in range(bars):
        notes, bass_note = chords[bar % 4]
        t0 = bar * 4 * BEAT
        # パッド
        p = pad([midi_hz(n) for n in notes[1:4]], 4 * BEAT + 0.4)
        add(left, p, t0, 0.07)
        add(right, p, t0, 0.07)
        # アルペジオ（右寄り）
        for k, idx in enumerate(arp_pattern):
            s = pluck(midi_hz(notes[idx]), 1.2)
            add(right, s, t0 + k * BEAT / 2, 0.20)
            add(left, s, t0 + k * BEAT / 2, 0.09)
        # ベース
        for k in (0, 2):
            b = bass(midi_hz(bass_note), 1.6 * BEAT)
            add(left, b, t0 + k * BEAT, 0.30)
            add(right, b, t0 + k * BEAT, 0.30)
        # パーカッション（最初の2小節は控えめに入る）
        perc = 0.5 if bar < 2 else 1.0
        for k in (0, 2):
            kk = kick()
            add(left, kk, t0 + k * BEAT, 0.28 * perc)
            add(right, kk, t0 + k * BEAT, 0.28 * perc)
        for k in range(8):
            sh = shaker()
            g = (0.05 if k % 2 == 0 else 0.08) * perc
            add(left, sh, t0 + k * BEAT / 2 + 0.01, g)
            add(right, sh, t0 + k * BEAT / 2, g * 0.8)
        # メロディ（後半8小節、左寄り）
        if bar >= 8:
            for k, n in enumerate(melody[bar - 8]):
                if n is None:
                    continue
                m = marimba(midi_hz(n), 1.0)
                add(left, m, t0 + k * BEAT / 2, 0.16)
                add(right, m, t0 + k * BEAT / 2, 0.10)

    # 末尾の余韻を先頭に重ねてシームレスなループにする
    n_loop = int(loop_len * SR)
    stereo = np.stack([left, right], axis=1)
    out = stereo[:n_loop].copy()
    rest = stereo[n_loop:]
    out[: len(rest)] += rest
    peak = np.max(np.abs(out))
    return out / peak * 0.85


def make_chop() -> np.ndarray:
    """斧が木に当たる「コッ」という音。"""
    t = np.arange(int(0.22 * SR)) / SR
    body = np.sin(2 * np.pi * 180 * t * (1 - t * 1.5)) * np.exp(-t * 35)
    knock = np.sin(2 * np.pi * 520 * t) * np.exp(-t * 60) * 0.5
    noise = np.diff(rng.uniform(-1, 1, len(t) + 1)) * np.exp(-t * 90) * 0.6
    sig = body + knock + noise
    sig = sig / np.max(np.abs(sig)) * 0.9
    return np.stack([sig, sig], axis=1)


def make_tree_fall() -> np.ndarray:
    """木が倒れる「メキメキ…ドサッ」。"""
    dur = 1.1
    t = np.arange(int(dur * SR)) / SR
    crack = np.zeros_like(t)
    for c in rng.uniform(0.0, 0.45, 14):
        i = int(c * SR)
        n = int(0.03 * SR)
        crack[i:i + n] += np.diff(rng.uniform(-1, 1, n + 1))[: len(crack[i:i + n])] * np.exp(-np.arange(n) / SR * 120)
    thud_t = np.maximum(0, t - 0.55)
    thud = np.sin(2 * np.pi * 70 * thud_t * (1 - thud_t)) * np.exp(-thud_t * 9) * (t > 0.55)
    rustle = np.diff(rng.uniform(-1, 1, len(t) + 1)) * np.exp(-thud_t * 6) * (t > 0.55) * 0.25
    sig = crack * 0.6 + thud + rustle
    sig = sig / np.max(np.abs(sig)) * 0.9
    return np.stack([sig, sig], axis=1)


def write(name: str, data: np.ndarray) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    wav_path = OUT_DIR / f"{name}.wav"
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if shutil.which("ffmpeg"):
        ogg = OUT_DIR / f"{name}.ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4", str(ogg)], check=True)
        wav_path.unlink()
        print(ogg, ogg.stat().st_size // 1024, "KB")
    else:
        print(wav_path)


if __name__ == "__main__":
    write("bgm_forest", make_bgm())
    write("chop", make_chop())
    write("tree_fall", make_tree_fall())
