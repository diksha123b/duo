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
