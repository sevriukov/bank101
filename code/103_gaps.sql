-- Э87. Недостатки базы одним списком: m.dig_gap (вид, банк, дата, пояснение). Лакуна — это отсутствие сведений, а не ноль.
-- В m.dig_state добавляются признаки: известны ли обороты, известно ли деление остатков на рубли и валюту.
\set ON_ERROR_STOP on
set work_mem = '2GB';
drop table if exists m.dig_gap;
create table m.dig_gap (kind text, regn int, dat date, detail text);
-- 1. отчётные даты, которых нет в базе вовсе
insert into m.dig_gap
select 'нет отчётной даты в базе', null, d::date, 'среза нет ни в одном источнике'
  from generate_series('1998-01-01'::date, '2022-02-01', interval '1 month') d
 where d::date not in (select distinct dat from m.bank_date);
-- 2. дыры внутри линии банка: между первой и последней отчётностью месяца нет (кроме дат из п. 1)
insert into m.dig_gap
select 'дыра в линии банка', b.regn, d::date, 'банк отчитывался до и после этой даты'
  from (select regn, min(dat) d0, max(dat) d1 from m.bank_date group by 1) b, generate_series(b.d0, b.d1, interval '1 month') d
 where not exists (select 1 from m.bank_date x where x.regn = b.regn and x.dat = d::date)
   and d::date in (select distinct dat from m.bank_date);
-- 3. лицензия действовала, отчётности в базе нет (до первой или после последней отчётной даты)
insert into m.dig_gap
select 'лицензия действовала, отчётности нет', f.regn, d::date, case when d::date < f.first_rep then 'до первой отчётности в базе' else 'после последней отчётности в базе' end
  from m.fate f, generate_series(greatest(date_trunc('month', f.lic_start) + interval '1 month', '1998-01-01'), least(date_trunc('month', coalesce(f.death_date, '2022-02-01')), '2022-02-01'), interval '1 month') d
 where f.lic_start is not null and (d::date < f.first_rep or d::date > f.last_rep) and d::date in (select distinct dat from m.bank_date);
-- 4–7. точка есть, но неполна или ненадёжна
insert into m.dig_gap select 'нет валюты баланса', regn, dat, 'активы не положительны; в векторы не входит' from m.bank_date where 'no_assets' = any(flags);
insert into m.dig_gap select 'остатки восстановлены, оборотов нет', regn, dat, 'остатки взяты из входящих остатков следующей формы; обороты неизвестны' from m.bank_date where 'restored' = any(flags);
insert into m.dig_gap select 'баланс не сходится', regn, dat, 'актив не равен пассиву; невязка ' || round(imbalance::numeric, 4) from m.bank_date where 'unbalanced' = any(flags);
insert into m.dig_gap select 'скачок валюты баланса', regn, dat, 'резкое изменение, возможна ошибка источника' from m.bank_date where 'spike' = any(flags);
insert into m.dig_gap select 'нет деления остатков на рубли и валюту', regn, dat, 'строк ' || n_rows || ', доля баланса ' || share_of_balance from m.dig_flag;
insert into m.dig_gap select 'деление на рубли и валюту взято из файлов Access', regn, dat, 'строк ' || count(*) from m.dig_fix group by regn, dat;
-- 8. сумма долей листьев стороны баланса отличается от единицы более чем на 1 %
insert into m.dig_gap
select 'сумма долей листьев не равна единице', c.regn, c.dat, 'актив ' || round((sum(c.v_rub + c.v_fx) filter (where a.side = 'A') / bd.assets)::numeric, 3) || ', пассив ' || round((-sum(c.v_rub + c.v_fx) filter (where a.side = 'P') / bd.assets)::numeric, 3)
  from m.dig_cell c join m.dig_axis a using (ch_id, srok) join m.bank_date bd using (regn, dat)
 where bd.assets > 0 group by c.regn, c.dat, bd.assets
having abs(coalesce(sum(c.v_rub + c.v_fx) filter (where a.side = 'A'), 0) / bd.assets - 1) > 0.01 or abs(coalesce(-sum(c.v_rub + c.v_fx) filter (where a.side = 'P'), 0) / bd.assets - 1) > 0.01;
-- 9. недостатки справочника судеб (по банку, без даты)
insert into m.dig_gap select 'причина отзыва не установлена', regn, revoke_date, name from m.fate where death_kind = 'revoked_reason_unknown';
insert into m.dig_gap select 'вид прекращения лицензии не установлен', regn, lic_end, name from m.fate where death_kind = 'ended_kind_unknown';
insert into m.dig_gap select 'дата отзыва раньше последней отчётности', regn, revoke_date, name || '; последняя отчётность ' || last_rep from m.fate where revoke_date is not null and last_rep > revoke_date + interval '13 months';
insert into m.dig_gap select 'нет даты начала лицензии', regn, null, name from m.fate where lic_start is null;
create index on m.dig_gap (regn, dat); create index on m.dig_gap (kind);
-- признаки в таблице векторов
alter table m.dig_state add column if not exists turn_known boolean default true, add column if not exists split_known boolean default true;
update m.dig_state s set turn_known = false from m.bank_date b where b.regn = s.regn and b.dat = s.dat and 'restored' = any(b.flags);
update m.dig_state s set split_known = false from m.dig_flag f where f.regn = s.regn and f.dat = s.dat;
select kind, count(*) n, count(distinct regn) banks, min(dat), max(dat) from m.dig_gap group by 1 order by 2 desc;
select count(*) points, count(*) filter (where not turn_known) no_turn, count(*) filter (where not split_known) no_split from m.dig_state;
-- 10. Отчётность после отзыва лицензии: до января 2006 г. Банк России публиковал балансы ликвидируемых банков.
--     Это не лакуна, а особое состояние: точка есть, но банк уже не действует. Помечается в m.dig_state (after_revoke).
insert into m.dig_gap
select 'отчётность после отзыва лицензии (ликвидация)', b.regn, b.dat, 'отзыв ' || f.revoke_date
  from m.bank_date b join m.fate f using (regn) where f.revoke_date is not null and b.dat > f.revoke_date + interval '1 month';
update m.dig_gap set detail = detail || ' — банк отчитывался как ликвидируемый' where kind = 'дата отзыва раньше последней отчётности';
alter table m.dig_state add column if not exists after_revoke boolean default false;
update m.dig_state s set after_revoke = true from m.fate f where f.regn = s.regn and f.revoke_date is not null and s.dat > f.revoke_date + interval '1 month';
select count(*) filter (where after_revoke) after_revoke_points, count(distinct regn) filter (where after_revoke) banks from m.dig_state;
-- 11. Поправка 6 октября: «деление взято из файлов Access» оказалось мнимым у пар, где и в файлах Access валютных остатков нет
--     (итог целиком записан в рублёвый столбец), хотя банк имел валютные остатки в соседние известные месяцы. Это лакуна.
create table if not exists m.dig_nosplit as
select x.regn, x.dat from (select regn, dat from m.dig_fix group by 1, 2 having sum(abs(iv)) = 0) x
 where exists (select 1 from m.dig_cell c where c.regn = x.regn and c.v_fx <> 0 and c.dat in ('2006-01-01', '2007-01-01', '2005-02-01', '2005-04-01', '2004-09-01', '2004-11-01'));
update m.dig_state s set split_known = false from m.dig_nosplit n where n.regn = s.regn and n.dat = s.dat;
delete from m.dig_gap where kind = 'деление на рубли и валюту взято из файлов Access' and (regn, dat) in (select regn, dat from m.dig_nosplit);
delete from m.dig_gap where kind = 'нет деления остатков на рубли и валюту: в обоих источниках валюта записана в рублёвый столбец';
insert into m.dig_gap select 'нет деления остатков на рубли и валюту: в обоих источниках валюта записана в рублёвый столбец', regn, dat, 'банк имел валютные остатки в соседние известные месяцы' from m.dig_nosplit;
select count(*) nosplit_points from m.dig_nosplit; select count(*) filter (where not split_known) from m.dig_state;
