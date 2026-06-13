import { createElement as h } from 'react';
import { toast } from 'react-hot-toast';

// Unified notification entry point for the whole dashboard. One visual language
// for every in-app toast (retro card style, consistent per level), plus an
// optional mirror to an OS notification via the service worker for "important"
// events (deploys, nightlies, alerts) so they're visible like the Android push
// notifications. Local SW notifications only show while the app is running; push
// notifications sent by the central still cover the tab-closed case.

export type NotifyLevel = 'info' | 'success' | 'warn' | 'error' | 'alert';

interface NotifyOptions {
  level?: NotifyLevel;
  description?: string;   // second line, smaller/muted
  durationMs?: number;
  // Also raise an OS notification through the SW (when permission is granted).
  important?: boolean;
  // Tag/route for the OS notification click + dedup.
  data?: Record<string, unknown>;
}

const LEVEL: Record<NotifyLevel, { icon: string; accent: string; border: string }> = {
  info:    { icon: 'ℹ️', accent: 'text-accent',   border: 'border-black' },
  success: { icon: '✅', accent: 'text-success',  border: 'border-black' },
  warn:    { icon: '⚠️', accent: 'text-warning',  border: 'border-black' },
  error:   { icon: '⛔', accent: 'text-danger',   border: 'border-danger' },
  alert:   { icon: '🔥', accent: 'text-accent',   border: 'border-accent' },
};

const DEFAULT_DURATION: Record<NotifyLevel, number> = {
  info: 4000, success: 3500, warn: 6000, error: 6000, alert: 8000,
};

// Fire an OS notification through the active service worker registration. Best
// effort: silently no-ops without permission or SW support.
async function mirrorToOS(title: string, body?: string, data?: Record<string, unknown>) {
  try {
    if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
    if (!('serviceWorker' in navigator)) return;
    const reg = await navigator.serviceWorker.getRegistration();
    if (!reg) return;
    await reg.showNotification(title, {
      body,
      icon: '/pwa-192x192.png',
      badge: '/favicon.svg',
      tag: typeof data?.tag === 'string' ? data.tag : undefined,
      data,
    });
  } catch { /* ignore */ }
}

// The single styled toast renderer. Kept as a custom toast so every level shares
// the exact same retro card; react-hot-toast's default look is never used.
function show(title: string, opts: NotifyOptions = {}) {
  const level = opts.level ?? 'info';
  const meta = LEVEL[level];
  const duration = opts.durationMs ?? DEFAULT_DURATION[level];

  toast.custom((t) => {
    // Build the card with DOM so this stays a .ts module (no JSX needed).
    return cardElement(t.visible, meta, title, opts.description) as any;
  }, { duration });

  if (opts.important) void mirrorToOS(title, opts.description, opts.data);
}

// Builds the card with createElement so this stays a .ts module (no JSX).
// Returns a React element react-hot-toast can render.
function cardElement(
  visible: boolean,
  meta: { icon: string; accent: string; border: string },
  title: string,
  description?: string,
) {
  return h(
    'div',
    {
      className: `${visible ? 'opacity-100' : 'opacity-0'} flex items-start gap-2.5 border-4 ${meta.border} bg-bg-card p-3 font-mono text-xs text-text-primary shadow-[4px_4px_0px_0px_black] transition-opacity max-w-sm`,
    },
    h('span', { className: 'text-base leading-none' }, meta.icon),
    h(
      'div',
      { className: 'min-w-0 flex-1' },
      h('div', { className: `font-black uppercase ${meta.accent} break-words` }, title),
      description
        ? h('div', { className: 'mt-1 text-[0.625rem] text-text-muted break-words whitespace-pre-wrap' }, description)
        : null,
    ),
  );
}

export const notify = {
  info: (title: string, o?: Omit<NotifyOptions, 'level'>) => show(title, { ...o, level: 'info' }),
  success: (title: string, o?: Omit<NotifyOptions, 'level'>) => show(title, { ...o, level: 'success' }),
  warn: (title: string, o?: Omit<NotifyOptions, 'level'>) => show(title, { ...o, level: 'warn' }),
  error: (title: string, o?: Omit<NotifyOptions, 'level'>) => show(title, { ...o, level: 'error' }),
  alert: (title: string, o?: Omit<NotifyOptions, 'level'>) => show(title, { ...o, level: 'alert' }),
  // Escape hatch for the rare hand-built toast (e.g. with action buttons).
  raw: toast,
};
