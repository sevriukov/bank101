-- Чистая матрёшка, шаг 2: исправленная привязка счетов к листьям дерева (m.knt) и готовая
-- таблица соответствия m.map (счёт, сторона, дата) -> лист. Таблицы схемы tree не изменяются.
\set ON_ERROR_STOP on
\timing on
set work_mem = '4GB';

-- 2.0 Официальный план счетов (579-П, редакция 2022 г.) и копия дерева
drop table if exists m.plan579, m.tree, m.knt, m.map, m.unmapped cascade;
create table m.plan579 (konto int, name text, side text, note text);
\copy m.plan579 from 'plan_579P_2022.csv' csv

create table m.tree as
with recursive r as (
  select ch_id, p_id, name, 1 depth, ch_id root from tree.balance_tree where p_id = 0
  union all
  select b.ch_id, b.p_id, b.name, r.depth + 1, r.root from tree.balance_tree b join r on b.p_id = r.ch_id)
select r.ch_id, r.p_id, r.name, r.depth,
       case r.root when 70 then 'A' else 'P' end side,
       not exists (select 1 from tree.balance_tree c where c.p_id = r.ch_id) is_leaf
  from r;
alter table m.tree add primary key (ch_id);

-- 2.1 Привязка без дублей. origin: orig — исходная привязка (Excel 2013), manual — решение по спорному счёту, bulk2014 — счета,
--     добавленные в 2025 г. одной датой 01.01.2014, auto:* — добавлено этим скриптом.
create table m.knt (
  id serial primary key, dat1 date, dat2 date, konto int, name text, ap smallint,
  ch_id int references m.tree, srok int, origin text);
insert into m.knt (dat1, dat2, konto, name, ap, ch_id, srok, origin)
select distinct on (dat1, dat2, konto, ch_id)
       dat1, dat2, konto, name, nullif(ap, '-')::smallint, ch_id, srok,
       case when dat1 = '2014-01-01' then 'bulk2014' else 'orig' end
  from tree.balance_tree_knt
 order by dat1, dat2, konto, ch_id;

-- 2.2 Переиспользованные номера: счёт введён Указанием 4555-У (с 01.01.2019), а старая привязка
--     с прежним смыслом открыта до 2100 г. — закрываем её 01.01.2019.
update m.knt k set dat2 = '2019-01-01'
 where origin = 'orig' and dat2 = '2100-01-01' and dat1 < '2019-01-01'
   and konto in (select konto from m.plan579 where note like '%4555-У%');

-- 2.3 Счетам, добавленным оптом с 01.01.2014, ставим реальное начало: первая дата в данных
--     (после последнего исходного интервала этого счёта) минус месяц плюс день,
--     как в исходной привязке (02.01.2008 для счетов, появившихся в форме на 01.02.2008).
create temp table kdates as select distinct konto, ap, dat from m.r101 where ii is not null and ii <> 0;
update m.knt k set dat1 = f.d
  from (select b.id, (min(d.dat) - interval '1 month' + interval '1 day')::date d
          from m.knt b join kdates d on d.konto = b.konto
         where b.origin = 'bulk2014'
           and d.dat > coalesce((select max(o.dat2) from m.knt o where o.konto = b.konto and o.origin = 'orig'), '1900-01-01')
         group by b.id) f
 where k.id = f.id and f.d <> k.dat1;

-- 2.4 Непривязанные (счёт, сторона, период) — «острова» дат без действующего интервала
create temp table islands as
with d as (
  select k.konto, k.ap, k.dat,
         exists (select 1 from m.knt x where x.konto = k.konto and k.dat between x.dat1 and x.dat2) mapped,
         row_number() over (partition by k.konto, k.ap order by k.dat) rn
    from kdates k),
u as (select *, rn - row_number() over (partition by konto, ap order by dat) grp from d where not mapped)
select konto, ap, grp, min(dat) d1, max(dat) d2, count(*) n_dates from u group by 1, 2, 3;

-- 2.5 Предложение листа для каждого острова. Правила по убыванию приоритета:
--     R1 — ближайший по времени собственный интервал счёта (кроме переиспользованных номеров);
--     R2 — счёт с тем же официальным названием в том же разделе (первые 2 цифры), действующий на дату;
--     R3 — ближайший по номеру счёт той же группы второго порядка (3 цифры) и той же стороны;
--     R4 — то же в пределах первых двух цифр номера;
--     R5 — остаток на нетипичной стороне счёта: тот же лист, что у основной стороны этого счёта.
create temp table proposal as
select i.*,
       coalesce(r1.ch_id, r2.ch_id, r3.ch_id, r4.ch_id) ch_id,
       case when r1.ch_id is not null then 'auto:R1' when r2.ch_id is not null then 'auto:R2'
            when r3.ch_id is not null then 'auto:R3' when r4.ch_id is not null then 'auto:R4' end origin,
       coalesce(p.name, (select name from tree.plan t where t.konto = i.konto limit 1)) name
  from islands i
  left join m.plan579 p on p.konto = i.konto
  left join lateral (
    select k.ch_id from m.knt k
     where k.konto = i.konto and k.ap is not distinct from i.ap
       and not (coalesce(p.note, '') like '%4555-У%' and i.d1 >= '2019-01-01')
     order by least(abs(k.dat1 - i.d1), abs(k.dat2 - i.d1)) limit 1) r1 on true
  left join lateral (
    select k.ch_id from m.knt k join m.plan579 q on q.konto = k.konto
     where q.name = p.name and k.konto <> i.konto and k.konto / 1000 = i.konto / 1000
       and i.d1 between k.dat1 and k.dat2 and k.ap is not distinct from i.ap
     group by k.ch_id order by count(*) desc limit 1) r2 on true
  left join lateral (
    select k.ch_id from m.knt k
     where k.konto / 100 = i.konto / 100 and k.konto <> i.konto
       and i.d1 between k.dat1 and k.dat2 and k.ap is not distinct from i.ap
     order by abs(k.konto - i.konto) limit 1) r3 on true
  left join lateral (
    select k.ch_id from m.knt k
     where k.konto / 1000 = i.konto / 1000 and k.konto <> i.konto
       and i.d1 between k.dat1 and k.dat2 and k.ap is not distinct from i.ap
     order by abs(k.konto - i.konto) limit 1) r4 on true;

-- R5: если у того же счёта есть предложение по правилу R2 для другой стороны, берём его лист
update proposal p set ch_id = q.ch_id, origin = 'auto:R5'
  from proposal q
 where q.konto = p.konto and q.ap <> p.ap and q.origin = 'auto:R2' and p.origin is distinct from 'auto:R2';

insert into m.knt (dat1, dat2, konto, name, ap, ch_id, srok, origin)
select (d1 - interval '1 month' + interval '1 day')::date,
       case when d2 = (select max(dat) from kdates) then '2100-01-01'::date else d2 end,
       konto, name, ap, ch_id, 3, origin
  from proposal where ch_id is not null;

create table m.unmapped as select konto, ap, d1, d2, n_dates, name from proposal where ch_id is null;

-- 2.5а Ручные решения по спорным счетам (согласовано 03.10.2026).
--   47501 (П) / 47502 (А) «Расчёты по выданным банковским гарантиям», с 2019 г. — в «Сальдо прочих операций»,
--     как и их пара по смыслу 47422 / 47423;
--   50709 (А) 2014–2019 «Долевые ценные бумаги, оцениваемые по себестоимости» — в «Корпоративные и прочие —
--     резидентов», как 50706. (В 2002–2008 гг. 50709 — пассив «Резервы под обесценение», исходная привязка к «Резервам».)
update m.knt set ch_id = 168, origin = 'manual'
 where origin like 'auto%' and konto in (47501, 47502) and dat1 >= '2019-01-01';
update m.knt set ch_id = 113, origin = 'manual'
 where origin like 'auto%' and konto = 50709 and ap = 1 and dat1 >= '2014-01-01';

-- 2.6 Итоговое соответствие (счёт, сторона, дата) -> лист. При нескольких подходящих интервалах
--     выигрывает совпадающий по стороне счёта (это разводит 4 счёта, привязанных в 2001–2008 гг.
--     одновременно к резервам как пассивные и к требованиям как активные), затем исходный, затем более поздний.
create table m.map as
select distinct on (d.konto, d.ap, d.dat) d.konto, d.ap, d.dat, k.ch_id, k.srok, k.id knt_id
  from kdates d join m.knt k on k.konto = d.konto and d.dat between k.dat1 and k.dat2
 order by d.konto, d.ap, d.dat, (k.ap = d.ap) desc nulls last, (k.origin = 'orig') desc, k.dat1 desc;
create unique index on m.map (konto, ap, dat);
analyze m.map;

\echo === привязка: строк по происхождению
select origin, count(*) row_cnt, count(distinct konto) kontos from m.knt group by 1 order by 1;
\echo === автоматически предложенные листья (на проверку)
select k.origin, k.konto, k.ap, k.dat1, k.dat2, k.ch_id, left(t.name, 40) leaf, left(k.name, 60) account
  from m.knt k join m.tree t using (ch_id) where k.origin like 'auto%' order by k.konto, k.dat1;
\echo === осталось без привязки
select * from m.unmapped order by konto;
