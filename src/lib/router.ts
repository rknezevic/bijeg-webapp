/** Tiny router helper: "/" = home, "/s/ABC123" = a room. */
export function navigate(path: string) {
  window.history.pushState(null, '', path);
  window.dispatchEvent(new PopStateEvent('popstate'));
}
