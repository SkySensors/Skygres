CREATE SCHEMA partman;

CREATE EXTENSION pg_partman SCHEMA partman;

CREATE EXTENSION pg_cron; 

SELECT cron.schedule('daily-partman-maintenance', '0 6 * * *', $$CALL partman.run_maintenance_proc()$$);

UPDATE cron.job
	SET nodename='';

CREATE TABLE weather_stations (
	mac_address macaddr PRIMARY KEY,
	lon numeric NOT NULL,
	lat numeric NOT NULL
);

CREATE TABLE sensors (
	mac_address macaddr,
	TYPE TEXT,
	calibration_offset NUMERIC DEFAULT 1,
    PRIMARY KEY(mac_address, type),
	CONSTRAINT fk_weather_mac_address FOREIGN KEY(mac_address) REFERENCES weather_stations(mac_address) ON DELETE CASCADE
);

CREATE TABLE public.sensor_values (
	mac_address macaddr NOT NULL,
	TYPE TEXT NOT NULL,
	unix_time bigint NOT NULL,
	value numeric
) PARTITION BY RANGE (unix_time);

CREATE TABLE partman.template_sensor_values AS TABLE public.sensor_values;

CREATE UNIQUE INDEX idx_template_sensor_values_macaddr_type_unix_time ON partman.template_sensor_values (mac_address, type, unix_time);

SELECT partman.create_parent('public.sensor_values', 'unix_time', '1 months', 'range', 'milliseconds', p_template_table:= 'partman.template_sensor_values');

       
CREATE OR REPLACE PROCEDURE sp_calibration_of_sensors_offset(
   days_back int,
   in_radius int
)
LANGUAGE plpgsql    
AS $$
BEGIN
	UPDATE sensors
		SET calibration_offset = sub.calibration_offset
	FROM (
		/* Calculate the offset */
		WITH a AS (
			SELECT ws.*, sv.TYPE, sv.unix_time, sv.value
				, st_transform(ST_SetSrid(ST_MakePoint(lon, lat),4326),4326)::geography AS geog -- CREATE a location FROM longitude AND latitude
			FROM weather_stations ws
			LEFT JOIN sensors s ON ws.mac_address = s.mac_address 
			LEFT JOIN public.sensor_values sv ON ws.mac_address = sv.mac_address AND s."type" = sv.TYPE
			-- Within this days
			WHERE sv.unix_time > EXTRACT(EPOCH FROM NOW() - days_back * INTERVAL '1 DAY') * 1000
		), b AS ( --Need two identical tables to join all nearby weather stations
			SELECT ws.*, sv.TYPE, sv.unix_time, sv.value, st_transform(ST_SetSrid(ST_MakePoint(lon, lat),4326),4326)::geography AS geog
			FROM weather_stations ws
			LEFT JOIN sensors s ON ws.mac_address = s.mac_address 
			LEFT JOIN public.sensor_values sv ON ws.mac_address = sv.mac_address AND s."type" = sv.TYPE
			WHERE sv.unix_time > EXTRACT(EPOCH FROM NOW() - days_back * INTERVAL '1 DAY') * 1000
		)
		SELECT a.mac_address AS mac_address, a.TYPE, (AVG(b.value)/AVG(a.value))AS calibration_offset
		FROM a JOIN b ON ST_DWithin(a.geog, b.geog, in_radius)
		GROUP BY a.mac_address, a.TYPE
	) AS sub 
	WHERE sensors.mac_address = sub.mac_address AND sensors."type" = sub.TYPE;
	
    COMMIT;
END;$$;

CREATE VIEW calibrated_sensor_values AS (
	SELECT sv.mac_address, sv."type", sv.unix_time, (sv.value * s.calibration_offset) AS value
	FROM sensor_values sv 
	JOIN sensors s ON sv.mac_address = s.mac_address 
		AND sv.TYPE = s."type" 
	ORDER BY unix_time
	);


/** Create cron job to calibrate sensors every day **/

SELECT cron.schedule('daily-calibration-within-1000m', '0 1 * * *', $$CALL public.sp_calibration_of_sensors_offset(1, 1000)$$);

CREATE TABLE time_slots(
	mac_address macaddr PRIMARY KEY,
	seconds_number int,
	CONSTRAINT fk_macaddr
		FOREIGN KEY(mac_address)
		REFERENCES weather_stations(mac_address)
)