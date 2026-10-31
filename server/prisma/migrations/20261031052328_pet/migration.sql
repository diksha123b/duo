-- CreateTable
CREATE TABLE "pets" (
    "pair_id" UUID NOT NULL,
    "name" TEXT NOT NULL DEFAULT 'Mochi',
    "color" TEXT NOT NULL DEFAULT 'peach',
    "outfit" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pets_pkey" PRIMARY KEY ("pair_id")
);

-- CreateTable
CREATE TABLE "pet_pats" (
    "pair_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pet_pats_pkey" PRIMARY KEY ("pair_id","user_id","day")
);

-- AddForeignKey
ALTER TABLE "pets" ADD CONSTRAINT "pets_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pet_pats" ADD CONSTRAINT "pet_pats_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
