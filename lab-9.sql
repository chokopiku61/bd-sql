--1. Написать функцию, которая для заданного кодом поставщика определяет количество его операций заданного типа (A или R). Найти поставщиков, которые выполнили больше операций типа R, чем поставщик «Надежный».
create or replace function agent_operation_count(
	p_agent_id agent.id_ag%type,
	p_type operation.typeop%type
)
returns bigint
language plpgsql stable as $$
begin
	return (
		select count(*) from operation o
		where o.id_ag = p_agent_id and o.typeop = p_type
	);
end;
$$;

select a.id_ag, a.name_ag
from agent a
where agent_operation_count(a.id_ag, 'R') > (
	select agent_operation_count(a2.id_ag, 'R')
	from agent a2
	where a2.name_ag = 'Надежный'
);

--2. Изменить функцию GOODSBYAGENT так, чтобы она возвращала ещё один параметр — код товара (id_goods).
create or replace function goodsbyagent_2(p_agent agent.name_ag%type)
returns table (id_goods goods.id_goods%type, goods goods.nomenclature%type, cnt bigint)
language plpgsql stable as $$
declare
	v_agent_id agent.id_ag%type;
begin
	v_agent_id := (select a.id_ag from agent a where a.name_ag = p_agent);

	if v_agent_id is null then
		raise exception 'Поставщик «%» не найден', p_agent;
	end if;

	return query
		select g.id_goods, g.nomenclature, count(*)
		from operation o
		join goods g on g.id_goods = o.id_goods
		where o.id_ag = v_agent_id
		group by g.id_goods, g.nomenclature
		order by g.nomenclature, g.id_goods;
end;
$$;

select a.id_goods, a.goods, g.measure, a.cnt
from goodsbyagent_2('Надежный') a
join goods g using (id_goods);

--3. Изменить функцию GOODSBYAGENT так, чтобы строки в формируемой таблице были пронумерованы.
create or replace function goodsbyagent_3(p_agent agent.name_ag%type)
returns table (row_no integer, namegoods goods.nomenclature%type, c_op bigint)
language plpgsql as $$
declare
	v_agent_id agent.id_ag%type;
	r record;
begin
	v_agent_id := (select a.id_ag from agent a where a.name_ag = p_agent);

	if v_agent_id is null then
		raise exception 'Поставщик «%» не найден', p_agent;
	end if;

	row_no := 0;

	for r in
		select g.nomenclature, count(*) as cnt
		from operation o
		join goods g on g.id_goods = o.id_goods
		where o.id_ag = v_agent_id
		group by g.id_goods, g.nomenclature
		order by g.nomenclature, g.id_goods
	loop
		row_no := row_no + 1;
		namegoods := r.nomenclature;
		c_op := r.cnt;

		insert into log_file (inform)
		values ('Найден товар ' || trim(namegoods));

		return next;
	end loop;
end;
$$;

--4. Изменить функцию GOODSBYAGENT так, чтобы она выдавала ещё одну строку в таблице «ИТОГО».
create or replace function goodsbyagent_4(p_agent agent.name_ag%type)
returns table (namegoods goods.nomenclature%type, c_op bigint)
language plpgsql as $$
declare
	v_agent_id agent.id_ag%type;
	v_total bigint := 0;
	r record;
begin
	v_agent_id := (select a.id_ag from agent a where a.name_ag = p_agent);

	if v_agent_id is null then
		raise exception 'Поставщик «%» не найден', p_agent;
	end if;

	for r in
		select g.nomenclature, count(*) as cnt
		from operation o
		join goods g on g.id_goods = o.id_goods
		where o.id_ag = v_agent_id
		group by g.id_goods, g.nomenclature
		order by g.nomenclature, g.id_goods
	loop
		namegoods := r.nomenclature;
		c_op := r.cnt;
		v_total := v_total + c_op;

		insert into log_file (inform)
		values ('Найден товар ' || trim(namegoods));

		return next;
	end loop;

	namegoods := 'ИТОГО';
	c_op := v_total;
	return next;
end;
$$;

--5. Написать функцию, которая по паре дат формирует таблицу с названиями товаров, для которых в этот период были операции. Для каждого товара указать приход (A) и расход (R) в двух столбцах.
create or replace function goods_turnover(p_date_from date, p_date_to date)
returns table (namegoods goods.nomenclature%type, income numeric, expense numeric)
language plpgsql stable as $$
begin
	return query
		select g.nomenclature,
			coalesce(sum(o.quantity) filter (where o.typeop = 'A'), 0),
			coalesce(sum(o.quantity) filter (where o.typeop = 'R'), 0)
		from operation o
		join goods g on g.id_goods = o.id_goods
		where o.op_date between p_date_from and p_date_to
		group by g.id_goods, g.nomenclature
		order by g.nomenclature, g.id_goods;
end;
$$;

--6. Написать функцию, которая по заданным названию таблицы (TNAME) и названию столбца (ST_NAME) определяет количество записей, для которых в этом столбце отсутствует значение.
create or replace function count_nulls(p_table regclass, p_column name)
returns bigint
language plpgsql stable as $$
declare
	v_count bigint;
begin
	execute format('select count(*) from %s where %I is null', p_table, p_column)
		into v_count;

	return v_count;
end;
$$;

--7. Написать функцию, которая по заданным названию таблицы (TNAME) и названиям двух столбцов (ST1_NAME, ST2_NAME) группирует данные по первому столбцу и возвращает минимум и максимум по второму.
create or replace function grouped_min_max(p_table regclass, p_group name, p_value name)
returns table (group_value text, min_value text, max_value text)
language plpgsql stable as $$
begin
	return query execute format(
		'select t.%1$I::text, min(t.%2$I)::text, max(t.%2$I)::text
		from %3$s t
		group by t.%1$I',
		p_group, p_value, p_table
	);
end;
$$;
