export function createSelectionToken() {
  let sequence = 0;
  return {
    next() { sequence += 1; return sequence; },
    isCurrent(token) { return token === sequence; },
  };
}

export function sectionHref(href, section) {
  const url = new URL(href);
  if (section === "recordings") {
    url.searchParams.set("view", "recordings");
  } else {
    url.searchParams.set("view", "runs");
    for (const key of ["session", "t", "from", "to", "export"]) url.searchParams.delete(key);
  }
  return `${url.pathname}${url.search}${url.hash}`;
}
