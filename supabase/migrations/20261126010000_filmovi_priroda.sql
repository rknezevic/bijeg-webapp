-- New question categories: films & TV series, nature & society.
alter table public.questions drop constraint if exists questions_category_check;
alter table public.questions add constraint questions_category_check
  check (category in ('hrvatska','opce','nogomet','sport','geografija','matematika','stihovi','igrice','filmovi','priroda'));
