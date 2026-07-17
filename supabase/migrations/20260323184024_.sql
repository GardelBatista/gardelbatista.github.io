-- Add cover_url and category columns to curso_courses
ALTER TABLE public.curso_courses 
  ADD COLUMN IF NOT EXISTS cover_url text,
  ADD COLUMN IF NOT EXISTS category text;

-- Create storage bucket for course covers
INSERT INTO storage.buckets (id, name, public)
VALUES ('curso-covers', 'curso-covers', true)
ON CONFLICT (id) DO NOTHING;

-- RLS: users can upload their own covers
CREATE POLICY "Users can upload course covers"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'curso-covers' AND (storage.foldername(name))[1] = auth.uid()::text);

-- RLS: users can update their own covers
CREATE POLICY "Users can update course covers"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'curso-covers' AND (storage.foldername(name))[1] = auth.uid()::text);

-- RLS: users can delete their own covers
CREATE POLICY "Users can delete course covers"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'curso-covers' AND (storage.foldername(name))[1] = auth.uid()::text);

-- RLS: anyone can view covers (public bucket)
CREATE POLICY "Anyone can view course covers"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'curso-covers');;
