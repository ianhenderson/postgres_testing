/**
 * Clear out tables.
 */

DROP TABLE IF EXISTS users CASCADE ;
DROP TABLE IF EXISTS kanji CASCADE ;
DROP TABLE IF EXISTS words CASCADE ;
DROP TABLE IF EXISTS kanji_words CASCADE ;
DROP TABLE IF EXISTS seen_words CASCADE ;
DROP TABLE IF EXISTS seen_kanji CASCADE ;
DROP TABLE IF EXISTS study_queue CASCADE ;

/**
 * Add extensions.
 */
CREATE EXTENSION IF NOT EXISTS pgcrypto ;

/**
 * Create relations.
 */
CREATE TABLE IF NOT EXISTS users (
	id SERIAL PRIMARY KEY,
	username text UNIQUE NOT NULL,
	password_hash text NOT NULL
) ;
CREATE TABLE IF NOT EXISTS kanji (
	id SERIAL PRIMARY KEY,
	kanji text UNIQUE
) ;
CREATE TABLE IF NOT EXISTS words (
	id SERIAL PRIMARY KEY,
	word text UNIQUE
) ;
CREATE TABLE IF NOT EXISTS kanji_words (
	id SERIAL PRIMARY KEY,
	kanji_id integer REFERENCES kanji,
	word_id integer REFERENCES words
) ;
CREATE TABLE IF NOT EXISTS seen_words (
	id SERIAL PRIMARY KEY,
	word_id integer REFERENCES words
) ;
CREATE TABLE IF NOT EXISTS seen_kanji (
	id SERIAL PRIMARY KEY,
	kanji_id integer REFERENCES kanji
) ;
CREATE TABLE IF NOT EXISTS study_queue (
	id SERIAL PRIMARY KEY,
	user_id integer REFERENCES users,
	kanji_id integer REFERENCES kanji,
	seen boolean DEFAULT FALSE
) ;

/**
 * Helper functions.
 */
DROP FUNCTION IF EXISTS kst_kanji_filter(text) ;
CREATE OR REPLACE FUNCTION kst_kanji_filter(str text) RETURNS SETOF text AS $$
	SELECT unnest( regexp_matches(str, '[\u4e00-\u9faf]', 'g') );
$$ LANGUAGE SQL;


DROP FUNCTION IF EXISTS kst_kanji_insert(str text, username text) ;
DROP FUNCTION IF EXISTS kst_kanji_insert(str text, user_id integer) ;
CREATE OR REPLACE FUNCTION kst_kanji_insert(str text, user_id integer) RETURNS VOID AS $$
	-- filter sentence -> kanji only
	WITH chars AS (
		SELECT DISTINCT char FROM kst_kanji_filter(str) AS char
	),
	-- insert kanji into kanji table
	ins_k AS (
		INSERT INTO kanji (kanji)
		SELECT char FROM chars
		WHERE NOT EXISTS (
			SELECT kanji from kanji WHERE kanji = char
		)
		RETURNING id, kanji
	),
	-- all kanji_ids (current + inserted above) matching filtered chars
	char_ids AS (
		SELECT kanji.id, kanji.kanji FROM kanji, chars
		WHERE kanji.kanji = chars.char
		UNION DISTINCT SELECT id, kanji FROM ins_k
	),
	-- insert word into words table
	ins_w AS (
		INSERT INTO words (word)
		VALUES (str)
		ON CONFLICT (word)
		DO UPDATE SET word = EXCLUDED.word
		RETURNING id
	),
	-- get user_id
	users AS (
		SELECT * from users
		WHERE id = user_id
	),
	-- insert kanji into study_queue
	study_queue_ids AS (
		INSERT INTO study_queue (user_id, kanji_id)
		SELECT users.id, char_ids.id FROM char_ids, users
	)
	-- insert ids for word <-> kanji(s) relation into kanji_words table
	INSERT INTO kanji_words (kanji_id, word_id)
	SELECT char_ids.id, ins_w.id FROM char_ids, ins_w
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_kanji_get_related_words_for(text) ;
CREATE OR REPLACE FUNCTION kst_kanji_get_related_words_for(str text) RETURNS SETOF text AS $$
	SELECT words.word FROM words, kanji, kanji_words
		WHERE (kanji.kanji = str)
		AND (kanji_words.kanji_id = kanji.id)
		AND (kanji_words.word_id = words.id);
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_get_next_row_to_study(integer) ;
CREATE OR REPLACE FUNCTION kst_user_get_next_row_to_study(userid integer) RETURNS table(id integer, kanji_id integer) AS $$
	SELECT sq.id, sq.kanji_id FROM study_queue sq
		WHERE (sq.user_id = userid)
		AND (sq.seen = false)
		ORDER BY sq.id
		LIMIT 1;
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_get_next_char_to_study(integer) ;
CREATE OR REPLACE FUNCTION kst_user_get_next_char_to_study(userid integer) RETURNS text AS $$
	SELECT k.kanji from kanji k
		WHERE k.id = ( SELECT id from kst_user_get_next_row_to_study(userid) )
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_mark_next_as_done(integer) ;
CREATE OR REPLACE FUNCTION kst_user_mark_next_as_done(userid integer) RETURNS SETOF record AS $$
	UPDATE study_queue
	SET seen = true
	WHERE id IN ( SELECT id from kst_user_get_next_row_to_study(userid) )
	RETURNING *
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_get_next_studyrow_full(integer) ;
CREATE OR REPLACE FUNCTION kst_user_get_next_studyrow_full(userid integer) RETURNS table(next_char text, rel_words text[]) AS $$
	SELECT next_char, array_agg(words) AS words 
	FROM kst_user_get_next_char_to_study(userid) next_char, 
	LATERAL kst_kanji_get_related_words_for(next_char) words 
	GROUP BY next_char
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_add(new_username text, password text) ;
CREATE OR REPLACE FUNCTION kst_user_add(new_username text, password text) RETURNS record AS $$
	INSERT INTO users (username, password_hash)
	VALUES ( new_username, crypt(password, gen_salt('bf', 12)) )
	RETURNING *
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS kst_user_check(name text, password text) ;
CREATE OR REPLACE FUNCTION kst_user_check(name text, password text) RETURNS SETOF record AS $$
	SELECT * FROM users
		WHERE users.username = name
		AND users.password_hash = ( crypt(password, users.password_hash) )
$$ LANGUAGE SQL;

/**
 * Dummy data.
 */

-- EXPLAIN ANALYZE
select kst_user_add('ian', 'ian');
-- EXPLAIN ANALYZE
-- select kst_user_add('ian', 'ian');
-- EXPLAIN ANALYZE
-- select kst_user_check('ian', 'ian');
-- select kst_user_check('ian', 'ian');
-- select kst_user_check('ian', 'ian');
-- select kst_user_check('ian', 'ian');
-- select kst_user_check('ian', 'ian');
-- select kst_user_check('in', 'ia');
-- insert into kanji (kanji) values ('日'),('本'), ('悠');

-- EXPLAIN ANALYZE
-- select kst_kanji_insert('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- EXPLAIN ANALYZE
-- select kst_kanji_filter('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- select kst_kanji_insert('日本語が大好きです');
-- select kst_kanji_insert('日本日本');
-- select kst_kanji_insert('本日');
-- select kst_kanji_insert('本屋さん');
-- select kst_kanji_insert('大嫌い');



select kst_kanji_insert('本校', 1);
select kst_kanji_insert('日本語', 1);
select kst_kanji_insert('日曜日', 1);
select kst_kanji_insert('朝日麦酒', 1);
select kst_kanji_insert('犬が大好き', 1);
select kst_kanji_insert('パソコン', 1);

-- select kst_kanji_get_related_words_for('本');
-- EXPLAIN ANALYZE
-- select kst_kanji_get_related_words_for('日');
-- select kst_kanji_get_related_words_for('嫌');

table users;
table kanji;
table words;
table kanji_words;
table study_queue;
