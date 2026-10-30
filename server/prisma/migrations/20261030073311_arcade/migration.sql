-- CreateEnum
CREATE TYPE "ArcadeKind" AS ENUM ('TIC_TAC_TOE', 'FOUR_IN_A_ROW', 'DOTS_AND_BOXES', 'CHESS', 'LUDO', 'WORD_TILES');

-- CreateEnum
CREATE TYPE "MatchStatus" AS ENUM ('ACTIVE', 'FINISHED', 'ABANDONED');

-- CreateTable
CREATE TABLE "matches" (
    "id" UUID NOT NULL,
    "pair_id" UUID NOT NULL,
    "kind" "ArcadeKind" NOT NULL,
    "players" UUID[],
    "state" JSONB NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 0,
    "status" "MatchStatus" NOT NULL DEFAULT 'ACTIVE',
    "winner_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "matches_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "matches_pair_id_status_idx" ON "matches"("pair_id", "status");

-- AddForeignKey
ALTER TABLE "matches" ADD CONSTRAINT "matches_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
