-- Схема

DROP TABLE IF EXISTS "Peers";
CREATE TABLE IF NOT EXISTS "Peers"
(
    "Nickname" VARCHAR(255) NOT NULL PRIMARY KEY,
    "Birthday" DATE
);


DROP TABLE IF EXISTS "Tasks";
CREATE TABLE IF NOT EXISTS "Tasks"
(
    "Title"      VARCHAR(255) PRIMARY KEY,
    "ParentTask" VARCHAR(255) REFERENCES "Tasks" ("Title") ON DELETE CASCADE ,
    "MaxXP"      int2 DEFAULT 0 CHECK ("MaxXP" >= 0 )
);

CREATE OR REPLACE FUNCTION check_null_constraint() RETURNS TRIGGER AS
$$
BEGIN
  IF NEW."ParentTask" IS NULL AND EXISTS (SELECT 1 FROM "Tasks" WHERE "ParentTask" IS NULL) THEN
    RAISE EXCEPTION 'Only one record can have NULL value for ParentTask field';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER enforce_null_constraint
    BEFORE INSERT OR UPDATE
    ON "Tasks"
    FOR EACH ROW
EXECUTE FUNCTION check_null_constraint();


DROP TABLE IF EXISTS "Checks";
CREATE TABLE IF NOT EXISTS "Checks"
(
    "ID"    SERIAL PRIMARY KEY,
    "Peer"  VARCHAR(255) REFERENCES "Peers" ("Nickname") ON DELETE CASCADE,
    "Tasks" VARCHAR(255) REFERENCES "Tasks" ("Title") ON DELETE CASCADE,
    "Date"  DATE
);

DROP INDEX IF EXISTS idx_checks_peer_tasks;
CREATE UNIQUE INDEX idx_checks_peer_tasks ON "Checks" ("Peer", "Tasks");


-- P2P
-- DROP TYPE IF EXISTS state;
CREATE TYPE  State AS ENUM ('Start', 'Success', 'Failure');

DROP TABLE IF EXISTS "P2P";
CREATE TABLE IF NOT EXISTS "P2P"
(
    "ID"           SERIAL PRIMARY KEY,
    "Check"        INT REFERENCES "Checks",
    "CheckingPeer" VARCHAR(255) NOT NULL REFERENCES "Peers",
    "State"        State NOT NULL DEFAULT 'Start',
    "Time"           time(0) DEFAULT NOW()
)
;

CREATE UNIQUE INDEX idx_p2p_check_checking_peer_state ON "P2P" ("Check", "CheckingPeer", "State");
-- максимум 2 записи +
-- если запись 1 в своем роде - старт +
-- если старт уже есть - 2я не старт +
-- у одной проверки может быть только один проверяющий пир +
-- ?? сделать запрет на update
-- В таблице не может быть больше одной незавершенной P2P проверки,
-- относящейся к конкретному заданию, пиру и проверяющему.





DROP FUNCTION p2p_trigger_function();
CREATE OR REPLACE FUNCTION p2p_trigger_function() RETURNS TRIGGER AS
$$
BEGIN
  IF (SELECT count(*) > 1   FROM "P2P" WHERE "CheckingPeer" = NEW."CheckingPeer" AND "Check" = NEW."Check")  THEN
    RAISE EXCEPTION 'У одной проверки не может быть более 2 записей';
  END IF;

  IF (
      (SELECT count(*) = 0   FROM "P2P" WHERE "CheckingPeer" = NEW."CheckingPeer" AND "Check" = NEW."Check")
            AND
       (SELECT NEW."State" != 'Start')
      )  THEN
    RAISE EXCEPTION 'Начальная запись о проверке должна быть "Start"';
  END IF;

  IF (
       (SELECT count(*) FROM "P2P" WHERE "Check" = NEW."Check") > 0
            AND
        (SELECT (SELECT "CheckingPeer"  FROM "P2P" WHERE "Check" = NEW."Check" LIMIT 1) != NEW."CheckingPeer")
      ) THEN
      RAISE EXCEPTION 'Проверка может проверяться только одним пиром';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER p2p_checks_trigger ON "P2P";

CREATE TRIGGER p2p_checks_trigger
BEFORE INSERT OR UPDATE ON "P2P"
FOR EACH ROW
EXECUTE FUNCTION p2p_trigger_function();



INSERT INTO public."P2P" ("ID", "Check", "CheckingPeer", "State", "Time") VALUES (DEFAULT, 2::integer, 'abolonef'::varchar(255), 'Start'::state, DEFAULT);
INSERT INTO public."P2P" ("ID", "Check", "CheckingPeer", "State", "Time") VALUES (DEFAULT, 2::integer, 'abolonef'::varchar(255), 'Failure'::state, DEFAULT);


-- Verter

DROP TABLE IF EXISTS "Verter";
CREATE TABLE IF NOT EXISTS "Verter"
(
    "ID"    SERIAL PRIMARY KEY,
    "Check" INT,
    "State" State,
    "Time"  TIMESTAMP(0) DEFAULT NOW()
)
;

DROP TABLE IF EXISTS "TransferredPoints";
CREATE TABLE IF NOT EXISTS "TransferredPoints"
(
    "CheckingPeer" VARCHAR(255) NOT NULL,
    "CheckedPeer"  VARCHAR(255) NOT NULL,
    "PointsAmount" INT CHECK ( "PointsAmount" >= 0 )
)
;


DROP TABLE IF EXISTS "Friends";
CREATE TABLE IF NOT EXISTS "Friends"
(
    "ID"    SERIAL PRIMARY KEY,
    "Peer1" VARCHAR(255),
    "Peer2" VARCHAR(255)
)
;

DROP TABLE IF EXISTS "Recommendations";
CREATE TABLE IF NOT EXISTS "Recommendations"
(
    "ID"              SERIAL PRIMARY KEY,
    "Peer"            VARCHAR(255),
    "RecommendedPeer" VARCHAR(255)
)
;

DROP TABLE IF EXISTS "XP";
CREATE TABLE IF NOT EXISTS "XP"
(
    "ID"       SERIAL PRIMARY KEY,
    "Check"    INT,
    "XPAmount" INT
)
;

DROP TABLE IF EXISTS "TimeTracking";
CREATE TABLE IF NOT EXISTS "TimeTracking"
(
    "ID"   SERIAL PRIMARY KEY,
    "Peer" VARCHAR,
    "Date" DATE,
    "Time" TIMESTAMP(0) DEFAULT NOW(),
    "State"  INT,
    CONSTRAINT state_chk_constraint CHECK (State = 1 OR State = 2)
)
;




-- Данные
INSERT INTO "Peers" ("Nickname")
VALUES ('akolobaha'),
       ('gengarka'),
       ('bernardi'),
       ('phella'),
       ('abolonef')
;

INSERT INTO "Tasks" ("Title", "ParentTask", "MaxXP")
VALUES
    ('Simple bash', NULL, 50),
    ('Strings', 'Simple bash', 250),
    ('Linux basics', 'Strings', 450),
    ('Docker', 'Linux basics', 200),
    ('SQL 1', 'Docker', 175)
;

INSERT INTO "Checks" ("ID", "Peer", "Tasks", "Date")
VALUES
    (0, 'akolobaha', 'Simple bash', '2023-07-01'),
    (1, 'gengarka', 'Strings', '2023-07-02'),
    (2, 'bernardi', 'Strings', '2023-07-03'),
    (3, 'phella', 'Strings', '2023-07-04'),
    (4, 'abolonef', 'Strings', '2023-07-05'),
    (5, 'abolonef', 'Simple bash', '2023-07-01'),
    (6, 'phella', 'Linux basics', '2023-07-02'),
    (7, 'gengarka', 'Linux basics', '2023-07-03'),
    (8, 'bernardi', 'Docker', '2023-07-04'),
    (9, 'akolobaha', 'SQL 1', '2023-07-05')
;


INSERT INTO "P2P" ("Check", "CheckingPeer", "State", "Time")
VALUES
    (1, 'gengarka', 'Start', '08:41'),
    (2, 'akolobaha', 'Start', '09:45'),
    (3, 'phella', 'Start', '18:30'),
    (4, 'abolonef', 'Start', '20:25'),
    (5, 'bernardi', 'Start', '23:41')
;





-- INSERT INTO "P2P" ("Check", "CheckingPeer", "State", Time)
--VALUES
  --  ('')