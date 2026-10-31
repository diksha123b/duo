-- The demo partner is now called Duo Jr. (it was "Sam (bot)").
UPDATE "profiles" SET "display_name" = 'Duo Jr.'
WHERE "user_id" IN (SELECT "id" FROM "users" WHERE "is_bot" = true);
