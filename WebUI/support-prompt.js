import { t } from './i18n.js';

// Native owns eligibility and the durable once-only flag. The page acknowledges only a
// visible dialog, then keeps that presentation alive when the acknowledgement clears it.
export function createSupportPrompt({ container, send, escapeHTML: e, icon, morph, canPresent, restoreFocus }) {
  let state = null;
  let presented = false;
  let dismissed = false;
  let acknowledged = false;
  let acknowledgementAttempted = false;
  let acknowledgement = null;
  let choosing = false;
  let error = '';
  let previousFocus = null;

  const blocked = () => document.hidden || !canPresent()
    || [...document.querySelectorAll('dialog[open]')].some(dialog => dialog !== container);

  function render(next) {
    state = next ?? state;
    if (dismissed || (!presented && state?.supportPromptPending !== true)) return;
    // Steam authentication and onboarding keep priority, including a new request that
    // arrives while this dialog is open. Resume this same presentation when they finish.
    if (blocked()) {
      if (container.open) container.close();
      return;
    }
    const off = choosing ? ' disabled' : '';
    const choice = (value, glyph, title, note) => `<button type="button" class="dialog-choice" data-action="supportPromptChoice" data-choice="${value}"${off}><span class="dialog-guide-icon">${icon(glyph, 20)}</span><span class="dialog-choice-body"><span class="dialog-choice-title">${e(title)}</span><span class="dialog-choice-note">${e(note)}</span></span>${icon('external', 15)}</button>`;
    morph(container, `<div class="dialog-head"><div class="dialog-heading"><h2 id="support-dialog-title" tabindex="-1">${e(t('Feeling good?'))}</h2></div><button type="button" class="quiet icon-button" data-action="supportPromptChoice" data-choice="dismiss" aria-label="${e(t('Dismiss support prompt'))}">${icon('close')}</button></div><div class="dialog-body"><p id="support-dialog-description">${e(t('Your first downloaded wallpaper is up and running. Enjoying WallpaperMachine? You can help it grow.'))}</p><div class="dialog-choices">${choice('star', 'github', t('Star on GitHub'), t('Help others discover WallpaperMachine.'))}${choice('supporter', 'heart', t('Become a Supporter'), t('Support development with a one-time contribution.'))}</div>${error ? `<p class="notice error" role="alert">${e(error)}</p>` : ''}<div class="dialog-actions">${error && !acknowledged ? `<button type="button" data-action="supportPromptRetry"${off}>${e(t('Try again'))}</button>` : ''}<button type="button" class="quiet" data-action="supportPromptChoice" data-choice="dismiss">${e(t('Not now'))}</button></div></div>`);
    if (!container.open) {
      if (!presented) previousFocus = document.activeElement;
      container.showModal();
      presented = true;
      container.querySelector('#support-dialog-title')?.focus();
    }
    if (!acknowledgementAttempted) acknowledge();
  }

  function acknowledge() {
    if (acknowledged) return Promise.resolve(true);
    if (acknowledgement) return acknowledgement;
    acknowledgementAttempted = true;
    error = '';
    // Deferring the call assigns the promise before send() synchronously re-renders.
    acknowledgement = Promise.resolve().then(() => send('supportPromptShown')).then(() => {
      acknowledged = true;
      return true;
    }).catch(failure => {
      error = failure?.message || String(failure);
      return false;
    }).finally(() => {
      acknowledgement = null;
      render(state);
    });
    return acknowledgement;
  }

  function close() {
    dismissed = true;
    const wasOpen = container.open;
    if (wasOpen) container.close();
    if (wasOpen) restoreFocus(previousFocus);
  }

  async function choose(choice) {
    if (dismissed || !['star', 'supporter', 'dismiss'].includes(choice)) return;
    // Leaving is always available, even when persistence or opening a link fails.
    if (choice === 'dismiss') {
      close();
      try { await send('supportPromptChoice', { choice }); } catch { /* The panel shows the connection error. */ }
      return;
    }
    if (choosing) return;
    choosing = true;
    error = '';
    render(state);
    try {
      if (!await acknowledge() || dismissed) return;
      await send('supportPromptChoice', { choice });
      close();
    } catch (failure) {
      error = failure?.message || String(failure);
    } finally {
      choosing = false;
      render(state);
    }
  }

  container.addEventListener('click', event => {
    const control = event.target.closest('[data-action]');
    if (!control || control.disabled) return;
    if (control.dataset.action === 'supportPromptRetry') acknowledge();
    else if (control.dataset.action === 'supportPromptChoice') choose(control.dataset.choice);
  });
  container.addEventListener('cancel', event => { event.preventDefault(); choose('dismiss'); });
  document.addEventListener('visibilitychange', () => render(state));
  return { render };
}
