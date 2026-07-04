#mengambil semua kolom di dataset toko_peralatan_dapur

select *
from toko_peralatan_dapur.orders;

#membuat table baru supaya kolom tidak null

CREATE OR REPLACE TABLE toko_peralatan_dapur.orders_clean AS
SELECT *
FROM toko_peralatan_dapur.orders
WHERE order_id IS NOT NULL;

select *
from toko_peralatan_dapur.orders_clean;

#1. Berapa total ongkos kirim yang dibayarkan pelanggan di seluruh pesanan sepanjang 2025, dan berapa per pesanan?

select
sum(shipping_fee) AS total_ongkir,
avg(shipping_fee) AS rerata_ongkir,
from toko_peralatan_dapur.orders_clean
where extract(year from sales_date) = 2025;

#2. Sebutkan 5 produk dengan unit terjual terbanyak dari pesanan completed. Apakah daftarnya berbeda dengan top 5 produk berdasarkan revenue?

#top 5 unit terjual paling banyak dengan status complete
select product_name, sum(quantity) as total_unit
from toko_peralatan_dapur.orders_clean
where status_clean='complete'
group by product_name
order by total_unit desc
limit 5;

#top 5 unit dengan total revenue
select product_name, sum(total_sales) as total_revenue
from toko_peralatan_dapur.orders_clean
where status_clean='complete'
group by product_name
order by total_revenue desc
limit 5;


#3. Berapa jumlah pesanan dan total revenue completed selama Q4 (Oktober-Desember) 2025?

select
count(distinct order_id) as jumlah_pesanan,
sum(total_sales) as total_revenue
from toko_peralatan_dapur.orders_clean
where status_clean='complete' and sales_date between '2025-10-01' and '2025-12-31';

#4. Kota mana yang memiliki rata-rata ongkos kirim paling mahal, dan berapa selisihnya dengan kota yang paling murah?

with kota as (
  select city_clean, avg(shipping_fee) as rerata_ongkir
  from toko_peralatan_dapur.orders_clean
  group by city_clean
)

select
(select city_clean from kota order by rerata_ongkir desc limit 1) as kota_termahal,
(select max(rerata_ongkir) from kota) as ongkir_termahal,
(select city_clean from kota order by rerata_ongkir desc limit 1) as kota_termurah,
(select min(rerata_ongkir) from kota) as ongkir_termurah,
(select max(rerata_ongkir)-min(rerata_ongkir) from kota) as selisih;

#5. Berapa total nilai rupiah dari pesanan yang berstatus refund, dan berapa persentasenya terhadap gross sales setahun?

select
  sum(case when status_clean='refund' then total_sales else 0 end) as total_refund,
  sum(total_sales) as gross_sales,
  round(
    sum(case when status_clean='refund'then total_sales else 0 end)
    / sum(total_sales)*100,2
  ) as percent_refund
from toko_peralatan_dapur.orders_clean;

#6. Produk apa saja (5 teratas) dengan rata-rata quantity per pesanan tertinggi, dengan syarat minimal 50 pesanan completed?

select product_name,
count(distinct order_id) as jumlah_pesanan,
avg(quantity) as rerata_jumlah_per_pesanan
from toko_peralatan_dapur.orders_clean
where status_clean='complete'
group by product_name
having count(distinct order_id) >= 50
order by rerata_jumlah_per_pesanan desc
limit 5;

#7. Untuk masing-masing dari 3 kategori, bulan apa yang mencatat revenue completed tertinggi?

with per_bulan as (
  select
    category_clean,
    format_date('%Y-%m', sales_date) as bulan,
    sum(total_sales) as revenue
  from toko_peralatan_dapur.orders_clean
  where status_clean='complete'
  group by category_clean, bulan
),
ranked as (
  select *,
    row_number() over(partition by category_clean order by revenue desc) as sekarang
  from per_bulan
)
select category_clean, bulan, ranked.revenue
from ranked
where sekarang=1;

#8. Dari 57 produk yang ada, berapa produk teratas yang menyumbang 80% dari total revenue completed?

with revenue_per_produk as (
  select product_name, sum(total_sales) as revenue
  from toko_peralatan_dapur.orders_clean
  where status_clean='complete'
  group by product_name
),
cumulative as (
  select product_name,
  revenue,
  sum(revenue) over (order by revenue desc) as cumulative_revenue,
  sum(revenue) over () as total_revenue,
  row_number() over (order by revenue desc) as rank_product
from revenue_per_produk
)
select min(rank_product) as total_produk_80_persen
from cumulative
where cumulative_revenue >= 0.8 * total_revenue;

#9. Untuk pelanggan dengan lebih dari 5 pesanan completed, berapa rata-rata jeda hari antara dua pesanan berturut-turut, dan siapa pelanggan dengan jeda rata-rata tersingkat?

with pelanggan_valid as (
  select customer_name_clean
  from toko_peralatan_dapur.orders_clean
  where status_clean='complete'
  group by customer_name_clean
  having count(distinct order_id)=5
),
tanggal_urut as (
  select
    t.customer_name_clean,
    t.sales_date,
    lag(t.sales_date) over (partition by t.customer_name_clean order by t.sales_date) as tanggal_sebelumnya
  from toko_peralatan_dapur.orders_clean t
  join pelanggan_valid p on t.customer_name_clean = p.customer_name_clean
  where t.status_clean='complete'
),
jeda as(
  select
    customer_name_clean,
    avg(date_diff(sales_date, tanggal_sebelumnya, day)) as rerata_jeda_hari
  from tanggal_urut
  where tanggal_sebelumnya is not null
  group by customer_name_clean
)
select
  (select avg(rerata_jeda_hari) from jeda) as rerata_jeda_keseluruhan,
  (select customer_name_clean from jeda order by rerata_jeda_hari asc limit 1) as pelanggan_jeda_tersingkat,
  (select min(rerata_jeda_hari) from jeda) as jeda_tersingkat_hari;

#10. Produk apa yang memiliki refund rate tertinggi, dan berapa potensi revenue yang bisa diselamatkan jika refund rate produk tersebut turun ke rata-rata toko (~5%)?

with per_produk as(
  select
    product_name,
    countif(status_clean='refund') as jumlah_refund,
    count(*) as total_pesanan,
    sum(case when status_clean='refund' then total_sales else 0 end) as revenue_refund,
    safe_divide(countif(status_clean='refund'), count(*)) as refund_rate
  from toko_peralatan_dapur.orders_clean
  group by product_name
)
select
  product_name,
  refund_rate,
  revenue_refund,
  revenue_refund * greatest(refund_rate - 0.05,0)/refund_rate as potensi_revenue_selamat
from per_produk
order by refund_rate desc
limit 1;