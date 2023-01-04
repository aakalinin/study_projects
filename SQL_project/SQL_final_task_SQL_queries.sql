set search_path = bookings



-- Запрос № 1. В каких городах больше одного аэропорта? --

select city as "Город", count(airport_code) as "Количество аэропортов"
from airports
group by city
having count(airport_code) > 1
order by 2 desc



-- Запрос № 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? (Подзапрос) ==

select distinct airport_name as "Название аэропорта", airport_code as "Код аэропорта", city as "Город" 
from airports a 
join flights f on a.airport_code = f.departure_airport 
join aircrafts a2 on a2.aircraft_code = f.aircraft_code
where a2.aircraft_code = (select a3.aircraft_code from aircrafts a3 order by range desc limit 1)
order by 3, 1



-- Запрос № 3. Вывести 10 рейсов с максимальным временем задержки вылета (Оператор LIMIT) --

select flight_id, flight_no, departure_airport, arrival_airport, (actual_departure - scheduled_departure) as "Departure delay"
from flights
where status in ('Departed', 'Arrived') 
order by 5 desc
limit 10



-- Запрос № 4. Были ли брони, по которым не были получены посадочные талоны? (Верный тип JOIN) -- 

select count(b.book_ref) 
from bookings b 
left join tickets t on b.book_ref = t.book_ref
left join boarding_passes bp on t.ticket_no = bp.ticket_no 
where bp.boarding_no is null
 


-- Запрос № 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
-- Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
-- Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом илиболее ранних рейсах в течении дня
-- (Оконная функция, Подзапросы или/и cte) --

with cte_ts as
    (
    select flight_id, count(seat_no) as taken_seats 
    from boarding_passes bp 
    group by flight_id 
    ),
  cte_os as 
    (
    select aircraft_code, count(s.seat_no) as overall_seats
    from seats s
    group by aircraft_code 
    )
select f.flight_id as "id перелета", f.flight_no as "Номер рейса", departure_airport as "Аэропорт вылета",
	actual_departure as "Время вылета (факт)", overall_seats as "Всего мест", overall_seats - taken_seats as "Cвободно мест",
	(round (((overall_seats - taken_seats)::numeric / overall_seats::numeric), 2) * 100) as "% свободных мест",
    	sum (taken_seats) over (partition by departure_airport, date_trunc('day', actual_departure) order by actual_departure) as "К-во вывез. пасс-ров (накоп. ежедн.)"
from cte_ts 
join flights f on cte_ts.flight_id = f.flight_id 
join cte_os on cte_os.aircraft_code = f.aircraft_code 
join airports a2 on f.departure_airport = a2.airport_code 
order by departure_airport, actual_departure asc



-- Запрос № 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества (Подзапрос или окно, Оператор ROUND) --

select distinct on (a.model) a.model as "Тип самолета",
		round((count( f.flight_id) over(partition by a.model)::numeric / count(f.flight_id) over()::numeric),2) * 100 as "Доля перелетов, %"
from aircrafts a
left join flights f using (aircraft_code)
group by 1, f.flight_id 
order by 1



-- Запрос № 7. Были ли города, в которые можно добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета? (CTE) --

with cte_1 as (
		select tf.flight_id, tf.fare_conditions, tf.amount as Amount_Business
		from ticket_flights tf 
		where tf.fare_conditions = 'Business'
		),
     cte_2 as (
	 	select tf2.flight_id, tf2.fare_conditions, tf2.amount as Amount_Economy
	 	from ticket_flights tf2
	 	where tf2.fare_conditions = 'Economy'
	 	)
select city as "Город", flight_no as "№ рейса (перелета)", Amount_Economy as "Стоимость эконом-класса", Amount_Business as "Стоимость бизнес-класса"
from flights f 
join cte_1 on f.flight_id = cte_1.flight_id 
join cte_2 on f.flight_id = cte_2.flight_id
join airports a on a.airport_code = f.arrival_airport  
where Amount_Economy > Amount_Business
group by 1, 2, 3, 4



-- Запрос № 8. Между какими городами нет прямых рейсов? (Декартово произведение в предложении FROM, Самостоятельно созданные представления (если облачное подключение, то без представления), Оператор EXCEPT) --

create view cities_combination as
  (select a.city as dep_city, a2.city as arr_city
  from airports a, airports a2 
  where a.city > a2.city)

select * 
from cities_combination
except
select departure_city, arrival_city 
from routes
order by 1, 2



-- Запрос № 9.  Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов в самолетах, обслуживающих эти рейсы * (Оператор RADIANS или использование sind/cosd, CASE) --

with cte_departure_coordinates as
  (
  select flight_id, departure_airport, longitude as departure_longitude, latitude as departure_latitude
  from flights f
  join airports a on a.airport_code = f.departure_airport
  ),
     cte_arrival_coordinates as
  (
  select flight_id, arrival_airport, longitude as arrival_longitude, latitude as arrival_latitude
  from flights f2
  join airports a2 on a2.airport_code = f2.arrival_airport
  ),
     cte_combined as
  (
  select f3.flight_id, aircraft_code, f3.departure_airport, departure_longitude, departure_latitude, f3.arrival_airport, arrival_longitude, arrival_latitude,
  			round((6371*(acos(sind(departure_latitude)*sind(arrival_latitude) + cosd(departure_latitude)*cosd(arrival_latitude)*cosd(departure_longitude - arrival_longitude))))::numeric,0) as distance_km
  from flights f3
  join cte_departure_coordinates on cte_departure_coordinates.flight_id = f3.flight_id 
  join cte_arrival_coordinates on cte_arrival_coordinates.flight_id = f3.flight_id 
  where f3.departure_airport = cte_departure_coordinates.departure_airport and f3.arrival_airport = cte_arrival_coordinates.arrival_airport
  )
select distinct on (departure_airport, arrival_airport) departure_airport, arrival_airport, 
   distance_km,
   range,
   case when distance_km <= a3.range then 'Enough range'
   else 'Not enough range'
   end as range_sufficiency
from cte_combined
join aircrafts a3 on a3.aircraft_code = cte_combined.aircraft_code 
order by 1,2
