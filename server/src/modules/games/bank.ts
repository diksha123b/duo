import { createHash } from 'node:crypto';
import { AGREE_SCALE, type GameContent, type GameTypeName } from './content.js';

// Curated questions. Used directly until Day 5, then as the fallback when
// LLM generation fails or returns something that doesn't validate.

import type { Relationship } from '@prisma/client';

// `only` limits a question to some relationships (e.g. date ideas are for partners).
type Q = { prompt: string; options: string[]; correctOption?: number; only?: Relationship[] };
const PARTNERS_ONLY: Relationship[] = ['PARTNERS'];

const WOULD_YOU_RATHER: Q[] = [
  { prompt: 'Would you rather…', options: ['Travel to the past', 'Travel to the future'] },
  { prompt: 'Would you rather…', options: ['Have a beach holiday', 'Have a mountain holiday'] },
  { prompt: 'Would you rather…', options: ['Only eat street food forever', 'Only eat home food forever'] },
  { prompt: 'Would you rather…', options: ['Read minds', 'Be invisible'] },
  { prompt: 'Would you rather…', options: ['Watch the sunrise', 'Watch the sunset'] },
  { prompt: 'Would you rather…', options: ['Never use social media again', 'Never watch a movie again'] },
  { prompt: 'Would you rather…', options: ['Live in a big city', 'Live in a small town'] },
  { prompt: 'Would you rather…', options: ['Have a cat', 'Have a dog'] },
  { prompt: 'Would you rather…', options: ['Be a famous singer', 'Be a famous athlete'] },
  { prompt: 'Would you rather…', options: ['Plan every trip in detail', 'Decide everything on the spot'] },
  { prompt: 'Would you rather…', options: ['Have chai', 'Have coffee'] },
  { prompt: 'Would you rather…', options: ['Plan a surprise date', 'Be surprised'], only: PARTNERS_ONLY },
  {
    prompt: 'Would you rather…',
    options: ['Share a room again', 'Share one phone for a week'],
    only: ['SIBLINGS'],
  },
  {
    prompt: 'Would you rather…',
    options: ['Cook dinner for the family', 'Plan the next family outing'],
    only: ['PARENT_CHILD', 'SIBLINGS'],
  },
  { prompt: 'Would you rather…', options: ['Win a quiz show', 'Win a dance competition'] },
  { prompt: 'Would you rather…', options: ['Talk to animals', 'Speak every language'] },
  { prompt: 'Would you rather…', options: ['Go on a road trip', 'Go on a train journey'] },
  { prompt: 'Would you rather…', options: ['Stay up all night', 'Wake up at 5 am'] },
  { prompt: 'Would you rather…', options: ['Cook dinner', 'Do the dishes'] },
  { prompt: 'Would you rather…', options: ['Explore space', 'Explore the deep ocean'] },
  { prompt: 'Would you rather…', options: ['Rewatch your favourite show', 'Start a brand new one'] },
  { prompt: 'Would you rather…', options: ['Have a huge party', 'Have a quiet night in'] },
  { prompt: 'Would you rather…', options: ['Always be 10 minutes late', 'Always be 20 minutes early'] },
];

const WHO_KNOWS_WHOM: Q[] = [
  {
    prompt: 'Ideal weekend?',
    options: ['Out with friends', 'Netflix and snacks', 'An adventure', 'Sleeping in'],
  },
  { prompt: 'Go-to comfort food?', options: ['Maggi', 'Biryani', 'Pizza', 'Ice cream'] },
  {
    prompt: 'Most likely to be late because…',
    options: ['Overslept', 'Got distracted', 'Traffic', 'Never late'],
  },
  { prompt: 'Favourite season?', options: ['Summer', 'Monsoon', 'Winter', 'Spring'] },
  {
    prompt: 'In a group project, they are…',
    options: ['The leader', 'The ideas person', 'The doer', 'The vibe'],
  },
  { prompt: 'Biggest fear?', options: ['Heights', 'Spiders', 'Public speaking', 'The dark'] },
  { prompt: 'Dream job?', options: ['Founder', 'Artist', 'Traveller', 'Scientist'] },
  { prompt: 'How do they handle stress?', options: ['Music', 'Food', 'Sleep', 'Talking it out'] },
  { prompt: 'Phone screen time per day?', options: ['Under 2 hours', '2–4 hours', '4–6 hours', '6+ hours'] },
  { prompt: 'Pick a superpower', options: ['Flying', 'Teleporting', 'Time freeze', 'Super strength'] },
  { prompt: 'Favourite way to celebrate?', options: ['Big dinner', 'Trip', 'Party', 'Quiet day'] },
  { prompt: 'How do they show they care?', options: ['Kind words', 'Little gifts', 'Spending time', 'Hugs'] },
  { prompt: 'Which genre do they reach for first?', options: ['Comedy', 'Thriller', 'Romance', 'Sci-fi'] },
];

const SHARED_TRIVIA: Q[] = [
  {
    prompt: 'Which planet is known as the Red Planet?',
    options: ['Venus', 'Mars', 'Jupiter', 'Mercury'],
    correctOption: 1,
  },
  {
    prompt: 'How many players are on a cricket team on the field?',
    options: ['9', '10', '11', '12'],
    correctOption: 2,
  },
  {
    prompt: 'What is the largest ocean on Earth?',
    options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'],
    correctOption: 3,
  },
  {
    prompt: 'Which gas do plants absorb from the air?',
    options: ['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Helium'],
    correctOption: 1,
  },
  {
    prompt: 'Who painted the Mona Lisa?',
    options: ['Leonardo da Vinci', 'Picasso', 'Van Gogh', 'Michelangelo'],
    correctOption: 0,
  },
  {
    prompt: 'What is the boiling point of water at sea level in °C?',
    options: ['90', '100', '110', '120'],
    correctOption: 1,
  },
  {
    prompt: 'Which is the longest river in the world?',
    options: ['Amazon', 'Nile', 'Ganga', 'Yangtze'],
    correctOption: 1,
  },
  { prompt: 'How many continents are there?', options: ['5', '6', '7', '8'], correctOption: 2 },
  {
    prompt: 'What does CPU stand for?',
    options: [
      'Central Processing Unit',
      'Computer Power Unit',
      'Core Program Utility',
      'Central Program Unit',
    ],
    correctOption: 0,
  },
  { prompt: 'Which is the smallest prime number?', options: ['0', '1', '2', '3'], correctOption: 2 },
  {
    prompt: 'In which country is the Taj Mahal?',
    options: ['Pakistan', 'India', 'Nepal', 'Bangladesh'],
    correctOption: 1,
  },
  {
    prompt: 'Which animal is known as the Ship of the Desert?',
    options: ['Horse', 'Camel', 'Elephant', 'Donkey'],
    correctOption: 1,
  },
  { prompt: 'What is the chemical symbol for gold?', options: ['Go', 'Gd', 'Au', 'Ag'], correctOption: 2 },
  { prompt: 'How many sides does a hexagon have?', options: ['5', '6', '7', '8'], correctOption: 1 },
  {
    prompt: 'Which language has the most native speakers?',
    options: ['English', 'Hindi', 'Spanish', 'Mandarin'],
    correctOption: 3,
  },
  {
    prompt: 'Which organ pumps blood around the body?',
    options: ['Lungs', 'Liver', 'Heart', 'Kidney'],
    correctOption: 2,
  },
  {
    prompt: 'Who wrote "Romeo and Juliet"?',
    options: ['Charles Dickens', 'William Shakespeare', 'Jane Austen', 'Mark Twain'],
    correctOption: 1,
  },
  {
    prompt: 'What is the fastest land animal?',
    options: ['Lion', 'Cheetah', 'Horse', 'Leopard'],
    correctOption: 1,
  },
];

const EMOJI_DECODE: Q[] = [
  {
    prompt: '🦁👑🌅 (movie)',
    options: ['The Lion King', 'Madagascar', 'Jungle Book', 'Tarzan'],
    correctOption: 0,
  },
  { prompt: '🚢🧊💔 (movie)', options: ['Jaws', 'Titanic', 'Frozen', 'Life of Pi'], correctOption: 1 },
  { prompt: '🕷️🧑🕸️ (movie)', options: ['Ant-Man', 'Batman', 'Spider-Man', 'Venom'], correctOption: 2 },
  {
    prompt: '🧙‍♂️⚡👓 (movie)',
    options: ['Lord of the Rings', 'Doctor Strange', 'Merlin', 'Harry Potter'],
    correctOption: 3,
  },
  { prompt: '👸❄️⛄ (movie)', options: ['Frozen', 'Cinderella', 'Brave', 'Moana'], correctOption: 0 },
  {
    prompt: '🦖🏝️🚙 (movie)',
    options: ['King Kong', 'Jurassic Park', 'Godzilla', 'Cast Away'],
    correctOption: 1,
  },
  {
    prompt: '🐠🔍🌊 (movie)',
    options: ['Shark Tale', 'Moana', 'Finding Nemo', 'The Little Mermaid'],
    correctOption: 2,
  },
  {
    prompt: '🏏🏆🇮🇳 (movie)',
    options: ['Dangal', 'Chak De! India', 'Gully Boy', 'Lagaan'],
    correctOption: 3,
  },
  {
    prompt: '👻👻📞 (movie)',
    options: ['Ghostbusters', 'Casper', 'The Conjuring', 'Coco'],
    correctOption: 0,
  },
  { prompt: '🧸🤠🚀 (movie)', options: ['Cars', 'Toy Story', 'Up', 'Wall-E'], correctOption: 1 },
  {
    prompt: '☔🎶💃 (song)',
    options: ['Umbrella', 'Purple Rain', 'Singin’ in the Rain', 'Raindrops'],
    correctOption: 2,
  },
  { prompt: '🌍🗺️🍕🍝 (food)', options: ['Paella', 'Sushi', 'Tacos', 'Italian food'], correctOption: 3 },
  { prompt: '🍎📱💻 (brand)', options: ['Apple', 'Samsung', 'Google', 'Microsoft'], correctOption: 0 },
  {
    prompt: '⭐⚔️🌌 (movie)',
    options: ['Star Trek', 'Star Wars', 'Interstellar', 'Avatar'],
    correctOption: 1,
  },
];

const AGREE_O_METER: Q[] = [
  { prompt: 'Pineapple belongs on pizza.', options: AGREE_SCALE },
  { prompt: 'Breakfast is the best meal of the day.', options: AGREE_SCALE },
  { prompt: 'Texting is better than calling.', options: AGREE_SCALE },
  { prompt: 'Rainy days are the best days.', options: AGREE_SCALE },
  { prompt: 'The book is always better than the movie.', options: AGREE_SCALE },
  { prompt: 'Weekends should be for doing nothing at all.', options: AGREE_SCALE },
  { prompt: 'Sequels are never as good as the original.', options: AGREE_SCALE },
  { prompt: 'Spicy food makes everything better.', options: AGREE_SCALE },
  { prompt: 'Planning a trip is half the fun.', options: AGREE_SCALE },
  { prompt: 'Cats are better company than dogs.', options: AGREE_SCALE },
  { prompt: 'Early mornings are underrated.', options: AGREE_SCALE },
  { prompt: 'Board games beat video games.', options: AGREE_SCALE },
];

const RANK_IT: Q[] = [
  {
    prompt: 'Rank these lazy Sunday plans',
    options: ['Movie marathon', 'Long walk', 'Cooking together', 'Afternoon nap'],
  },
  { prompt: 'Rank these desserts', options: ['Ice cream', 'Gulab jamun', 'Chocolate cake', 'Cheesecake'] },
  { prompt: 'Rank these holiday spots', options: ['Beach', 'Mountains', 'Big city', 'Countryside'] },
  {
    prompt: 'Rank these date ideas',
    options: ['Stargazing', 'Food crawl', 'Concert', 'Museum'],
    only: PARTNERS_ONLY,
  },
  { prompt: 'Rank these hangout plans', options: ['Stargazing', 'Food crawl', 'Concert', 'Museum'] },
  {
    prompt: 'Rank these family traditions',
    options: ['Festival food', 'Road trips', 'Movie nights', 'Game nights'],
  },
  { prompt: 'Rank these superpowers', options: ['Flying', 'Teleporting', 'Mind reading', 'Time travel'] },
  { prompt: 'Rank these snacks', options: ['Samosa', 'Popcorn', 'Chips', 'Fruit'] },
  { prompt: 'Rank these seasons', options: ['Summer', 'Monsoon', 'Winter', 'Spring'] },
  { prompt: 'Rank these ways to relax', options: ['Music', 'Reading', 'Gaming', 'Sleeping'] },
  { prompt: 'Rank these pets', options: ['Dog', 'Cat', 'Rabbit', 'Fish'] },
  { prompt: 'Rank these drinks', options: ['Chai', 'Coffee', 'Hot chocolate', 'Lemonade'] },
];

const TITLES: Record<GameTypeName, string> = {
  WOULD_YOU_RATHER: 'Would You Rather',
  WHO_KNOWS_WHOM: 'Who Knows Whom Better?',
  SHARED_TRIVIA: 'Team Trivia',
  EMOJI_DECODE: 'Emoji Decode',
  AGREE_O_METER: 'Agree-o-meter',
  RANK_IT: 'Rank It',
};

const POOLS: Record<Exclude<GameTypeName, 'WHO_KNOWS_WHOM'>, Q[]> = {
  WOULD_YOU_RATHER,
  SHARED_TRIVIA,
  EMOJI_DECODE,
  AGREE_O_METER,
  RANK_IT,
};

// Deterministic shuffle seeded by pair + day: both partners get the same game,
// and different pairs/days get different picks.
function seededPick<T>(items: T[], count: number, seed: string): T[] {
  return items
    .map((item, i) => ({ item, rank: createHash('sha256').update(`${seed}:${i}`).digest().readUInt32BE(0) }))
    .sort((a, b) => a.rank - b.rank)
    .slice(0, count)
    .map((x) => x.item);
}

const forPair = (pool: Q[], relationship: Relationship) =>
  pool
    .filter((q) => !q.only || q.only.includes(relationship))
    .map((q) => ({ prompt: q.prompt, options: q.options, correctOption: q.correctOption }));

export function bankGame(
  type: GameTypeName,
  seed: string,
  relationship: Relationship = 'FRIENDS',
): GameContent {
  if (type === 'WHO_KNOWS_WHOM') {
    const picks = seededPick(forPair(WHO_KNOWS_WHOM, relationship), 6, seed);
    return {
      type,
      title: TITLES[type],
      questions: picks.map((q, i) => ({ ...q, about: i % 2 === 0 ? ('A' as const) : ('B' as const) })),
    };
  }
  return { type, title: TITLES[type], questions: seededPick(forPair(POOLS[type], relationship), 5, seed) };
}
