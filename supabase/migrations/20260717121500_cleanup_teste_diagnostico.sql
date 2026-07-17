-- remove os registros do teste de certificação do setup (2026-07-17)
delete from public.batista_diagnostico_leads where nome = 'TESTE (pode apagar)';
delete from public.batista_diagnostico_events where session_id = 'teste-setup';
