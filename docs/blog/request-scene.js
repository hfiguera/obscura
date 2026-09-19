// A deterministic SVG timeline. No animation library, requests, or user data.
(() => {
  const scene = document.querySelector('.request-scene');
  const fallback = document.querySelector('.motion-fallback');
  if (!scene || !fallback || !window.SVGSVGElement || !window.requestAnimationFrame ||
      !window.cancelAnimationFrame || !window.matchMedia ||
      !getComputedStyle(scene).getPropertyValue('--scene-text').trim()) return;
  const duration = 11000;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  if (!reduce.addEventListener) return;
  const play = scene.querySelector('.request-scene-play');
  const seek = scene.querySelector('.request-scene-seek');
  const caption = scene.querySelector('.request-scene-caption');
  const clock = scene.querySelector('.request-scene-time');
  const art = [...scene.querySelectorAll('.request-scene-art')].map(svg => {
    const parts = {};
    svg.querySelectorAll('[data-part]').forEach(el => { parts[el.dataset.part] = el; });
    return parts;
  });
  const progress = (t, start, end) => Math.max(0, Math.min(1, (t - start) / (end - start)));
  const ease = x => x === 1 ? 1 : 1 - Math.pow(2, -10 * x);
  let time = duration;
  let running = false;
  let frame;
  let previous;
  let autoPlayed = false;

  function renderRequest(t) {
    art.forEach(p => {
      const duplicate = ease(progress(t, 1400, 3200));
      p.copy.setAttribute('transform', `translate(${Number(p.copy.dataset.x) * (1 - duplicate)} ${Number(p.copy.dataset.y) * (1 - duplicate)})`);
      p.copy.setAttribute('opacity', progress(t, 1400, 1700));
      p['original-route'].setAttribute('opacity', progress(t, 400, 1000));
      [['email', 3550], ['password', 4750]].forEach(([key, start]) => {
        const cover = ease(progress(t, start, start + 550));
        const uncover = ease(progress(t, start + 700, start + 1150));
        p[`${key}-clip`].setAttribute('width', t < start + 650 ? 216 : 0);
        p[`${key}-mask`].setAttribute('width', 216 * cover * (1 - uncover));
        p[`${key}-mask`].setAttribute('x', 216 * uncover);
        p[`${key}-token`].setAttribute('opacity', t >= start + 650 ? 1 : 0);
      });
      p.scan.setAttribute('opacity', t > 3250 && t < 6100 ? .7 : 0);
      p.scan.setAttribute('transform', `translate(0 ${50 + 115 * progress(t, 3250, 6100)})`);
      [['email', 6450], ['password', 7650]].forEach(([key, start]) => {
        const flight = p[`flight-${key}`];
        const position = ease(progress(t, start, start + 1450));
        const x = Number(flight.dataset.fromX) + (Number(flight.dataset.toX) - Number(flight.dataset.fromX)) * position;
        const y = Number(flight.dataset.fromY) + (Number(flight.dataset.toY) - Number(flight.dataset.fromY)) * position;
        flight.setAttribute('transform', `translate(${x} ${y})`);
        flight.setAttribute('opacity', progress(t, start, start + 180) * (1 - progress(t, start + 1300, start + 1500)));
        p[`log-${key}`].setAttribute('opacity', progress(t, start + 1350, start + 1700));
      });
      p.receipt?.setAttribute('opacity', progress(t, 9600, 10100));
    });
    return t < 1400 ? 'Phoenix parses the request. The controller receives the original values.'
      : t < 3500 ? 'The Plug prepares a separate copy. The original request stays in place.'
      : t < 6400 ? 'Email and password disappear behind the redaction mask. Safe markers take their place.'
      : t < 9500 ? 'Only the sanitized fields cross the logging boundary.'
      : 'Original parameters stay in the application. Only the sanitized copy reaches the log.';
  }

  // Each SVG element describes only its own motion; layouts remain authored per article.
  // Default markup is the completed diagram, so failed scripts retain all conclusions.
  const timelines = [...scene.querySelectorAll('[data-show], [data-hide], [data-shift], [data-drift], [data-draw], [data-mask], [data-flight]')].map(el => ({
    el,
    base: el.getAttribute('transform') || '',
    values: Object.fromEntries(['show', 'hide', 'shift', 'drift', 'draw', 'mask', 'flight'].filter(key => el.dataset[key]).map(key => [key, el.dataset[key].split(' ').map(Number)]))
  }));
  const messages = scene.querySelector('.scene-captions');
  const captions = messages ? JSON.parse(messages.textContent) : null;

  function renderTimeline(t) {
    timelines.forEach(({ el, base, values: v }) => {
      let opacity = 1;
      if (v.show) opacity *= progress(t, ...v.show);
      if (v.hide) opacity *= 1 - progress(t, ...v.hide);
      if (v.show || v.hide) el.setAttribute('opacity', opacity);
      for (const key of ['shift', 'drift']) {
        if (!v[key]) continue;
        const [start, end, x, y] = v[key];
        const f = key === 'shift' ? 1 - ease(progress(t, start, end)) : ease(progress(t, start, end));
        el.setAttribute('transform', `${base} translate(${x*f} ${y*f})`);
      }
      if (v.draw) {
        el.setAttribute('stroke-dasharray', '1');
        el.setAttribute('stroke-dashoffset', 1 - progress(t, ...v.draw));
      }
      if (v.mask) {
        const [start, middle, end, width] = v.mask;
        const cover = ease(progress(t, start, middle));
        const uncover = ease(progress(t, middle, end));
        el.setAttribute('width', width * cover * (1 - uncover));
        el.setAttribute('x', width * uncover);
      }
      if (v.flight) {
        const [start, end, x1, y1, x2, y2] = v.flight;
        const f = ease(progress(t, start, end));
        el.setAttribute('transform', `translate(${x1+(x2-x1)*f} ${y1+(y2-y1)*f})`);
        el.setAttribute('opacity', progress(t, start, start+150) * (1-progress(t, end-150, end)));
      }
    });
    return captions.filter(([start]) => start <= t).at(-1)[1];
  }

  function render(t) {
    const message = captions ? renderTimeline(t) : renderRequest(t);
    if (caption.textContent !== message) caption.textContent = message;
    seek.value = Math.round(t);
    seek.setAttribute('aria-valuetext', `${(t / 1000).toFixed(1)} seconds. ${message}`);
    clock.textContent = `0:${String(Math.floor(t / 1000)).padStart(2, '0')}`;
  }

  function pause() {
    running = false;
    cancelAnimationFrame(frame);
    scene.removeAttribute('data-playing');
    const label = time >= duration ? 'Replay' : 'Play';
    play.querySelector('span').textContent = label;
    play.setAttribute('aria-label', `${label} animation`);
  }

  function tick(now) {
    if (!running) return;
    if (previous !== undefined) time = Math.min(duration, time + now - previous);
    previous = now;
    render(time);
    if (time >= duration) pause();
    else frame = requestAnimationFrame(tick);
  }

  function start() {
    if (reduce.matches) return;
    if (time >= duration) time = 0;
    running = true;
    previous = undefined;
    scene.setAttribute('data-playing', '');
    play.querySelector('span').textContent = 'Pause';
    play.setAttribute('aria-label', 'Pause animation');
    render(time);
    frame = requestAnimationFrame(tick);
  }

  play.addEventListener('click', () => { autoPlayed = true; running ? pause() : start(); });
  seek.addEventListener('input', () => {
    autoPlayed = true;
    pause();
    time = Number(seek.value);
    render(time);
    pause();
  });

  function preference() {
    pause();
    const hadFocus = scene.contains(document.activeElement);
    if (reduce.matches) {
      time = duration;
      render(time);
    }
    scene.querySelector('.request-scene-controls').hidden = reduce.matches;
    scene.hidden = reduce.matches;
    fallback.hidden = !reduce.matches;
    if (reduce.matches && hadFocus) fallback.focus({ preventScroll: true });
  }
  // Keep the image visible if setup or the first render fails.
  render(time);
  reduce.addEventListener('change', preference);
  preference();
  window.addEventListener('beforeprint', pause);
  document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) pause();
      // Play one pass when the reader first reaches the scene. Never loop.
      else if (entry.intersectionRatio >= .35 && !autoPlayed && !reduce.matches && !document.hidden) {
        autoPlayed = true;
        start();
      }
    }, { threshold: [0, .35] });
    observer.observe(scene);
  }
})();
