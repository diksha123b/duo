-- AlterTable
ALTER TABLE "matches" ADD COLUMN     "settings" JSONB NOT NULL DEFAULT '{}';
