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

       
    