-- Э90. Относительные координаты и векторы движения. Оригиналы и представления m.dig_view, m.raw5_view не меняются.
--   m.*_month_mean — средний вектор системы за месяц («центр системы»);
--   m.dig_view_rel — отклонение банка от центра системы за тот же месяц (общий сдвиг всей системы вычтен);
--   m.*_move, m.*_move_rel — движение банка за месяц: разность соседних точек его линии (только соседние месяцы);
--       len — длина шага, cosdist — косинусное расстояние между соседними точками, turn_known — известны ли обороты на обеих датах.
-- Для цепочки по счетам движение считается на сжатых векторах (m.raw5_pca — базис abs, m.raw5_pcr — отклонения от центра месяца).
\set ON_ERROR_STOP on
\timing on
set work_mem = '4GB'; set max_parallel_workers_per_gather = 8;
\if :do_dig
drop materialized view if exists m.dig_move_rel; drop materialized view if exists m.dig_move; drop materialized view if exists m.dig_view_rel; drop materialized view if exists m.dig_month_mean;
create materialized view m.dig_month_mean as select dat, count(*) n, (avg(v))::vector(966) v from m.dig_view group by dat;
create materialized view m.dig_view_rel as
select a.regn, a.dat, a.lna, a.t, a.turn_known, (a.v - c.v)::vector(966) v from m.dig_view a join m.dig_month_mean c using (dat);
create unique index on m.dig_view_rel (regn, dat); create index on m.dig_view_rel (dat);
create materialized view m.dig_move as
select b.regn, b.dat, (a.turn_known and b.turn_known) turn_known, vector_norm(b.v - a.v)::real len, (a.v <=> b.v)::real cosdist, (b.v - a.v)::vector(966) d
  from m.dig_view a join m.dig_view b on b.regn = a.regn and b.dat = (a.dat + interval '1 month')::date;
create materialized view m.dig_move_rel as
select b.regn, b.dat, (a.turn_known and b.turn_known) turn_known, vector_norm(b.v - a.v)::real len, (a.v <=> b.v)::real cosdist, (b.v - a.v)::vector(966) d
  from m.dig_view_rel a join m.dig_view_rel b on b.regn = a.regn and b.dat = (a.dat + interval '1 month')::date;
create unique index on m.dig_move (regn, dat); create index on m.dig_move (dat); create unique index on m.dig_move_rel (regn, dat); create index on m.dig_move_rel (dat);
set maintenance_work_mem = '8GB'; set max_parallel_maintenance_workers = 0;
create index dig_view_rel_hnsw on m.dig_view_rel using hnsw (v vector_cosine_ops);
analyze m.dig_view_rel; analyze m.dig_move; analyze m.dig_move_rel;
select count(*) moves from m.dig_move;
\endif
\if :do_raw5
drop materialized view if exists m.raw5_move_rel; drop materialized view if exists m.raw5_move;
create materialized view m.raw5_move as
select b.regn, b.dat, (a.turn_known and b.turn_known) turn_known, vector_norm(b.p - a.p)::real len, (a.p <=> b.p)::real cosdist, (b.p - a.p)::vector(1024) d
  from m.raw5_pca a join m.raw5_pca b on b.regn = a.regn and b.dat = (a.dat + interval '1 month')::date;
create materialized view m.raw5_move_rel as
select b.regn, b.dat, (a.turn_known and b.turn_known) turn_known, vector_norm(b.p - a.p)::real len, (a.p <=> b.p)::real cosdist, (b.p - a.p)::vector(1024) d
  from m.raw5_pcr a join m.raw5_pcr b on b.regn = a.regn and b.dat = (a.dat + interval '1 month')::date;
create unique index on m.raw5_move (regn, dat); create index on m.raw5_move (dat); create unique index on m.raw5_move_rel (regn, dat); create index on m.raw5_move_rel (dat);
analyze m.raw5_move; analyze m.raw5_move_rel;
select count(*) moves from m.raw5_move;
\endif
