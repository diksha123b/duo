// The pair's pet grows from what the two of them do together. Everything
// here is pure so the rules are easy to test and to show in the app.

/** XP for each shared thing the pair does. */
export const XP = { daily: 30, bonus: 10, match: 15, pat: 5 } as const;

export const COLORS = ['peach', 'mint', 'sky', 'grape', 'sunflower'] as const;
export type PetColor = (typeof COLORS)[number];

/** Accessories, in the order they unlock. */
export const OUTFITS = [
  { id: 'bow', level: 3 },
  { id: 'flower', level: 4 },
  { id: 'cap', level: 5 },
  { id: 'party', level: 6 },
  { id: 'tophat', level: 7 },
  { id: 'crown', level: 9 },
] as const;
export type OutfitId = (typeof OUTFITS)[number]['id'];
export const OUTFIT_IDS = OUTFITS.map((o) => o.id) as [OutfitId, ...OutfitId[]];

export type Stage = 'egg' | 'baby' | 'kid' | 'grown';
export type Mood = 'happy' | 'hungry' | 'sleepy';

/**
 * XP needed to reach `level`: 0, 30, 90, 180, 300… Level 2 is exactly one
 * daily game, so the egg hatches the first time the pair plays together.
 */
export const xpForLevel = (level: number) => 15 * level * (level - 1);

export function levelFor(xp: number): number {
  let level = 1;
  while (xpForLevel(level + 1) <= xp) level++;
  return level;
}

export function stageFor(level: number): Stage {
  if (level <= 1) return 'egg';
  if (level <= 3) return 'baby';
  if (level <= 6) return 'kid';
  return 'grown';
}

/** Happy if the daily game was finished today, hungry after a day off, then sleepy. */
export function moodFor(lastDaily: string | null, today: string, yesterday: string): Mood {
  if (lastDaily === today) return 'happy';
  if (lastDaily === yesterday) return 'hungry';
  return 'sleepy';
}

export const unlockedOutfits = (level: number) => OUTFITS.filter((o) => o.level <= level).map((o) => o.id);
