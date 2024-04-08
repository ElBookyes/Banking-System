--1.Пакет, който да обслужва вписване на потребители (login). За
--целта трябва да се изгради отделна таблица, с потребители, като
--връзката потребител клиент да е 1:1. Паролата трябва да бъде
--хеширана.

CREATE TABLE USERS (
    USER_ID NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CLIENT_ID NUMBER UNIQUE,
    USERNAME VARCHAR2(100) UNIQUE NOT NULL,
    PASSWORD_HASH VARCHAR2(100) NOT NULL,
    CONSTRAINT FK_USERS_CLIENTS FOREIGN KEY (CLIENT_ID) REFERENCES CLIENTS(CLIENT_ID)
);

CREATE OR REPLACE PACKAGE USER_AUTH_PACKAGE AS
    PROCEDURE REGISTER_USER(
        p_client_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    );

    FUNCTION LOGIN_USER(
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    ) RETURN NUMBER;
END USER_AUTH_PACKAGE;
/

CREATE OR REPLACE PACKAGE BODY USER_AUTH_PACKAGE AS
    PROCEDURE REGISTER_USER(
        p_client_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO USERS (CLIENT_ID, USERNAME, PASSWORD_HASH)
        VALUES (p_client_id, p_username, DBMS_CRYPTO.HASH(p_password, 3));
        COMMIT;
    END REGISTER_USER;

    FUNCTION LOGIN_USER(
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    ) RETURN NUMBER IS
        v_user_id USERS.USER_ID%TYPE;
    BEGIN
        SELECT USER_ID INTO v_user_id
        FROM USERS
        WHERE USERNAME = p_username
        AND PASSWORD_HASH = DBMS_CRYPTO.HASH(p_password, 3);

        RETURN v_user_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END LOGIN_USER;
END USER_AUTH_PACKAGE;
/

--2.Функционалност чрез Scheduled job, който да прихваща
--потребителите, които не са се вписвали в приложението
--последните 3 месеца и да ги запазва в отделна таблица. Честота
--на изпълнение веднъж дневно.

CREATE TABLE INACTIVE_USERS (
    USER_ID NUMBER,
    USERNAME VARCHAR2(100),
    LAST_LOGIN_DATE DATE,
    CONSTRAINT FK_INACTIVE_USERS_USERS FOREIGN KEY (USER_ID) REFERENCES USERS(USER_ID)
);

ALTER TABLE USERS ADD (last_login_date DATE);

CREATE OR REPLACE PROCEDURE find_inactive_users AS
BEGIN
    DELETE FROM INACTIVE_USERS;

    INSERT INTO INACTIVE_USERS (USER_ID, USERNAME, LAST_LOGIN_DATE)
    SELECT USER_ID, USERNAME, LAST_LOGIN_DATE
    FROM USERS
    WHERE LAST_LOGIN_DATE < SYSDATE - INTERVAL '3' MONTH;
    COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name          => 'Capture_Inactive_Users',
        job_type          => 'PLSQL_BLOCK',
        job_action        => 'BEGIN
                                 INSERT INTO INACTIVE_USERS (USER_ID, USERNAME, LAST_LOGIN_DATE)
                                 SELECT USER_ID, USERNAME, MAX(LAST_LOGIN_DATE)
                                 FROM USERS
                                 WHERE LAST_LOGIN_DATE < TRUNC(SYSDATE) - INTERVAL ''3'' MONTH
                                 GROUP BY USER_ID, USERNAME;
                             END;',
        start_date        => SYSTIMESTAMP,
        repeat_interval   => 'FREQ=DAILY',
        enabled           => TRUE
    );
END;
/

INSERT INTO USERS (username, last_login_date, password_hash)
VALUES ('test_user', TO_DATE('2022-01-01', 'YYYY-MM-DD'), 'your_password_hash_here');

BEGIN
 find_inactive_users;
END;
/

SELECT * FROM INACTIVE_USERS;

SELECT * FROM USER_SCHEDULER_JOB_RUN_DETAILS WHERE JOB_NAME = 'FIND_INACTIVE_USERS_JOB' ORDER BY ACTUAL_START_DATE DESC;

--3. Пакет с CRUD операции за обработка на потребителите, които
--използват приложението.

CREATE OR REPLACE PACKAGE USER_CRUD_PACKAGE AS
    PROCEDURE CREATE_USER(
        p_client_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    );

    FUNCTION READ_USER(
        p_user_id IN NUMBER
    ) RETURN SYS_REFCURSOR;

    PROCEDURE UPDATE_USER(
        p_user_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    );

    PROCEDURE DELETE_USER(
        p_user_id IN NUMBER
    );
END USER_CRUD_PACKAGE;
/

CREATE OR REPLACE PACKAGE BODY USER_CRUD_PACKAGE AS
    PROCEDURE CREATE_USER(
        p_client_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO USERS (CLIENT_ID, USERNAME, PASSWORD_HASH)
        VALUES (p_client_id, p_username, DBMS_CRYPTO.HASH(p_password, 3));
        COMMIT;
    END CREATE_USER;

    FUNCTION READ_USER(
        p_user_id IN NUMBER
    ) RETURN SYS_REFCURSOR IS
        v_user_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_user_cursor FOR
        SELECT *
        FROM USERS
        WHERE USER_ID = p_user_id;
        RETURN v_user_cursor;
    END READ_USER;

    PROCEDURE UPDATE_USER(
        p_user_id IN NUMBER,
        p_username IN VARCHAR2,
        p_password IN VARCHAR2
    ) IS
    BEGIN
        UPDATE USERS
        SET USERNAME = p_username,
            PASSWORD_HASH = DBMS_CRYPTO.HASH(p_password, 3)
        WHERE USER_ID = p_user_id;
        COMMIT;
    END UPDATE_USER;

    PROCEDURE DELETE_USER(
        p_user_id IN NUMBER
    ) IS
    BEGIN
        DELETE FROM USERS
        WHERE USER_ID = p_user_id;
        COMMIT;
    END DELETE_USER;
END USER_CRUD_PACKAGE;
/

--4.Scheduled job, който да следи потребителите, които не са сменяли
--паролата си последните 3 месеца и да ги подготвя за известяване. Честота на изпълнение веднъж дневно.

CREATE TABLE PASSWORD_EXPIRY_USERS (
    USER_ID NUMBER,
    USERNAME VARCHAR2(100),
    LAST_PASSWORD_CHANGE_DATE DATE
);

ALTER TABLE USERS ADD (LAST_PASSWORD_CHANGE_DATE DATE);

CREATE OR REPLACE PROCEDURE find_users_with_expired_password AS
BEGIN
    DELETE FROM PASSWORD_EXPIRY_USERS; -- Изтриваме предишните данни, ако има такива

    INSERT INTO PASSWORD_EXPIRY_USERS (user_id, username, last_password_change_date)
    SELECT user_id, username, last_password_change_date
    FROM USERS
    WHERE last_password_change_date < SYSDATE - INTERVAL '3' MONTH;
    COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name          => 'Monitor_Password_Expiry',
        job_type          => 'PLSQL_BLOCK',
        job_action        => 'BEGIN
                                 INSERT INTO PASSWORD_EXPIRY_USERS (USER_ID, USERNAME, LAST_PASSWORD_CHANGE_DATE)
                                 SELECT USER_ID, USERNAME, MAX(PASSWORD_CHANGE_DATE)
                                 FROM USERS
                                 WHERE PASSWORD_CHANGE_DATE < TRUNC(SYSDATE) - INTERVAL ''3'' MONTH
                                 GROUP BY USER_ID, USERNAME;
                             END;',
        start_date        => SYSTIMESTAMP,
        repeat_interval   => 'FREQ=DAILY',
        enabled           => TRUE
    );
END;
/

BEGIN
    find_users_with_expired_password;
END;
/

SELECT * FROM PASSWORD_EXPIRY_USERS;

SELECT * FROM USER_SCHEDULER_JOB_RUN_DETAILS WHERE JOB_NAME = 'FIND_USERS_WITH_EXPIRED_PASSWORD_JOB' ORDER BY ACTUAL_START_DATE DESC;


--5.Scheduled job, който да следи наличността по сметките и да
--обновява статуса на всеки клиент на “VIP”, когато стойността
--стане по-голяма от 100000.

ALTER TABLE CLIENTS ADD STATUS VARCHAR2(50);

CREATE OR REPLACE PROCEDURE update_vip_client_status AS
BEGIN
    UPDATE CLIENTS
    SET STATUS = 'VIP'
    WHERE BALANCE > 100000;
    COMMIT;
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name          => 'Update_Client_Status_to_VIP',
        job_type          => 'PLSQL_BLOCK',
        job_action        => 'BEGIN
                                 UPDATE CLIENTS
                                 SET STATUS = ''VIP''
                                 WHERE CLIENT_ID IN (
                                     SELECT DISTINCT CLIENT_ID
                                     FROM ACCOUNTS
                                     WHERE BALANCE > 100000
                                 );
                             END;',
        start_date        => SYSTIMESTAMP,
        repeat_interval   => 'FREQ=DAILY',
        enabled           => TRUE
    );
END;
/

BEGIN
    update_vip_client_status;
END;
/

SELECT * FROM CLIENTS;

SELECT * FROM USER_SCHEDULER_JOB_RUN_DETAILS WHERE JOB_NAME = 'UPDATE_VIP_CLIENT_STATUS_JOB' ORDER BY ACTUAL_START_DATE DESC;



