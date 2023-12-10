/*1) Написать процедуру добавления P2P проверки
Параметры: ник проверяемого, ник проверяющего, название задания, статус P2P проверки, время. 
*/

CREATE PROCEDURE add_peer_review
(checked_peer varchar, checking_peer varchar, task_name text, p2p_status check_status, p2p_time TIME)  AS $$
    BEGIN
        IF (p2p_status = 'Start') -- Если задан статус "начало", в качестве проверки указать только что добавленную запись
		THEN
            IF ((SELECT COUNT(*) FROM p2p
                JOIN checks 
				ON p2p."Check" = checks.id
                WHERE p2p.checkingpeer = checking_peer
                    AND checks.peer = checked_peer 
				 	AND checks.task = task_name) = 0) 
			THEN
				INSERT INTO checks -- добавить запись в таблицу Checks (в качестве даты использовать сегодняшнюю)
                VALUES ((SELECT MAX(id) FROM checks) + 1, checked_peer, task_name, NOW());

                INSERT INTO p2p -- добавить запись в таблицу P2P 
                VALUES ((SELECT MAX(id) FROM p2p) + 1, (SELECT MAX(id) FROM checks), checking_peer, p2p_status, p2p_time);
             
            ELSE
                RAISE EXCEPTION 'Ошибка: Проверка не завершена';
            END IF;
			
        ELSE -- иначе указать проверку с незавершенным P2P этапом
            INSERT INTO p2p
            VALUES ((SELECT MAX(id) FROM p2p) + 1,
                    (SELECT "Check" FROM p2p
                     JOIN checks 
					 ON p2p."Check" = checks.id
                     WHERE p2p.checkingpeer = checking_peer 
					 	AND checks.peer = checked_peer
					 	AND checks.task = task_name),
                    checking_peer, p2p_status, p2p_time);
        END IF;
    END;
 $$ LANGUAGE plpgsql; -- процедурный язык PL/pgSQL (добавляет сложные функции условного вычисления)

-- Удаление процедуры и добавленных строк
/*
DELETE FROM p2p WHERE id = (SELECT MAX(id) FROM p2p);
DELETE FROM checks WHERE id = (SELECT MAX(id) FROM checks);
DROP PROCEDURE IF EXISTS add_peer_review CASCADE;
*/

-- Тест 1, ожидается добавление записей в таблицы checks, p2p
-- Корректный ввод
/*
CALL add_peer_review('peer1', 'peer2', 'C5_s21_decimal', 'Start'::check_status, '10:11:00');
SELECT * FROM checks;
SELECT * FROM p2p;
*/

-- Тест 2, ожидается 'Ошибка: Проверка не завершена'
-- Попытка добавления записи, при имеющейся незавершенной проверкe проекта "C5_s21_decimal" у пары пиров
/*
CALL add_peer_review ('peer8', 'peer10', 'C5_s21_decimal', 'Start'::check_status, '10:11:00');
*/

-- Тест 3, ожидается добавление записей в таблицы p2p
-- Добавление записей для случая, когда у проверяющего имеется незакрытая проверка
/*
CALL add_peer_review('peer3', 'peer10', 'C5_s21_decimal', 'Start'::check_status, '10:11:00');
*/

-- Тест 4, ожидается ERROR
-- Попытка добавления неверной записи
/*
CALL add_peer_review('peer2', 'peer10', 'C5_s21_decimal', 'Failure'::check_status, '10:11:00');
*/

/*2) Написать процедуру добавления проверки Verter'ом
Параметры: ник проверяемого, название задания, статус проверки Verter'ом, время. 
Добавить запись в таблицу Verter (в качестве проверки указать проверку соответствующего задания с самым поздним (по времени) успешным P2P этапом)
*/

CREATE PROCEDURE add_verter_review(checked_peer varchar, task_name text, verter_status check_status,
								   verter_time time) AS $$
    BEGIN
        IF (verter_status = 'Start') THEN
                IF ((SELECT MAX(p2p.time) FROM p2p -- проверка задания с самым поздним (по времени) успешным P2P этапом
                    JOIN checks 
					ON p2p."Check" = checks.id
                    WHERE checks.peer = checked_peer 
					 	AND checks.task = task_name
                        AND p2p.state = 'Success') IS NOT NULL ) 
						THEN

                    INSERT INTO verter -- добавить запись в таблицу Verter 
                    VALUES ((SELECT MAX(id) FROM verter) + 1,
                            (SELECT DISTINCT checks.id FROM p2p
                             JOIN checks 
							 ON p2p."Check" = checks.id
                             WHERE checks.peer = checked_peer 
							 	AND p2p.state = 'Success'
                                AND checks.task = task_name),
                            verter_status, verter_time);
            ELSE
                RAISE EXCEPTION 'P2P-проверка не завершена или имеет статус Failure';
            END IF;
        ELSE
            INSERT INTO verter
            VALUES ((SELECT MAX(id) FROM verter) + 1,
                    (SELECT "Check" FROM verter
                     GROUP BY "Check" HAVING COUNT(*) % 2 = 1), verter_status, verter_time);
        END IF;
    END;
$$ LANGUAGE plpgsql;


-- Удаление процедуры и добавленных строк
/*
DROP PROCEDURE add_verter_review CASCADE;
DELETE FROM verter WHERE id = (SELECT MAX(id) FROM verter);
*/

-- Тест 1, ожидается добавление записей в таблицу verter
-- Корректный ввод
/*
CALL add_verter_review('peer2', 'C4_s21_math', 'Start', '10:11:00');
SELECT * FROM verter;
*/

-- Тест 2, ожидается 'P2P-проверка не завершена или имеет статус Failure'
-- Попытка добавления записи при условии, что p2p проверка еще не завершена
/*
CALL add_verter_review('peer8', 'C5_s21_decimal', 'Start', '10:11:00');
*/

-- Тест 3, ожидается 'P2P-проверка не завершена или имеет статус Failure'
-- Попытка добавления записи при условии, что нет успешных p2p проверок 
/*
CALL add_verter_review('peer7', 'C4_s21_math', 'Start', '10:11:00');
*/


/*3) Написать триггер: после добавления записи со статутом "начало" в таблицу P2P, 
изменить соответствующую запись в таблице TransferredPoints
*/

CREATE OR REPLACE FUNCTION fnc_trg_update_transferredpoints() RETURNS TRIGGER AS $trg_update_transferredpoints$
	DECLARE t2 varchar = ((
               SELECT checks.peer
			   FROM p2p
               JOIN checks 
			   ON p2p."Check" = checks.id
			   WHERE checks.id = NEW."Check"
           )
			UNION
			(
               SELECT checks.peer 
			   FROM p2p
               JOIN checks 
			   ON p2p."Check" = checks.id
			   WHERE checks.id = NEW."Check"
           ));
    BEGIN
       IF (NEW.state = 'Start') -- после добавления записи со статутом "начало"
	   THEN
           WITH t1 AS (
               SELECT checks.peer AS peer 
			   FROM p2p
               JOIN checks 
			   ON p2p."Check" = checks.id
			   AND NEW."Check" = checks.id
           )
           UPDATE transferredpoints -- изменить существующую запись в таблице TransferredPoints
           SET pointsamount = pointsamount + 1
           FROM t1
           WHERE  transferredpoints.checkedpeer = t1.peer
		   AND  transferredpoints.checkingpeer = NEW.checkingpeer;
       END IF;
	   IF ((SELECT COUNT(*)
		  FROM transferredpoints
		  WHERE checkedpeer = t2
		  AND checkingpeer = NEW.checkingpeer) = 0
		  AND NEW.state = 'Start')
		  THEN
		  INSERT INTO transferredpoints -- если такой пары пиров не существует, добавить новую запись
		  VALUES (DEFAULT, 
				  NEW.checkingpeer, 
				  t2,
				  '1');
       
	   END IF;
	   RETURN NULL;
    END;
$trg_update_transferredpoints$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_transferredpoints
AFTER INSERT ON P2P
    FOR EACH ROW EXECUTE FUNCTION fnc_trg_update_transferredpoints();
	
	
-- Удаление триггера и добавленных строк
/*
DROP FUNCTION IF EXISTS fnc_trg_update_transferredpoints() CASCADE;
DELETE FROM p2p WHERE id = (SELECT MAX(id) FROM p2p);
DELETE FROM transferredpoints WHERE id = (SELECT MAX(id) FROM transferredpoints);
*/

-- Тест 1, ожидается добавление 1 поинта в паре пиров peer8 - peer6 в таблице transferredpoints
-- Добавление записи со статутом "начало" в таблицу P2P с помощью INSERT
/*
INSERT INTO p2p
VALUES ((SELECT MAX(id) FROM p2p) + 1, 8, 'peer8', 'Start', '10:11:00');
*/

-- Тест 2, ожидается добавление новой строки в таблице transferredpoints с 1 поинтом в столбце pointamount
-- Добавление записи со статутом "начало" в таблицу P2P с помощью вызова add_peer_review
/*
CALL add_peer_review('peer6', 'peer7', 'C6_s21_matrix', 'Start', '10:11:00');
*/




/*4) Написать триггер: перед добавлением записи в таблицу XP, проверить корректность добавляемой записи
Запись считается корректной, если:

Количество XP не превышает максимальное доступное для проверяемой задачи
Поле Check ссылается на успешную проверку
Если запись не прошла проверку, не добавлять её в таблицу.*/


CREATE OR REPLACE FUNCTION fnc_check_before_insert_xp() RETURNS TRIGGER AS $trg_check_before_insert_xp$
    BEGIN
        IF ((SELECT maxxp FROM checks
            JOIN tasks 
			ON checks.task = tasks.title
            WHERE NEW."Check" = checks.id) < NEW.xpamount OR
            (SELECT state 
			 FROM p2p
             WHERE NEW."Check" = p2p."Check" AND p2p.state IN ('Success', 'Failure')) = 'Failure' OR
            (SELECT state 
			 FROM verter
             WHERE NEW."Check" = verter."Check" AND verter.state = 'Failure') = 'Failure') 
			 THEN
                RAISE EXCEPTION 'Результат проверки не успешен или некорректное количество xp';
        END IF;
    RETURN (NEW.id, NEW."Check", NEW.xpamount);
    END;
$trg_check_before_insert_xp$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_before_insert_xp
BEFORE INSERT ON XP
    FOR EACH ROW EXECUTE FUNCTION fnc_check_before_insert_xp();


-- Удаление триггера и добавленных строк
/*
DROP FUNCTION IF EXISTS fnc_check_before_insert_xp() CASCADE;
DELETE FROM xp WHERE id = (SELECT MAX(id) FROM xp);
*/

-- Тест 1, ожидается добавление записи в таблицу ХР т.к. проверки p2p и verter успешны
/*
INSERT INTO xp (id, "Check", xpamount)
VALUES (23, 13, 100);
*/

-- Тест 2, ожидается 'Результат проверки не успешен или некорректное количество xp' 
-- т.к. проверка р2р успешна, а проверкa verter нет
/*
INSERT INTO xp (id, "Check", xpamount)
VALUES (23, 19, 300);
*/

-- Тест 3, ожидается 'Результат проверки не успешен или некорректное количество xp' 
-- т.к. некорректное количество xp
/*
INSERT INTO xp (id, "Check", xpamount)
VALUES (24, 16, 1150)
*/
