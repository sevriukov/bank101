-- Чистая матрёшка, шаг 3: свёртка по дереву на всех уровнях и контроль качества.
\set ON_ERROR_STOP on
\timing on
set work_mem = '6GB';
set max_parallel_workers_per_gather = 8;

drop table if exists m.leaf, m.anc, m.node, m.bank_date cascade;

-- 3.1 Листья. Знак: активные счета с плюсом, пассивные с минусом (как в tree.agr1).
--     v — исходящий остаток, v0 — входящий, td / tc — обороты по дебету / кредиту, g — валовая сумма остатков.
create table m.leaf as
select r.dat, r.regn, mp.ch_id,
       sum(r.ii * (3 - 2 * r.ap)) v,
       sum(r.vi * (3 - 2 * r.ap)) v0,
       sum(r.oia) td, sum(r.oip) tc,
       sum(abs(r.ii)) g
  from m.r101 r join m.map mp using (konto, ap, dat)
 group by 1, 2, 3;

-- 3.2 Замыкание дерева: каждый узел получает все листья своего поддерева (в т. ч. лист — сам себя)
create table m.anc as
with recursive r as (
  select ch_id leaf, ch_id node from m.tree where is_leaf
  union all
  select r.leaf, t.p_id from r join m.tree t on t.ch_id = r.node where t.p_id <> 0)
select * from r;

-- 3.3 Все 168 узлов матрёшки
create table m.node as
select l.dat, l.regn, a.node ch_id, sum(l.v) v, sum(l.v0) v0, sum(l.td) td, sum(l.tc) tc
  from m.leaf l join m.anc a on a.leaf = l.ch_id
 group by 1, 2, 3;
create index on m.node (dat, ch_id);
create index on m.node (regn, dat);
analyze m.node;

-- 3.4 Паспорт каждой пары банк–дата: валюта баланса (чистый Актив = узел 70), невязка, источник, флаги
create table m.bank_date as
with b as (
  select dat, regn,
         coalesce(max(v) filter (where ch_id = 70), 0) assets,
         coalesce(-max(v) filter (where ch_id = 1), 0) liabilities
    from m.node where ch_id in (1, 70) group by 1, 2),
r as (
  select dat, regn, min(src) src, count(*) n_rows, sum(abs(ii)) gross from m.r101 group by 1, 2),
u as (
  select r.dat, r.regn, sum(abs(r.ii)) gross_unmapped
    from m.r101 r where not exists (select 1 from m.map mp where mp.konto = r.konto and mp.ap = r.ap and mp.dat = r.dat)
   group by 1, 2),
x as (
  select b.*, r.src, r.n_rows,
         coalesce(u.gross_unmapped, 0) / nullif(r.gross, 0) unmapped_share,
         lag(b.assets) over w prev_assets, lead(b.assets) over w next_assets,
         lag(b.dat) over w prev_dat, lead(b.dat) over w next_dat
    from b join r using (dat, regn) left join u using (dat, regn)
  window w as (partition by b.regn order by b.dat))
select dat, regn, src, n_rows, assets, liabilities,
       case when assets > 0 then (assets - liabilities) / assets end imbalance,
       unmapped_share,
       array_remove(array[
         case when src = 'restored' then 'restored' end,
         case when assets <= 0 then 'no_assets' end,
         case when assets > 0 and abs(assets - liabilities) / assets > 0.001 then 'unbalanced' end,
         case when prev_assets > 0 and next_assets > 0
               and prev_dat = (dat - interval '1 month')::date and next_dat = (dat + interval '1 month')::date
               and (assets > 5 * greatest(prev_assets, next_assets) or assets < least(prev_assets, next_assets) / 5)
              then 'spike' end], null) flags
  from x;
alter table m.bank_date add primary key (dat, regn);

-- 3.5 Три способа выразить значение узла (из заметок автора): натуральное, структурная доля, доля рынка.
--     v_nat — в натуральном знаке (пассивы положительные); struct_ppm — доля в валюте баланса банка, млн-е доли;
--     market_ppm — доля банка в сумме узла по всем банкам на дату, млн-е доли.
create view m.node_share as
select n.dat, n.regn, n.ch_id, t.depth, t.side,
       n.v * (case t.side when 'P' then -1 else 1 end) v_nat,
       case when b.assets > 0 then n.v * (case t.side when 'P' then -1 else 1 end) / b.assets * 1e6 end struct_ppm,
       n.v / nullif(sum(n.v) over (partition by n.dat, n.ch_id), 0) * 1e6 market_ppm,
       b.flags
  from m.node n join m.tree t using (ch_id) join m.bank_date b using (dat, regn);

-- ===================== контроль =====================
\echo === объём
select (select count(*) from m.r101) r101_rows, (select count(*) from m.leaf) leaf_rows, (select count(*) from m.node) node_rows,
       (select count(*) from m.bank_date) bank_dates, (select count(distinct dat) from m.bank_date) dates;
\echo === сходимость баланса и флаги
select count(*) bank_dates,
       count(*) filter (where 'unbalanced' = any(flags)) unbalanced,
       round(100.0 * count(*) filter (where 'unbalanced' = any(flags)) / count(*), 2) unbalanced_pct,
       count(*) filter (where 'restored' = any(flags)) restored,
       count(*) filter (where 'spike' = any(flags)) spike,
       count(*) filter (where 'no_assets' = any(flags)) no_assets,
       count(*) filter (where flags = '{}') clean
  from m.bank_date;
\echo === по годам
select extract(year from dat) y, count(distinct dat) dates, count(*) bank_dates,
       count(*) filter (where 'unbalanced' = any(flags)) unbalanced,
       count(*) filter (where 'restored' = any(flags)) restored,
       count(*) filter (where 'spike' = any(flags)) spike,
       round(100 * avg(unmapped_share), 3) avg_unmapped_pct
  from m.bank_date group by 1 order by 1;
\echo === системная динамика: даты с изменением суммы активов более чем на 25 % или числа банков более чем на 10 %
select * from (
  select dat, count(*) banks, round(sum(assets) / 1e9, 2) assets,
         round(100 * (sum(assets) / lag(sum(assets)) over (order by dat) - 1), 1) chg_pct,
         count(*) - lag(count(*)) over (order by dat) d_banks,
         dat - lag(dat) over (order by dat) gap_days
    from m.bank_date group by 1) x
 where abs(chg_pct) > 25 or abs(d_banks) > 0.1 * banks or gap_days > 31 order by dat;
\echo === преемственность: исходящий остаток узла на D против входящего на D+1 (по листьям)
select round(100.0 * count(*) filter (where abs(a.v - b.v0) <= 1) / count(*), 2) exact_pct,
       round(100 * sum(abs(a.v - b.v0)) / sum(abs(a.v)), 3) diff_pct_of_volume
  from m.leaf a join m.leaf b on b.regn = a.regn and b.ch_id = a.ch_id and b.dat = (a.dat + interval '1 month')::date
 where b.v0 is not null;
