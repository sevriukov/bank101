-- Чистая матрёшка, шаг 1: единая таблица остатков m.r101 из четырёх исходных выгрузок.
-- Исходные таблицы public.r101mdb / r101cbr / r101i / r101i2 не изменяются. Вариант для пакета: вместо таблицы r101a
-- (её в пакете нет) читается r101mdb — те же файлы Access, загруженные заново.
\set ON_ERROR_STOP on
\timing on
set work_mem = '6GB';
set max_parallel_workers_per_gather = 8;

drop schema if exists m cascade;
create schema m;

-- 1.1 Все источники в одном виде.
create unlogged table m.src0 as
select 'a'::text src, dat::date dat, regn::numeric::int regn, konto::numeric::int konto, ap::int ap,
       vr, vv, vi, ora, ova, oia, orp, ovp, oip, ir, iv, ii
  from public.r101mdb          -- файлы Access; срез 01.07.1998 берётся ниже отдельной строкой источника, файл 0808_all.mdb — копия июльского
 where konto ~ '^[0-9]{5}(\.0)?$' and regn ~ '^-?[0-9]+(\.0)?$' and ap in ('1', '2')
   and dat <> '1998-07-01' and file not ilike '%0808_all%'
union all
-- настоящий срез 01.07.1998 из исходного файла Access (BAL98-06/0798.mdb), см. 00_load_mdb.py
select 'mdb', dat, regn::numeric::int, konto::int, ap::int,
       vr, vv, vi, ora, ova, oia, orp, ovp, oip, ir, iv, ii
  from public.r101mdb
 where dat = '1998-07-01' and konto ~ '^[0-9]{5}$' and ap in ('1', '2')
union all
select 'cbr', dat::date, regn::numeric::int, konto::int, ap::int,
       vr, vv, vi, ora, ova, oia, orp, ovp, oip, ir, iv, ii
  from public.r101cbr
 where konto ~ '^[0-9]{5}$' and regn ~ '^-?[0-9]+(\.0)?$' and ap in (1, 2)
union all
select 'i', to_date(dat, 'YYYY-DD-MM'), regn::numeric::int, konto::int, ap::int,   -- в r101i/i2 день и месяц переставлены
       vr, vv, vi, ora, ova, oia, orp, ovp, oip, ir, iv, ii
  from public.r101i
 where konto ~ '^[0-9]{5}$' and regn ~ '^-?[0-9]+(\.0)?$' and ap in (1, 2)
union all
select 'i2', to_date(dat, 'YYYY-DD-MM'), regn::numeric::int, konto::int, ap::int,
       vr, vv, vi, ora, ova, oia, orp, ovp, oip, ir, iv, ii
  from public.r101i2
 where konto ~ '^[0-9]{5}$' and regn ~ '^-?[0-9]+(\.0)?$' and ap in (1, 2);

-- 1.2 Только балансовые счета главы А, без мусорных regn и полностью нулевых строк;
--     внутри одного источника по ключу остаётся одна, наиболее заполненная строка.
create unlogged table m.src as
select distinct on (src, dat, regn, konto, ap) *
  from m.src0
 where konto between 10101 and 70802
   and konto % 10000 <> 0 and konto not in (20299, 20999)      -- итоговые строки разделов, не счета
   and regn not in (-1, 9006, 14811, 14812, 25941)
   and not (coalesce(vi, 0) = 0 and coalesce(oia, 0) = 0 and coalesce(oip, 0) = 0 and coalesce(ii, 0) = 0)
 order by src, dat, regn, konto, ap,
          ((vi is not null and vi <> 0)::int + (oia is not null and oia <> 0)::int +
           (oip is not null and oip <> 0)::int + (ii is not null and ii <> 0)::int +
           (vr is not null and vr <> 0)::int + (ir is not null and ir <> 0)::int) desc;
drop table m.src0;

-- 1.3 Для каждой пары банк–дата выбирается ОДИН источник целиком: тот, у которого лучше сходится
--     баланс (актив = пассив); при равенстве — где больше строк; затем приоритет cbr > a > i2 > i.
create table m.src_choice as
with s as (
  select src, dat, regn, count(*) n,
         coalesce(sum(ii) filter (where ap = 1), 0) act,
         coalesce(sum(ii * (3 - 2 * ap)), 0) diff
    from m.src group by 1, 2, 3)
select distinct on (dat, regn) dat, regn, src, n, act,
       case when act > 0 then round(abs(diff) / act, 6) end imbalance,
       count(*) over (partition by dat, regn) n_sources
  from s
 order by dat, regn,
          case when act > 0 then round(abs(diff) / act, 3) else 9 end,
          n desc,
          array_position(array['cbr', 'mdb', 'a', 'i2', 'i'], src);

create table m.r101 as
select s.dat, s.regn, s.konto, s.ap, s.vr, s.vv, s.vi, s.ora, s.ova, s.oia, s.orp, s.ovp, s.oip, s.ir, s.iv, s.ii, s.src
  from m.src s join m.src_choice c using (dat, regn, src);
drop table m.src;
create index on m.r101 (regn, dat);
analyze m.r101;

-- 1.4 Закрытие лакун. Форма 101 — оборотно-сальдовая ведомость: входящие остатки формы на дату D+1
--     равны исходящим на дату D. Если у банка нет формы на D, но есть на D+1 и
--     (есть форма на D-1 или дата D отсутствует в данных целиком), остатки на D берутся из D+1.
create table m.restored as
with bd as (select distinct dat, regn from m.r101),
     cal as (select generate_series(min(dat), max(dat), interval '1 month')::date dat from bd),
     sysd as (select distinct dat from bd),
     need as (
       select (n.dat - interval '1 month')::date dat, n.regn, n.dat next_dat
         from bd n
        where not exists (select 1 from bd x where x.regn = n.regn and x.dat = (n.dat - interval '1 month')::date)
          and (exists (select 1 from bd p where p.regn = n.regn and p.dat = (n.dat - interval '2 month')::date)
               or not exists (select 1 from sysd d where d.dat = (n.dat - interval '1 month')::date))
          and (n.dat - interval '1 month')::date >= (select min(dat) - interval '1 month' from bd))   -- включая входящие остатки самой первой формы
select need.dat, r.regn, r.konto, r.ap,
       null::numeric vr, null::numeric vv, null::numeric vi,
       null::numeric ora, null::numeric ova, null::numeric oia,
       null::numeric orp, null::numeric ovp, null::numeric oip,
       r.vr ir, r.vv iv, r.vi ii, 'restored'::text src
  from need join m.r101 r on r.regn = need.regn and r.dat = need.next_dat
 where r.vi is not null and r.vi <> 0;

insert into m.r101 select * from m.restored;
analyze m.r101;

\echo === источники по годам (пар банк–дата)
select extract(year from dat) y,
       count(*) filter (where src = 'a') a, count(*) filter (where src = 'mdb') mdb, count(*) filter (where src = 'cbr') cbr,
       count(*) filter (where src = 'i') i, count(*) filter (where src = 'i2') i2,
       count(*) filter (where n_sources > 1) had_several_sources
  from m.src_choice c group by 1 order by 1;
\echo === восстановленные даты
select dat, count(distinct regn) banks, count(*) row_cnt from m.restored group by 1 order by 2 desc limit 15;
select count(*) rows_total, count(distinct (dat, regn)) bank_dates, count(distinct dat) dates from m.r101;
