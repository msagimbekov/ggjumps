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

BPM = 108.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 32

# Two bars per chord. D major with a lydian lift: Dmaj9, Bm11, Gmaj9(#11), Asus -> A.
CHORDS = [
    [50, 57, 61, 64, 66],  # Dmaj9 (D A C# E F#)
    [47, 54, 57, 61, 62],  # Bm11-ish (B F# A C# D)
    [43, 50, 54, 57, 61],  # Gmaj9 (G D F# A C#)
    [45, 52, 57, 59, 64],  # Asus (A E A B E)
]
ARP = [
    [62, 66, 69, 73, 74, 73, 69, 66],
    [59, 62, 66, 69, 71, 69, 66, 62],
    [62, 66, 67, 71, 73, 71, 67, 66],
    [61, 64, 69, 71, 73, 71, 69, 64],
]
# Lead motif (bars 17-24), (beat offset, midi, beats) relative to each 2-bar chord.
LEAD = [
    [(0, 78, 1.5), (1.5, 76, 0.5), (2, 73, 2), (5, 74, 1), (6, 76, 2)],
    [(0, 74, 1.5), (1.5, 73, 0.5), (2, 71, 3), (6, 69, 2)],
    [(0, 71, 1), (1, 73, 1), (2, 74, 2), (4, 78, 1.5), (5.5, 76, 2.5)],
    [(0, 76, 3), (3, 73, 1), (4, 71, 4)],
]


def section(bar):
    """0 = intro (pad + arp), 1 = groove, 2 = groove + lead, 3 = breather."""
    return bar // 8


def music():
    length = BARS * BAR
    n = int(length * SR)
    pad = np.zeros((n, 2))
    arp = np.zeros((n, 2))
    bass = np.zeros(n)
    drums = np.zeros((n, 2))
    lead = np.zeros((n, 2))
    duck = np.ones(n)

    # Pad: detuned saws through a soft lowpass, chords crossfading.
    for c in range(BARS // 2):
        chord = CHORDS[c % 4]
        start = c * 2 * BAR
        dur = 2 * BAR + 0.8
        t = t_of(dur)
        e = env_adsr(len(t), 0.7, 0.5, 0.85, 0.9)
        brightness = [1400, 2200, 2600, 1100][section(c * 2)]
        for i, m in enumerate(chord):
            voice = np.zeros((len(t), 2))
            for d, p in ((-7, -0.7), (0, 0.0), (7, 0.7)):
                f = hz(m) * 2 ** (d / 1200.0)
                voice += pan(saw(f, t, rng.random() * 6.28, top=4000), p)
            for ch in range(2):
                voice[:, ch] = lowpass(voice[:, ch], brightness)
            add(pad, voice * e[:, None] * (0.10 if i else 0.07), start)
    # Slow swell so the pad breathes with each chord.
    lfo = 0.85 + 0.15 * np.sin(2 * np.pi * np.arange(n) / SR / (2 * BAR) - np.pi / 2)
    pad *= lfo[:, None]

    # Arp: FM plucks in 16ths, bouncing left/right.
    step = BEAT / 4
    for k in range(int(length / step)):
        at = k * step
        bar = int(at / BAR)
        notes = ARP[(bar // 2) % 4]
        sec = section(bar)
        m = notes[k % 8] + (12 if sec == 2 and k % 16 >= 8 else 0)
        vel = 0.55 + 0.45 * (k % 4 == 0) - 0.15 * (k % 2)
        if sec == 3:
            vel *= 0.6
        t = t_of(0.45)
        tone = fm(hz(m), t, 2.0, 1.6, 0.06) * np.exp(-t / 0.13)
        tone = lowpass(tone, 5200)
        add(arp, pan(tone * vel * 0.22, 0.45 if k % 2 else -0.45), at)
    # Dotted-eighth ping-pong echo on the arp: the rushing feel.
    delay = int(BEAT * 0.75 * SR)
    echo = np.zeros_like(arp)
    fb = 0.42
    src = arp.copy()
    for k in range(1, 5):
        shifted = np.zeros_like(arp)
        shifted[delay * k:] = src[: n - delay * k]
        shifted = shifted[:, ::-1] if k % 2 else shifted
        echo += shifted * (fb ** k)
    for ch in range(2):
        echo[:, ch] = lowpass(echo[:, ch], 3500)
    arp = arp + echo

    # Bass and drums in the groove sections.
    for b in range(BARS):
        sec = section(b)
        root = CHORDS[(b // 2) % 4][0] - 12
        for beat in range(4):
            at = b * BAR + beat * BEAT
            if sec in (1, 2) or (sec == 3 and b >= 30):
                # Kick: sine with a quick pitch drop.
                t = t_of(0.35)
                f = 48 + 90 * np.exp(-t / 0.03)
                kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
                kick += 0.25 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR) * np.exp(-t / 0.015)
                add(drums, pan(kick * 0.55, 0.0), at)
                # Duck the pad and bass a little on each beat.
                d = 1.0 - 0.38 * np.exp(-t_of(BEAT) / 0.14)
                i0 = int(at * SR)
                duck[i0:i0 + len(d)] = np.minimum(duck[i0:i0 + len(d)], d[: n - i0])
            if sec in (1, 2):
                # Offbeat hat and soft 16th shaker.
                for s in range(4):
                    t = t_of(0.12 if s == 2 else 0.05)
                    noise = highpass(rng.standard_normal(len(t)), 7000 if s == 2 else 9000)
                    hat = noise * np.exp(-t / (0.035 if s == 2 else 0.012))
                    add(drums, pan(hat * (0.16 if s == 2 else 0.06), 0.3 if s % 2 else -0.2), at + s * BEAT / 4)
                if beat in (1, 3):
                    # Finger-snap / rim on 2 and 4.
                    t = t_of(0.18)
                    snap = bandpass(rng.standard_normal(len(t)), 1500, 5500) * np.exp(-t / 0.035)
                    snap += 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-t / 0.02)
                    add(drums, pan(snap * 0.22, 0.1), at)
            if sec in (1, 2):
                # Bass: round 8ths, the second one an octave up.
                for half in range(2):
                    t = t_of(BEAT / 2)
                    f = hz(root + (12 if half and beat % 2 else 0))
                    tone = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)
                    tone = np.tanh(tone * 1.4) * env_adsr(len(t), 0.005, 0.1, 0.7, 0.06)
                    add(bass, tone * 0.32, at + half * BEAT / 2)
    bass = lowpass(bass, 900)

    # Lead: soft FM bell melody in section 2.
    for c in range(8, 12):
        start = c * 2 * BAR
        for off, m, beats in LEAD[c % 4]:
            dur = beats * BEAT + 1.2
            t = t_of(dur)
            vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.4, 0, 1)
            tone = fm(hz(m) * vib, t, 1.0, 1.1, 0.4) * 0.7 + fm(hz(m), t, 3.5, 0.8, 0.08) * 0.3
            tone *= env_adsr(len(t), 0.02, 0.3, 0.55, 1.2, hold=beats * BEAT)
            add(lead, pan(tone * 0.17, -0.15), start + off * BEAT)

    pad *= duck[:, None]
    mix = pad + arp * 0.9 + lead + pan(bass * duck, 0.0) + drums
    # Reverb on everything but the low end; more on pad, arp and lead.
    ir = reverb_ir(2.6, damp=4500)
    send = pad * 0.6 + arp * 0.5 + lead * 0.7 + drums * 0.08
    wet = reverb(send, ir, 1.0)[:, :] - np.pad(send, ((0, len(ir) - 1), (0, 0)))
    full = np.zeros((n + len(ir) - 1, 2))
    full[:n] += mix
    full += wet * 0.35
    # Fold the tail onto the start: a seamless loop.
    out = full[:n].copy()
    tail = full[n:]
    out[: len(tail)] += tail
    out = np.tanh(out * 1.1) / 1.1
    return out


# ---------------------------------------------------------------------------- effects


def splash():
    t = t_of(1.1)
    n = len(t)
    noise = rng.standard_normal(n)
    # Body: a filtered noise burst that opens then closes, like water parting.
    body = sweep_filter(noise, 4500, 500) * np.exp(-t / 0.18)
    body += bandpass(noise, 300, 1400) * np.exp(-t / 0.35) * 0.5
    # The plunge: a deep bloop whose pitch drops.
    f = 380 * np.exp(-t / 0.12) + 90
    bloop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    x = body * 0.7 + bloop * 0.6
    # Falling droplets: tiny rising chirps scattered over the first half second.
    for k in range(14):
        at = 0.06 + rng.random() * 0.5
        dt = t_of(0.05)
        f0 = 900 + rng.random() * 1800
        chirp = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 1.6 * dt / 0.05)) / SR) * np.exp(-dt / 0.012)
        add(x, chirp * (0.08 + rng.random() * 0.1), at)
    x = np.tanh(x * 1.5)
    st = reverb(pan(x, 0.0), reverb_ir(0.9, damp=3500, seed=3), 0.22)
    return st


def land(ice=False):
    t = t_of(0.5)
    # Soft jelly plop: a short pitch drop plus a little wobble as the bubble settles.
    base = 520 if ice else 300
    f = base * np.exp(-t / 0.025) + (240 if ice else 120)
    f *= 1 + 0.06 * np.sin(2 * np.pi * 14 * t) * np.exp(-t / 0.1)
    plop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
    thump = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.05)
    tap = bandpass(rng.standard_normal(len(t)), 800, 4000) * np.exp(-t / 0.006)
    x = plop * 0.8 + thump * (0.2 if ice else 0.55) + tap * 0.25
    if ice:
        # Glassy sparkle and a short hiss of sliding.
        for k, m in enumerate([88, 95, 100]):
            add(x, fm(hz(m), t_of(0.4), 1.4, 0.8, 0.05) * np.exp(-t_of(0.4) / 0.08) * 0.12, 0.01 + k * 0.03)
        x += highpass(rng.standard_normal(len(t)), 5000) * np.exp(-t / 0.12) * 0.05
    st = reverb(pan(x, 0.0), reverb_ir(0.6, damp=5000, seed=4), 0.12)
    return st


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
