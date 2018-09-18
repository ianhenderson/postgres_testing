/**
 * Clear out schema/tables.
 */

DROP SCHEMA IF EXISTS kst CASCADE ;
CREATE SCHEMA IF NOT EXISTS kst;

/**
 * Add extensions.
 */
CREATE EXTENSION IF NOT EXISTS pgcrypto ;

/**
 * Create relations.
 */
CREATE TABLE IF NOT EXISTS kst.users (
	id SERIAL PRIMARY KEY,
	username text UNIQUE NOT NULL,
	password_hash text NOT NULL
) ;
CREATE TABLE IF NOT EXISTS kst.kanji (
	id SERIAL PRIMARY KEY,
	kanji text UNIQUE
) ;
CREATE TABLE IF NOT EXISTS kst.words (
	id SERIAL PRIMARY KEY,
	word text UNIQUE
) ;
CREATE TABLE IF NOT EXISTS kst.kanji_words (
	kanji_id integer REFERENCES kst.kanji,
	word_id integer REFERENCES kst.words,
	PRIMARY KEY (kanji_id, word_id)
) ;
CREATE TABLE IF NOT EXISTS kst.study_queue (
	id SERIAL PRIMARY KEY,
	user_id integer REFERENCES kst.users,
	kanji_id integer REFERENCES kst.kanji,
	seen boolean DEFAULT FALSE
) ;

/**
 * Helper functions.
 */
CREATE OR REPLACE FUNCTION kst.kst_kanji_filter(str text) RETURNS SETOF text AS $$
	SELECT unnest( regexp_matches(str, '[\u4e00-\u9faf]', 'g') );
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION kst.kst_word_insert_v2(str text, user_id integer) RETURNS VOID AS $$
	-- filter sentence -> kanji only
	WITH chars AS (
		SELECT DISTINCT char FROM kst.kst_kanji_filter(str) AS char
	),
	-- upsert kanji into kanji table
	char_ids AS (
		INSERT INTO kst.kanji (kanji)
		SELECT char FROM chars
		ON CONFLICT (kanji)
		DO UPDATE SET kanji = EXCLUDED.kanji
		RETURNING id
	),
	-- upsert word into words table
	word_ids AS (
		INSERT INTO kst.words (word)
		VALUES (str)
		ON CONFLICT (word)
		DO UPDATE SET word = EXCLUDED.word
		RETURNING id
	),
	-- insert kanji into study_queue
	study_queue_ids AS (
		INSERT INTO kst.study_queue (user_id, kanji_id)
		SELECT user_id, char_ids.id FROM char_ids
	)
	-- insert ids for word <-> kanji(s) relation into kanji_words table
	INSERT INTO kst.kanji_words (kanji_id, word_id)
	SELECT char_ids.id, word_ids.id FROM char_ids, word_ids
	ON CONFLICT DO NOTHING
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION kst.kst_word_insert(str text, user_id integer) RETURNS VOID AS $$
	-- filter sentence -> kanji only
	WITH chars AS (
		SELECT DISTINCT char FROM kst.kst_kanji_filter(str) AS char
	),
	-- insert kanji into kanji table
	ins_k AS (
		INSERT INTO kst.kanji (kanji)
		SELECT char FROM chars
		WHERE NOT EXISTS (
			SELECT kanji from kst.kanji WHERE kanji = char
		)
		RETURNING id, kanji
	),
	-- all kanji_ids (current + inserted above) matching filtered chars
	char_ids AS (
		SELECT kanji.id, kanji.kanji FROM kst.kanji, chars
		WHERE kanji.kanji = chars.char
		UNION DISTINCT SELECT id, kanji FROM ins_k
	),
	-- insert word into words table
	ins_w AS (
		INSERT INTO kst.words (word)
		VALUES (str)
		ON CONFLICT (word)
		DO UPDATE SET word = EXCLUDED.word
		RETURNING id
	),
	-- get user_id
	users AS (
		SELECT * from kst.users
		WHERE id = user_id
	),
	-- insert kanji into study_queue
	study_queue_ids AS (
		INSERT INTO kst.study_queue (user_id, kanji_id)
		SELECT users.id, char_ids.id FROM char_ids, users
	)
	-- insert ids for word <-> kanji(s) relation into kanji_words table
	INSERT INTO kst.kanji_words (kanji_id, word_id)
	SELECT char_ids.id, ins_w.id FROM char_ids, ins_w
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION kst.kst_user_add(new_username text, password text) RETURNS record AS $$
	INSERT INTO kst.users (username, password_hash)
	VALUES ( new_username, crypt(password, gen_salt('bf', 12)) )
	RETURNING *
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION kst.kst_user_check(name text, password text) RETURNS SETOF record AS $$
	SELECT * FROM kst.users
		WHERE users.username = name
		AND users.password_hash = ( crypt(password, users.password_hash) )
$$ LANGUAGE SQL;

-- v2 Functions
CREATE OR REPLACE FUNCTION kst.kst_user_get_next_row_to_study_v2(userid integer) RETURNS table(queue_id integer, total_unseen bigint, next_char text, rel_words text[]) AS $$
	WITH next_study_row AS (
		SELECT * FROM kst.study_queue sq
			WHERE (sq.user_id = userid)
			AND (sq.seen = false)
			ORDER BY sq.id
			LIMIT 1
	),
	total_unseen AS (
		SELECT count(*) FROM kst.study_queue sq
			WHERE (sq.user_id = userid)
			AND (sq.seen = false)
	)
	SELECT
		nsr.id as queue_id,
		tu.count as total_unseen,
		k.kanji as next_char,
		array_agg(DISTINCT w.word) as rel_words
	FROM
		kst.users u,
		kst.kanji k,
		kst.words w,
		kst.kanji_words kw,
		total_unseen tu,
		next_study_row nsr
	WHERE (u.id = userid)
	AND (k.id = nsr.kanji_id)
	AND (kw.kanji_id = k.id)
	AND (kw.word_id = w.id)
	GROUP BY next_char, queue_id, total_unseen;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION kst.kst_queue_markdone(queue_id integer) RETURNS SETOF record AS $$
	UPDATE kst.study_queue sq
	SET seen = true
	WHERE (sq.id = queue_id)
	RETURNING *
$$ LANGUAGE SQL;


/**
 * Dummy data.
 */

-- EXPLAIN ANALYZE
select kst.kst_user_add('ian', 'ian');
-- EXPLAIN ANALYZE
-- select kst.kst_user_add('ian', 'ian');
-- EXPLAIN ANALYZE
-- select kst.kst_user_check('ian', 'ian');
-- select kst.kst_user_check('ian', 'ian');
-- select kst.kst_user_check('ian', 'ian');
-- select kst.kst_user_check('ian', 'ian');
-- select kst.kst_user_check('ian', 'ian');
-- select kst.kst_user_check('in', 'ia');
-- insert into kanji (kanji) values ('日'),('本'), ('悠');

-- EXPLAIN ANALYZE
-- select kst.kst_word_insert('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- EXPLAIN ANALYZE
-- select kst.kst_kanji_filter('長崎は９日、７２回目の「原爆の日」を迎え、早朝から祈りに包まれた。長崎市の平和公園では平和祈念式典が開かれ、被爆者や遺族ら約５４００人が出席した。田上富久市長は平和宣言で、７月に国連で採択された核兵器禁止条約の交渉会議に参加しなかった日本政府の姿勢を「被爆地は到底理解できない」と厳しく非難し、条約を批准するよう迫った。一方、安倍晋三首相は６日の広島市での平和記念式典でのあいさつと同様、条約に言及しなかった。');
-- select kst.kst_word_insert('日本語が大好きです');
-- select kst.kst_word_insert('日本日本');
-- select kst.kst_word_insert('本日');
-- select kst.kst_word_insert('本屋さん');
-- select kst.kst_word_insert('大嫌い');



select kst.kst_word_insert('本校', 1);
select kst.kst_word_insert('日本語', 1);
select kst.kst_word_insert('日曜日', 1);
select kst.kst_word_insert('朝日麦酒', 1);
select kst.kst_word_insert('犬が大好き', 1);
select kst.kst_word_insert('パソコン', 1);

-- select kst.kst_kanji_get_related_words_for('本');
-- EXPLAIN ANALYZE
-- select kst.kst_kanji_get_related_words_for('日');
-- select kst.kst_kanji_get_related_words_for('嫌');

table kst.users;
table kst.kanji;
table kst.words;
table kst.kanji_words;
table kst.study_queue;
