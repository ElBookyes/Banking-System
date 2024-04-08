---ORACLE HW 2

--1. Създайте тригер, който автоматично обновява статуса на клиент в
--базата данни, когато общият баланс на техните сметки преминава
--определен праг. Ако общият баланс на клиента надхвърли
--100,000 лева, статусът му трябва да бъде обновен на "VIP
--клиент". Този тригер ще гарантира, че важните клиенти се
--идентифицират и обслужват по подходящ начин.

select *
from CLIENTS;

ALTER TABLE CLIENTS ADD STATUS VARCHAR2(200);

INSERT INTO CLIENTS (FIRST_NAME, LAST_NAME, EMAIL, STATUS)
VALUES ('Гопката', 'Гопов', 'gopka@example.com', 'Обикновен клиент');

INSERT INTO ACCOUNTS (CLIENT_ID, BALANCE)
SELECT CLIENT_ID, 678000
FROM CLIENTS
WHERE FIRST_NAME = 'Гопката' AND LAST_NAME = 'Гопов';

CREATE OR REPLACE TRIGGER Update_Client_Status
AFTER INSERT OR UPDATE OF BALANCE ON ACCOUNTS
FOR EACH ROW
DECLARE
    v_total_balance NUMBER;
BEGIN
    SELECT SUM(BALANCE)
    INTO v_total_balance
    FROM ACCOUNTS
    WHERE CLIENT_ID = :new.CLIENT_ID;

    IF v_total_balance > 100000 THEN
        UPDATE CLIENTS
        SET STATUS = 'VIP Client'
        WHERE CLIENT_ID = :new.CLIENT_ID;
    END IF;
END;
/




--2. Пренапишете функционалността от първия проект (домашна
--работа 1), която следи движението на служителите между отдели,
--да работи с тригери.


CREATE OR REPLACE TRIGGER Insert_Employee_Movement_Trigger
AFTER INSERT ON EMPLOYEE_MOVEMENT
FOR EACH ROW
BEGIN
    UPDATE EMPLOYEE
    SET DEPARTMENT = :new.DEPARTMENT_TO
    WHERE EMPLOYEE_ID = :new.EMPLOYEE_ID;
END;
/

CREATE OR REPLACE TRIGGER Update_Employee_Movement_Trigger
AFTER UPDATE OF DEPARTMENT_TO ON EMPLOYEE_MOVEMENT
FOR EACH ROW
BEGIN
    UPDATE EMPLOYEE
    SET DEPARTMENT = :new.DEPARTMENT_TO
    WHERE EMPLOYEE_ID = :new.EMPLOYEE_ID;
END;
/


--3. Създайте функции/процедури за извличане, добавяне, изтриване
--и промяна на данните на сметките.

CREATE OR REPLACE PROCEDURE Get_Account_Info(
    p_client_id IN NUMBER,
    p_account_info OUT SYS_REFCURSOR
)
AS
BEGIN
    OPEN p_account_info FOR
    SELECT *
    FROM ACCOUNTS
    WHERE CLIENT_ID = p_client_id;
END;
/


CREATE OR REPLACE PROCEDURE Add_Account(
    p_client_id IN NUMBER,
    p_balance IN NUMBER,
    p_currency IN VARCHAR2
)
AS
BEGIN
    INSERT INTO ACCOUNTS (CLIENT_ID, BALANCE, CURRENCY)
    VALUES (p_client_id, p_balance, p_currency);
    COMMIT;
END;
/


CREATE OR REPLACE PROCEDURE Delete_Account(
    p_account_id IN NUMBER
)
AS
BEGIN
    DELETE FROM ACCOUNTS
    WHERE ACCOUNT_ID = p_account_id;
    COMMIT;
END;
/


CREATE OR REPLACE PROCEDURE Update_Account_Balance(
    p_account_id IN NUMBER,
    p_new_balance IN NUMBER
)
AS
BEGIN
    UPDATE ACCOUNTS
    SET BALANCE = p_new_balance
    WHERE ACCOUNT_ID = p_account_id;
    COMMIT;
END;
/

--4. Създайте функции/процедури за извличане, добавяне, изтриване
--и промяна на данните на клиентите.

CREATE OR REPLACE PROCEDURE Get_Client_Info(
    p_client_id IN NUMBER,
    p_client_info OUT SYS_REFCURSOR
)
AS
BEGIN
    OPEN p_client_info FOR
    SELECT *
    FROM CLIENTS
    WHERE CLIENT_ID = p_client_id;
END;
/



CREATE OR REPLACE PROCEDURE Add_Client(
    p_first_name IN VARCHAR2,
    p_last_name IN VARCHAR2,
    p_extra_name IN VARCHAR2,
    p_address IN VARCHAR2,
    p_mobile_phone IN VARCHAR2,
    p_email IN VARCHAR2
)
AS
BEGIN
    INSERT INTO CLIENTS (FIRST_NAME, LAST_NAME, EXTRA_NAME, ADDRESS, MOBILE_PHONE, EMAIL)
    VALUES (p_first_name, p_last_name, p_extra_name, p_address, p_mobile_phone, p_email);
    COMMIT;
END;
/


CREATE OR REPLACE PROCEDURE Delete_Client(
    p_client_id IN NUMBER
)
AS
BEGIN
    DELETE FROM CLIENTS
    WHERE CLIENT_ID = p_client_id;
    COMMIT;
END;
/


CREATE OR REPLACE PROCEDURE Update_Client_Info(
    p_client_id IN NUMBER,
    p_address IN VARCHAR2,
    p_mobile_phone IN VARCHAR2,
    p_email IN VARCHAR2
)
AS
BEGIN
    UPDATE CLIENTS
    SET ADDRESS = p_address,
        MOBILE_PHONE = p_mobile_phone,
        EMAIL = p_email
    WHERE CLIENT_ID = p_client_id;
    COMMIT;
END;
/


--5 Създайте функционалност за изпращане на пари между
--отделните клиенти на банката.

CREATE OR REPLACE PROCEDURE Transfer_Money_Between_Clients(
    p_sender_id IN NUMBER,
    p_receiver_id IN NUMBER,
    p_amount IN NUMBER
)
AS
    v_sender_balance NUMBER;
BEGIN
    SELECT BALANCE INTO v_sender_balance
    FROM ACCOUNTS
    WHERE CLIENT_ID = p_sender_id;

    IF v_sender_balance >= p_amount THEN
        UPDATE ACCOUNTS
        SET BALANCE = BALANCE - p_amount
        WHERE CLIENT_ID = p_sender_id;

        UPDATE ACCOUNTS
        SET BALANCE = BALANCE + p_amount
        WHERE CLIENT_ID = p_receiver_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Transfer successful.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Insufficient balance for transfer.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/


--6. Имплементирайте модул за обработка на валутни курсове, като го
--прилагате при изпращане на преводи във валута, различна от
--валутите на сметките. (Примерно: Превод на 100 евро от Сметка
--А (левова) към сметка Сметка Б (доларова).

CREATE TABLE EXCHANGE_RATES (
    FROM_CURRENCY VARCHAR2(3),
    TO_CURRENCY VARCHAR2(3),
    RATE NUMBER,
    CONSTRAINT currency_exchange_pk PRIMARY KEY (FROM_CURRENCY, TO_CURRENCY)
);

CREATE OR REPLACE PROCEDURE Transfer_Money_With_Currency_Conversion(
    p_sender_id IN NUMBER,
    p_receiver_id IN NUMBER,
    p_amount IN NUMBER,
    p_currency VARCHAR2
)
AS
    v_sender_currency VARCHAR2(3);
    v_receiver_currency VARCHAR2(3);
    v_sender_balance NUMBER;
    v_amount_in_base_currency NUMBER;
    v_exchange_rate NUMBER;
    v_amount_converted NUMBER;
BEGIN
    SELECT CURRENCY INTO v_sender_currency
    FROM ACCOUNTS
    WHERE CLIENT_ID = p_sender_id;

    SELECT CURRENCY INTO v_receiver_currency
    FROM ACCOUNTS
    WHERE CLIENT_ID = p_receiver_id;

    SELECT BALANCE INTO v_sender_balance
    FROM ACCOUNTS
    WHERE CLIENT_ID = p_sender_id;

    SELECT RATE INTO v_exchange_rate
    FROM EXCHANGE_RATES
    WHERE FROM_CURRENCY = v_sender_currency
    AND TO_CURRENCY = 'BGN';

    v_amount_in_base_currency := p_amount * v_exchange_rate;

    SELECT RATE INTO v_exchange_rate
    FROM EXCHANGE_RATES
    WHERE FROM_CURRENCY = 'BGN'
    AND TO_CURRENCY = v_receiver_currency;

    v_amount_converted := v_amount_in_base_currency / v_exchange_rate;

    IF v_sender_balance >= p_amount THEN
        UPDATE ACCOUNTS
        SET BALANCE = BALANCE - p_amount
        WHERE CLIENT_ID = p_sender_id;

        UPDATE ACCOUNTS
        SET BALANCE = BALANCE + v_amount_converted
        WHERE CLIENT_ID = p_receiver_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Transfer successful.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Insufficient balance for transfer.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/


