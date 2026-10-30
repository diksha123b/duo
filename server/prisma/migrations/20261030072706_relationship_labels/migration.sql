-- AlterEnum
ALTER TYPE "Relationship" ADD VALUE 'COLLEAGUES';

-- AlterTable
ALTER TABLE "invites" ADD COLUMN     "relationship_label" TEXT;

-- AlterTable
ALTER TABLE "pairs" ADD COLUMN     "relationship_label" TEXT;
