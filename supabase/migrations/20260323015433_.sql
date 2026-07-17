
-- 1. curso_courses
CREATE TABLE public.curso_courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  drive_folder_id text NOT NULL,
  drive_folder_name text,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'ready', 'error')),
  error_message text,
  raw_ai_response jsonb,
  total_modules int DEFAULT 0,
  total_lessons int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, drive_folder_id)
);

-- 2. curso_modules
CREATE TABLE public.curso_modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.curso_courses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  order_index int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- 3. curso_lessons
CREATE TABLE public.curso_lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_id uuid NOT NULL REFERENCES public.curso_modules(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  order_index int NOT NULL DEFAULT 0,
  drive_file_id text,
  drive_file_url text,
  drive_file_embed_url text,
  mime_type text,
  duration int,
  created_at timestamptz DEFAULT now()
);

-- 4. curso_progress
CREATE TABLE public.curso_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL REFERENCES public.curso_lessons(id) ON DELETE CASCADE,
  completed boolean DEFAULT false,
  last_position int DEFAULT 0,
  duration int DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, lesson_id)
);

-- 5. curso_notes
CREATE TABLE public.curso_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL REFERENCES public.curso_lessons(id) ON DELETE CASCADE,
  content text NOT NULL,
  timestamp int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- INDICES
CREATE INDEX idx_curso_courses_user_id ON public.curso_courses(user_id);
CREATE INDEX idx_curso_lessons_module_id ON public.curso_lessons(module_id);
CREATE INDEX idx_curso_progress_user_id ON public.curso_progress(user_id);
CREATE INDEX idx_curso_progress_lesson_id ON public.curso_progress(lesson_id);

-- RLS
ALTER TABLE public.curso_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curso_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curso_lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curso_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curso_notes ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users manage own courses" ON public.curso_courses
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users manage own modules" ON public.curso_modules
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users manage own lessons" ON public.curso_lessons
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users manage own progress" ON public.curso_progress
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users manage own notes" ON public.curso_notes
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
;
