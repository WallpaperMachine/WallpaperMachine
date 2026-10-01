// Property presets in the inspector: named snapshots of a wallpaper's authored properties that
// can be applied again, renamed, deleted, exported as a portable file and imported back.
// Native owns the presets (`wallpaperPresets` in the snapshot for the selected wallpaper: id,
// items, canSave, status, error) and every file it reads or writes; the page keeps only which
// preset is picked in the menu, a name being typed, and a Delete waiting for its second click.
import { t } from './i18n.js';

export function createPresets({ send, render, escapeHTML, icon, button, keyAttr, disabled, busy }) {
  let state = null;
  let picked = ''; // The preset chosen in the menu, for Apply, Rename, Export and Delete.
  let editor = null; // { mode: 'save' | 'rename', presetID, name }
  let armed = ''; // The preset whose Delete has been pressed once.

  const presets = () => state?.wallpaperPresets;
  const items = () => (presets()?.items || []).filter(item => item && typeof item.id === 'string');
  const byID = (id) => items().find(item => item.id === id) || null;
  // Requests keyed by the wallpaper (save, apply, export, import) and those keyed by the
  // preset alone (rename, delete) both count as a change under way.
  const pendingChange = () => { const id = presets()?.wallpaperID; return ['wallpaperPresetSave', 'wallpaperPresetApply', 'wallpaperPresetRename', 'wallpaperPresetDelete', 'wallpaperPresetExport', 'wallpaperPresetImport'].some(action => busy(action) || (id && busy(action, { id }))); };

  // The page's choice follows the snapshot: a preset that was deleted, or another wallpaper's
  // presets arriving, drops it.
  function sync(snapshot) {
    const before = presets()?.wallpaperID;
    state = snapshot;
    if (presets()?.wallpaperID !== before) { picked = ''; editor = null; armed = ''; }
    if (picked && !byID(picked)) picked = '';
    if (editor?.presetID && !byID(editor.presetID)) editor = null;
    if (armed && !byID(armed)) armed = '';
  }

  function nameForm(id) {
    const rename = editor.mode === 'rename';
    return `<form class="inline-form" data-form="presetName" data-cancel="presetCancelEdit" ${keyAttr('preset-editor')}>`
      + `<label class="sr-only" for="preset-name">${escapeHTML(t('Preset name'))}</label>`
      + `<input id="preset-name" type="text" required maxlength="120" autocomplete="off" spellcheck="false" placeholder="${escapeHTML(t('Preset name'))}" value="${escapeHTML(editor.name)}" data-input="presetName" data-id="${escapeHTML(id)}">`
      + `<div class="actions"><button type="submit" class="primary"${disabled(pendingChange())}>${escapeHTML(rename ? t('Save') : t('Save preset'))}</button>${button(t('Cancel'), 'presetCancelEdit', {}, { className: 'quiet' })}</div></form>`;
  }

  // Drawn at the top of Wallpaper properties. Apply is the one primary action; saving the
  // current values, renaming, exporting and deleting sit beside it as links.
  function section(item, options) {
    const data = presets();
    if (!data || data.wallpaperID !== item.id) return '';
    const id = item.id;
    const all = items();
    const chosen = byID(picked);
    // Pending edits block both directions: the wallpaper does not have them yet, so they are
    // not worth saving, and applying a preset over them would throw them away unasked.
    const dirty = Boolean(options?.dirty);
    const canSave = data.canSave !== false && !dirty;
    const off = pendingChange();
    const menu = `<label class="sr-only" for="preset-picker">${escapeHTML(t('Presets'))}</label><select id="preset-picker" data-change="presetPick" data-id="${escapeHTML(id)}"${disabled(off || !all.length)}><option value=""${picked ? '' : ' selected'}>${escapeHTML(all.length ? t('Choose a preset…') : t('No presets saved yet'))}</option>${all.map(preset => `<option value="${escapeHTML(preset.id)}"${preset.id === picked ? ' selected' : ''}>${escapeHTML(preset.name)}</option>`).join('')}</select>`;
    const apply = button(t('Apply'), 'wallpaperPresetApply', { id, presetID: picked }, { className: 'primary', disabled: off || !chosen || dirty, title: dirty ? t('Apply or revert your changes first') : chosen ? t('Apply preset “{name}”', { name: chosen.name }) : t('Choose a preset to apply') });
    const editing = editor ? nameForm(id) : '';
    const confirm = chosen && armed === chosen.id && !editor
      ? `<div class="confirm-row" ${keyAttr(`preset-confirm-${chosen.id}`)}><p class="muted"><small>${escapeHTML(t('Delete preset “{name}”? The wallpaper keeps its current values.', { name: chosen.name }))}</small></p><div class="actions">${button(t('Delete'), 'wallpaperPresetDelete', { presetID: chosen.id }, { className: 'danger', disabled: off })}${button(t('Cancel'), 'presetDisarm', {}, { className: 'quiet' })}</div></div>`
      : '';
    const tools = editor || confirm ? '' : `<div class="preset-tools">`
      + button(t('Save current…'), 'presetSaveBegin', { id }, { className: 'link', icon: 'bookmark', disabled: off || !canSave, title: dirty ? t('Apply or revert your changes first') : t('Saves the values the wallpaper is using now as a new preset') })
      + button(t('Import…'), 'wallpaperPresetImport', { id }, { className: 'link', icon: 'upload', disabled: off, title: t('Adds a preset from a file exported by WallpaperMachine') })
      + (chosen ? button(t('Rename…'), 'presetRenameBegin', { presetID: chosen.id }, { className: 'link', disabled: off })
        + button(t('Export…'), 'wallpaperPresetExport', { id, presetID: chosen.id }, { className: 'link', icon: 'download', disabled: off, title: t('Saves “{name}” as a file you can share or keep', { name: chosen.name }) })
        + button(t('Delete…'), 'presetDeleteBegin', { presetID: chosen.id }, { className: 'link danger', disabled: off }) : '')
      + `</div>`;
    const note = dirty && !editor ? `<p class="muted"><small>${escapeHTML(t('Apply or revert your changes before saving or applying a preset.'))}</small></p>` : '';
    const status = data.status ? `<p class="muted" role="status"><small>${escapeHTML(data.status)}</small></p>` : '';
    const error = data.error ? `<p class="notice error" role="alert">${escapeHTML(data.error)}</p>` : '';
    return `<div class="preset-bar" ${keyAttr(`presets-${id}`)}><div class="preset-row">${menu}${apply}</div>${tools}${editing}${confirm}${note}${status}${error}</div>`;
  }

  function focusEditor() { document.getElementById('preset-name')?.focus(); }

  async function handleAction(action, data) {
    switch (action) {
      case 'presetSaveBegin': editor = { mode: 'save', name: '' }; armed = ''; render(); focusEditor(); return true;
      case 'presetRenameBegin': {
        const item = byID(data.presetId);
        if (!item) return true;
        editor = { mode: 'rename', presetID: item.id, name: item.name }; armed = ''; render(); focusEditor(); return true;
      }
      case 'presetCancelEdit': editor = null; render(); return true;
      case 'presetDeleteBegin': armed = data.presetId; render(); document.querySelector('[data-action="wallpaperPresetDelete"]')?.focus(); return true;
      case 'presetDisarm': armed = ''; render(); return true;
      case 'wallpaperPresetDelete': {
        const item = byID(data.presetId);
        armed = '';
        if (!item) { render(); return true; }
        await send('wallpaperPresetDelete', { presetID: item.id });
        if (picked === item.id) picked = '';
        render(); return true;
      }
      case 'wallpaperPresetApply': {
        const item = byID(data.presetId);
        if (!item) return true;
        await send('wallpaperPresetApply', { id: data.id, presetID: item.id });
        return true;
      }
      case 'wallpaperPresetExport': {
        const item = byID(data.presetId);
        if (!item) return true;
        await send('wallpaperPresetExport', { id: data.id, presetID: item.id });
        return true;
      }
      case 'wallpaperPresetImport': await send('wallpaperPresetImport', { id: data.id }); return true;
      default: return false;
    }
  }

  function handleChange(element) {
    if (element.dataset.change !== 'presetPick') return false;
    picked = element.value;
    armed = '';
    render();
    return true;
  }

  function handleInput(element) {
    if (element.dataset.input !== 'presetName' || !editor) return false;
    editor.name = element.value;
    return true;
  }

  async function handleSubmit(form) {
    if (form.dataset.form !== 'presetName' || !editor) return false;
    const input = form.querySelector('[data-input="presetName"]');
    const name = String(input?.value || '').trim();
    if (!name) return true;
    const current = editor;
    if (current.mode === 'rename') {
      await send('wallpaperPresetRename', { presetID: current.presetID, name });
      if (editor === current) editor = null;
      render(); return true;
    }
    const before = new Set(items().map(item => item.id));
    await send('wallpaperPresetSave', { id: input.dataset.id, name });
    if (editor === current) editor = null;
    const created = items().find(item => !before.has(item.id));
    if (created) picked = created.id;
    render(); return true;
  }

  return { sync, section, handleAction, handleChange, handleInput, handleSubmit };
}
