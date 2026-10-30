-- DropIndex
DROP INDEX "games_pair_id_day_key";

-- AlterTable
ALTER TABLE "games" ADD COLUMN     "is_daily" BOOLEAN NOT NULL DEFAULT true;

-- CreateIndex
CREATE INDEX "games_pair_id_day_idx" ON "games"("pair_id", "day");

-- Still only one daily game per pair per day; bonus games are unlimited.
CREATE UNIQUE INDEX "games_one_daily_per_day" ON "games"("pair_id", "day") WHERE "is_daily";
