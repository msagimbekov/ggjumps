"""Synthesises the game's music and sound effects into res://audio/.

Everything is made from scratch (additive / FM synthesis, filtered noise, a convolution
reverb), so there are no third-party samples to license. Re-run after changing a sound:

    python -m pip install numpy scipy soundfile
    python tools/gen_audio.py

The music is rendered once around the loop and its reverb tail is folded back onto the start,
so it loops without a seam.
"""

import os

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def env_adsr(n, a, d, s, r, hold=None):
    """Attack / decay / sustain / release envelope over n samples (times in seconds)."""
    e = np.zeros(n)
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    hold_n = n - r_n if hold is None else int(hold * SR)
    i = np.arange(n)
    e = np.where(i < a_n, i / max(a_n, 1), 1.0)
    dec = (i >= a_n) & (i < a_n + d_n)
    e = np.where(dec, 1.0 - (1.0 - s) * (i - a_n) / max(d_n, 1), e)
    e = np.where(i >= a_n + d_n, s, e)
    rel = i >= hold_n
    level = e[min(hold_n, n - 1)]
    e = np.where(rel, level * np.clip(1.0 - (i - hold_n) / max(r_n, 1), 0, 1), e)
    return e


def lowpass(x, fc, order=2):
    b, a = signal.butter(order, min(fc / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def highpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def sweep_filter(x, f0, f1, q=0.7):
    """Lowpass whose cutoff glides from f0 to f1 (processed in short blocks)."""
    out = np.zeros_like(x)
    block = 256
    zi = None
    n_blocks = (len(x) + block - 1) // block
    for k in range(n_blocks):
        u = k / max(n_blocks - 1, 1)
        fc = f0 * (f1 / f0) ** u
        b, a = signal.butter(2, min(fc / (SR / 2), 0.99), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0.0
        seg = x[k * block:(k + 1) * block]
        y, zi = signal.lfilter(b, a, seg, zi=zi)
        out[k * block:k * block + len(seg)] = y
    return out


def saw(f, t, phase=0.0, top=7000.0):
    """Band-limited sawtooth by additive synthesis."""
    out = np.zeros_like(t)
    k = 1
    while f * k < top and k < 40:
        out += np.sin(2 * np.pi * f * k * t + phase * k) / k
        k += 1
    return out * 0.6


def fm(f, t, ratio, index, decay):
    """Two-operator FM; the index fades so the tone mellows (bells, plucks)."""
    mod = np.sin(2 * np.pi * f * ratio * t) * index * np.exp(-t / decay)
    return np.sin(2 * np.pi * f * t + mod)


def reverb_ir(seconds, damp=5000.0, seed=1):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    decay = np.exp(-t * 6.9 / seconds)
    ir = np.stack([r.standard_normal(n) * decay, r.standard_normal(n) * decay], axis=1)
    for c in range(2):
        ir[:, c] = lowpass(ir[:, c], damp)
    ir[: int(0.012 * SR)] = 0.0  # pre-delay
    return ir / np.sqrt(np.sum(ir ** 2) / 2)


def reverb(stereo, ir, wet):
    out = np.zeros((len(stereo) + len(ir) - 1, 2))
    for c in range(2):
        out[:, c] = signal.fftconvolve(stereo[:, c], ir[:, c])
    dry = np.zeros_like(out)
    dry[: len(stereo)] = stereo
    return dry + out * wet


def pan(mono, p):
    """p = -1 (left) .. 1 (right), equal power."""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def add(buf, x, at):
    i = int(at * SR)
    j = min(i + len(x), len(buf))
    if j > i:
        buf[i:j] += x[: j - i]


def norm(x, peak):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def trim(x, floor_db=-58.0):
    """Cuts the silent end of a one-shot and fades out the last 30 ms."""
    level = np.max(np.abs(x), axis=1) if x.ndim > 1 else np.abs(x)
    loud = np.nonzero(level > 10 ** (floor_db / 20.0))[0]
    end = min(len(x), (loud[-1] if len(loud) else len(x)) + int(0.03 * SR))
    x = x[:end].copy()
    fade = np.linspace(1.0, 0.0, min(int(0.03 * SR), end))
    x[-len(fade):] *= fade[:, None] if x.ndim > 1 else fade
    return x


def write(name, x, peak=0.9):
    x = norm(x, peak)
    path = os.path.join(OUT, name)
    if name.endswith(".ogg"):
        # libsndfile's Vorbis encoder overflows the stack on big writes: feed it in blocks.
        with sf.SoundFile(path, "w", SR, x.shape[1], format="OGG", subtype="VORBIS") as f:
            for i in range(0, len(x), 4096):
                f.write(x[i:i + 4096].astype(np.float32))
    else:
        x = trim(x)
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
    print("wrote", name, "%.2fs" % (len(x) / SR))


# ---------------------------------------------------------------------------- music

BPM = 72.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 24

# Two bars per chord, all soft colours: Dmaj9, Bm9, Gmaj9(#11), Asus2.
CHORDS = [
    [50, 57, 61, 64, 66],  # Dmaj9 (D A C# E F#)
    [47, 54, 57, 61, 62],  # Bm9-ish (B F# A C# D)
    [43, 50, 54, 57, 61],  # Gmaj9 (G D F# A C#)
    [45, 52, 57, 59, 64],  # Asus2 (A E A B E)
]
# Notes the drifting plucks pick from, per chord.
DRIFT = [
    [62, 66, 69, 73, 76, 78],
    [59, 62, 66, 69, 73, 74],
    [62, 66, 67, 69, 73, 74],
    [61, 64, 66, 69, 71, 76],
]
# A few long bell notes over the middle pass: (beat offset in the 2-bar chord, midi, beats).
BELLS = [
    [(0, 78, 3), (4, 76, 4)],
    [(0, 74, 4), (5, 73, 3)],
    [(0, 71, 3), (4, 74, 4)],
    [(0, 73, 6)],
]


def music():
    """Calm ambient loop: slow pads, drifting water-drop plucks with echoes, a soft bass
    hum and faint surf. Gentle motion, no drums, no driving rhythm."""
    r = np.random.default_rng(21)
    length = BARS * BAR
    n = int(length * SR)
    full_n = n + int(6.0 * SR)  # room for the last notes to ring out; folded back onto the start
    pad = np.zeros((full_n, 2))
    drops = np.zeros((full_n, 2))
    bells = np.zeros((full_n, 2))
    bass = np.zeros(full_n)

    # Pad: detuned saws, dark and slow, with an airy sine an octave up.
    for c in range(BARS // 2):
        chord = CHORDS[c % 4]
        start = c * 2 * BAR
        dur = 2 * BAR + 2.0
        t = t_of(dur)
        e = env_adsr(len(t), 1.8, 1.0, 0.85, 2.0)
        for i, m in enumerate(chord):
            voice = np.zeros((len(t), 2))
            for d, p in ((-6, -0.6), (0, 0.0), (6, 0.6)):
                f = hz(m) * 2 ** (d / 1200.0)
                voice += pan(saw(f, t, r.random() * 6.28, top=3000), p)
            for ch in range(2):
                voice[:, ch] = lowpass(voice[:, ch], 1100)
            air = pan(np.sin(2 * np.pi * hz(m + 12) * t + r.random() * 6.28), 0.5 - i * 0.25) * 0.25
            add(pad, (voice + air) * e[:, None] * (0.09 if i else 0.06), start)
    lfo = 0.8 + 0.2 * np.sin(2 * np.pi * np.arange(full_n) / SR / (2 * BAR) - np.pi / 2)
    pad *= lfo[:, None]

    # Drifting plucks: soft bell-like drops on the 8ths, with rests, wandering across the stereo field.
    step = BEAT / 2
    for k in range(int(length / step)):
        bar = int(k * step / BAR)
        if r.random() < (0.45 if bar < 8 else 0.3):
            continue
        notes = DRIFT[(bar // 2) % 4]
        m = notes[r.integers(len(notes))]
        vel = 0.35 + 0.3 * r.random() + (0.15 if k % 4 == 0 else 0.0)
        t = t_of(1.2)
        tone = fm(hz(m), t, 2.0, 0.7, 0.05) * np.exp(-t / 0.38) * np.clip(t / 0.004, 0, 1)
        tone = lowpass(tone, 3800)
        add(drops, pan(tone * vel * 0.16, np.sin(k * 0.37) * 0.6), k * step)
    # Long, soft echoes trailing each drop.
    delay = int(BEAT * 0.75 * SR)
    echo = np.zeros_like(drops)
    for k in range(1, 6):
        shifted = np.zeros_like(drops)
        shifted[delay * k:] = drops[: full_n - delay * k]
        echo += (shifted[:, ::-1] if k % 2 else shifted) * (0.45 ** k)
    for ch in range(2):
        echo[:, ch] = lowpass(echo[:, ch], 2400)
    drops = drops + echo

    # Bass: a quiet hum on each chord root.
    for c in range(BARS // 2):
        t = t_of(2 * BAR + 1.5)
        f = hz(CHORDS[c % 4][0] - 12)
        tone = np.sin(2 * np.pi * f * t) + 0.15 * np.sin(4 * np.pi * f * t)
        add(bass, tone * env_adsr(len(t), 1.2, 0.5, 0.9, 1.5) * 0.16, c * 2 * BAR)

    # Bells: a handful of long, soft notes over the middle pass only.
    for c in range(4, 8):
        start = c * 2 * BAR
        for off, m, beats in BELLS[c % 4]:
            dur = beats * BEAT + 2.5
            t = t_of(dur)
            vib = 1.0 + 0.003 * np.sin(2 * np.pi * 4.5 * t) * np.clip(t / 0.8, 0, 1)
            tone = fm(hz(m) * vib, t, 1.0, 0.8, 0.5)
            tone *= env_adsr(len(t), 0.08, 0.6, 0.5, 2.5, hold=beats * BEAT)
            add(bells, pan(tone * 0.09, -0.2), start + off * BEAT)

    # Faint surf: filtered noise swelling slowly, like waves on a far shore.
    # The loop is a whole number of swells and each starts silent, so the seam is clean.
    surf = lowpass(r.standard_normal(full_n), 500)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(full_n) / SR / (BAR * 1.5) - np.pi / 2)
    swell[n:] = 0.0
    surf = np.stack([surf, np.roll(surf, int(0.013 * SR))], axis=1) * (swell ** 2)[:, None] * 0.05

    mix = pad + drops + bells + pan(lowpass(bass, 400), 0.0) + surf
    ir = reverb_ir(3.8, damp=4000)
    send = pad * 0.7 + drops * 0.7 + bells * 0.9
    wet = reverb(send, ir, 1.0) - np.pad(send, ((0, len(ir) - 1), (0, 0)))
    full = np.zeros((full_n + len(ir) - 1, 2))
    full[:full_n] += mix
    full += wet * 0.45
    # Fold the tail onto the start: a seamless loop.
    out = full[:n].copy()
    tail = full[n:]
    out[: len(tail)] += tail
    return np.tanh(out * 1.05) / 1.05


# ---------------------------------------------------------------------------- effects


def bubble(f0, amp, rise=0.1):
    """One air bubble ringing in water (van den Doel's model): a damped sine whose pitch
    rises as the bubble moves up. Many of these together are what makes water sound wet."""
    d = 0.13 * f0 + 0.0072 * f0 ** 1.5  # damping, bigger for higher (smaller) bubbles
    dur = min(6.0 / d, 0.4)
    t = t_of(dur)
    f = f0 * (1.0 + rise * d * t)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-d * t)
    return x * np.clip(t / 0.0008, 0, 1) * amp


def splash():
    r = np.random.default_rng(11)
    t = t_of(1.0)
    n = len(t)
    x = np.zeros(n)
    # Impact: a sharp, broadband slap of the surface breaking.
    noise = r.standard_normal(n)
    slap = bandpass(noise, 400, 4500) * np.exp(-t / 0.045) * np.clip(t / 0.002, 0, 1)
    body = bandpass(noise, 150, 700) * np.exp(-t / 0.07) * np.clip(t / 0.004, 0, 1)
    x += slap * 0.5 + body * 0.6
    # Spray: a short hiss of water thrown into the air.
    spray = highpass(r.standard_normal(n), 2500) * np.exp(-t / 0.18) * np.clip(t / 0.015, 0, 1)
    x += spray * 0.05
    # The plunk: the air pocket behind the bubble closing, a low bubble with a rising pitch.
    add(x, bubble(420, 0.7, rise=0.25), 0.025)
    add(x, bubble(690, 0.35, rise=0.2), 0.04)
    # The bubble cloud: dozens of small bubbles, most of them right after the impact.
    for k in range(45):
        at = 0.01 + r.exponential(0.09)
        f0 = 700 * (6.0 ** r.random())
        add(x, bubble(f0, (0.08 + 0.18 * r.random()) * (800 / f0) ** 0.4), at)
    # Drops falling back: light plips with a tiny tick, scattered later.
    for k in range(16):
        at = 0.22 + r.random() * 0.55
        f0 = 1400 + 3200 * r.random()
        amp = 0.05 + 0.1 * r.random()
        add(x, bubble(f0, amp, rise=0.15), at)
        tick = highpass(r.standard_normal(int(0.004 * SR)), 3000) * np.exp(-t_of(0.004) / 0.001)
        add(x, tick * amp * 0.6, at - 0.002)
    x = lowpass(x, 7500, order=1)  # water is never crisp at the top
    st = np.stack([x, x], axis=1)
    # A touch of stereo spread on the cloud, and a small outdoor ambience.
    d = int(0.0007 * SR)
    st[d:, 1] = x[:-d] * 0.85 + x[d:] * 0.15
    return reverb(st, reverb_ir(0.5, damp=6000, seed=3), 0.08)


def land(ice=False):
    """A liquid bubble touching down: a soft wet splat with a light 'blip', no weight."""
    r = np.random.default_rng(12 if ice else 13)
    t = t_of(0.35)
    n = len(t)
    x = np.zeros(n)
    # Contact: a tiny, bright tick, then a short wet smack of the skin flattening.
    tick = bandpass(r.standard_normal(n), 2500, 9000) * np.exp(-t / 0.0025)
    smack = bandpass(r.standard_normal(n), 900, 3500) * np.exp(-t / 0.018) * np.clip(t / 0.002, 0, 1)
    x += tick * 0.35 + smack * 0.45
    # The jelly wobble: a quick upward 'blip', then a smaller one as it rebounds.
    f0 = 1250 if ice else 820
    add(x, bubble(f0, 0.55, rise=0.35), 0.003)
    add(x, bubble(f0 * 1.35, 0.18, rise=0.35), 0.075)
    if ice:
        # Glassy: a faint high clink from the hard surface.
        ct = t_of(0.3)
        clink = (np.sin(2 * np.pi * 3150 * ct) + 0.5 * np.sin(2 * np.pi * 4720 * ct)) * np.exp(-ct / 0.06)
        add(x, clink * 0.12, 0.0)
    x = highpass(x, 250)  # nothing heavy underneath
    return reverb(np.stack([x, x], axis=1), reverb_ir(0.35, damp=7000, seed=4), 0.06)


def chime(notes, gap, tail, bright=1.0):
    dur = gap * len(notes) + tail
    out = np.zeros((int(dur * SR), 2))
    for k, m in enumerate(notes):
        t = t_of(tail + 0.3)
        tone = fm(hz(m), t, 1.0, 1.4 * bright, 0.25) * 0.6 + fm(hz(m) * 2, t, 3.5, 1.0 * bright, 0.05) * 0.25
        tone += np.sin(2 * np.pi * hz(m + 12) * t) * 0.12 * np.exp(-t / 0.3)
        tone *= np.exp(-t / (0.5 + 0.1 * k)) * np.clip(t / 0.004, 0, 1)
        add(out, pan(tone, -0.3 + 0.6 * k / max(len(notes) - 1, 1)), k * gap)
    return out


def life():
    x = chime([74, 78, 81, 86, 90], 0.07, 1.1)
    # A sparkly shimmer on top.
    t = t_of(0.9)
    shimmer = np.zeros(len(t))
    for k in range(10):
        shimmer += np.sin(2 * np.pi * hz(98 + (k % 3) * 2) * (1 + 0.001 * k) * t + k) * 0.05
    shimmer *= np.exp(-t / 0.3) * np.clip(t / 0.15, 0, 1)
    add(x, pan(shimmer, 0.2), 0.25)
    return reverb(x, reverb_ir(1.6, damp=7000, seed=5), 0.3)


def drop():
    # Small pop when a bubble is collected: a rising blip.
    t = t_of(0.3)
    f = 500 + 900 * (1 - np.exp(-t / 0.04))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.06) * np.clip(t / 0.003, 0, 1)
    x += fm(hz(91), t, 2.0, 0.6, 0.04) * np.exp(-t / 0.08) * 0.3
    return reverb(pan(x, 0.0), reverb_ir(0.8, damp=6000, seed=6), 0.2)


def sonar(sweep):
    t = t_of(1.6)
    n = len(t)
    x = np.zeros(n)
    at = 0.0
    if sweep:
        # Power-up: a quick rising sweep into the ping.
        st = t_of(0.28)
        f = 300 * (12 ** (st / 0.28))
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * st / 0.28) ** 2
        add(x, s * 0.35, 0.0)
        at = 0.24
    pt = t_of(1.6 - at)
    ping = np.sin(2 * np.pi * 1320 * pt) * 0.8 + np.sin(2 * np.pi * 2640 * pt) * 0.15 * np.exp(-pt / 0.1)
    ping *= np.exp(-pt / 0.35) * np.clip(pt / 0.003, 0, 1)
    add(x, ping * (1.0 if sweep else 0.7), at)
    st = pan(x, 0.0)
    # Sonar echo, panned away.
    d = int(0.32 * SR)
    echo = np.zeros_like(st)
    echo[d:, 1] += st[:-d, 0] * 0.35
    echo[2 * d:, 0] += st[:-2 * d, 0] * 0.15
    return reverb(st + echo, reverb_ir(1.2, damp=5000, seed=8), 0.25)[:n]


def main():
    os.makedirs(OUT, exist_ok=True)
    write("splash.wav", splash(), 0.95)
    write("land.wav", land(), 0.85)
    write("land_ice.wav", land(ice=True), 0.85)
    write("life.wav", life(), 0.85)
    write("drop.wav", drop(), 0.7)
    write("radar_on.wav", sonar(True), 0.8)
    write("radar_ping.wav", sonar(False), 0.6)
    write("music.ogg", music(), 0.8)


if __name__ == "__main__":
    main()
