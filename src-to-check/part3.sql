--1) Write a function that returns the TransferredPoints table in a more human-readable form

DROP FUNCTION IF EXISTS fnc_readable_transferred_points;

CREATE OR REPLACE FUNCTION fnc_readable_transferred_points()
RETURNS table (peer1 varchar, peer2 varchar, amount int) AS $readTransferredPoints$
    BEGIN
        return query
        --making revert table to find peer connections
        WITH tp2 AS (SELECT tp.checkedpeer checkingpeer, tp.checkingpeer checkedpeer
            FROM transferredpoints AS tp),
        --making duplicate with points because intersect won't work
        tp3 AS (SELECT tp.checkedpeer checkingpeer, tp.checkingpeer checkedpeer, tp.pointsamount
            FROM transferredpoints AS tp),
        --finding intersections
        inter_points AS (SELECT checkingpeer, checkedpeer FROM transferredpoints
        INTERSECT
        SELECT * FROM tp2),
        count_points AS (SELECT ip1.checkingpeer, ip1.checkedpeer, CAST (count(ip1.checkingpeer) AS int) ca
            FROM inter_points ip1
            LEFT JOIN inter_points ip2 ON ip1.checkingpeer = ip2.checkedpeer
            GROUP BY ip1.checkingpeer, ip1.checkedpeer),
        -- removing wrong intersections
        clear_points AS (SELECT cp.checkingpeer, cp.checkedpeer, ca, tp.pointsamount FROM count_points cp, transferredpoints tp
        WHERE ca > 1 AND cp.checkingpeer = tp.checkingpeer AND cp.checkedpeer = tp.checkedpeer),
        --finding reverse points
        second_points AS ( SELECT tp3.checkingpeer, tp3.checkedpeer, -(tp3.pointsamount) pointsamount FROM tp3
                WHERE (tp3.checkingpeer, tp3.checkedpeer) IN
              (SELECT clear_points.checkingpeer, clear_points.checkedpeer FROM clear_points)),
        --making table of intersections with final points
        repeatedPoints AS (SELECT cp.checkingpeer, cp.checkedpeer, cp.pointsamount FROM clear_points cp
        UNION
        SELECT * FROM second_points),
        --summarizing points
        final_points AS (SELECT rp.checkingpeer, rp.checkedpeer, CAST (sum(pointsamount) AS int) FROM repeatedPoints rp
            GROUP BY rp.checkingpeer, rp.checkedpeer)
         --finale
        SELECT tp.checkingpeer, tp.checkedpeer, tp.pointsamount FROM transferredpoints tp
            WHERE ((checkingpeer, checkedpeer) NOT IN (SELECT checkingpeer, checkedpeer FROM final_points)) AND
                  (checkingpeer, checkedpeer) NOT IN (SELECT checkedpeer, checkingpeer FROM final_points)
        UNION
        SELECT * FROM final_points ORDER BY 1;
    end;
    $readTransferredPoints$ LANGUAGE plpgsql;

-- SELECT * FROM fnc_readable_transferred_points();


--2) Write a function that returns a table of the following form: user name, name of the checked task, number of XP received
DROP FUNCTION IF EXISTS fnc_successful_checks();
CREATE OR REPLACE FUNCTION fnc_successful_checks()
RETURNS table (peer varchar, task varchar, xp int) AS $successfulChecks$
    BEGIN
        return query
        SELECT checks.peer, checks.task, x.xpamount xp FROM checks
        JOIN p2p p on checks.id = p."Check"
        JOIN xp x on checks.id = x."Check"
        WHERE p.state = 'Success' ORDER BY peer;
    end;
    $successfulChecks$ language plpgsql;

-- SELECT * FROM fnc_successful_checks();

--3) Write a function that finds the peers who have not left campus for the whole day

DROP FUNCTION IF EXISTS fnc_find_diligent_students(d date);
CREATE OR REPLACE FUNCTION fnc_find_diligent_students(d date)
RETURNS table (peer varchar) AS $noLifeStudents$
    BEGIN
        return query
        WITH tt AS (SELECT timetracking.peer, count(timetracking.state) c, timetracking.date FROM timetracking
        WHERE state = 2 AND date = d GROUP BY timetracking.peer, timetracking.date)
        SELECT tt.peer FROM tt WHERE c = 1;
    end;
    $noLifeStudents$ LANGUAGE plpgsql;

-- SELECT * FROM fnc_find_diligent_students('2023-01-01');


--4) Calculate the change in the number of peer points of each peer using the TransferredPoints table

DROP PROCEDURE IF EXISTS proc_count_points(IN c refcursor);
CREATE OR REPLACE PROCEDURE proc_count_points(IN c refcursor)
LANGUAGE plpgsql AS $proc_count_points$
    BEGIN
        OPEN c FOR
        WITH points_taken AS (SELECT tp.checkingpeer Peer, SUM(tp.pointsamount) PointsChange FROM transferredpoints tp
    GROUP BY tp.checkingpeer),
        points_given AS (SELECT tp.checkedpeer Peer, SUM(-tp.pointsamount) PointsChange FROM transferredpoints tp
    GROUP BY tp.checkedpeer),
        all_points AS (SELECT * FROM points_taken UNION SELECT * FROM points_given),
    result AS(SELECT all_points.Peer, SUM(PointsChange) FROM all_points GROUP BY all_points.Peer
        ORDER BY 1)
        SELECT * FROM result;
    end;
$proc_count_points$;

-- BEGIN;
-- CALL proc_count_points('1');
-- FETCH ALL IN "1";
-- END;

--5) Calculate the change in the number of peer points of each peer using the table returned by the first function from Part 3

CREATE OR REPLACE PROCEDURE proc_count_points_fnc(IN c refcursor)
LANGUAGE plpgsql AS $proc_count_points_fnc$
    BEGIN
        OPEN c FOR
        WITH points_taken AS (SELECT tp.peer1 Peer, SUM(tp.amount) PointsChange FROM fnc_readable_transferred_points() AS tp
    GROUP BY tp.peer1),
        points_given AS (SELECT tp.peer2 Peer, SUM(-tp.amount) PointsChange FROM fnc_readable_transferred_points() tp
    GROUP BY tp.peer2),
        all_points AS (SELECT * FROM points_taken UNION ALL SELECT * FROM points_given),
    result AS(SELECT all_points.Peer, SUM(PointsChange) PointsChange FROM all_points GROUP BY Peer
        ORDER BY 1)
        SELECT * FROM result;
    end;
$proc_count_points_fnc$;

-- BEGIN;
-- CALL proc_count_points_fnc('1');
-- FETCH ALL IN "1";
-- end ;


--6) Find the most frequently checked task for each day
DROP PROCEDURE IF EXISTS proc_count_most_frequently_checked_tasks(c refcursor);
CREATE OR REPLACE PROCEDURE proc_count_most_frequently_checked_tasks(
    IN c refcursor
)
LANGUAGE plpgsql AS $proc_count_most_frequently_checked_tasks$
    BEGIN
        OPEN c for
        WITH counted_checks AS (SELECT task, date, count(task) amount FROM checks GROUP BY task, date),
        max_count AS (SELECT cc.task, cc.date, cc.amount FROM counted_checks cc
        WHERE amount = (SELECT max(amount) FROM counted_checks WHERE counted_checks.date = cc.date))
        SELECT date, task FROM  max_count ORDER BY date;
    end;
    $proc_count_most_frequently_checked_tasks$;
--
-- INSERT INTO checks VALUES (21, 'peer1', 'C3_s21_string+', '2023-04-05');
-- DELETE FROM checks WHERE id = 21;
-- BEGIN ;
-- CALL proc_count_most_frequently_checked_tasks('1');
-- FETCH ALL IN "1";
-- end;

-- 7) Find all peers who have completed the whole given block of tasks and the completion date of the last task

-- INSERT INTO checks VALUES (21, 'peer4', 'SQL3_RetailAnalitycs v1.0', '2023-06-03');
-- INSERT INTO xp VALUES (13, 21, 500);
-- INSERT INTO checks VALUES (22, 'peer4', 'SQL2_Info21 v1.0', '2023-06-03');
-- INSERT INTO xp VALUES (14, 22, 500);
-- INSERT INTO checks VALUES (23, 'peer4', 'SQL1_Bootcamp', '2023-06-03');
-- INSERT INTO xp VALUES (15, 23, 500);
-- DELETE FROM xp WHERE id = 13;
-- DELETE FROM checks WHERE id = 21;
-- UPDATE checks SET date = '2023-06-04' WHERE id = 21;

DROP PROCEDURE IF EXISTS proc_count_number_of_peers_finished_block(c refcursor, block text);
CREATE OR REPLACE PROCEDURE proc_count_number_of_peers_finished_block(
    IN c refcursor, IN block text
    )
LANGUAGE plpgsql AS $proc_count_number_of_peers_finished_block$
    BEGIN
        OPEN c for
        WITH tasks_in_blocks AS (
            SELECT substring(tasks.title  FROM '\D+\d+') AS task FROM tasks
        ),
        block_tasks AS (SELECT t.task trimmed_task FROM tasks_in_blocks t
            WHERE substring(t.task FROM '\D+') = block),
        peers_finished_block AS (SELECT c.peer, c.task, c.date, b.trimmed_task  FROM checks c
            JOIN block_tasks b ON substring(c.task FROM '\D+\d+') = b.trimmed_task
            WHERE c.id IN (SELECT xp."Check" FROM xp)),
        result AS (SELECT (SELECT CASE WHEN (SELECT COUNT(*) FROM peers_finished_block) != (SELECT COUNT(*) FROM tasks_in_blocks)
            THEN peers_finished_block.peer
            ELSE (SELECT peer "Peer" FROM peers_finished_block WHERE date = '1990-01-01') END) , date AS "Date"
        FROM peers_finished_block WHERE peers_finished_block.trimmed_task = (SELECT MAX(block_tasks.trimmed_task) FROM block_tasks))
        SELECT * FROM result;
    end;
    $proc_count_number_of_peers_finished_block$;
DELETE FROM xp WHERE "Check" = 21;

-- BEGIN;
-- CALL proc_count_number_of_peers_finished_block('1', 'SQL');
-- FETCH ALL IN "1";
-- end;

--8) Determine which peer each student should go to for a check.
DROP PROCEDURE IF EXISTS proc_recommendations(c refcursor);
CREATE OR REPLACE PROCEDURE proc_recommendations(IN c refcursor)
LANGUAGE plpgsql AS $proc_recommendations$
    BEGIN
        OPEN c FOR
        WITH friends_reccomendations AS (SELECT f.peer1, r.recommendedpeer  FROM friends f, recommendations r
            WHERE f.peer2 = r.peer AND f.peer1 <> r.recommendedpeer ORDER BY 1, 2),
        rec_amount AS (SELECT peer1, recommendedpeer, COUNT(recommendedpeer) amount  FROM friends_reccomendations fr
            GROUP BY peer1, recommendedpeer)
        SELECT peer1, recommendedpeer FROM rec_amount r1 WHERE amount = (SELECT max(amount) FROM rec_amount r2
            WHERE r1.peer1 = r2.peer1);
    end;
    $proc_recommendations$;

-- BEGIN;
-- CALL proc_recommendations('1');
-- FETCH ALL IN "1";
-- end;


--9) Determine the percentage of peers who:
DROP PROCEDURE IF EXISTS proc_blocks_started(c refcursor, block1 varchar, block2 varchar);
CREATE OR REPLACE PROCEDURE proc_blocks_started(IN c refcursor, block1 varchar, block2 varchar)
LANGUAGE plpgsql AS $proc_blocks_started$
    DECLARE n int := (SELECT CASE WHEN (SELECT COUNT(*) FROM peers) = 0 THEN 1 ELSE COUNT(*) END FROM peers);
    BEGIN
        OPEN c FOR
        WITH blocks_from_checks AS (SELECT peer, substring(task FROM '\D*') block FROM checks),
             block1_started AS (SELECT DISTINCT peer FROM blocks_from_checks WHERE block = block1),
             block2_started AS (SELECT DISTINCT peer FROM blocks_from_checks WHERE block = block2),
             both_blocks AS (SELECT DISTINCT peer FROM blocks_from_checks
             WHERE peer IN (SELECT * FROM block1_started) AND peer IN (SELECT * FROM block2_started)),
             no_blocks AS (SELECT DISTINCT peer FROM blocks_from_checks
             WHERE peer NOT IN (SELECT * FROM block1_started) AND peer NOT IN (SELECT * FROM block2_started) AND peer NOT IN (SELECT * FROM both_blocks))
        SELECT (SELECT COUNT(*)::numeric FROM block1_started) / n * 100 AS StartedBlock1, (SELECT COUNT(*)::numeric FROM block2_started) / n * 100  AS StartedBlock2,
               (SELECT COUNT(*)::numeric FROM both_blocks) / n * 100  AS StartedBothBlocks, (SELECT COUNT(*)::numeric FROM no_blocks) / n * 100  AS DidntStartAnyBlock;
    end;
    $proc_blocks_started$;
-- BEGIN;
-- CALL proc_blocks_started('1', 'C', 'C');
-- FETCH ALL IN "1";
-- end;

--10) Determine the percentage of peers who have ever successfully passed a check on their birthday
DROP PROCEDURE IF EXISTS proc_success_on_birthday(c refcursor);
CREATE OR REPLACE PROCEDURE proc_success_on_birthday(IN c refcursor)
LANGUAGE plpgsql AS $proc_success_on_birthday$
--     DECLARE n numeric = (SELECT COUNT(*) n FROM peers p);
    BEGIN
        OPEN c for
        WITH birthday_checks AS (SELECT p.nickname, p.birthday, c.id, (to_char(p.birthday, 'mon DD')) day_of_birth,
                                        (to_char(c.date, 'mon DD')) day_of_check
        FROM peers p, checks c WHERE p.nickname = c.peer),
        successfull_checks AS (SELECT nickname FROM birthday_checks, p2p
            WHERE day_of_birth = day_of_check AND p2p."Check" = birthday_checks.id AND p2p.state = 'Success'),
        fail_checks AS (SELECT nickname FROM birthday_checks, p2p WHERE day_of_birth = day_of_check
                                                    AND p2p."Check" = birthday_checks.id AND p2p.state = 'Failure'),
        amount_of_peers AS (SELECT (SELECT COUNT(*) FROM successfull_checks s) + (SELECT COUNT(*) FROM fail_checks f) AS n),
        s_amount AS (SELECT (CASE WHEN amount_of_peers.n = 0 THEN 0
            ELSE ((SELECT COUNT(*) FROM successfull_checks)) / (SELECT a.n FROM amount_of_peers a) * 100 END) AS percent
        FROM amount_of_peers, successfull_checks),
        f_amount AS (SELECT (CASE WHEN amount_of_peers.n = 0 THEN 0
            ELSE ((SELECT COUNT(*) FROM fail_checks) / (SELECT a.n FROM amount_of_peers a) * 100) END) AS percent
        FROM amount_of_peers, fail_checks)
        SELECT COALESCE(s_amount.percent, '0') "SuccessfulChecks", COALESCE(f_amount.percent, '0') "UnsuccessfulChecks"
        FROM f_amount
        FULL JOIN s_amount ON true AND false;
    end;
    $proc_success_on_birthday$;
--
-- UPDATE peers SET birthday = '1990-04-05' WHERE nickname = 'peer7';

-- BEGIN;
-- CALL proc_success_on_birthday('1');
-- FETCH ALL IN "1";
-- end;

--11) Determine all peers who did the given tasks 1 and 2, but did not do task 3

CREATE OR REPLACE PROCEDURE proc_first_two_not_three(IN c refcursor, task1 varchar, task2 varchar, task3 varchar)
AS $proc_first_two_not_three$
    BEGIN
        open c for
        WITH task1_succeed AS (SELECT DISTINCT checks.peer FROM checks, xp, tasks WHERE checks.id = xp."Check"
                                                                    AND checks.task = task1),
             task2_succeed AS (SELECT DISTINCT checks.peer FROM checks, xp, tasks WHERE checks.id = xp."Check"
                                                                    AND checks.task = task2),
             task3__fail AS (SELECT DISTINCT checks.peer FROM checks, xp, tasks WHERE checks.id NOT IN (SELECT "Check" FROM xp)
                 AND checks.task = task3),
             all_tasks AS (SELECT DISTINCT peer FROM checks WHERE peer NOT IN (SELECT peer FROM checks WHERE checks.task = task3))
        SELECT peer FROM task1_succeed
        INTERSECT
        SELECT peer FROM task2_succeed
        INTERSECT
        SELECT peer FROM all_tasks
        EXCEPT
        SELECT peer FROM task3__fail ORDER BY peer ASC;
    end;
    $proc_first_two_not_three$ LANGUAGE plpgsql;

-- UPDATE p2p SET state = 'Failure' WHERE id = 37;

-- BEGIN;
-- CALL proc_first_two_not_three('1', 'C3_s21_string+', 'C3_s21_string+', 'C4_s21_math');
-- FETCH ALL IN "1";
-- end;

--12) Using recursive common table expression, output the number of preceding tasks for each task

DROP FUNCTION IF EXISTS fnc_count_parent_projects();
CREATE OR REPLACE FUNCTION fnc_count_parent_projects()
RETURNS table (Task varchar, PrevCount int)
AS $fnc_count_parent_projects$
    BEGIN
        return query
        WITH recursive parent_projects AS (
            SELECT title, parenttask AS current_task, (CASE WHEN parenttask IS NULL THEN 0 ELSE 1 END) amount FROM tasks
            UNION
            SELECT t.title, t.parenttask AS current_task, (CASE WHEN t.parenttask IS NULL THEN 0 ELSE amount + 1 END)
                AS amount FROM tasks t
            JOIN parent_projects pp ON pp.title = t.parenttask
    )
        SELECT title, MAX(amount) FROM parent_projects GROUP BY title;
    end;
    $fnc_count_parent_projects$ LANGUAGE plpgsql;

-- SELECT * FROM fnc_count_parent_projects();

--13) Find "lucky" days for checks. A day is considered "lucky" if it has at least N consecutive successful checks
DROP PROCEDURE IF EXISTS proc_lucky_days(c refcursor, N int);
CREATE OR REPLACE PROCEDURE proc_lucky_days(IN c refcursor, N int)
LANGUAGE plpgsql AS $proc_lucky_days$
    BEGIN
        OPEN c for
            WITH  all_checks AS (
                SELECT c.id, c.date, p2p.time, p2p.state, xp.xpamount FROM checks c, p2p, xp
                WHERE c.id = p2p."Check" AND (p2p.state = 'Success' OR p2p.state = 'Failure')
                AND c.id = xp."Check" AND xpamount >= (SELECT tasks.maxxp FROM tasks WHERE tasks.title = c.task) * 0.8
                ORDER BY c.date, p2p.time),
             amount_of_succesful_checks_in_a_row AS (
                 SELECT id, date, time, state,
                (CASE WHEN state = 'Success' THEN row_number() over (partition by state, date) ELSE 0 END) AS amount
                                                     FROM all_checks ORDER BY date
             ),
             max_in_day AS (SELECT a.date, MAX(amount) amount FROM amount_of_succesful_checks_in_a_row a GROUP BY date),
             max_in_day_of_week AS (SELECT to_char(m.date, 'day') AS dow, sum(amount) s_amount FROM max_in_day m
                                                                                               GROUP BY dow)
             SELECT dow FROM max_in_day_of_week WHERE s_amount >= N;
    end;
    $proc_lucky_days$;
-- BEGIN;
-- CALL proc_lucky_days('1', 3);
-- FETCH ALL IN "1";
-- end;


--14) Find the peer with the highest amount of XP

DROP FUNCTION IF EXISTS fnc_find_biggest_xp_peer();
CREATE OR REPLACE FUNCTION fnc_find_biggest_xp_peer()
RETURNS TABLE (Peer varchar, XP bigint)
AS $$
    BEGIN
    return query
    WITH succesful_projects AS
    (
        SELECT checks.peer, checks.id , checks.task FROM checks
        JOIN xp ON checks.id = xp."Check"

    ),
        xp_amount AS (SELECT s.peer, xp.xpamount, s.task, s.id FROM succesful_projects s, xp WHERE s.id = xp."Check"),
        sum_xp AS (SELECT x.peer, SUM(x.xpamount) AS xp FROM xp_amount x GROUP BY x.peer ORDER BY xp DESC)
    SELECT * FROM sum_xp WHERE sum_xp.xp = (SELECT MAX(sum_xp.xp) FROM sum_xp);
    end;
$$ LANGUAGE plpgsql;

-- SELECT* FROM fnc_find_biggest_xp_peer();

--15) Determine the peers that came before the given time at least N times during the whole time

CREATE OR REPLACE PROCEDURE proc_find_entrance_before_time(IN c refcursor, t time, number int)
LANGUAGE plpgsql AS $proc_find_entrance_before_time$
    BEGIN
        open c for
        WITH entrance_times AS (SELECT DISTINCT tt.peer, tt.date EarlyEntries FROM timetracking tt WHERE state = 1 AND time < t),
             count_entries AS (SELECT et.peer, COUNT(et.peer) EarlyEntries FROM entrance_times et GROUP BY et.peer)
        SELECT * FROM count_entries WHERE EarlyEntries >= number;
    end;
    $proc_find_entrance_before_time$;

-- INSERT INTO timetracking VALUES (17, 'peer1', '2023-05-27', '9:00:00', 1);

-- BEGIN;
-- CALL proc_find_entrance_before_time('1', '22:00:00', 2);
-- FETCH ALL IN "1";
-- CLOSE "1";
-- END;

--16) Determine the peers who left the campus more than M times during the last N days
DROP PROCEDURE IF EXISTS proc_find_exits_last_days(IN c refcursor, N int, M int);
CREATE OR REPLACE PROCEDURE proc_find_exits_last_days(IN c refcursor, N int, M int)
LANGUAGE plpgsql
AS $proc_find_entrance_last_days$
    DECLARE date_start date := now()::date - N;
    BEGIN
        open c for
        WITH exits AS (
            SELECT tt.peer, COUNT(tt.date) exits FROM timetracking tt
            WHERE state = '2' AND tt.date BETWEEN date_start AND now()::date
            GROUP BY tt.peer
        )
        SELECT e.peer  FROM exits e WHERE e.exits >= M;
    end;
$proc_find_entrance_last_days$;

-- INSERT INTO timetracking VALUES (21, 'peer2', '2023-05-27', '13:00:00', 1);
-- INSERT INTO timetracking VALUES (22, 'peer2', '2023-05-27', '14:00:00', 2);

-- BEGIN;
-- CALL proc_find_exits_last_days('1', 360, 2);
-- FETCH ALL IN "1";
-- CLOSE "1";
-- END;

--17) Determine for each month the percentage of early entries

DROP FUNCTION IF EXISTS fnc_count_early_entries_percent();
CREATE OR REPLACE FUNCTION fnc_count_early_entries_percent()
RETURNS table (Month varchar, EarlyEntries numeric(5, 1))
AS $fnc_count_early_entries_percent$
    BEGIN
        return query
        WITH entries AS (
            SELECT tt.peer, tt.time, (to_char(tt.date, 'month')) AS entrance_date,
                   (to_char(p.birthday, 'month')) AS birthday FROM timetracking tt
            JOIN peers p on p.nickname = tt.peer
            WHERE tt.state = 1
            ),
         number_of_entries AS (
             SELECT e.peer, e.time, e.entrance_date FROM entries e
             WHERE e.entrance_date = e.birthday
             ),
         total_number_of_entries AS (
             SELECT DISTINCT e.peer, e.entrance_date, COUNT(e.entrance_date) entries FROM entries e
             WHERE e.entrance_date = e.birthday GROUP BY e.peer, e.entrance_date
             ),
         number_of_early_entries AS (SELECT t.entries, substring(t.entrance_date from '\D*') AS month
             FROM total_number_of_entries t, number_of_entries n
                 WHERE n.time < '12:00:00' AND n.entrance_date = t.entrance_date AND n.peer = t.peer GROUP BY t.entrance_date, t.entries),
         months AS (SELECT TRIM(to_char(generate_series('2023-01-01'::date, '2023-12-01'::date, '1 month'), 'month')) AS month, 0 AS entries),
        result AS (
            SELECT TRIM(t.month::varchar) AS month,
            (t.entries::numeric / (SELECT SUM(t.entries) FROM total_number_of_entries t) * 100) AS entries
            FROM number_of_early_entries t
            GROUP BY t.entries, t.month
            UNION ALL
            SELECT m.month::varchar, 0 FROM months m, number_of_early_entries n)
        SELECT r.month::varchar, (SUM(r.entries))::numeric(5,1) FROM result r GROUP BY r.month
            ORDER BY concat('2023-'::varchar, r.month::varchar,'-01'::varchar)::date;
    end;
    $fnc_count_early_entries_percent$ LANGUAGE plpgsql;

-- SELECT * FROM fnc_count_early_entries_percent();
--
-- UPDATE timetracking SET time = '08:00:00' WHERE id = 1;
-- INSERT INTO timetracking VALUES (23, 'peer1', '2023-01-01', '08:00:00', 1);
-- UPDATE timetracking SET date = '2023-04-05' WHERE id = 13 OR id = 14;
-- UPDATE timetracking SET time = '08:00:00' WHERE id = 13;


