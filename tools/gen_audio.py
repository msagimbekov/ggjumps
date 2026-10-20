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
    if i < 0:  # a humanised note nudged before the start
        x, i = x[-i:], 0
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

BPM = 84.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 24

# Island progression, two bars each: C, Am, F, G (C major, the classic lazy-beach turn).
ROOTS = [48, 45, 41, 43]
# Ukulele voicings, strings G C E A (re-entrant tuning): C 0003, Am 2000, F 2010, G 0232.
UKE = [
    [67, 60, 64, 72],
    [69, 60, 64, 69],
    [69, 60, 65, 69],
    [67, 62, 67, 71],
]
# Island strum per bar: (beat, down?, velocity).
STRUM = [(0.0, True, 0.9), (1.0, True, 0.6), (1.5, False, 0.45), (2.5, False, 0.5), (3.0, True, 0.7), (3.5, False, 0.45)]
# Steel drum tune, per two-bar chord: (beat, midi, beats).
TUNE = [
    [(0, 76, 1), (1, 79, 1), (2, 81, 1.5), (3.5, 79, 0.5), (4, 76, 2), (6, 74, 2)],
    [(0, 72, 1), (1, 76, 1), (2, 79, 2), (4, 81, 1), (5, 79, 1), (6, 76, 2)],
    [(0, 77, 1.5), (1.5, 76, 0.5), (2, 74, 1), (3, 72, 1), (4, 74, 2), (6, 69, 2)],
    [(0, 71, 1), (1, 74, 1), (2, 79, 2), (4, 77, 1), (5, 76, 1), (6, 74, 2)],
]
# Marimba broken chords for the last pass.
MARIMBA = [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]]


def pluck(f, dur, seed, bright=7000.0, decay=0.9965):
    """Karplus-Strong string: a burst of noise circulating in a delay line, losing its
    highs each pass. Nylon/ukulele-like with a soft excitation and short sustain."""
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    period = SR / f
    d = int(period)
    a = period - d  # fractional part, by linear interpolation
    y = np.zeros(n + d + 1)
    # A finger pulls the string into a triangle (plucked a fifth of the way along), which keeps
    # the fundamental strong and the overtones falling off softly; a little noise adds the grain.
    x = np.linspace(0.0, 1.0, d + 1)
    burst = np.where(x < 0.2, x / 0.2, (1.0 - x) / 0.8)
    burst = burst - burst.mean() + 0.4 * lowpass(r.standard_normal(d + 1), bright)
    y[: d + 1] = burst
    k = d + 1
    while k < len(y):
        end = min(k + d, len(y))
        m = end - k
        y[k:end] = decay * ((1 - a) * y[k - d:k - d + m] + a * y[k - d - 1:k - d - 1 + m])
        k = end
    out = y[d + 1:d + 1 + n]
    # A little wooden body resonance.
    body = bandpass(out, 180, 320) * 0.3 + bandpass(out, 420, 700) * 0.2
    return (out + body) * np.clip(np.arange(n) / (0.002 * SR), 0, 1)


def marimba(f, dur):
    t = t_of(dur)
    tone = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.5)
    tone += 0.25 * np.sin(2 * np.pi * f * 3.98 * t) * np.exp(-t / 0.09)
    tone += 0.08 * np.sin(2 * np.pi * f * 9.9 * t) * np.exp(-t / 0.025)
    return tone * np.clip(t / 0.003, 0, 1)


def steel_pan(f, dur):
    """Steel drum: strong octave and twelfth partials that bloom a moment after the hit."""
    t = t_of(dur)
    tone = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.9)
    tone += 0.55 * np.sin(2 * np.pi * f * 2.003 * t) * np.exp(-t / 0.45) * np.clip(t / 0.02, 0, 1)
    tone += 0.3 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t / 0.22)
    tone += 0.12 * np.sin(2 * np.pi * f * 4.02 * t) * np.exp(-t / 0.08)
    tone *= 1.0 + 0.04 * np.sin(2 * np.pi * 5.5 * t)  # the shimmer of the pan
    ping = bandpass(rng.standard_normal(len(t)), 2000, 6000) * np.exp(-t / 0.004) * 0.3
    return (tone + ping) * np.clip(t / 0.002, 0, 1)


def wave_event(dur, seed):
    """One wave rolling in: a rumble that swells, crashes bright, then hisses away as foam."""
    r = np.random.default_rng(seed)
    t = t_of(dur)
    n = len(t)
    u = t / dur
    swell = np.sin(np.pi * np.clip(u / 0.35, 0, 1) / 2) ** 2 * np.exp(-np.clip(t - 0.35 * dur, 0, None) / (0.3 * dur))
    out = np.zeros((n, 2))
    for ch in range(2):
        noise = r.standard_normal(n)
        wash = sweep_filter(noise, 220, 1600)
        wash = np.where(u < 0.4, wash, sweep_filter(noise, 1600, 380))  # brightest as it breaks
        foam = highpass(r.standard_normal(n), 3000) * np.clip((t - 0.3 * dur) / (0.15 * dur), 0, 1) * np.exp(-np.clip(t - 0.45 * dur, 0, None) / (0.2 * dur))
        out[:, ch] = wash * swell + foam * 0.25
    return out


def gull(seed):
    """A far-off gull: a few nasal 'kyow' calls gliding down."""
    r = np.random.default_rng(seed)
    out = np.zeros(int(1.8 * SR))
    for k in range(3):
        t = t_of(0.32 - 0.03 * k)
        f0 = 1850 - 120 * k + r.random() * 60
        f = f0 * (1 + 0.15 * np.sin(np.pi * t / t[-1])) - 500 * (t / t[-1]) ** 2
        ph = 2 * np.pi * np.cumsum(f) / SR
        call = np.tanh(2.2 * np.sin(ph + 1.5 * np.sin(ph)))
        call *= np.sin(np.pi * t / t[-1]) ** 0.6 * (1 + 0.3 * np.sin(2 * np.pi * 38 * t))
        add(out, bandpass(call, 900, 4500), 0.05 + k * 0.45)
    return out


def music():
    """Island loop: ukulele strum, round bass, shaker, a steel drum tune, marimba and the sea.
    Three passes of the C-Am-F-G turn: strum and sea; + steel drum; + marimba."""
    r = np.random.default_rng(31)
    length = BARS * BAR
    n = int(length * SR)
    full_n = n + int(6.0 * SR)  # room for tails; folded back onto the start
    uke = np.zeros((full_n, 2))
    bass = np.zeros(full_n)
    perc = np.zeros((full_n, 2))
    lead = np.zeros((full_n, 2))
    sea = np.zeros((full_n, 2))

    strings = {}
    for chord in UKE:
        for m in chord:
            for v in range(3):
                strings.setdefault((m, v), pluck(hz(m), 2.2, seed=m * 10 + v))

    for b in range(BARS):
        chord = UKE[(b // 2) % 4]
        for beat, down, vel in STRUM:
            at = max(b * BAR + beat * BEAT + r.normal(0, 0.006), 0.0)
            order = chord if down else chord[::-1][:3]  # up strums catch the top strings
            gap = 0.016 if down else 0.011
            for i, m in enumerate(order):
                s = strings[(m, int(r.integers(3)))] * vel * (0.85 + 0.3 * r.random())
                # Strings fan out across the stereo field a little.
                add(uke, pan(s * 0.2, -0.35 + 0.23 * chord.index(m)), at + i * gap)

        # Bass: root on 1, fifth on 3, a passing note on the "and" of 4.
        root = ROOTS[(b // 2) % 4]
        for beat, m, length_b in [(0, root, 1.5), (2, root + 7, 1.25), (3.5, root + (12 if b % 2 == 0 else 5), 0.5)]:
            t = t_of(length_b * BEAT + 0.15)
            f = hz(m)
            tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.1)
            tone *= np.exp(-t / 0.7) * env_adsr(len(t), 0.008, 0.05, 1.0, 0.12)
            add(bass, tone * 0.24, b * BAR + beat * BEAT)

        # Shaker on the 8ths (laid back, slightly swung) and a soft hand drum.
        for e in range(8):
            at = b * BAR + e * BEAT / 2 + (0.035 if e % 2 else 0.0)
            t = t_of(0.09)
            sh = bandpass(r.standard_normal(len(t)), 5000, 11000) * np.sin(np.pi * np.clip(t / 0.07, 0, 1)) ** 2
            add(perc, pan(sh * (0.12 if e % 2 else 0.07), 0.35), at)
        for beat, f, v in [(1.5, 210, 0.5), (3.0, 160, 0.6), (3.5, 210, 0.35)]:
            t = t_of(0.3)
            drum = np.sin(2 * np.pi * f * (1 + 0.15 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.09)
            drum += bandpass(r.standard_normal(len(t)), 800, 3000) * np.exp(-t / 0.008) * 0.3
            add(perc, pan(drum * v * 0.22, -0.3), b * BAR + beat * BEAT)

    # Steel drum tune on the second and third pass (with a little echo, played a bit loose).
    for c in range(4, 12):
        for off, m, beats in TUNE[c % 4]:
            if c >= 8 and off >= 4:
                continue  # last pass: only the first half of each phrase, the marimba answers
            note = steel_pan(hz(m), beats * BEAT + 1.0) * 0.17
            add(lead, pan(note, 0.15), c * 2 * BAR + off * BEAT + r.normal(0, 0.008))
    # Marimba rolling broken chords on the last pass.
    for b in range(16, BARS):
        notes = MARIMBA[(b // 2) % 4]
        for e in range(8):
            if r.random() < 0.3:
                continue
            m = notes[[0, 2, 1, 3, 2, 1, 3, 2][e]] + 12
            add(lead, pan(marimba(hz(m), 0.8) * 0.11 * (1.0 if e % 2 == 0 else 0.7), -0.4), b * BAR + e * BEAT / 2)

    # The sea: waves every few seconds plus a constant low surf, and two distant gulls.
    at = 0.0
    k = 0
    while at < length:
        dur = 5.5 + r.random() * 2.5
        add(sea, wave_event(dur, seed=100 + k) * (0.09 + 0.04 * r.random()), at)
        at += dur * (0.75 + 0.2 * r.random())
        k += 1
    # Constant surf, crossfaded over its own seam so the loop point is silent.
    rumble = np.stack([lowpass(r.standard_normal(full_n), 260), lowpass(r.standard_normal(full_n), 260)], axis=1)
    fade = int(2.0 * SR)
    ramp = np.linspace(0.0, 1.0, fade)[:, None]
    rumble[:fade] = rumble[:fade] * ramp + rumble[n:n + fade] * (1.0 - ramp)
    sea[:n] += rumble[:n] * 0.045
    for at, s, p in [(9.5, 1, -0.7), (44.0, 2, 0.6)]:
        add(sea, pan(gull(s) * 0.035, p), at)

    mix = uke + pan(lowpass(bass, 700), 0.0) + perc + lead + sea
    ir = reverb_ir(1.9, damp=5000)
    send = uke * 0.35 + lead * 0.6 + perc * 0.2 + sea * 0.3
    wet = reverb(send, ir, 1.0) - np.pad(send, ((0, len(ir) - 1), (0, 0)))
    full = np.zeros((full_n + len(ir) - 1, 2))
    full[:full_n] += mix
    full += wet * 0.3
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
