-- Active: 1792402677809@@class.mmcs.sfedu.ru@5432
begin;

--1. Создайте процедуры для добавления новых данных в таблицу AGENT.
create or replace procedure add_agent(
	p_id agent.id_ag%type,
	p_name agent.name_ag%type,
	p_town agent.town%type,
	p_phone agent.phone%type
)
language plpgsql as $$
begin
	insert into agent (id_ag, name_ag, town, phone)
	values (p_id, p_name, p_town, p_phone);
end;
$$;

create or replace procedure add_agent(
	p_id agent.id_ag%type,
	p_name agent.name_ag%type
)
language plpgsql as $$
begin
	call add_agent(p_id, p_name, null, null);
end;
$$;

--2. Создайте процедуру изменения остатка на складе. Параметры — название товара, название склада, новое количество. Предположить, что параметры заданы правильно.
create or replace procedure rest_update(
	p_goods goods.nomenclature%type,
	p_wh warehouse.name%type,
	p_quantity goods_wh.quantity%type
)
language plpgsql as $$
begin
	update goods_wh gw
	set quantity = p_quantity
	where gw.id_goods = (select g.id_goods from goods g where g.nomenclature = p_goods)
		and gw.id_wh = (select w.id_wh from warehouse w where w.name = p_wh);
end;
$$;

--3. Создайте процедуру удаления остатка со склада (должна быть удалена запись из таблицы GOODS_WH). Параметры — название товара, название склада. Предположить, что параметры могут быть заданы неправильно.
create or replace procedure rest_delete(
	p_goods goods.nomenclature%type,
	p_wh warehouse.name%type
)
language plpgsql as $$
declare
	v_goods_id goods.id_goods%type;
	v_wh_id warehouse.id_wh%type;
begin
	select g.id_goods into strict v_goods_id
	from goods g
	where g.nomenclature = p_goods;

	select w.id_wh into strict v_wh_id
	from warehouse w
	where w.name = p_wh;

	delete from goods_wh gw
	where gw.id_goods = v_goods_id and gw.id_wh = v_wh_id;

	if not found then
		raise exception 'Для товара «%» на складе «%» нет записи об остатке', p_goods, p_wh;
	end if;
exception
	when no_data_found then
		raise exception 'Товар «%» или склад «%» не найден', p_goods, p_wh;
	when too_many_rows then
		raise exception 'Название товара «%» или склада «%» неоднозначно', p_goods, p_wh;
end;
$$;


--4. Изменить процедуру REST_INSERT так, чтобы дополнительно контролировалось условие — комбинация id_goods, id_wh в таблице GOODS_WH должна быть уникальной.
create unique index if not exists goods_wh_goods_warehouse_uidx
	on goods_wh (id_goods, id_wh);

create or replace procedure rest_insert(
	goods goods.nomenclature%type,
	wh warehouse.name%type,
	qt goods_wh.quantity%type
)
language plpgsql as $$
declare
	v_goods_id goods.id_goods%type;
	v_wh_id warehouse.id_wh%type;
	v_error text;
begin
	begin
		select g.id_goods into strict v_goods_id
		from goods g
		where g.nomenclature = rest_insert.goods;

		select w.id_wh into strict v_wh_id
		from warehouse w
		where w.name = rest_insert.wh;
	exception
		when no_data_found then
			v_error := 'Товар или склад не найден';
		when too_many_rows then
			v_error := 'Неоднозначное название товара или склада';
	end;

	if v_error is null then
		if qt is null or qt <= 0 then
			v_error := 'Количество должно быть положительным';
		else
			insert into goods_wh (id_goods, id_wh, quantity)
			values (v_goods_id, v_wh_id, qt)
			on conflict (id_goods, id_wh) do nothing;

			if not found then
				v_error := 'Запись об остатке уже существует';
			end if;
		end if;
	end if;

	if v_error is not null then
		insert into log_file (inform)
		values ('REST_INSERT: ' || v_error);
		commit;
		raise exception '%', v_error;
	end if;
end;
$$;

commit;

--5. Данные в таблицах могут быть такими, что процедура всегда будет выдавать ошибку. Для полной отладки внесите изменения в таблицы так, чтобы проверить все случаи.
begin;

create or replace procedure inventory_5(
	id_goods goods.id_goods%type,
	id_wh warehouse.id_wh%type,
	user_name log_file.user_name%type
)
language plpgsql as $$
declare
	v_actual numeric;
	v_expected numeric;
	v_result text;
begin
	select coalesce((
		select gw.quantity from goods_wh gw
		where gw.id_goods = inventory_5.id_goods and gw.id_wh = inventory_5.id_wh
	), 0) into v_actual;

	select coalesce(
		sum(o.quantity) filter (where o.typeop = 'R'), 0
	) - coalesce(
		sum(o.quantity) filter (where o.typeop = 'A'), 0
	) into v_expected
	from operation o
	where o.id_goods = inventory_5.id_goods and o.id_wh = inventory_5.id_wh;

	if v_actual = v_expected then
		v_result := format('Остаток соответствует операциям: %s', v_actual);
	else
		v_result := format('Расхождение остатков: фактический %s, расчётный %s', v_actual, v_expected);
	end if;

	insert into log_file (inform, user_name, ddata)
	values (v_result, inventory_5.user_name, current_date);
	raise notice '%', v_result;
end;
$$;

call add_agent('LAB8_AG', 'Контрагент ЛР8');

insert into goods (id_goods, nomenclature, measure)
values ('LAB8_G', 'Товар ЛР8', 'шт');

insert into warehouse (id_wh, name)
values ('LAB8_W', 'Склад ЛР8');

insert into operation (id_goods, id_ag, id_wh, typeop, quantity, op_date)
values ('LAB8_G', 'LAB8_AG', 'LAB8_W', 'R', 15, current_date),
	('LAB8_G', 'LAB8_AG', 'LAB8_W', 'A', 5, current_date);

call rest_insert('Товар ЛР8', 'Склад ЛР8', 10);
call inventory_5('LAB8_G', 'LAB8_W', 'lab8_test');

call rest_update('Товар ЛР8', 'Склад ЛР8', 8);
call inventory_5('LAB8_G', 'LAB8_W', 'lab8_test');

call rest_update('Товар ЛР8', 'Склад ЛР8', 12);
call inventory_5('LAB8_G', 'LAB8_W', 'lab8_test');

delete from operation o
where o.id_goods = 'LAB8_G' and o.id_wh = 'LAB8_W';

call inventory_5('LAB8_G', 'LAB8_W', 'lab8_test');

call rest_delete('Товар ЛР8', 'Склад ЛР8');
call inventory_5('LAB8_G', 'LAB8_W', 'lab8_test');

select l.inform, l.user_name, l.ddata
from log_file l
where l.user_name = 'lab8_test';

rollback;

--6. Измените (или создайте по аналогии новую) процедуру INVENTORY, которая будет уточнять результаты инвентаризации. Уточнение должно для случая ошибки разделять ситуации «недостача на складе» и «неучтённый остаток на складе».
create or replace procedure inventory_6(
	id_goods goods.id_goods%type,
	id_wh warehouse.id_wh%type,
	user_name log_file.user_name%type
)
language plpgsql as $$
declare
	v_actual numeric;
	v_expected numeric;
	v_result text;
begin
	select coalesce((
		select gw.quantity from goods_wh gw
		where gw.id_goods = inventory_6.id_goods and gw.id_wh = inventory_6.id_wh
	), 0) into v_actual;

	select coalesce(
		sum(o.quantity) filter (where o.typeop = 'R'), 0
	) - coalesce(
		sum(o.quantity) filter (where o.typeop = 'A'), 0
	) into v_expected
	from operation o
	where o.id_goods = inventory_6.id_goods and o.id_wh = inventory_6.id_wh;

	if v_actual = v_expected then
		v_result := format('Остаток соответствует операциям: %s', v_actual);
	elsif v_actual < v_expected then
		v_result := format('Недостача на складе: %s', v_expected - v_actual);
	else
		v_result := format('Неучтённый остаток на складе: %s', v_actual - v_expected);
	end if;

	insert into log_file (inform, user_name, ddata)
	values (v_result, inventory_6.user_name, current_date);
	raise notice '%', v_result;
end;
$$;

--7. Измените (или создайте по аналогии новую) процедуру INVENTORY, которая будет дополнительно в начале работы записывать в LOG_FILE информацию о начале инвентаризации с указанием названия склада и названия товара.
create or replace procedure inventory_7(
	id_goods goods.id_goods%type,
	id_wh warehouse.id_wh%type,
	user_name log_file.user_name%type
)
language plpgsql as $$
declare
	v_goods_name goods.nomenclature%type;
	v_wh_name warehouse.name%type;
	v_actual numeric;
	v_expected numeric;
	v_result text;
begin
	select g.nomenclature into strict v_goods_name
	from goods g
	where g.id_goods = inventory_7.id_goods;

	select w.name into strict v_wh_name
	from warehouse w
	where w.id_wh = inventory_7.id_wh;

	insert into log_file (inform, user_name, ddata)
	values (format('Начало инвентаризации: %s, %s', trim(v_wh_name), trim(v_goods_name)),
		inventory_7.user_name, current_date);

	select coalesce((
		select gw.quantity from goods_wh gw
		where gw.id_goods = inventory_7.id_goods and gw.id_wh = inventory_7.id_wh
	), 0) into v_actual;

	select coalesce(
		sum(o.quantity) filter (where o.typeop = 'R'), 0
	) - coalesce(
		sum(o.quantity) filter (where o.typeop = 'A'), 0
	) into v_expected
	from operation o
	where o.id_goods = inventory_7.id_goods and o.id_wh = inventory_7.id_wh;

	if v_actual = v_expected then
		v_result := format('Остаток соответствует операциям: %s', v_actual);
	else
		v_result := format('Расхождение остатков: фактический %s, расчётный %s', v_actual, v_expected);
	end if;

	insert into log_file (inform, user_name, ddata)
	values (v_result, inventory_7.user_name, current_date);
	raise notice '%', v_result;
end;
$$;

--8. Дополните процедуру из примера 4 так, чтобы она перед выдачей информации в случае ошибки проверяла, есть ли вообще операции для заданных товара и склада.
create or replace procedure inventory(
	id_goods goods.id_goods%type,
	id_wh warehouse.id_wh%type,
	user_name log_file.user_name%type
)
language plpgsql as $$
declare
	v_actual numeric;
	v_expected numeric;
	v_result text;
	cur_op record;
begin
	select coalesce((
		select gw.quantity from goods_wh gw
		where gw.id_goods = inventory.id_goods and gw.id_wh = inventory.id_wh
	), 0) into v_actual;

	select coalesce(
		sum(o.quantity) filter (where o.typeop = 'R'), 0
	) - coalesce(
		sum(o.quantity) filter (where o.typeop = 'A'), 0
	) into v_expected
	from operation o
	where o.id_goods = inventory.id_goods and o.id_wh = inventory.id_wh;

	if v_actual = v_expected then
		v_result := format('Остаток соответствует операциям: %s', v_actual);
	else
		v_result := format('Расхождение остатков: фактический %s, расчётный %s', v_actual, v_expected);
	end if;

	insert into log_file (inform, user_name, ddata)
	values (v_result, inventory.user_name, current_date);
	raise notice '%', v_result;

	if v_actual <> v_expected then
		if exists (
			select 1 from operation o
			where o.id_goods = inventory.id_goods and o.id_wh = inventory.id_wh
		) then
			insert into log_file (inform, user_name, ddata)
			values ('Расшифровка по операциям', inventory.user_name, current_date);

			for cur_op in
				select o.id, o.op_date, o.typeop, o.quantity
				from operation o
				where o.id_goods = inventory.id_goods and o.id_wh = inventory.id_wh
				order by o.op_date, o.id
			loop
				insert into log_file (inform, user_name, ddata)
				values (format('Операция №%s, тип %s, количество %s',
					cur_op.id, cur_op.typeop, cur_op.quantity), inventory.user_name, cur_op.op_date);
			end loop;
		else
			insert into log_file (inform, user_name, ddata)
			values ('Для товара на этом складе операций нет', inventory.user_name, current_date);
		end if;
	end if;
end;
$$;
