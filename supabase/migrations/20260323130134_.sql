
-- Add source to curso_courses (drive or manual)
ALTER TABLE public.curso_courses
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'drive';

-- Add youtube_url to curso_lessons
ALTER TABLE public.curso_lessons
  ADD COLUMN IF NOT EXISTS youtube_url text DEFAULT NULL;
;
