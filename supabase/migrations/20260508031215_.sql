-- Table for education materials
CREATE TABLE public.education_materials (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    slug TEXT NOT NULL UNIQUE,
    category TEXT DEFAULT 'Tutorial',
    thumbnail_url TEXT,
    content_type TEXT DEFAULT 'page', -- 'page' (internal route) or 'external'
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.education_materials ENABLE ROW LEVEL SECURITY;

-- Policies for education_materials
CREATE POLICY "Materials are viewable by everyone" 
ON public.education_materials FOR SELECT USING (true);

-- Add column to track which material the lead signed up for
ALTER TABLE public.mini_site_leads 
ADD COLUMN material_slug TEXT REFERENCES public.education_materials(slug);

-- Initial seed for the current tutorial
INSERT INTO public.education_materials (title, description, slug, category)
VALUES (
    'Criador Automático de Mini-Sites com IA', 
    'O guia definitivo para gerar sua estrutura premium de alta conversão em minutos.',
    'mini-site',
    'Lovable'
);
;
