--
-- PostgreSQL database dump
--

\restrict mzO22WzuIh3SdaOmZvIkIVsMaoEOsdPfTLbB94NfRCbqeV7uTMYsyBvYFIfDqep

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg12+2)
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pharmashare_db_user
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO pharmashare_db_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: likes_map; Type: TABLE; Schema: public; Owner: pharmashare_db_user
--

CREATE TABLE public.likes_map (
    id integer NOT NULL,
    user_name text,
    post_id integer
);


ALTER TABLE public.likes_map OWNER TO pharmashare_db_user;

--
-- Name: likes_map_id_seq; Type: SEQUENCE; Schema: public; Owner: pharmashare_db_user
--

CREATE SEQUENCE public.likes_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.likes_map_id_seq OWNER TO pharmashare_db_user;

--
-- Name: likes_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pharmashare_db_user
--

ALTER SEQUENCE public.likes_map_id_seq OWNED BY public.likes_map.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: pharmashare_db_user
--

CREATE TABLE public.posts (
    id integer NOT NULL,
    user_name text,
    drug_name text,
    likes integer DEFAULT 0,
    stars integer DEFAULT 0,
    message text,
    parent_id integer DEFAULT '-1'::integer,
    created_at text,
    title text,
    image_path text,
    category text,
    reports integer DEFAULT 0
);


ALTER TABLE public.posts OWNER TO pharmashare_db_user;

--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: pharmashare_db_user
--

CREATE SEQUENCE public.posts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.posts_id_seq OWNER TO pharmashare_db_user;

--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pharmashare_db_user
--

ALTER SEQUENCE public.posts_id_seq OWNED BY public.posts.id;


--
-- Name: stars_map; Type: TABLE; Schema: public; Owner: pharmashare_db_user
--

CREATE TABLE public.stars_map (
    id integer NOT NULL,
    user_name text,
    post_id integer
);


ALTER TABLE public.stars_map OWNER TO pharmashare_db_user;

--
-- Name: stars_map_id_seq; Type: SEQUENCE; Schema: public; Owner: pharmashare_db_user
--

CREATE SEQUENCE public.stars_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stars_map_id_seq OWNER TO pharmashare_db_user;

--
-- Name: stars_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pharmashare_db_user
--

ALTER SEQUENCE public.stars_map_id_seq OWNED BY public.stars_map.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: pharmashare_db_user
--

CREATE TABLE public.users (
    id integer NOT NULL,
    user_name text,
    password_digest text,
    email text,
    bio text,
    icon_path text
);


ALTER TABLE public.users OWNER TO pharmashare_db_user;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: pharmashare_db_user
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO pharmashare_db_user;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: pharmashare_db_user
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: likes_map id; Type: DEFAULT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.likes_map ALTER COLUMN id SET DEFAULT nextval('public.likes_map_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: stars_map id; Type: DEFAULT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.stars_map ALTER COLUMN id SET DEFAULT nextval('public.stars_map_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: likes_map; Type: TABLE DATA; Schema: public; Owner: pharmashare_db_user
--

COPY public.likes_map (id, user_name, post_id) FROM stdin;
7	かたばみ	29
8	かたばみ	30
9	キコリん	31
10	キコリん	30
11	キコリん	29
12	鴨	32
13	かたばみ	32
14	かたばみ	31
15	鴨	29
\.


--
-- Data for Name: posts; Type: TABLE DATA; Schema: public; Owner: pharmashare_db_user
--

COPY public.posts (id, user_name, drug_name, likes, stars, message, parent_id, created_at, title, image_path, category, reports) FROM stdin;
26	かたばみ	写真	0	0	写真デバッグ	24	2026/01/25 08:39	Re: 写真デバッグ	https://res.cloudinary.com/dsbz8smrp/image/upload/v1769297964/svh9dxzn8svqjrpszzow.heic	インシデントレポート	0
6	かたばみ	テスト	0	0	テスト　コメント	4	2026/01/17 18:05	Re: テスト		インシデントレポート	0
7	かたばみ	テスト	0	0	テスト　コメント	4	2026/01/17 18:05	Re: テスト		インシデントレポート	0
31	キコリん	タケキャブ10mg	2	2	腰痛が良くなった患者さんで、セレコックスが中止になった。\r\n胃腸の症状もなかったので、消化器の疾患もないなら服用されているタケキャブも必要ないと思い、処方医にタケキャブの中止を提案しましたところ、タケキャブも中止になりました。	-1	2026/01/25 16:06	タケキャブ中止を提案		疑義紹介、処方介入事例	0
11	かたばみ	iPhone	0	0	コメント	10	2026/01/19 00:02	Re: テストiPhone		インシデントレポート	0
12	かたばみ	iPhone	0	0	コメントテスト\r\n	10	2026/01/19 00:03	Re: テストiPhone	1768748595_IMG_6782.jpeg	インシデントレポート	0
17	かたばみ	クエチアピン	0	0	こめんと　　返信テスト　文字大きさ	2	2026/01/20 08:24	Re: 糖尿病患者へのクエチアピン		指導のコツ	0
30	やまださん	カルボシステイン	2	1	カルボシステインが長期投与されている患者。とくにたんの症状に悩まされているわけでもなく、冬季に服用開始され、そのままDo処方され内服が４ヶ月続いていた。往診前に処方医に上記の旨を報告し往診時に再度確認していただくようにした\r\n　→カルボシステインの見切り終了となった。	-1	2026/01/25 15:55	カルボシステイン　長期投与		疑義紹介、処方介入事例	0
29	やまださん	アルファカルシドール錠	3	1	パラスターでアルファカルシドール錠を脱ヒートした。\r\nその際に錠剤の排出トレーに静電気でアルファカルシドール錠がくっついていたのに気づかず、次の薬剤に混ざってしまった。調剤薬監査の際に発覚した。\r\n特に冬場の静電気が発生する時期にはパラスターの排出トレーに錠剤が残ってないか特に注意するようにする。	-1	2026/01/25 15:51	パラスターにアルファカルシドール錠がのこっていた		インシデントレポート	0
33	鴨	アルファカルシドール錠	0	0	特に平べったくて、軽い錠剤はよくくっついてますよね💦	29	2026/01/25 20:50	Re: パラスターにアルファカルシドール錠がのこっていた		インシデントレポート	0
23	かたばみ	写真投稿テスト　永続保存	0	0	ここ	22	2026/01/25 07:35	Re: 写真投稿テスト	1769294112_IMG_6849.heic	インシデントレポート	0
32	鴨	イコサペント酸エチル粒状カプセル	2	0	イコサペント酸エチルを長期服用されている患者（８６歳男性）。\r\n採血の結果より投与目的が不明だったので、次回往診時に処方の見直しを依頼しました。次回往診時にも変わらず処方継続となりました。	-1	2026/01/25 19:53	イコサペント酸エチルの漫然投与を指摘した事例		疑義紹介、処方介入事例	0
\.


--
-- Data for Name: stars_map; Type: TABLE DATA; Schema: public; Owner: pharmashare_db_user
--

COPY public.stars_map (id, user_name, post_id) FROM stdin;
7	かたばみ	29
8	かたばみ	30
9	キコリん	31
10	かたばみ	31
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: pharmashare_db_user
--

COPY public.users (id, user_name, password_digest, email, bio, icon_path) FROM stdin;
2	ここす	$2a$12$JYDYEZk6BfVOjRfmwDp1ROr/rfCesW.EAPb4idGLAkNNs/hJgRTM.	\N	\N	\N
3	１２３４	$2a$12$TDapt6biHyL99x9L7cvejup8RZgKqkeNTI/G2Pb7/KRX2FpJNU8zy	\N	\N	\N
4	テスト	$2a$12$ytrrxT9KPnvmYBwBtzBXw.9Hou6oT/ASfRTMNBFNSHYUyJLNZXeu6	test@gmail.com	testo  自己紹介	icon_1768661356_kyler-nixon-208872_jpg-600x400-1-2.jpg
5	やまださん	$2a$12$HiSX6CT0TgHYD0YvzaY4v.NO0otqczXipkJifDCf55ZytQ/hPAJw2	yamada@gmail.com	\N	\N
6	キコリん	$2a$12$Zs8k360PKiWXZamrhhPw.OO0dbi/xS3nWBOl/JFsEiDnoFFfdOmD.	kikorinn@gmail.com	\N	\N
7	鴨	$2a$12$jfLpaQ.5tYfHD9/Y6VKOUeT4F8N/d4lgw/TNH1CNwwLY30J9txH6e	kamo@gmail.com	\N	\N
1	かたばみ	$2a$12$U86tRq3NLkyTu7RhpP./SePLV5WxdC7yPUMB0fenPyczCYapwROIW	1234@gmail.com	かたばみ　テスト　自己紹介	https://res.cloudinary.com/dsbz8smrp/image/upload/v1769263165/eoyizkitnanp02wwhkne.jpg
\.


--
-- Name: likes_map_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pharmashare_db_user
--

SELECT pg_catalog.setval('public.likes_map_id_seq', 15, true);


--
-- Name: posts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pharmashare_db_user
--

SELECT pg_catalog.setval('public.posts_id_seq', 33, true);


--
-- Name: stars_map_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pharmashare_db_user
--

SELECT pg_catalog.setval('public.stars_map_id_seq', 11, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: pharmashare_db_user
--

SELECT pg_catalog.setval('public.users_id_seq', 7, true);


--
-- Name: likes_map likes_map_pkey; Type: CONSTRAINT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.likes_map
    ADD CONSTRAINT likes_map_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: stars_map stars_map_pkey; Type: CONSTRAINT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.stars_map
    ADD CONSTRAINT stars_map_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_user_name_key; Type: CONSTRAINT; Schema: public; Owner: pharmashare_db_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_user_name_key UNIQUE (user_name);


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON SEQUENCES TO pharmashare_db_user;


--
-- Name: DEFAULT PRIVILEGES FOR TYPES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TYPES TO pharmashare_db_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON FUNCTIONS TO pharmashare_db_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: -; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TABLES TO pharmashare_db_user;


--
-- PostgreSQL database dump complete
--

\unrestrict mzO22WzuIh3SdaOmZvIkIVsMaoEOsdPfTLbB94NfRCbqeV7uTMYsyBvYFIfDqep

