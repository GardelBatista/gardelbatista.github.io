
CREATE TABLE public.mini_site_leads (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  specialty TEXT NOT NULL,
  phone TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'mini-site',
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.mini_site_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can submit a mini-site lead"
ON public.mini_site_leads
FOR INSERT
TO anon, authenticated
WITH CHECK (true);

CREATE POLICY "Admins can view mini-site leads"
ON public.mini_site_leads
FOR SELECT
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.user_roles
  WHERE user_id = auth.uid() AND role = 'admin'
));

CREATE POLICY "Admins can delete mini-site leads"
ON public.mini_site_leads
FOR DELETE
TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.user_roles
  WHERE user_id = auth.uid() AND role = 'admin'
));

CREATE INDEX idx_mini_site_leads_created_at ON public.mini_site_leads (created_at DESC);
;
