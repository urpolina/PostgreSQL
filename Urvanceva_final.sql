-- 1. В каких городах больше одного аэропорта?
--
-- Из таблицы airports группируем города и считаем для каждого города количество аэропортов в нем, 
-- в результат выводим те где выполняется условие, что количество аэропортов для города больше 1.

select city, count (airport_code)
from airports
group by 1
having count (airport_code) > 1

-- 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?
-- - Подзапрос
--
-- В подзапросе из таблицы aircrafts сортируем по дальности перелета от большего к меньшему,
-- выводим одно первое значение. 
-- Присоединяем таблицы с перелетами и аэропортами. Таблицу с аэропортами присоединяем по коду аэропорта вылета, 
-- следуя логике, что если самолет прибыл в аэропорт, то из него же он и вылетит в дальнейшем.
-- Выводим название аэропортов, из которых вылетает самолет с максимальной дальностью перелета.
 
select a.airport_name  
from (	select aircraft_code, "range"
		from aircrafts
		order by 2 desc limit 1) t 
join flights f on t.aircraft_code = f.aircraft_code
join airports a on f.departure_airport = a.airport_code 
group by 1

-- 3. Вывести 10 рейсов с максимальным временем задержки вылета
-- - Оператор LIMIT
--
-- Из таблицы flights вычисляем время задержки, без учета нулевых значений колонки фактического времени вылета.
-- Сортируем по времени задержки от большего к меньшему и выводим 10 первых значений.

select flight_no, scheduled_departure, actual_departure, actual_departure - scheduled_departure as delay
from flights 
where actual_departure is not null
order by 4 desc limit 10

-- 4. Были ли брони, по которым не были получены посадочные талоны?
-- - Верный тип JOIN
--
-- Таблицу bookings соединяем с tickets и boarding_passes используя left join, так как нам нужны все брони.
-- Выводим значения брони, где номер посадочного талона отсутствует.
-- Брони, по которым не были получены посадочные талоны = 127899

select b.book_ref, bp.boarding_no  
from bookings b 
left join tickets t on b.book_ref = t.book_ref 
left join boarding_passes bp on t.ticket_no = bp.ticket_no 
where bp.boarding_no is null

-- 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
-- Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого
-- аэропорта на каждый день. Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже 
-- вылетело из данного аэропорта на этом или более ранних рейсах в течении дня.
-- - Оконная функция
-- - Подзапросы или/и cte
--
-- Создаем cte по общему количеству мест в кажой модели самолета из таблицы seats.
-- Создаем cte по количеству мест в каждои перелете из таблицы boarding_passes.
-- С помощью оконной функции считаем суммарное накопление количества вывезенных пассажиров по количеству мест
-- для каждого аэропорта, сортируем по дню вылета, используем таблицы flights и boarding_passes.
-- Количество свободных мест выводим, высчитывая разницу между общим количеством мест и количеством мест, 
-- на которые выданы посадочные талоны в каждом перелете. Процент свободных мест считаем как отношение разницы
-- к общему количеству мест.

--explain analyze 
with cte1 as (select s.aircraft_code, count(s.seat_no)
				from seats s 
				group by 1),
	cte2 as (select bp.flight_id, count(bp.seat_no) 
				from boarding_passes bp 
				group by 1)
select t.flight_id,
		c1.count - c2.count as "free", 
		(c1.count - c2.count)*100/c1.count as "%%", 
		t.actual_departure,
		t.departure_airport,
		t.all_passengers
from (select f.flight_id, f.actual_departure, f.departure_airport, f.aircraft_code,
			sum(count (bp.seat_no)) over (partition by f.departure_airport, f.actual_departure order by f.actual_departure) as all_passengers
		from flights f 
		join boarding_passes bp on f.flight_id = bp.flight_id
		group by 1) t
join cte1 c1 on t.aircraft_code = c1.aircraft_code
join cte2 c2 on t.flight_id = c2.flight_id

-- 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.
-- - Подзапрос или окно
-- - Оператор ROUND
--
-- Из таблицы flights с помощью оконной функции вычисляем общее количество перелетов, группировкой по коду самолета
-- вычисляем количество перелетов для кажого типа самолета.
-- Находим процентное соотношение перелетов по типам самолетов от общего количества, функцией round округляем до сотых.

select t.aircraft_code, round(aircraft_flights*100/total, 2) 
from (	select f.aircraft_code,
				count(f.flight_id) as aircraft_flights,
				sum(count (f.flight_id)) over () as total
				from flights f
		group by f.aircraft_code) t


-- 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?
-- - CTE
--
-- Создаем два cte, один отбирает из таблицы ticket_flights перелеты с категорией бизнес, второй - с категорией эконом.
-- Чтобы вывести города берем таблицу flights, присоединяем к ней таблицу airports и два cte. 
-- В результат выводим название городов при условии, что стоимость бизнеса меньше эконома.

--explain analyze 
with cte1 as (	select *  
				from ticket_flights  
				where fare_conditions = 'Business'),
	cte2 as (	select *  
				from ticket_flights  
				where fare_conditions = 'Economy')
select a.city
from flights f
join airports a on f.arrival_airport = a.airport_code 
join cte1 b on f.flight_id = b.flight_id
join cte2 e on f.flight_id = e.flight_id
where b.amount < e.amount
group by 1

-- 8. Между какими городами нет прямых рейсов?
-- - Декартово произведение в предложении FROM
-- - Самостоятельно созданные представления (если облачное подключение, то без представления)
-- - Оператор EXCEPT

-- Создаем представление, в котором находим все сочетания городов в существующих в базе данных перелетах из таблицы
-- flights, дважды присоединяем таблицу airports, с помощью оператора ">" отбираем пары городов, которые не совпадают
-- между собой, а также убираем зеркальные пары городов по типу город1|город2 = город2|город1.
-- Декартовым произведении в предложении from соединяем таблицу airports с самой собой чтобы получить все возможные
-- сочетания городов, также оператором ">" оставляем только уникальные пары городов.
-- Оператором except из всех пар городов исключаем пары городов, полученные из данных о перелетах.

create view airpots_2 as
select a.city as city1, a2.city as city2
from flights f 
join airports a on f.departure_airport = a.airport_code
join airports a2 on f.arrival_airport = a2.airport_code 
where a.city > a2.city
group by 1,2

select a1.city as city1, a2.city as city2
from airports a1, airports a2
where a1.city > a2.city
except
select * from airpots_2

-- 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью
-- перелетов  в самолетах, обслуживающих эти рейсы.
-- - Оператор RADIANS или использование sind/cosd
-- - CASE 

-- К таблице flights присоединяем дважды таблицу airports по коду аэропорта вылета и коду аэропорта прилета и присоединяем
-- таблицу aircrafts по коду самолета. С помощью оператора ">" отбираем уникальные пары аэропортов. Выводим информацию о коде
-- аэропорта вылета и коде аэропорта прилета, коде самолета, осуществившем перелет между данными аэропортами и его допустимую
-- максимальную дальность. По формуле находим расстояние между аэропортами, используем sind/cosd, а также acos чтобы получить 
-- растояние в радианах. Берем данную выборку в подзапрос, чтобы использовать алиас для формулы в операторе case. 
-- В case прописываем условие для случаев когда растояние между аэропортами больше/меньше/равно допустимой максимальной дальности
-- самолета.

select t.airport1, t.airport2, 
		case 
			when distance > aircraft_range then 'bad'
			when distance < aircraft_range then 'good'
			when distance = aircraft_range then 'some times may be good, some times may be shit'
		end c
from (
		select ad.airport_code as airport1, aa.airport_code as airport2, f.aircraft_code, a."range" as aircraft_range,
				acos(sind(ad.latitude)*sind(aa.latitude)+cosd(ad.latitude)*cosd(aa.latitude)*cosd(ad.longitude-aa.longitude))*6371 as distance
				from flights f 
		join airports ad on f.departure_airport = ad.airport_code
		join airports aa on f.arrival_airport = aa.airport_code
		join aircrafts a on f.aircraft_code = a.aircraft_code 
		where f.departure_airport > f.arrival_airport
		group by 1, 2, 3, 4) t
