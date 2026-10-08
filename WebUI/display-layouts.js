import { t } from './i18n.js';

const layouts = state => state.displayLayouts?.items || [];
const eligible = state => (state.displays || []).filter(display => display.enabled && display.mode === 'standalone');
const actionButton = (ctx, label, action, args, off, accessible = label) => `<button type="button" class="settings-button" data-action="${ctx.e(action)}" data-args="${ctx.e(JSON.stringify(args))}" aria-label="${ctx.e(accessible)}"${off ? ' disabled' : ''}>${ctx.e(label)}</button>`;

function nameForm(ctx, id) {
  const key = id || 'new';
  return `<form class="settings-inline-form" data-form="display-layout" data-key="layout-editor-${ctx.e(key)}"><label class="sr-only" for="layout-name-${ctx.e(key)}">${ctx.e(t('Layout name'))}</label><input id="layout-name-${ctx.e(key)}" name="name" data-layout-name type="text" required maxlength="128" autocomplete="off" value="${ctx.e(ctx.view.layoutEditor.name)}"${ctx.busy ? ' disabled' : ''}><button type="submit" class="settings-button"${ctx.busy ? ' disabled' : ''}>${ctx.e(t('Save'))}</button>${ctx.button(t('Cancel'), 'layoutCancel', {}, ctx.busy)}</form>`;
}

export function displayTransferRow(ctx, display, off) {
  if (!ctx.state.displayLayouts || !display.wallpaperID || display.mode !== 'standalone') return '';
  const peers = eligible(ctx.state).filter(peer => peer.id !== display.id);
  if (!peers.length) return '';
  const chosen = ctx.view.layoutPeers?.get(display.id) || '';
  const peer = peers.find(peer => peer.id === chosen);
  const args = { sourceID: display.id, targetID: chosen };
  const select = `<select data-key="layout-peer-${ctx.e(display.id)}" data-layout-peer="${ctx.e(display.id)}" aria-label="${ctx.e(t('Destination for {display}', { display: display.title }))}"${off ? ' disabled' : ''}><option value=""${!peer ? ' selected' : ''}>${ctx.e(t('Choose display'))}</option>${peers.map(item => `<option value="${ctx.e(item.id)}"${item.id === chosen ? ' selected' : ''}>${ctx.e(item.title)}</option>`).join('')}</select>`;
  return ctx.disclosure(`display-transfer-${display.id}`, t('Copy or swap wallpapers'), ctx.row(`display-transfer-row-${display.id}`, t('Other display'), select
    + actionButton(ctx, t('Copy wallpaper'), 'displayCopyWallpaper', args, off || !peer, t('Copy wallpaper from {source} to {target}', { source: display.title, target: peer?.title || t('Choose display') }))
    + actionButton(ctx, t('Swap wallpapers'), 'displaySwapWallpapers', args, off || !peer?.wallpaperID, t('Swap wallpapers on {source} and {target}', { source: display.title, target: peer?.title || t('Choose display') })),
  t('Only wallpaper choices are copied or swapped. Playlists and automatic rules keep running. Swapping needs a wallpaper on both displays.')), 'settings-disclosure-rows');
}

export function displayLayoutsGroup(ctx) {
  const { state, view, e, button, busy } = ctx;
  if (!state.displayLayouts) return '';
  const items = layouts(state);
  const rows = items.map(layout => {
    if (view.layoutEditor?.id === layout.id) return `<div class="settings-display-layout" data-layout-id="${e(layout.id)}" data-key="layout-${e(layout.id)}">${nameForm(ctx, layout.id)}</div>`;
    const assignments = layout.assignments.map(value => `<li>${e(t('{display}: {wallpaper}', { display: value.displayTitle, wallpaper: value.wallpaperTitle }))}</li>`).join('');
    const actions = view.layoutConfirm === layout.id
      ? `<div class="settings-confirm" role="group" aria-label="${e(t('Delete layout'))}"><span class="settings-note">${e(t('Delete “{name}”? Current wallpapers stay as they are.', { name: layout.name }))}</span>${button(t('Delete'), 'displayLayoutDelete', { layoutID: layout.id }, busy, 'settings-destructive')}${button(t('Cancel'), 'layoutDeleteCancel', { id: layout.id }, busy)}</div>`
      : `<div class="settings-form-actions">${actionButton(ctx, t('Apply'), 'displayLayoutApply', { layoutID: layout.id }, busy || Boolean(layout.unavailable), t('Apply layout “{name}”', { name: layout.name }))}${actionButton(ctx, t('Rename…'), 'layoutRename', { id: layout.id }, busy, t('Rename layout “{name}”', { name: layout.name }))}${actionButton(ctx, t('Delete…'), 'layoutDeleteAsk', { id: layout.id }, busy, t('Delete layout “{name}”', { name: layout.name }))}</div>`;
    return `<div class="settings-display-layout" data-layout-id="${e(layout.id)}" data-key="layout-${e(layout.id)}"><h4>${e(layout.name)}</h4><ul class="settings-list">${assignments}</ul>${layout.unavailable ? `<p class="settings-note">${e(layout.unavailable)}</p>` : ''}${actions}</div>`;
  }).join('');
  const save = view.layoutEditor && !view.layoutEditor.id ? nameForm(ctx, null) : button(t('Save current layout…'), 'layoutNew', {}, busy || !state.displayLayouts.canSave || items.length >= state.displayLayouts.limit);
  return ctx.group('display-layouts', t('Display layouts'), `<p class="settings-note">${e(t('Save wallpaper choices for enabled independent displays. Empty and mirrored displays are left out. Playlists, automatic rules, properties and scaling are not saved in a layout.'))}</p>`
    + (rows || `<p class="settings-empty">${e(t('No saved layouts yet. Arrange your wallpapers, then save the layout.'))}</p>`)
    + save
    + `<p class="settings-note" role="status" aria-live="polite" aria-atomic="true" data-key="layout-status">${e(view.layoutMessage || '')}</p>`
    + (view.layoutError || state.displayLayouts.error ? `<div class="settings-error settings-layout-error" role="alert" tabindex="-1" data-key="layout-error">${e(view.layoutError || state.displayLayouts.error)}</div>` : '')
    + (items.length >= state.displayLayouts.limit ? `<p class="settings-note">${e(t('The limit of {count} layouts is reached. Delete one before saving another.', { count: state.displayLayouts.limit }))}</p>` : ''));
}

function restoreFocus(view, action, id) {
  if (view.layoutError) {
    const error = view.container.querySelector('.settings-layout-error'); error?.focus(); return;
  }
  const row = id && ([...view.container.querySelectorAll('[data-layout-id]')].find(row => row.dataset.layoutId === id)
    || [...view.container.querySelectorAll('[data-layout-peer]')].find(input => input.dataset.layoutPeer === id)?.closest('details'));
  const target = (row || view.container).querySelector(`[data-action="${action}"]`);
  [target, view.container.querySelector('[data-action="layoutNew"]'),
    view.container.querySelector('[data-key="display-layouts"] button:not(:disabled)')]
    .find(button => button && !button.disabled)?.focus();
}

export function displayLayoutInput(view, input) {
  if (!input.hasAttribute('data-layout-name') || !view.layoutEditor) return false;
  view.layoutEditor.name = input.value;
  return true;
}

export function displayLayoutChange(view, input, draw) {
  if (!input.hasAttribute('data-layout-peer')) return false;
  view.layoutPeers ||= new Map();
  view.layoutPeers.set(input.dataset.layoutPeer, input.value);
  draw();
  return true;
}

export async function displayLayoutClick(view, action, args, draw, submit) {
  const id = args.id || args.layoutID;
  if (action === 'layoutNew' || action === 'layoutRename') {
    const current = layouts(view.state).find(item => item.id === id);
    view.layoutEditor = { id: current?.id, name: current?.name || '' };
    view.layoutConfirm = null; view.layoutError = ''; draw();
    view.container.querySelector('[data-layout-name]')?.focus(); return;
  }
  if (action === 'layoutCancel') {
    const prior = view.layoutEditor?.id; view.layoutEditor = null; view.layoutError = ''; draw();
    restoreFocus(view, prior ? 'layoutRename' : 'layoutNew', prior); return;
  }
  if (action === 'layoutDeleteAsk' || action === 'layoutDeleteCancel') {
    view.layoutConfirm = action === 'layoutDeleteAsk' ? id : null; view.layoutEditor = null; view.layoutError = ''; draw();
    restoreFocus(view, action === 'layoutDeleteAsk' ? 'displayLayoutDelete' : 'layoutDeleteAsk', id); return;
  }
  view.layoutError = ''; view.layoutMessage = '';
  await submit(action, args, () => {
    view.layoutConfirm = null;
    view.layoutMessage = t(action === 'displayLayoutDelete' ? 'Layout deleted. Current wallpapers are unchanged.' : 'Wallpaper arrangement applied.');
  }, error => { view.layoutError = error; });
  restoreFocus(view, action === 'displayLayoutDelete' ? 'layoutNew' : action, id || args.sourceID);
}

export async function displayLayoutSubmit(view, form, draw, submit) {
  if (!form.reportValidity() || !view.layoutEditor) return;
  const { id, name } = view.layoutEditor;
  view.layoutError = ''; view.layoutMessage = '';
  await submit(id ? 'displayLayoutRename' : 'displayLayoutSave', { name, ...(id ? { layoutID: id } : {}) }, () => {
    view.layoutEditor = null; view.layoutMessage = t(id ? 'Layout renamed.' : 'Display layout saved.');
  }, error => { view.layoutError = error; });
  draw();
  if (view.layoutEditor && !view.layoutError) view.container.querySelector('[data-layout-name]')?.focus();
  else restoreFocus(view, id ? 'layoutRename' : 'layoutNew', id);
}
