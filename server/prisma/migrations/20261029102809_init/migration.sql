-- CreateEnum
CREATE TYPE "GameType" AS ENUM ('WHO_KNOWS_WHOM', 'WOULD_YOU_RATHER', 'SHARED_TRIVIA');

-- CreateEnum
CREATE TYPE "GameSource" AS ENUM ('AI', 'BANK');

-- CreateEnum
CREATE TYPE "GenerationStatus" AS ENUM ('SUCCESS', 'INVALID', 'FAILED');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT,
    "google_id" TEXT,
    "current_pair_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "family_id" UUID NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "profiles" (
    "user_id" UUID NOT NULL,
    "display_name" TEXT NOT NULL,
    "interests" TEXT[],
    "timezone" TEXT NOT NULL DEFAULT 'UTC',
    "avatar_url" TEXT,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "pairs" (
    "id" UUID NOT NULL,
    "user_a_id" UUID NOT NULL,
    "user_b_id" UUID NOT NULL,
    "timezone" TEXT NOT NULL DEFAULT 'UTC',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at" TIMESTAMP(3),

    CONSTRAINT "pairs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invites" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "creator_id" UUID NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "used_at" TIMESTAMP(3),
    "used_by_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "invites_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "games" (
    "id" UUID NOT NULL,
    "pair_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "type" "GameType" NOT NULL,
    "source" "GameSource" NOT NULL,
    "title" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMP(3),

    CONSTRAINT "games_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "questions" (
    "id" UUID NOT NULL,
    "game_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "prompt" TEXT NOT NULL,
    "options" TEXT[],
    "correct_option" INTEGER,
    "meta" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "questions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "answers" (
    "id" UUID NOT NULL,
    "question_id" UUID NOT NULL,
    "game_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "choice" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "answers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "submissions" (
    "id" UUID NOT NULL,
    "game_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "idempotency_key" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "submissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "streaks" (
    "pair_id" UUID NOT NULL,
    "current" INTEGER NOT NULL DEFAULT 0,
    "longest" INTEGER NOT NULL DEFAULT 0,
    "last_completed_day" DATE,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "streaks_pkey" PRIMARY KEY ("pair_id")
);

-- CreateTable
CREATE TABLE "events" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "user_id" UUID,
    "pair_id" UUID,
    "props" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "generation_logs" (
    "id" UUID NOT NULL,
    "pair_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "status" "GenerationStatus" NOT NULL,
    "model" TEXT NOT NULL,
    "latency_ms" INTEGER NOT NULL,
    "input_tokens" INTEGER,
    "output_tokens" INTEGER,
    "cost_usd" DECIMAL(10,6),
    "error" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "generation_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_google_id_key" ON "users"("google_id");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_family_id_idx" ON "refresh_tokens"("family_id");

-- CreateIndex
CREATE INDEX "pairs_user_a_id_idx" ON "pairs"("user_a_id");

-- CreateIndex
CREATE INDEX "pairs_user_b_id_idx" ON "pairs"("user_b_id");

-- CreateIndex
CREATE UNIQUE INDEX "invites_code_key" ON "invites"("code");

-- CreateIndex
CREATE INDEX "invites_creator_id_idx" ON "invites"("creator_id");

-- CreateIndex
CREATE UNIQUE INDEX "games_pair_id_day_key" ON "games"("pair_id", "day");

-- CreateIndex
CREATE UNIQUE INDEX "questions_game_id_position_key" ON "questions"("game_id", "position");

-- CreateIndex
CREATE UNIQUE INDEX "answers_question_id_user_id_key" ON "answers"("question_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "submissions_idempotency_key_key" ON "submissions"("idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "submissions_game_id_user_id_key" ON "submissions"("game_id", "user_id");

-- CreateIndex
CREATE INDEX "events_name_created_at_idx" ON "events"("name", "created_at");

-- CreateIndex
CREATE INDEX "generation_logs_created_at_idx" ON "generation_logs"("created_at");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_current_pair_id_fkey" FOREIGN KEY ("current_pair_id") REFERENCES "pairs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "profiles" ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "invites" ADD CONSTRAINT "invites_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "games" ADD CONSTRAINT "games_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "questions" ADD CONSTRAINT "questions_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "games"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "answers" ADD CONSTRAINT "answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "questions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "answers" ADD CONSTRAINT "answers_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "games"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "answers" ADD CONSTRAINT "answers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "submissions" ADD CONSTRAINT "submissions_game_id_fkey" FOREIGN KEY ("game_id") REFERENCES "games"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "submissions" ADD CONSTRAINT "submissions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "streaks" ADD CONSTRAINT "streaks_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "events" ADD CONSTRAINT "events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "events" ADD CONSTRAINT "events_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "generation_logs" ADD CONSTRAINT "generation_logs_pair_id_fkey" FOREIGN KEY ("pair_id") REFERENCES "pairs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
