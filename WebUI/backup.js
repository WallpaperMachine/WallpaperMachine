// Settings → Storage → Backup: export the app's settings, playlists, collections, presets and
// the files chosen for wallpapers as one package, and restore such a package later. Native
// does every file operation behind its own pickers and reports through `backup` in the
// snapshot (busy, status, error, preview, pendingRestore). A restore is staged here and
// applied the next time the app opens, so nothing is overwritten while it runs; the page only
// keeps the two choices made before asking: whether the library goes in, and what to do
// where the package and this Mac disagree.
import { t } from './i18n.js';

const conflictPolicies = [['keepExisting', 'Keep what is on this Mac'], ['replace', 'Replace with the backup']];

function bytes(value) {
  if (!Number.isFinite(value) || value < 0) return '';
  if (value < 1024) return `${value} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let size = value / 1024, unit = 0;
  while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit++; }
  return `${size.toLocaleString(undefined, { maximumFractionDigits: 1 })} ${units[unit]}`;
}
function when(milliseconds, locale) {
  const date = new Date(Number(milliseconds));
  return Number.isFinite(date.getTime()) ? date.toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' }) : '';
}

export function backupGroup(ctx, locale) {
  const { e, state, view, row, group, button, toggle, error, draft, busy, unavailable } = ctx;
  const backup = state.backup;
  if (!backup || typeof backup !== 'object') return '';
  const working = Boolean(backup.busy);
  const locked = busy || unavailable || working;
  const includeLibrary = Boolean(draft('backup-include-library', false));
  const pending = Boolean(backup.pendingRestore);
  const preview = backup.preview && typeof backup.preview === 'object' ? backup.preview : null;
  const policy = String(draft('backup-conflict', 'keepExisting'));
  const note = (key, text, style = 'settings-note') => `<div class="${style}" data-key="${e(key)}">${e(text)}</div>`;

  const exportRows = row('backup-export', t('Back up settings'), button(t('Export…'), 'backupExport', { includeLibrary }, locked || pending, 'settings-primary'), t('Saves a .wmbackup package with the renderer settings, every wallpaper’s options, playlists, collections, presets, favorites and the files you chose for wallpapers. Steam sign-ins, passwords, logs and caches are never included.'))
    + row('backup-include-library', t('Include the wallpaper library'), toggle('backup-include-library', t('Include the wallpaper library'), includeLibrary, 'data-local', locked || pending), t('Copies every installed wallpaper as well, which can take a lot of space. Without it, a restore lists the wallpapers to download or import again.'), '', 'backup-include-library');

  const previewRows = preview ? (() => {
    const facts = [];
    if (preview.name) facts.push(preview.name);
    const created = preview.createdAt != null ? when(preview.createdAt, locale) : '';
    if (created) facts.push(t('Made {time}', { time: created }));
    const size = bytes(Number(preview.byteCount));
    if (size) facts.push(size);
    const tally = (value, one, many) => { const count = Number(value) || 0; return t(count === 1 ? one : many, { count: count.toLocaleString() }); };
    const counts = [
      tally(preview.wallpaperCount, '{count} wallpaper', '{count} wallpapers'),
      preview.presetCount != null ? tally(preview.presetCount, '{count} preset', '{count} presets') : '',
      preview.collectionCount != null ? tally(preview.collectionCount, '{count} collection', '{count} collections') : '',
      preview.includesLibrary ? t('wallpaper library included') : t('no wallpaper files'),
    ].filter(Boolean).join(' · ');
    const conflicts = Array.isArray(preview.conflicts) ? preview.conflicts.filter(Boolean) : [];
    const warnings = Array.isArray(preview.warnings) ? preview.warnings.filter(Boolean) : [];
    const list = (key, items, style) => items.length ? `<ul class="settings-list ${style}" data-key="${e(key)}">${items.map(item => `<li>${e(item)}</li>`).join('')}</ul>` : '';
    const choice = conflicts.length ? `<div class="settings-choices" role="radiogroup" aria-label="${e(t('Where the backup and this Mac disagree'))}" data-key="backup-conflict">${conflictPolicies.map(([id, label]) => `<label class="settings-choice"><input type="radio" name="backup-conflict" value="${id}" data-key="backup-conflict" data-local${policy === id ? ' checked' : ''}${locked ? ' disabled' : ''}><span>${e(t(label))}</span></label>`).join('')}</div>` : '';
    return row('backup-preview', t('Backup to restore'), `<span class="settings-status">${e(facts.join(' · '))}</span><span class="settings-note">${e(counts)}</span>`, '', 'settings-readout')
      + (conflicts.length ? row('backup-conflicts', t('Already on this Mac'), list('backup-conflict-list', conflicts, 'settings-conflicts') + choice, t('These items exist here and in the backup. Keep what is on this Mac, or replace it with the backup’s version.'), 'settings-readout') : '')
      + (warnings.length ? row('backup-warnings', t('Before you restore'), list('backup-warning-list', warnings, 'settings-warnings'), '', 'settings-readout') : '')
      + `<div class="settings-form-actions" data-key="backup-restore-actions">${button(t('Restore at next launch'), 'backupRestore', { conflictPolicy: policy }, locked || pending, 'settings-primary')}${button(t('Choose another…'), 'backupPreview', {}, locked || pending)}</div>`
      + note('backup-restore-note', t('Nothing changes until you quit and reopen WallpaperMachine. The restore is applied before anything else loads, keeps the current files until it has finished, and puts them back if it fails.'));
  })() : '';

  const restoreRows = pending
    ? row('backup-pending', t('Restore'), button(t('Cancel restore'), 'backupCancelRestore', {}, locked, 'settings-destructive'), t('A restore is ready and will be applied the next time you open WallpaperMachine. Quit and reopen the app when you are ready; it does not restart on its own.'))
    : preview ? previewRows
      : row('backup-restore', t('Restore'), button(t('Choose backup…'), 'backupPreview', {}, locked), t('Pick a .wmbackup package to see what it holds before anything is restored.'));

  const progress = working ? row('backup-busy', t('In progress'), `<span class="settings-status" role="status">${e(backup.status || t('Working…'))}</span>${button(t('Cancel'), 'backupCancel', {}, busy || unavailable)}`, '', 'settings-readout') + `<progress class="settings-progress" aria-label="${e(t('Backup progress'))}"></progress>` : '';
  const status = !working && backup.status ? `<div class="settings-notice" role="status" data-key="backup-status">${e(backup.status)}</div>` : '';
  return group('storage-backup', t('Backup'), exportRows + progress + restoreRows + status + error('backup-error', backup.error));
}
