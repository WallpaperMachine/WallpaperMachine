import { t } from './i18n.js';

export function playlistOrderMarkup(ctx, displayID, playlist, off) {
  const { state, e } = ctx;
  const library = new Map((state.wallpapers || []).map(item => [item.id, item]));
  const items = (playlist.wallpaperIDs || []).map(id => library.get(id)).filter(Boolean);
  if (!items.length) return `<p class="settings-empty">${e(t('The list is empty. In Installed, select wallpapers and choose Add to playlist, or use the list button in a wallpaper’s details.'))}</p>`;
  const control = (label, title, action, args, disabled) => `<button type="button" class="settings-button" data-action="${action}" data-args="${e(JSON.stringify(args))}" aria-label="${e(title)}"${disabled ? ' disabled' : ''}>${e(label)}</button>`;
  return `<p class="settings-note">${e(t('Drag wallpapers to reorder them, or use Move up and Move down.'))}</p><ol class="settings-playlist" data-key="playlist-order-${e(displayID)}">${items.map((item, index) => {
    const args = { id: item.id, displayID };
    return `<li class="settings-playlist-item" data-key="playlist-item-${e(displayID)}-${e(item.id)}" data-playlist-item="${e(item.id)}" data-playlist-display="${e(displayID)}" draggable="${!off}" title="${e(t('Drag to reorder'))}"><span class="settings-playlist-position" aria-hidden="true">${index + 1}</span><span class="settings-rule-name">${e(item.title)}</span><div class="settings-playlist-actions">${control(t('Move up'), t('Move {title} up', { title: item.title }), 'playlistMove', { ...args, direction: -1 }, off || index === 0)}${control(t('Move down'), t('Move {title} down', { title: item.title }), 'playlistMove', { ...args, direction: 1 }, off || index === items.length - 1)}${control(t('Remove'), t('Remove {title} from playlist', { title: item.title }), 'playlistRemove', args, off)}</div></li>`;
  }).join('')}</ol><p class="sr-only" role="status" aria-live="polite" aria-atomic="true">${e(ctx.view.playlistAnnouncement?.displayID === displayID ? ctx.view.playlistAnnouncement.text : '')}</p>`;
}

// Both input methods submit the original membership and order. Native validates that the
// snapshot is still current; a concurrent addition or reorder is never overwritten.
export function movePlaylistItem(view, { displayID, id, direction }, submit) {
  const expectedIDs = [...(view.state.playlists?.[displayID]?.wallpaperIDs || [])];
  const installed = new Set((view.state.wallpapers || []).map(item => item.id));
  const visible = expectedIDs.filter(id => installed.has(id));
  const index = visible.indexOf(id);
  const target = visible[index + direction];
  if (index < 0 || !target || ![-1, 1].includes(direction)) return;
  const ids = reordered(expectedIDs, id, target, direction === 1);
  return submit(displayID, ids, expectedIDs, id);
}

function reordered(original, id, target, after) {
  const ids = original.filter(value => value !== id);
  const index = ids.indexOf(target);
  if (index < 0) return original;
  ids.splice(index + (after ? 1 : 0), 0, id);
  return ids;
}

export function installPlaylistDrag(view, submit) {
  const { container } = view;
  let drag = null;
  const clearMarks = () => container.querySelectorAll('.playlist-drop-before, .playlist-drop-after').forEach(row => row.classList.remove('playlist-drop-before', 'playlist-drop-after'));
  const clear = () => { drag = null; clearMarks(); };
  const rowAt = event => event.target.closest('[data-playlist-item]');
  const destination = event => {
    const row = rowAt(event);
    if (!drag || !row || row.draggable !== true || row.dataset.playlistDisplay !== drag.displayID
        || row.dataset.playlistItem === drag.id || view.state.busy || view.pending.size) return null;
    const rect = row.getBoundingClientRect();
    return { row, after: event.clientY >= rect.top + rect.height / 2 };
  };
  container.addEventListener('dragstart', event => {
    const row = rowAt(event);
    if (!row || !row.draggable || view.state.busy || view.pending.size) return;
    const displayID = row.dataset.playlistDisplay;
    drag = { displayID, id: row.dataset.playlistItem,
      expectedIDs: [...(view.state.playlists?.[displayID]?.wallpaperIDs || [])] };
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', drag.id);
    }
  });
  container.addEventListener('dragover', event => {
    clearMarks();
    const target = destination(event);
    if (!target) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    target.row.classList.add(target.after ? 'playlist-drop-after' : 'playlist-drop-before');
  });
  container.addEventListener('drop', event => {
    const target = destination(event);
    if (!target) { clear(); return; }
    event.preventDefault();
    const { displayID, id, expectedIDs } = drag;
    const ids = reordered(expectedIDs, id, target.row.dataset.playlistItem, target.after);
    clear();
    if (ids.join('\0') !== expectedIDs.join('\0')) void submit(displayID, ids, expectedIDs, id);
  });
  container.addEventListener('dragend', clear);
}
