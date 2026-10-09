create extension if not exists vector; create schema if not exists m; create schema if not exists tree;






CREATE TABLE m.bank_date (
    dat date NOT NULL,
    regn integer NOT NULL,
    src text,
    n_rows bigint,
    assets numeric,
    liabilities numeric,
    imbalance numeric,
    unmapped_share numeric,
    flags text[]
);



CREATE TABLE m.dig_axis (
    cell bigint,
    ch_id integer,
    srok integer,
    name text,
    side text
);



CREATE TABLE m.dig_cell (
    dat date,
    regn integer,
    ch_id integer,
    srok integer,
    v_rub numeric,
    v_fx numeric,
    td_rub numeric,
    td_fx numeric,
    tc_rub numeric,
    tc_fx numeric
);



CREATE TABLE m.dig_coord (
    coord integer,
    ch_id integer,
    srok integer,
    side text,
    name text,
    facet text
);



CREATE TABLE m.dig_scale (
    coord integer,
    rule text,
    mean double precision,
    std double precision,
    used boolean,
    clip double precision,
    weight double precision
);



CREATE TABLE m.dig_state (
    regn integer NOT NULL,
    dat date NOT NULL,
    assets numeric,
    v public.vector(968),
    turn_known boolean DEFAULT true,
    split_known boolean DEFAULT true,
    after_revoke boolean DEFAULT false
);



CREATE TABLE m.knt (
    id integer NOT NULL,
    dat1 date,
    dat2 date,
    konto integer,
    name text,
    ap smallint,
    ch_id integer,
    srok integer,
    origin text
);



CREATE SEQUENCE m.knt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE m.knt_id_seq OWNED BY m.knt.id;



CREATE TABLE m.leaf (
    dat date,
    regn integer,
    ch_id integer,
    v numeric,
    v0 numeric,
    td numeric,
    tc numeric,
    g numeric
);



CREATE TABLE m.map (
    konto integer,
    ap integer,
    dat date,
    ch_id integer,
    srok integer,
    knt_id integer
);



CREATE TABLE m.node (
    dat date,
    regn integer,
    ch_id integer,
    v numeric,
    v0 numeric,
    td numeric,
    tc numeric
);



CREATE TABLE m.tree (
    ch_id integer NOT NULL,
    p_id integer,
    name text,
    depth integer,
    side text,
    is_leaf boolean
);



CREATE TABLE m.plan579 (
    konto integer,
    name text,
    side text,
    note text
);



CREATE TABLE m.r101 (
    dat date,
    regn integer,
    konto integer,
    ap integer,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric,
    src text
);



CREATE TABLE m.restored (
    dat date,
    regn integer,
    konto integer,
    ap integer,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric,
    src text
);



CREATE TABLE m.src_choice (
    dat date,
    regn integer,
    src text,
    n bigint,
    act numeric,
    imbalance numeric,
    n_sources bigint
);



CREATE TABLE public.r101cbr (
    regn text,
    plan text,
    konto text,
    ap numeric,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric,
    dat text,
    pr numeric
);



CREATE TABLE public.r101i (
    dat text,
    cp text,
    regn text,
    ap numeric,
    konto text,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric
);



CREATE TABLE public.r101i2 (
    dat text,
    cp text,
    regn text,
    ap numeric,
    konto text,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric
);



CREATE TABLE public.r101mdb (
    dat date,
    file text,
    cp text,
    regn text,
    konto text,
    ap text,
    vr numeric,
    vv numeric,
    vi numeric,
    ora numeric,
    ova numeric,
    oia numeric,
    orp numeric,
    ovp numeric,
    oip numeric,
    ir numeric,
    iv numeric,
    ii numeric
);



CREATE TABLE tree.balance_tree_knt (
    dat1 date NOT NULL,
    dat2 date NOT NULL,
    konto integer NOT NULL,
    name text NOT NULL,
    ap text,
    ch_id integer,
    srok integer
);



CREATE TABLE tree.balance_tree (
    ch_id integer NOT NULL,
    p_id integer,
    name text NOT NULL,
    l integer
);



CREATE TABLE tree.plan (
    konto integer,
    name text,
    ap integer
);



ALTER TABLE ONLY m.knt ALTER COLUMN id SET DEFAULT nextval('m.knt_id_seq'::regclass);


ALTER TABLE ONLY m.bank_date
    ADD CONSTRAINT bank_date_pkey PRIMARY KEY (dat, regn);



ALTER TABLE ONLY m.dig_state
    ADD CONSTRAINT dig_state_pkey PRIMARY KEY (regn, dat);



ALTER TABLE ONLY m.knt
    ADD CONSTRAINT knt_pkey PRIMARY KEY (id);



ALTER TABLE ONLY m.tree
    ADD CONSTRAINT tree_pkey PRIMARY KEY (ch_id);



ALTER TABLE ONLY tree.balance_tree
    ADD CONSTRAINT balance_tree_pkey PRIMARY KEY (ch_id);



CREATE INDEX dig_cell_regn_dat_idx ON m.dig_cell USING btree (regn, dat);



CREATE UNIQUE INDEX map_konto_ap_dat_idx ON m.map USING btree (konto, ap, dat);



CREATE INDEX node_dat_ch_id_idx ON m.node USING btree (dat, ch_id);



CREATE INDEX node_regn_dat_idx ON m.node USING btree (regn, dat);



CREATE INDEX r101_regn_dat_idx ON m.r101 USING btree (regn, dat);



ALTER TABLE ONLY m.knt
    ADD CONSTRAINT knt_ch_id_fkey FOREIGN KEY (ch_id) REFERENCES m.tree(ch_id);



ALTER TABLE ONLY tree.balance_tree_knt
    ADD CONSTRAINT balance_tree_knt_ch_id_fkey FOREIGN KEY (ch_id) REFERENCES tree.balance_tree(ch_id) ON DELETE CASCADE;


