// Accepts any IANA zone the runtime understands, including aliases like
// "Asia/Kolkata" that Intl.supportedValuesOf omits in favour of "Asia/Calcutta".
export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

// Calendar day ("YYYY-MM-DD") at `now` in the given zone. The en-CA locale
// formats dates as ISO, which avoids hand-assembling parts.
export function localDay(timezone: string, now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

// Postgres DATE columns map to JS Dates at UTC midnight.
export const dayToDate = (day: string) => new Date(`${day}T00:00:00.000Z`);
export const dateToDay = (date: Date) => date.toISOString().slice(0, 10);

export function addDays(day: string, n: number): string {
  const d = dayToDate(day);
  d.setUTCDate(d.getUTCDate() + n);
  return dateToDay(d);
}
