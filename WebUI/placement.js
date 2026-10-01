// Where a still image sits on a display: the inspector's Position on screen section for the
// pictures this app packages (imported images and pixiv pages). The picture is shown in a frame
// with the target display's proportions, laid out the way the wallpaper page lays it out (the
// chosen Image fit, times a zoom, with the overflow aligned by a horizontal and a vertical
// fraction), and can be dragged there or moved with the sliders and arrow keys. Native keeps the
// placement per display (`imagePlacement` in the snapshot) and applies it to the wallpaper; the
// page holds only the values being dragged until they are sent.
import { t } from './i18n.js';

const ZOOM_MIN = 1, ZOOM_MAX = 3;
const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const fraction = (value, fallback) => Number.isFinite(Number(value)) ? clamp(Number(value), 0, 1) : fallback;
const round = (value) => Math.round(value * 1000) / 1000;

export function createPlacement({ send, render, escapeHTML, icon, button, keyAttr, disabled, busy, safeImage }) {
  let state = null;
  let draft = null; // { x, y, zoom } while dragging or sliding, until native has the values.
  let drag = null; // { pointerId, startX, startY, x, y, overflowX, overflowY }
  let container = null;

  const placement = () => state?.imagePlacement;
  const shown = (item) => placement() && placement().wallpaperID === item.id;
  // Only a reset locks the controls: ordinary sends coalesce, so dragging on is allowed.
  const pending = () => { const data = placement(); return Boolean(data) && busy('imagePlacementReset', { id: data.wallpaperID, displayID: data.displayID }); };
  const displayTitle = () => (state?.displays || []).find(display => display.id === placement()?.displayID)?.title || '';
  function values() {
    const data = placement() || {};
    const base = { x: fraction(data.x, 0.5), y: fraction(data.y, data.fit === 'fill-top' ? 0 : 0.5), zoom: Number.isFinite(Number(data.zoom)) ? clamp(Number(data.zoom), ZOOM_MIN, ZOOM_MAX) : 1 };
    return draft ? { ...base, ...draft } : base;
  }

  function sync(snapshot) {
    const before = placement();
    state = snapshot;
    const now = placement();
    // A different wallpaper or display, or a placement that changed underneath, drops the draft.
    if (!now || !before || now.wallpaperID !== before.wallpaperID || now.displayID !== before.displayID) { draft = null; drag = null; }
  }

  const slider = (id, key, label, value, min, max, output) => `<div class="field placement-field" ${keyAttr(`placement-${key}`)}><label for="placement-${key}">${escapeHTML(label)}</label><div class="range-field"><input id="placement-${key}" type="range" min="${min}" max="${max}" step="1" value="${Math.round(value)}" data-change="placement" data-placement="${key}" data-id="${escapeHTML(id)}"${disabled(pending())}><output>${escapeHTML(output)}</output></div></div>`;
  const percent = (value) => `${Math.round(value * 100)}%`;
  const times = (value) => `${(Math.round(value * 100) / 100).toFixed(2)}×`;

  function section(item) {
    if (!shown(item)) return '';
    const data = placement();
    const id = item.id;
    const title = displayTitle();
    const head = `<summary>${escapeHTML(t('Position on screen'))}${icon('chevronRight', 14)}</summary>`;
    if (data.supported === false) {
      return `<section class="inspector-section"><details open ${keyAttr(`placement-${id}`)}>${head}<div class="section-content"><p class="muted"><small>${escapeHTML(data.reason || t('This picture cannot be positioned on the target display right now.'))}</small></p></div></details></section>`;
    }
    const current = values();
    const source = safeImage(item.preview);
    const stage = `<div class="placement-stage" tabindex="0" role="img" aria-roledescription="${escapeHTML(t('draggable picture'))}" aria-label="${escapeHTML(t('Picture position on {display}: {x} across, {y} down, {zoom} zoom. Drag, or use the arrow keys to move it.', { display: title, x: percent(current.x), y: percent(current.y), zoom: times(current.zoom) }))}" data-id="${escapeHTML(id)}" data-fit="${escapeHTML(data.fit || 'fill')}" ${keyAttr(`placement-stage-${id}`)}>${source ? `<img src="${escapeHTML(source)}" alt="" draggable="false" decoding="async" referrerpolicy="no-referrer">` : ''}</div>`;
    const note = data.fit === 'blur'
      ? t('The wallpaper also fills the edges with a blurred copy of the picture; the frame shows the picture alone.')
      : data.fit === 'center' && !(data.imagePixelSize && data.displayViewportSize) ? t('Original size cannot be previewed exactly here; the frame shows the picture fitted.') : '';
    return `<section class="inspector-section"><details open ${keyAttr(`placement-${id}`)}>${head}<div class="section-content placement">`
      + `<p class="muted"><small>${escapeHTML(t('On {display}. Drag the picture in the frame, or use the sliders. Each display keeps its own position.', { display: title }))}</small></p>`
      + stage
      + slider(id, 'x', t('Horizontal position'), current.x * 100, 0, 100, percent(current.x))
      + slider(id, 'y', t('Vertical position'), current.y * 100, 0, 100, percent(current.y))
      + slider(id, 'zoom', t('Zoom'), current.zoom * 100, ZOOM_MIN * 100, ZOOM_MAX * 100, times(current.zoom))
      + `<div class="actions">${button(t('Reset to Image fit'), 'imagePlacementReset', { id, displayID: data.displayID }, { className: 'link', icon: 'refresh', disabled: pending() || (data.customized === false && !draft), title: t('Puts the picture back where Image fit alone places it') })}</div>`
      + (note ? `<p class="muted"><small>${escapeHTML(note)}</small></p>` : '')
      + (data.error ? `<p class="notice error" role="alert">${escapeHTML(data.error)}</p>` : '')
      + `</div></details></section>`;
  }

  // The picture's box inside the frame, in frame pixels: how the wallpaper page sizes it for
  // the chosen fit, times the zoom, with the overflow aligned by x and y the way
  // object-position aligns it (0 keeps the leading edge in view, 1 the trailing edge).
  function geometry(stage, image) {
    const data = placement() || {};
    const width = stage.clientWidth, height = stage.clientHeight;
    if (!width || !height) return null;
    const aspect = Number(data.imageAspectRatio) > 0 ? Number(data.imageAspectRatio) : image?.naturalWidth && image?.naturalHeight ? image.naturalWidth / image.naturalHeight : null;
    if (!aspect) return null;
    const current = values();
    let base;
    if (data.fit === 'center' && Number(data.imagePixelSize?.width) > 0 && Number(data.displayViewportSize?.width) > 0) {
      base = Number(data.imagePixelSize.width) * (width / Number(data.displayViewportSize.width));
    } else if (data.fit === 'fit' || data.fit === 'blur' || data.fit === 'center') {
      base = Math.min(width, height * aspect);
    } else {
      base = Math.max(width, height * aspect);
    }
    const boxWidth = base * current.zoom, boxHeight = boxWidth / aspect;
    return { width, height, boxWidth, boxHeight, left: (width - boxWidth) * current.x, top: (height - boxHeight) * current.y, x: current.x, y: current.y };
  }

  // Styles go through the CSSOM: the page's policy allows no style attributes in markup.
  function layout() {
    const stage = container?.querySelector('.placement-stage');
    if (!stage) return;
    const data = placement() || {};
    const displayAspect = Number(data.displayAspectRatio) > 0 ? Number(data.displayAspectRatio) : Number(data.displayViewportSize?.width) > 0 && Number(data.displayViewportSize?.height) > 0 ? Number(data.displayViewportSize.width) / Number(data.displayViewportSize.height) : 1.6;
    stage.style.setProperty('--stage-aspect', String(displayAspect));
    const image = stage.querySelector('img');
    const box = image ? geometry(stage, image) : null;
    if (!image || !box) return;
    image.style.width = `${box.boxWidth}px`;
    image.style.height = `${box.boxHeight}px`;
    image.style.transform = `translate(${box.left}px, ${box.top}px)`;
    stage.classList.toggle('pannable', box.boxWidth > box.width + 0.5 || box.boxHeight > box.height + 0.5);
  }

  function reflect() {
    const current = values();
    for (const [key, text, value] of [['x', percent(current.x), current.x * 100], ['y', percent(current.y), current.y * 100], ['zoom', times(current.zoom), current.zoom * 100]]) {
      const input = container?.querySelector(`#placement-${key}`);
      if (input && input !== document.activeElement) input.value = String(Math.round(value));
      const output = input?.parentElement.querySelector('output');
      if (output) output.textContent = text;
    }
    layout();
  }

  // One request at a time. Values that change while one is on its way are sent once it is
  // back, latest value only, so the end of a drag is never dropped behind an earlier send and
  // the draft outlives every snapshot until native has the final numbers.
  let inFlight = null;
  let queued = false;
  async function commit(id) {
    if (inFlight) { queued = true; return inFlight; }
    const data = placement();
    if (!data || data.wallpaperID !== id || !draft) return;
    const current = values();
    const sent = { x: round(current.x), y: round(current.y), zoom: round(current.zoom) };
    inFlight = (async () => {
      try { await send('imagePlacement', { id, displayID: data.displayID, ...sent }); }
      finally {
        inFlight = null;
        if (queued) { queued = false; await commit(id); }
        else { draft = null; render(); }
      }
    })();
    return inFlight;
  }

  function bind(node) {
    container = node;
    node.addEventListener('pointerdown', event => {
      const stage = event.target.closest('.placement-stage');
      if (!stage || event.button !== 0 || pending()) return;
      const image = stage.querySelector('img');
      const box = image ? geometry(stage, image) : null;
      if (!box) return;
      event.preventDefault();
      stage.focus({ preventScroll: true });
      stage.setPointerCapture(event.pointerId);
      drag = { pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, x: box.x, y: box.y, overflowX: box.boxWidth - box.width, overflowY: box.boxHeight - box.height, moved: false, before: draft ? { ...draft } : null };
      stage.classList.add('dragging');
    });
    node.addEventListener('pointermove', event => {
      if (!drag || event.pointerId !== drag.pointerId) return;
      const dx = event.clientX - drag.startX, dy = event.clientY - drag.startY;
      const next = { ...values() };
      // Dragging the picture right shows more of its left side, so the fraction falls.
      if (drag.overflowX > 0.5) next.x = clamp(drag.x - dx / drag.overflowX, 0, 1);
      if (drag.overflowY > 0.5) next.y = clamp(drag.y - dy / drag.overflowY, 0, 1);
      if (Math.abs(dx) + Math.abs(dy) > 2) drag.moved = true;
      draft = { ...(draft || {}), x: next.x, y: next.y };
      reflect();
    });
    const end = (event) => {
      if (!drag || event.pointerId !== drag.pointerId) return;
      const stage = node.querySelector('.placement-stage');
      stage?.classList.remove('dragging');
      const { moved, before } = drag;
      drag = null;
      if (moved && stage) commit(stage.dataset.id).catch(() => {});
      else { draft = before; reflect(); }
    };
    node.addEventListener('pointerup', end);
    node.addEventListener('pointercancel', end);
    // The preview arrives after the markup; its own size decides the picture's proportions
    // when the snapshot did not measure them. Opening the section gives the frame its size.
    node.addEventListener('load', event => { if (event.target.closest?.('.placement-stage')) layout(); }, true);
    node.addEventListener('toggle', event => { if (event.target.querySelector?.('.placement-stage')) layout(); }, true);
  }

  // Sliders: the picture follows every input; the value is sent once the slider settles.
  function handleInput(element) {
    if (element.dataset.change !== 'placement') return false;
    const key = element.dataset.placement;
    const value = Number(element.value) / 100;
    if (!Number.isFinite(value)) return true;
    draft = { ...(draft || {}), [key]: key === 'zoom' ? clamp(value, ZOOM_MIN, ZOOM_MAX) : clamp(value, 0, 1) };
    reflect();
    return true;
  }
  function handleChange(element) {
    if (element.dataset.change !== 'placement') return false;
    handleInput(element);
    return commit(element.dataset.id);
  }
  // Arrow keys move the picture a step at a time from the frame itself; Shift takes bigger steps.
  function handleKeydown(event) {
    const stage = event.target.closest?.('.placement-stage');
    if (!stage || pending()) return false;
    const step = event.shiftKey ? 0.05 : 0.01;
    const delta = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[event.key];
    if (!delta) return false;
    event.preventDefault();
    const current = values();
    draft = { ...(draft || {}), x: clamp(current.x + delta[0], 0, 1), y: clamp(current.y + delta[1], 0, 1) };
    reflect();
    clearTimeout(handleKeydown.timer);
    handleKeydown.timer = setTimeout(() => commit(stage.dataset.id).catch(() => {}), 400);
    return true;
  }

  return { sync, section, bind, layout, handleInput, handleChange, handleKeydown };
}
