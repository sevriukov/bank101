-- Э87. Оцифровка базы: каждая точка «банк на дату» получает точные координаты. Без групп, исходов, периодов и обучения.
-- Шаг 1 (длинная форма). Ячейка = лист дерева × признак срочности счёта (161 ячейка). По шесть чисел на ячейку:
--   остаток в рублях и в валюте (знак как в дереве: активные счета +, пассивные −),
--   оборот по дебету и по кредиту, в рублях и в валюте. Все даты (287), все банки. Исходные таблицы не меняются.
\set ON_ERROR_STOP on
\timing on
set work_mem = '6GB';
set max_parallel_workers_per_gather = 8;
-- Поправка. У части строк источника cbr (февраль — декабрь 2006 г., март 2005 г.) итог остатка есть, а деления на рубли и валюту нет.
-- Деление берётся из исходных файлов Access (public.r101mdb) для той же строки, если итог совпадает. m.r101 не изменяется.
-- Пары «банк — дата», где деление восстановить не удалось, записаны в m.dig_flag и в плотные векторы не попадают как надёжные.
drop table if exists m.dig_fix;
create table m.dig_fix as
with bad as (select dat, regn, konto, ap, ii from m.r101 where coalesce(ii, 0) <> 0 and abs(coalesce(ir, 0) + coalesce(iv, 0) - ii) > 0.5 + 0.001 * abs(ii)),
     alt as (select m.dat, m.regn::numeric::int regn, m.konto::int konto, m.ap::int ap, max(m.ir) ir, max(m.iv) iv, max(m.ii) ii
               from public.r101mdb m where m.konto ~ '^[0-9]{5}$' and m.regn ~ '^[0-9]+$' and m.ap in ('1', '2')
                and (m.dat, m.regn) in (select dat, regn::text from bad) group by 1, 2, 3, 4)
select b.dat, b.regn, b.konto, b.ap, coalesce(a.ir, 0) ir, coalesce(a.iv, 0) iv
  from bad b join alt a using (dat, regn, konto, ap)
 where abs(coalesce(a.ir, 0) + coalesce(a.iv, 0) - b.ii) <= 0.5 + 0.001 * abs(b.ii);
create index on m.dig_fix (regn, dat, konto, ap);
drop table if exists m.dig_flag;
create table m.dig_flag as
select r.regn, r.dat, 'нет деления остатков на рубли и валюту'::text flag, count(*) n_rows,
       round((sum(abs(r.ii)) / nullif(max(bd.assets), 0) / 2)::numeric, 4) share_of_balance
  from m.r101 r left join m.dig_fix f using (regn, dat, konto, ap) join m.bank_date bd using (regn, dat)
 where f.regn is null and coalesce(r.ii, 0) <> 0 and abs(coalesce(r.ir, 0) + coalesce(r.iv, 0) - r.ii) > 0.5 + 0.001 * abs(r.ii)
 group by 1, 2;
select count(*) fixed_rows, count(distinct (regn, dat)) fixed_bank_dates from m.dig_fix;
select count(*) flagged_bank_dates, count(*) filter (where share_of_balance > 0.01) over_1pct from m.dig_flag;
drop table if exists m.dig_cell;
create table m.dig_cell as
select r.dat, r.regn, mp.ch_id, mp.srok,
       sum(coalesce(f.ir, r.ir, 0) * (3 - 2 * r.ap)) v_rub, sum(coalesce(f.iv, r.iv, 0) * (3 - 2 * r.ap)) v_fx,
       sum(coalesce(r.ora, 0)) td_rub, sum(coalesce(r.ova, 0)) td_fx,
       sum(coalesce(r.orp, 0)) tc_rub, sum(coalesce(r.ovp, 0)) tc_fx
  from m.r101 r join m.map mp using (konto, ap, dat) left join m.dig_fix f using (regn, dat, konto, ap)
 group by 1, 2, 3, 4;
create index on m.dig_cell (regn, dat);
analyze m.dig_cell;
-- перечень координат: номер ячейки по порядку (лист, срочность)
drop table if exists m.dig_axis;
create table m.dig_axis as
select row_number() over (order by t.side, c.ch_id, c.srok) - 1 as cell, c.ch_id, c.srok, t.name, t.side
  from (select distinct ch_id, srok from m.map) c join m.tree t using (ch_id);
select count(*) cells from m.dig_axis; select count(*) rows_cell from m.dig_cell;
