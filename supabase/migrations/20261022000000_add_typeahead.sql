-- Fast, authenticated type-ahead and parameterized keyword search.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

CREATE INDEX IF NOT EXISTS sentence_embeddings_title_trgm_idx
ON public.sentence_embeddings
USING gin (title gin_trgm_ops);

CREATE INDEX IF NOT EXISTS sentence_embeddings_speaker_trgm_idx
ON public.sentence_embeddings
USING gin (speaker gin_trgm_ops)
WHERE speaker IS NOT NULL;

CREATE INDEX IF NOT EXISTS sentence_embeddings_text_trgm_idx
ON public.sentence_embeddings
USING gin (text gin_trgm_ops);

CREATE OR REPLACE FUNCTION public.search_talk_suggestions(
  search_term text,
  suggestion_count integer DEFAULT 8
)
RETURNS TABLE (
  title text,
  speaker text,
  url text,
  match_type text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  WITH params AS (
    SELECT
      trim(search_term) AS term,
      replace(
        replace(
          replace(trim(search_term), '\', '\\'),
          '%', '\%'
        ),
        '_', '\_'
      ) AS escaped_term,
      least(greatest(suggestion_count, 1), 20) AS result_limit
  ),
  ranked AS (
    SELECT DISTINCT
      se.title,
      se.speaker,
      se.url,
      CASE
        WHEN se.title ILIKE p.escaped_term || '%' ESCAPE '\' THEN 'title'
        WHEN coalesce(se.speaker, '') ILIKE p.escaped_term || '%' ESCAPE '\' THEN 'speaker'
        WHEN se.title ILIKE '%' || p.escaped_term || '%' ESCAPE '\' THEN 'title'
        ELSE 'speaker'
      END AS match_type,
      CASE
        WHEN lower(se.title) = lower(p.term) THEN 0
        WHEN se.title ILIKE p.escaped_term || '%' ESCAPE '\' THEN 1
        WHEN lower(coalesce(se.speaker, '')) = lower(p.term) THEN 2
        WHEN coalesce(se.speaker, '') ILIKE p.escaped_term || '%' ESCAPE '\' THEN 3
        WHEN se.title ILIKE '%' || p.escaped_term || '%' ESCAPE '\' THEN 4
        ELSE 5
      END AS match_rank
    FROM public.sentence_embeddings AS se
    CROSS JOIN params AS p
    WHERE char_length(p.term) >= 3
      AND (
        se.title ILIKE '%' || p.escaped_term || '%' ESCAPE '\'
        OR coalesce(se.speaker, '') ILIKE '%' || p.escaped_term || '%' ESCAPE '\'
      )
  )
  SELECT ranked.title, ranked.speaker, ranked.url, ranked.match_type
  FROM ranked
  ORDER BY ranked.match_rank, ranked.title, ranked.speaker
  LIMIT (SELECT result_limit FROM params);
$$;

CREATE OR REPLACE FUNCTION public.search_keyword_sentences(
  search_term text,
  match_count integer DEFAULT 20
)
RETURNS TABLE (
  text text,
  talk_id uuid,
  title text,
  speaker text,
  url text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  WITH params AS (
    SELECT
      trim(search_term) AS term,
      replace(
        replace(
          replace(trim(search_term), '\', '\\'),
          '%', '\%'
        ),
        '_', '\_'
      ) AS escaped_term,
      least(greatest(match_count, 1), 100) AS result_limit
  )
  SELECT se.text, se.talk_id, se.title, se.speaker, se.url
  FROM public.sentence_embeddings AS se
  CROSS JOIN params AS p
  WHERE char_length(p.term) > 0
    AND (
      se.text ILIKE '%' || p.escaped_term || '%' ESCAPE '\'
      OR se.title ILIKE '%' || p.escaped_term || '%' ESCAPE '\'
      OR coalesce(se.speaker, '') ILIKE '%' || p.escaped_term || '%' ESCAPE '\'
    )
  ORDER BY
    CASE
      WHEN lower(se.title) = lower(p.term) THEN 0
      WHEN lower(coalesce(se.speaker, '')) = lower(p.term) THEN 1
      ELSE 2
    END,
    se.year DESC NULLS LAST,
    se.title,
    se.sentence_num
  LIMIT (SELECT result_limit FROM params);
$$;

REVOKE ALL ON FUNCTION public.search_talk_suggestions(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.search_keyword_sentences(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.search_talk_suggestions(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.search_keyword_sentences(text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.search_talk_suggestions(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_keyword_sentences(text, integer) TO authenticated;

-- Make newly created RPC functions visible to PostgREST immediately.
NOTIFY pgrst, 'reload schema';
