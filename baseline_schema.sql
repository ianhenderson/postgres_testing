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
DROP FUNCTION IF EXISTS filter_kanji(text) ;
CREATE OR REPLACE FUNCTION filter_kanji(str text) RETURNS SETOF text AS $$
	SELECT unnest( regexp_matches(str, '[\u4e00-\u9faf]', 'g') );
$$ LANGUAGE SQL;


DROP FUNCTION IF EXISTS insert_kanji(str text, username text) ;
CREATE OR REPLACE FUNCTION insert_kanji(str text, username text) RETURNS VOID AS $$
	-- filter sentence -> kanji only
	WITH chars AS (
		SELECT DISTINCT char FROM filter_kanji(str) AS char
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
		RETURNING id
	),
	-- get user_id
	users AS (
		SELECT * from users
		WHERE username = username
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

DROP FUNCTION IF EXISTS get_related_words_for_kanji(text) ;
CREATE OR REPLACE FUNCTION get_related_words_for_kanji(str text) RETURNS SETOF text AS $$
	SELECT words.word FROM words, kanji, kanji_words
		WHERE (kanji.kanji = str)
		AND (kanji_words.kanji_id = kanji.id)
		AND (kanji_words.word_id = words.id);
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS get_next_kanji_to_study(integer) ;
CREATE OR REPLACE FUNCTION get_next_kanji_to_study(userid integer) RETURNS table(id integer, kanji_id integer) AS $$
	SELECT sq.id, sq.kanji_id FROM study_queue sq
		WHERE (sq.user_id = userid)
		AND (sq.seen = false)
		ORDER BY sq.id
		LIMIT 1;
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS mark_next_kanji_to_study_done(integer) ;
CREATE OR REPLACE FUNCTION mark_next_kanji_to_study_done(userid integer) RETURNS SETOF record AS $$
	UPDATE study_queue
	SET seen = true
	WHERE id IN ( SELECT id from get_next_kanji_to_study(userid) )
	RETURNING *
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS add_new_user(new_username text, password text) ;
CREATE OR REPLACE FUNCTION add_new_user(new_username text, password text) RETURNS record AS $$
	INSERT INTO users (username, password_hash)
	VALUES ( new_username, crypt(password, gen_salt('bf', 12)) )
	RETURNING *
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS check_user(name text, password text) ;
CREATE OR REPLACE FUNCTION check_user(name text, password text) RETURNS SETOF record AS $$
	SELECT * FROM users
		WHERE users.username = name
		AND users.password_hash = ( crypt(password, users.password_hash) )
$$ LANGUAGE SQL;

/**
 * Dummy data.
 */

-- EXPLAIN ANALYZE
select add_new_user('ian', 'ian');
-- EXPLAIN ANALYZE
-- select add_new_user('ian', 'ian');
-- EXPLAIN ANALYZE
-- select check_user('ian', 'ian');
-- select check_user('ian', 'ian');
-- select check_user('ian', 'ian');
-- select check_user('ian', 'ian');
-- select check_user('ian', 'ian');
-- select check_user('in', 'ia');
-- insert into kanji (kanji) values ('日'),('本'), ('悠');

-- EXPLAIN ANALYZE
-- select insert_kanji('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- EXPLAIN ANALYZE
-- select filter_kanji('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- select insert_kanji('日本語が大好きです');
-- select insert_kanji('日本日本');
-- select insert_kanji('本日');
-- select insert_kanji('本屋さん');
-- select insert_kanji('大嫌い');



select insert_kanji('日本語', 'ian');
select insert_kanji('日曜日', 'ian');
select insert_kanji('朝日麦酒', 'ian');
-- select insert_kanji('犬が大好き', 'ian');
-- select insert_kanji('パソコン', 'ian');

-- select get_related_words_for_kanji('本');
-- EXPLAIN ANALYZE
-- select get_related_words_for_kanji('日');
-- select get_related_words_for_kanji('嫌');

select * from users;
select * from kanji;
select * from words;
select * from kanji_words;
select * from study_queue;
