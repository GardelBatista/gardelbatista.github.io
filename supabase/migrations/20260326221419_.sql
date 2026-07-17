
-- Create curso_resources table
CREATE TABLE public.curso_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.curso_courses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lesson_id uuid REFERENCES public.curso_lessons(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'link' CHECK (type IN ('link', 'pdf', 'note', 'video')),
  title text NOT NULL,
  content text,
  url text,
  tags text[] DEFAULT '{}',
  order_index int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Indices
CREATE INDEX idx_curso_resources_course_id ON public.curso_resources(course_id);
CREATE INDEX idx_curso_resources_user_id ON public.curso_resources(user_id);
CREATE INDEX idx_curso_resources_lesson_id ON public.curso_resources(lesson_id);

-- RLS
ALTER TABLE public.curso_resources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own resources" ON public.curso_resources
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Storage bucket for resource PDFs
INSERT INTO storage.buckets (id, name, public)
VALUES ('curso-resources', 'curso-resources', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies
CREATE POLICY "Users can upload resource files"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'curso-resources' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can view resource files"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'curso-resources' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can delete resource files"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'curso-resources' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Public can view resource files"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'curso-resources');
;
