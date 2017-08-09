CREATE OR REPLACE FUNCTION array_last(arr ANYARRAY) RETURNS ANYELEMENT AS $$
	SELECT arr[array_length(arr, 1)];
$$ LANGUAGE SQL;

-- CREATE OR REPLACE FUNCTION array_pop(tbl regclass) RETURNS ANYARRAY AS $$
-- 	SELECT vals AS out FROM tbl FOR UPDATE;
-- 	UPDATE tbl SET vals = vals[ 1 : array_length(vals, 1) - 1 ];
-- $$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION filter_kanji(str text) RETURNS text[] AS $$
	select regexp_matches(str, '[\u4e00-\u9faf]', 'g');
$$ LANGUAGE SQL;

