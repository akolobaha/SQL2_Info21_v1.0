CREATE TABLE del_table_1 (
    col1 text,
    col2 text,
    col3 text
);

CREATE TABLE del_table_2 (
    col1 text,
    col2 text,
    col3 text
);
CREATE TABLE table_del_1 (
    col1 text,
    col2 text,
    col3 text
);

DROP PROCEDURE IF EXISTS remove_table CASCADE;

CREATE OR REPLACE PROCEDURE remove_table(IN tablename text) AS $$
    BEGIN
        FOR tablename IN (SELECT table_name
                       FROM information_schema.tables
                       WHERE table_name LIKE concat(tablename,'%') AND table_schema = 'public')
            LOOP
                EXECUTE  concat('DROP TABLE ', tablename);
            END LOOP;
    END;
$$ LANGUAGE plpgsql;

-- CALL remove_table('del');

CREATE OR REPLACE PROCEDURE count_table(OUT count_tables int) AS $$
    BEGIN
        WITH get_params AS (SELECT r.routine_name AS function,
                        concat('(', p.parameter_mode, ' ', p.parameter_name, ' ', p.data_type, ')') AS params
                   FROM information_schema.routines AS r
                   JOIN information_schema.parameters AS p ON r.specific_name = p.specific_name
                   WHERE r.routine_type = 'FUNCTION' AND r.specific_schema = 'public' AND
                         p.specific_schema = 'public' AND parameter_name IS NOT NULL),
             f_concat AS (SELECT concat(function, ' ', string_agg(params, ','))
                          FROM get_params
                          GROUP BY function)
        SELECT COUNT(*) INTO count_tables
        FROM f_concat;
    END;
$$ LANGUAGE plpgsql;

--CALL count_table(NULL);

CREATE OR REPLACE PROCEDURE del_sql_dml_triggers(OUT count_del int) AS $$
    DECLARE tg_name text;
            table_name text;
    BEGIN
        SELECT COUNT(DISTINCT trigger_name) INTO count_del
        FROM information_schema.triggers
        WHERE trigger_schema = 'public';

        FOR tg_name, table_name IN (SELECT DISTINCT trigger_name, event_object_table
                         FROM information_schema.triggers
                         WHERE trigger_schema = 'public')
            LOOP
                EXECUTE concat('DROP TRIGGER ', tg_name, ' ON ', table_name);
            END LOOP;
    END;
$$ LANGUAGE plpgsql;

-- CALL del_sql_dml_triggers(NULL);

CREATE OR REPLACE PROCEDURE info(IN name text, IN ref refcursor) AS $$
    BEGIN
        OPEN ref FOR
            SELECT routine_name AS name, routine_type AS type
            FROM information_schema.routines
            WHERE specific_schema = 'public' AND routine_definition LIKE concat('%', name, '%');
    END;
$$ LANGUAGE plpgsql;

-- BEGIN;
-- CALL info('peers', 'ref');
-- FETCH ALL IN "ref";
-- END;
