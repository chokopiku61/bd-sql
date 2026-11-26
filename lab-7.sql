begin;

--1. Добавить в таблицу «Склады» 1–2 новых записи.
insert into warehouse (id_wh, name, town)
values ('L7_WH', 'Склад ЛР7', 'Ростов'),
	('L7_FREE', 'Резервный ЛР7', 'Азов');

--2. Добавить новые записи в таблицы «Остатки на складе» и «Операции». При добавлении использовать наименование товара, название склада и название агента.
insert into goods_wh (id_goods, id_wh, quantity)
values ((select g.id_goods from goods g where g.nomenclature = 'Папки'),
	(select w.id_wh from warehouse w where w.name = 'Склад ЛР7'), 40);

insert into operation (id_goods, id_ag, id_wh, typeop, quantity, price, op_date)
values ((select g.id_goods from goods g where g.nomenclature = 'Папки'),
	(select a.id_ag from agent a where a.name_ag = 'Астра'),
	(select w.id_wh from warehouse w where w.name = 'Склад ЛР7'),
	'R', 10, 120, current_date);

--3. Изменить в добавленных операциях цену товара и количество, используя наименование товара, название склада и название агента.
update operation o
set price = 130, quantity = 12
where o.id_goods = (select g.id_goods from goods g where g.nomenclature = 'Папки')
	and o.id_wh = (select w.id_wh from warehouse w where w.name = 'Склад ЛР7')
	and o.id_ag = (select a.id_ag from agent a where a.name_ag = 'Астра');

--4. Изменить во всех операциях по одному из агентов, заданному названием, цену товара.
update operation o
set price = 150
where o.id_ag = (select a.id_ag from agent a where a.name_ag = 'Астра');

--5. Удалить агентов, которые не выполнили ни одной операции.
delete from agent a
where not exists (select 1 from operation o where o.id_ag = a.id_ag);

--6. Удалить склады, на которых нет остатков и с которыми не было операций.
delete from warehouse w
where not exists (select 1 from goods_wh gw where gw.id_wh = w.id_wh)
	and not exists (select 1 from operation o where o.id_wh = w.id_wh);

--7. Найти товары, с которыми не было ни одной операции.
select g.id_goods, g.nomenclature
from goods g
where not exists (select 1 from operation o where o.id_goods = g.id_goods);

--8. Найти поставщиков, которые выполнили только одну операцию.
select a.id_ag, a.name_ag
from agent a
where a.id_ag in (
	select o.id_ag from operation o
	group by o.id_ag
	having count(*) = 1
);

--9. Найти товары, с которыми было больше всего операций. Добавьте операции так, чтобы в ответе получалось несколько товаров.
savepoint task_9;

with leaders as (
	select g.id_goods, count(o.id) as cnt,
		max(count(o.id)) over () as max_cnt
	from goods g
	left join operation o using (id_goods)
	group by g.id_goods
	order by cnt desc, g.id_goods
	limit 2
)
insert into operation (id_goods, id_ag, id_wh, typeop, quantity, price, op_date)
select l.id_goods,
	(select a.id_ag from agent a where a.name_ag = 'Астра'),
	(select w.id_wh from warehouse w where w.name = 'Склад ЛР7'),
	'R', 1, 1, current_date
from leaders l
cross join lateral generate_series(1, greatest(l.max_cnt, 1) - l.cnt);

select g.id_goods, g.nomenclature
from goods g
where g.id_goods in (
	select o.id_goods from operation o
	group by o.id_goods
	having count(*) >= all (select count(*) from operation group by id_goods)
);

rollback to savepoint task_9;
release savepoint task_9;

--10. Найти поставщиков, которые поставляли (операции A) папки по максимальной цене. Добавьте операции так, чтобы в ответе получалось несколько поставщиков.
savepoint task_10;

insert into agent (id_ag, name_ag)
values ('L7_PRICE', 'Поставщик ЛР7');

insert into operation (id_goods, id_ag, id_wh, typeop, quantity, price, op_date)
select g.id_goods, a.id_ag,
	(select w.id_wh from warehouse w where w.name = 'Склад ЛР7'),
	'A', 1,
	(select coalesce(max(o.price), 1) from operation o
		where o.id_goods = g.id_goods and o.typeop = 'A'),
	current_date
from goods g, agent a
where g.nomenclature = 'Папки' and a.name_ag in ('Астра', 'Поставщик ЛР7');

select a.id_ag, a.name_ag
from agent a
where a.id_ag in (
	select o.id_ag from operation o
	where o.typeop = 'A'
		and o.id_goods = (select g.id_goods from goods g where g.nomenclature = 'Папки')
		and o.price = (
			select max(o2.price) from operation o2
			where o2.typeop = 'A' and o2.id_goods = o.id_goods
		)
);

rollback to savepoint task_10;
release savepoint task_10;

--11. Найти поставщиков, которые работают более чем с одним складом.
select a.id_ag, a.name_ag
from agent a
where a.id_ag in (
	select o.id_ag from operation o
	group by o.id_ag
	having count(distinct o.id_wh) > 1
);

--12. Найти товары, с которыми работает только один поставщик. Добавьте поставщику несколько операций с одним товаром.
savepoint task_12;

insert into goods (id_goods, nomenclature, measure)
values ('L7_G', 'Товар ЛР7', 'шт');

insert into agent (id_ag, name_ag)
values ('L7_AG', 'Агент ЛР7');

insert into operation (id_goods, id_ag, id_wh, typeop, quantity, price, op_date)
values ('L7_G', 'L7_AG', 'L7_WH', 'A', 10, 100, current_date),
	('L7_G', 'L7_AG', 'L7_WH', 'A', 5, 105, current_date);

select g.id_goods, g.nomenclature
from goods g
where g.id_goods in (
	select o.id_goods from operation o
	group by o.id_goods
	having count(distinct o.id_ag) = 1
);

rollback to savepoint task_12;
release savepoint task_12;

--13. Найти товары, которые поставщик «Астра» поставлял наибольшее количество раз.
with astra_operations as (
	select o.id_goods from operation o
	where o.typeop = 'A'
		and o.id_ag = (select a.id_ag from agent a where a.name_ag = 'Астра')
)
select g.id_goods, g.nomenclature
from goods g
where g.id_goods in (
	select o.id_goods from astra_operations o
	group by o.id_goods
	having count(*) >= all (select count(*) from astra_operations group by id_goods)
);

--14. Не используя операцию соединения, составить список товаров на складе «Склад на Шолохова».
select g.id_goods, g.nomenclature
from goods g
where g.id_goods in (
	select gw.id_goods from goods_wh gw
	where gw.id_wh in (select w.id_wh from warehouse w where w.name = 'Склад на Шолохова')
);

--15. Не используя операцию соединения, составить список складов, на которые были поставки (операция A) товара «Бумага для факсов».
select w.id_wh, w.name
from warehouse w
where w.id_wh in (
	select o.id_wh from operation o
	where o.typeop = 'A'
		and o.id_goods in (select g.id_goods from goods g where g.nomenclature = 'Бумага для факсов')
);

rollback;
