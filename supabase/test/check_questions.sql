-- After loading seed.sql: lists questions where a wrong A/B/C option would be accepted
-- as a typed answer (should return 0 rows).
select category, question, answer, w as wrong_option
from public.questions, unnest(wrong) w
where public.check_answer(w, answer, aliases);
