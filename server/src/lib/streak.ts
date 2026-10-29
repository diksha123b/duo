import { addDays } from './time.js';

// Streaks count consecutive *calendar days in the pair's timezone* on which
// both partners finished the game. Days are "YYYY-MM-DD" strings, never
// instants, so DST changes and UTC offsets can't create or skip a day.

export interface StreakState {
  current: number;
  longest: number;
  lastCompletedDay: string | null;
}

/** New state after the game for `day` is completed. */
export function applyCompletion(s: StreakState, day: string): StreakState {
  const last = s.lastCompletedDay;
  // Already counted, or an older game finished late: no change.
  if (last !== null && day <= last) return s;
  const current = last !== null && addDays(last, 1) === day ? s.current + 1 : 1;
  return { current, longest: Math.max(s.longest, current), lastCompletedDay: day };
}

/**
 * What to show today. A streak survives until the end of the day after the
 * last completion (you still have today to play); after that it's 0.
 */
export function displayStreak(s: StreakState, today: string): number {
  if (!s.lastCompletedDay) return 0;
  return s.lastCompletedDay >= addDays(today, -1) ? s.current : 0;
}
