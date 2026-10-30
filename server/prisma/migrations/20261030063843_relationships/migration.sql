-- CreateEnum
CREATE TYPE "Relationship" AS ENUM ('PARTNERS', 'BEST_FRIENDS', 'FRIENDS', 'SIBLINGS', 'PARENT_CHILD');

-- AlterTable
ALTER TABLE "invites" ADD COLUMN     "creator_is_parent" BOOLEAN,
ADD COLUMN     "relationship" "Relationship" NOT NULL DEFAULT 'FRIENDS';

-- AlterTable
ALTER TABLE "pairs" ADD COLUMN     "parent_id" UUID,
ADD COLUMN     "relationship" "Relationship" NOT NULL DEFAULT 'FRIENDS';
