-- Add module_id column to curso_resources for direct module linkage
ALTER TABLE public.curso_resources
  ADD COLUMN IF NOT EXISTS module_id uuid REFERENCES public.curso_modules(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_curso_resources_module_id ON public.curso_resources(module_id);;
