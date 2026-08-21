// Звуковое оповещение о новом заказе — WebAudio, без файлов.
// Автoplay-политика: AudioContext разблокируется по первому клику/тапу.

let ctx: AudioContext | null = null;

function getContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AC) return null;
  if (!ctx) ctx = new AC();
  return ctx;
}

export function unlockAudio() {
  const c = getContext();
  if (c && c.state === 'suspended') {
    void c.resume();
  }
}

// Короткое beep-арпеджио из трёх нот (вверх), ~0.5 сек.
export function playNewOrderSound() {
  const c = getContext();
  if (!c) return;
  if (c.state === 'suspended') void c.resume();

  const notes = [880, 1174.66, 1567.98]; // A5, D6, G6
  const noteLen = 0.14;
  const startAt = c.currentTime + 0.01;

  notes.forEach((freq, i) => {
    const osc = c.createOscillator();
    const gain = c.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;

    const t0 = startAt + i * noteLen;
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.exponentialRampToValueAtTime(0.25, t0 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + noteLen);

    osc.connect(gain).connect(c.destination);
    osc.start(t0);
    osc.stop(t0 + noteLen + 0.02);
  });

  // Второй заход арпеджио для заметности
  notes.forEach((freq, i) => {
    const osc = c.createOscillator();
    const gain = c.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;

    const t0 = startAt + 0.5 + i * noteLen;
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.exponentialRampToValueAtTime(0.25, t0 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + noteLen);

    osc.connect(gain).connect(c.destination);
    osc.start(t0);
    osc.stop(t0 + noteLen + 0.02);
  });
}
