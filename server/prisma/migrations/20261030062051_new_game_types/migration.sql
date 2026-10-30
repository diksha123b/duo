-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "GameType" ADD VALUE 'EMOJI_DECODE';
ALTER TYPE "GameType" ADD VALUE 'AGREE_O_METER';
ALTER TYPE "GameType" ADD VALUE 'RANK_IT';

-- AlterTable
ALTER TABLE "answers" ADD COLUMN     "ranking" INTEGER[] DEFAULT ARRAY[]::INTEGER[];
