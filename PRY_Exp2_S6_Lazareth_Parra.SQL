-- ETAPA 1

--BORRAR TABLA
DROP TABLE recaudacion_bonos_medicos CASCADE CONSTRAINTS;

--CREAR TABLA
CREATE TABLE RECAUDACION_BONOS_MEDICOS (
    rut_medico VARCHAR2(20),
    nombre_medico VARCHAR2(100),
    --SE DEJA TODO EN CHAR POR FORMATOS
    total_recaudado VARCHAR2(50),
    unidad_medica VARCHAR2(100)
);

--SE LLENA LA TABLA
INSERT INTO RECAUDACION_BONOS_MEDICOS
SELECT    
-- RUT en formato con separador de miles, 0 anteriro en caso de ser menor a 10 millones y unido por - al digito verificador
TO_CHAR(m.rut_med, '09G999G999') || '-' || m.dv_run ,
-- Nombre completo en mayúscula, concadenado
UPPER(m.pnombre || ' ' || m.apaterno || ' ' || m.amaterno),  
-- Total recaudado por cada medico con signo peso y separador de miles
TO_CHAR(SUM(p.monto_a_cancelar), '$999G999G999'),  
-- Unidad medica capitalizada y justificada a la derecha
LPAD(INITCAP(u.nombre),30)

FROM BONO_CONSULTA b
--bonos que fueron pagados
JOIN PAGOS p ON b.id_bono = p.id_bono
JOIN MEDICO m ON b.rut_med = m.rut_med
--para otener el nombre de la unidad segun el id en medico
JOIN UNIDAD_CONSULTA u ON m.uni_id = u.uni_id

WHERE 
--se utilizan el periodo anterior a 12 meses antes de la fecha de sistema
    b.fecha_bono BETWEEN 
    TO_DATE('01-01-' || TO_CHAR(ADD_MONTHS(SYSDATE,-12),'YYYY'),'DD-MM-YYYY')
AND 
    TO_DATE('31-12-' || TO_CHAR(ADD_MONTHS(SYSDATE,-12),'YYYY'),'DD-MM-YYYY')
    --se quitan las especialidades a excluir segun el caso
    AND m.car_id NOT IN (100, 500, 600)

GROUP BY 
    m.rut_med, m.dv_run,
    m.pnombre, m.apaterno, m.amaterno,
    u.nombre;
    
--Se confirma    
COMMIT;    

--Se muestra la tabla ordenada por el total recaudado de forma ascendente
SELECT * 
FROM RECAUDACION_BONOS_MEDICOS
ORDER BY TO_NUMBER(REPLACE(REPLACE(total_recaudado,'$',''),'.','')) ASC;


--CASO 2

SELECT 
    -- Especialidad en mayúscula
    UPPER(e.nombre) AS ESPECIALIDAD_MEDICA,
    -- Cantidad de bonos sin pagar por especialidad
    COUNT(*) AS CANTIDAD_BONOS,
    -- Monto pérdida, suma de los bonos no pagos, con signo peso y separador de miles, justificado a la derecha
    LPAD(TO_CHAR(SUM(b.costo), '$999G999G999'), 20) AS MONTO_PERDIDA,
    -- Fecha del bono mas antiguo sin pagar en esa especialidad
    LPAD(TO_CHAR(MIN(b.fecha_bono), 'DD-MM-YYYY'), 15) AS FECHA_BONO,
    -- cuando la fecha del bono mas antiguo sin pgar es anterior al año anteriro al actual, se clasifica como incobrable
    CASE 
        WHEN MIN(b.fecha_bono) >= 
        --Se utiliza la fecha actual menos 12 meses para definir el año anteriro, de forma que no se suan fechas fijas
             TO_DATE('01-01-' || TO_CHAR(ADD_MONTHS(SYSDATE,-12),'YYYY'),'DD-MM-YYYY')
        THEN 'COBRABLE'
        ELSE 'INCOBRABLE'
    END AS ESTADO_DE_COBRO

FROM BONO_CONSULTA b
--relaciona cada bono con la especialidad del medico que atendio
JOIN DET_ESPECIALIDAD_MED d 
    ON b.rut_med = d.rut_med AND b.esp_id = d.esp_id
    --union para obtener el nombre de la especialidad
JOIN ESPECIALIDAD_MEDICA e 
    ON d.esp_id = e.esp_id
    --sub consulta para obtener los bonos que no estan pagados
WHERE b.id_bono NOT IN (SELECT id_bono FROM PAGOS)

GROUP BY e.nombre
ORDER BY 
--ordenado por cantidad de bonos y luego por monto perdido
    CANTIDAD_BONOS ASC,
    SUM(b.costo) DESC;


--CASO 3
--vacio la tabla de los datos erroneos anteriores, sin eliminarla
TRUNCATE TABLE CANT_BONOS_PACIENTES_ANNIO;

--inserto los valores para el año 2026
INSERT INTO CANT_BONOS_PACIENTES_ANNIO
SELECT 
    -- Año actual, en este caso 206
    TO_NUMBER(TO_CHAR(SYSDATE,'YYYY')),
    -- RUt sin digito verificador
    p.pac_run,
    -- digito verificador
    p.dv_run,
    -- calcula la edad con la fecha de nacimineto del paciente y la fecha actual, trunca el resultado para mostrar un nummero entero
    TRUNC(MONTHS_BETWEEN(SYSDATE, p.fecha_nacimiento)/12),
  -- Cantidad bonos del paciente en ese año
    COUNT(b.id_bono),
    -- Total de los bonos del paciente, en caso de no haber comprado se usa nvl para sleccionar 0 en vez de null
    NVL(SUM(b.costo),0),
    -- Sistema salud del paciente
    s.descripcion

FROM PACIENTE p
--Se utiliza left join para incluir a los pacientes sin bonos 
LEFT JOIN BONO_CONSULTA b 
    ON p.pac_run = b.pac_run
    --solo fechas de 2026, como se requiere en el caso
    AND b.fecha_bono BETWEEN 
    TO_DATE('01-01-' || TO_CHAR(SYSDATE,'YYYY'),'DD-MM-YYYY')
    AND 
    TO_DATE('31-12-' || TO_CHAR(SYSDATE,'YYYY'),'DD-MM-YYYY')
--relacion paciente con sistemade salud
LEFT JOIN SALUD sa ON p.sal_id = sa.sal_id
--nombre sist de salud
LEFT JOIN SISTEMA_SALUD s ON sa.tipo_sal_id = s.tipo_sal_id

GROUP BY 
    p.pac_run,
    p.dv_run, 
    p.fecha_nacimiento,
    s.descripcion
--cantidad de bonos menor o igual al promedio del año anterior
HAVING COUNT(b.id_bono) <= (
--promedio de bonos por paciente
    SELECT ROUND(AVG(cantidad))
    FROM (
    --cuantos bonos tiene cada paciente
        SELECT COUNT(*) cantidad
        FROM BONO_CONSULTA
        --para bonos del año anterior
        WHERE fecha_bono BETWEEN 
            TO_DATE('01-01-' || TO_CHAR(ADD_MONTHS(SYSDATE,-12),'YYYY'),'DD-MM-YYYY')
        AND 
            TO_DATE('31-12-' || TO_CHAR(ADD_MONTHS(SYSDATE,-12),'YYYY'),'DD-MM-YYYY')
        GROUP BY pac_run
    )
);
--Confirma
COMMIT;

--muestra tabla 
SELECT *
FROM CANT_BONOS_PACIENTES_ANNIO
--ordenado por monto total de forma ascendente y luego por edad
ORDER BY MONTO_TOTAL_BONOS ASC, EDAD DESC;