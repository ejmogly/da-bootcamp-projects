/*
*************************************
초급문제 13개입니다. 가벼운 마음으로 풀어봅시다!
*************************************
*/
USE lovepizza;
-- 초급 1. pizzas 테이블에서 가장 비싼 피자의 가격을 구하세요.
SELECT 
    MAX(price)
FROM
    pizzas;

-- 초급 2. order_details 테이블에서 수량(quantity)이 3이상 5이하인 주문 내역을 모두 조회하세요.
SELECT 
    *
FROM
    order_details
WHERE
    quantity >= 3 AND quantity <= 5;

-- 초급 3. orders 테이블에서 2015년 3월에 발생한 총 주문 건수를 구하세요.
SELECT 
    COUNT(*)
FROM
    orders
WHERE
    date LIKE '%2015-03%';

-- 초급 4. orders 테이블에서 2015년 6월 이후 오전(자정부터 정오 전까지)에 주문된 내역만 조회하세요.
SELECT 
    *
FROM
    orders
WHERE
    date >= '2015-06-01'
        AND (time >= '00:00:00'
        AND time <= '12:00:00');

-- 초급 5. pizzas 테이블에서 가격이 20보다 큰 피자 정보를 조회하고, 비싼 가격 순으로 정렬해주세요.
SELECT 
    *
FROM
    pizzas
WHERE
    price > 20
ORDER BY price DESC;

-- 초급 6. pizza_types 테이블에서 이름에 ‘Cheese’ 혹은 'Chicken'이 포함된 피자 종류를 조회하세요.
SELECT 
    *
FROM
    pizza_types
WHERE
    name LIKE '%Cheese%'
        OR name LIKE '%Chicken%';

-- 초급 7. orders 테이블에서 주말(토요일, 일요일)에 발생한 주문만 조회하세요.
SELECT 
    *
FROM
    orders
WHERE
    DAYOFWEEK(date) IN (1 , 7);

-- 초급 8. pizzas 테이블에서 피자 크기별(size) 평균 가격을 구하세요.
SELECT 
    size, AVG(price)
FROM
    pizzas
GROUP BY size;

-- 초급 9. orders 테이블에서 각 달의 총 주문 수량을 구하세요.
SELECT 
    MONTH(date) AS month, COUNT(*) AS total_sales
FROM
    orders
GROUP BY MONTH(date);

-- 초급 10. order_details 테이블에서 각 피자(pizza_id)별로 주문된 건 수(order_id)를 보여주세요.
SELECT 
    pizza_id, COUNT(order_id) AS total_ordes
FROM
    order_details
GROUP BY pizza_id;

-- 초급 11. order_details 테이블에서 각 피자(pizza_id)별로 총 주문 수량을 구하세요.
SELECT 
    pizza_id, SUM(quantity) AS total
FROM
    order_details
GROUP BY pizza_id;

-- 초급 12. pizzas 테이블에서 피자의 평균 가격보다 비싼 피자들을 조회하고 오름차순으로 정렬해주세요.
SELECT 
    *
FROM
    pizzas
WHERE
    price > (SELECT 
            AVG(price)
        FROM
            pizzas)
ORDER BY price;

-- 초급 13. pizzas 테이블에서 pizza_id의 길이가 10 미만인 피자의 종류만 order_details 테이블에서 조회하세요.(서브쿼리 사용)
SELECT 
    *
FROM
    order_details
WHERE
    pizza_id IN (SELECT 
            pizza_id
        FROM
            pizzas
        WHERE
            LENGTH(pizza_id) < 10);

/*
*************************************
잘 하셨습니다.
이번에는 중급 문제 8개입니다. 차근차근 해결해 나가봅시다.
*************************************
*/

-- 중급 1. orders 테이블에서 각 날짜별 총 주문 건수를 계산하고, 하루 총 주문 건수가 80건 이상인 날짜만 조회한 뒤, 주문 건수가 많은 순서대로 정렬하세요.
SELECT 
    date, COUNT(*) AS count
FROM
    orders
GROUP BY date
HAVING count >= 80
ORDER BY count DESC;

-- 중급 2. pizza_types 테이블에서 각 피자 카테고리별 피자 종류의 개수를 계산하고, 피자 종류가 3개 이상인 카테고리만 조회하여 피자 종류 개수 기준으로 오름차순 정렬하세요.
SELECT 
    category, COUNT(pizza_type_id) AS count
FROM
    pizza_types
GROUP BY category
HAVING count >= 3
ORDER BY count;

-- 중급 3. order_details 테이블에서 피자별(pizza_id) 총 주문 수량이 10개 이상인 피자만 조회하고, 총 주문 수량 기준으로 내림차순 정렬하세요.
SELECT 
    pizza_id, SUM(quantity) AS total
FROM
    order_details
GROUP BY pizza_id
HAVING total >= 10
ORDER BY total DESC;

-- 중급 4. pizzas 테이블에서 피자 ID와 크기(size)를 결합하여 새로운 컬럼(pizza_size_id)을 만들어 출력하세요. 예를 들어, pizza_id가 bbq_ckn_s이고 size가 S일 경우, bbq_ckn_s_S 형태로 출력됩니다.
SELECT 
    *, CONCAT(pizza_id, '_', size) AS pizza_size_id
FROM
    pizzas;

-- 중급 5. order_details 테이블에서 피자별 총 수익을 구하세요. (수익 = quantity * price)
SELECT 
    ord.pizza_id, SUM(ord.quantity * p.price)
FROM
    order_details ord
        LEFT JOIN
    pizzas p ON p.pizza_id = ord.pizza_id
GROUP BY pizza_id;

-- 중급 6. pizza_types 테이블에서 각 카테고리의 피자 종류 개수를 구하세요.
SELECT 
    category, COUNT(*) AS total
FROM
    pizza_types
GROUP BY category;

-- 중급 7. pizzas 테이블에서 가격이 15보다 크면 'Expensive', 그렇지 않으면 'Affordable'로 표시하는 컬럼을 추가하여 조회하세요.
SELECT 
    *,
    IF(price > 15,
        'Expensive',
        'Affordable') AS mind
FROM
    pizzas; 

-- 중급 8. 날짜별로 피자 주문 건수와 총 주문 수량을 구하세요.
SELECT 
    o.date, COUNT(order_details_id), SUM(quantity)
FROM
    order_details ord
        LEFT JOIN
    orders o ON ord.order_id = o.order_id
GROUP BY o.date;

/*
*************************************
정말 잘 하셨습니다.
마지막 고급 문제 7개입니다. 지금까지 학습한 내용 바깥의 범위가 필요할 수도 있습니다.
적극적으로 구글링하여 문제를 해결해보아도 좋습니다.
*************************************
*/

-- 고급 1. orders 테이블에서 시간대(time 컬럼)를 기준으로 오전(06:00~11:59), 오후(12:00~17:59), 저녁(18:00~23:59) 중 어느 시간대에 주문이 가장 많이 이루어졌는지 구하세요.
SELECT 
    time_zone, COUNT(*) AS total_sale
FROM
    (SELECT 
        *,
            CASE
                WHEN time BETWEEN '06:00:00' AND '11:59:00' THEN '오전'
                WHEN time BETWEEN '12:00:00' AND '17:59:00' THEN '오후'
                WHEN time BETWEEN '18:00:00' AND '23:59:00' THEN '저녁'
                ELSE NULL
            END AS time_zone
    FROM
        orders) t
GROUP BY time_zone
ORDER BY total_sale DESC
LIMIT 1;
-- 고급 2. order_details와 pizzas 테이블을 JOIN하여 피자 크기별 총 수익을 계산하고, 크기별 수익을 출력하세요.
SELECT 
    size, SUM(quantity * price) AS total
FROM
    order_details ord
        JOIN
    pizzas p ON p.pizza_id = ord.pizza_id
GROUP BY size;

-- 고급 3. pizza_types 테이블에서 재료(ingredients)의 단어 수를 계산하여 각 피자 타입의 재료가 몇 가지인지 출력하세요. 
SELECT 
    *,
    1 + LENGTH(ingredients) - LENGTH(REPLACE(ingredients, ',', '')) AS total_ing
FROM
    pizza_types;

-- 고급 4. order_details, pizzas, pizza_types 테이블을 JOIN하여 각 피자 종류의 총 수익을 계산하고, 수익이 높은 순서대로 출력하세요.
SELECT 
    p.pizza_type_id, SUM(quantity * price) AS total_sales
FROM
    order_details ord
        JOIN
    pizzas p ON p.pizza_id = ord.pizza_id
        JOIN
    pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pizza_type_id
ORDER BY total_sales DESC;  

-- 고급 5. order_details, pizzas, pizza_types 테이블을 JOIN하여 카테고리별 총 판매 수량을 계산하고, 가장 많이 팔린 카테고리를 출력하세요.
SELECT 
    pt.category, SUM(quantity) AS total
FROM
    order_details ord
        JOIN
    pizzas p ON p.pizza_id = ord.pizza_id
        JOIN
    pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY category
ORDER BY total DESC
LIMIT 1;

-- 고급 6. 월별로 피자 주문 수량이 가장 많았던 날(date)의 날짜와 총 수량을 출력해주세요.
select date, cnt from(SELECT 
    o.date, SUM(quantity) AS cnt, dense_rank() over(partition by month(date) order by SUM(quantity) desc)as order_rank
FROM
    order_details ord
        JOIN
    orders o ON o.order_id = ord.order_id
GROUP BY date)as t where order_rank=1;

-- 고급 7. 피자별(pizza_id) 판매 수량 순위에서 피자별 판매 수량 상위 10% 이내에 들기 위해서는 최소 몇 판이 판매가 이루어졌는지 구해주세요.
select min(qnt) from(select pizza_id, sum(quantity)as qnt, percent_rank() over(order by sum(quantity) desc) as per_rank from order_details group by pizza_id) t where per_rank<=0.1;


