#!/bin/bash
# Загрузка CSV пакета в PostgreSQL. Запуск из корня пакета: bash code/load.sh <имя базы> (перед этим: psql <база> -f data/schema.sql)
DB=${1:-bank}
load() { echo "$2 <- $1"; zstd -dc "data/$1" | psql "$DB" -q -c "\\copy $2 from stdin csv header"; }
load 1_source/r101_mdb.csv.zst public.r101mdb
load 1_source/r101_cbr.csv.zst public.r101cbr
load 1_source/r101_i.csv.zst public.r101i
load 1_source/r101_i2.csv.zst public.r101i2
load 2_clean/r101_clean.csv.zst m.r101
load 2_clean/src_choice.csv.zst m.src_choice
load 2_clean/restored.csv.zst m.restored
load 2_clean/bank_date.csv.zst m.bank_date
load 3_tree/tree.csv.zst m.tree
load 3_tree/account_to_leaf.csv.zst m.knt
load 3_tree/account_map.csv.zst m.map
load 3_tree/plan579.csv.zst m.plan579
load 3_tree/leaf_values.csv.zst m.leaf
load 3_tree/node_values.csv.zst m.node
load 3_tree/orig_plan.csv.zst tree.plan
load 3_tree/orig_balance_tree.csv.zst tree.balance_tree
load 3_tree/orig_balance_tree_knt.csv.zst tree.balance_tree_knt
load 8_vector/matryoshka_axes.csv.zst m.dig_axis
load 8_vector/matryoshka_coords.csv.zst m.dig_coord
load 8_vector/matryoshka_cells.csv.zst m.dig_cell
load 8_vector/matryoshka_state_vectors.csv.zst m.dig_state
load 8_vector/matryoshka_scale.csv.zst m.dig_scale
echo "готово"
