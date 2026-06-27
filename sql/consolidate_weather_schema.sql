-- Migration: Consolidate Weather Tables and Automate Friction Weight Mapping

-- 1. Create the consolidated weather table
CREATE TABLE IF NOT EXISTS external.weather_consolidated (
    id text PRIMARY KEY,
    station text NOT NULL,
    weather_date date NOT NULL,
    record_type text NOT NULL CHECK (record_type IN ('CURRENT', 'FORECAST')),
    temperature_temp_max numeric,
    temp_min numeric,
    humidity numeric,
    wind_speed numeric,
    rainfall_mm numeric,
    computed_rainfall_level text,
    friction_weight numeric NOT NULL,
    observed_or_forecasted_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

-- Index for analytics access patterns
CREATE INDEX IF NOT EXISTS idx_weather_consolidated_lookup 
ON external.weather_consolidated (station, weather_date, record_type);

-- 2. Create the mapping function to compute the PAGASA friction weight
CREATE OR REPLACE FUNCTION external.calculate_weather_friction(
    p_computed_rainfall_level text,
    p_rainfall_mm numeric,
    p_wind_speed numeric
) RETURNS numeric AS $$
DECLARE
    v_weight numeric;
    v_category text;
BEGIN
    -- 1. Determine category based on PAGASA wind and rainfall scales
    -- Wind speed in km/h: 
    -- >= 62.0 km/h -> Signal No. 2 or higher (Typhoon High)
    -- >= 39.0 km/h -> Signal No. 1 (Typhoon Low)
    IF COALESCE(p_wind_speed, 0) >= 62.0 THEN
        v_category := 'Typhoon (High)';
    ELSIF COALESCE(p_wind_speed, 0) >= 39.0 THEN
        v_category := 'Typhoon (Low)';
    ELSIF p_computed_rainfall_level = 'Orange' OR p_computed_rainfall_level = 'Red' THEN
        v_category := 'Torrential Rain';
    ELSIF p_computed_rainfall_level = 'Yellow' THEN
        v_category := 'Heavy Rain';
    ELSIF COALESCE(p_rainfall_mm, 0) > 0 THEN
        v_category := 'Light/Moderate Rain';
    ELSE
        v_category := 'Clear / Fair';
    END IF;

    -- 2. Fetch the corresponding weight from the external.friction_weight table
    SELECT friction_weight INTO v_weight
    FROM external.friction_weight
    WHERE friction_domain = 'pagasa' AND trigger_category = v_category
    LIMIT 1;

    RETURN COALESCE(v_weight, 0.0);
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Create trigger function for weather_current
CREATE OR REPLACE FUNCTION external.sync_weather_current_to_consolidated()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.weather_consolidated WHERE id = 'WTH-CUR-' || REPLACE(REPLACE(UPPER(OLD.station), ' ', '-'), '.', '');
        RETURN OLD;
    ELSE
        INSERT INTO external.weather_consolidated (
            id, station, weather_date, record_type,
            temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
            computed_rainfall_level, friction_weight, observed_or_forecasted_at, updated_at
        )
        VALUES (
            'WTH-CUR-' || REPLACE(REPLACE(UPPER(NEW.station), ' ', '-'), '.', ''),
            NEW.station,
            COALESCE(NEW.observed_at::date, CURRENT_DATE),
            'CURRENT',
            NEW.temperature,
            NULL,
            NEW.humidity,
            NEW.wind_speed,
            NEW.rainfall_mm,
            NEW.computed_rainfall_level,
            external.calculate_weather_friction(NEW.computed_rainfall_level, NEW.rainfall_mm, NEW.wind_speed),
            NEW.observed_at,
            now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            weather_date = EXCLUDED.weather_date,
            record_type = EXCLUDED.record_type,
            temperature_temp_max = EXCLUDED.temperature_temp_max,
            temp_min = EXCLUDED.temp_min,
            humidity = EXCLUDED.humidity,
            wind_speed = EXCLUDED.wind_speed,
            rainfall_mm = EXCLUDED.rainfall_mm,
            computed_rainfall_level = EXCLUDED.computed_rainfall_level,
            friction_weight = EXCLUDED.friction_weight,
            observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
            updated_at = now();
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 4. Create trigger function for weather_forecasts
CREATE OR REPLACE FUNCTION external.sync_weather_forecasts_to_consolidated()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.weather_consolidated WHERE id = REPLACE(OLD.id, 'FCT-', 'WTH-FCT-');
        RETURN OLD;
    ELSE
        INSERT INTO external.weather_consolidated (
            id, station, weather_date, record_type,
            temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
            computed_rainfall_level, friction_weight, observed_or_forecasted_at, updated_at
        )
        VALUES (
            REPLACE(NEW.id, 'FCT-', 'WTH-FCT-'),
            NEW.station,
            NEW.forecast_date,
            'FORECAST',
            NEW.temp_max,
            NEW.temp_min,
            NEW.humidity_mean,
            NEW.wind_speed_max,
            NEW.rainfall_sum_mm,
            NEW.computed_rainfall_level,
            external.calculate_weather_friction(NEW.computed_rainfall_level, NEW.rainfall_sum_mm, NEW.wind_speed_max),
            NEW.fetched_at,
            now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            weather_date = EXCLUDED.weather_date,
            record_type = EXCLUDED.record_type,
            temperature_temp_max = EXCLUDED.temperature_temp_max,
            temp_min = EXCLUDED.temp_min,
            humidity = EXCLUDED.humidity,
            wind_speed = EXCLUDED.wind_speed,
            rainfall_mm = EXCLUDED.rainfall_mm,
            computed_rainfall_level = EXCLUDED.computed_rainfall_level,
            friction_weight = EXCLUDED.friction_weight,
            observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
            updated_at = now();
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 5. Attach Triggers to original tables
DROP TRIGGER IF EXISTS tg_sync_weather_current ON external.weather_current;
CREATE TRIGGER tg_sync_weather_current
AFTER INSERT OR UPDATE OR DELETE ON external.weather_current
FOR EACH ROW EXECUTE FUNCTION external.sync_weather_current_to_consolidated();

DROP TRIGGER IF EXISTS tg_sync_weather_forecasts ON external.weather_forecasts;
CREATE TRIGGER tg_sync_weather_forecasts
AFTER INSERT OR UPDATE OR DELETE ON external.weather_forecasts
FOR EACH ROW EXECUTE FUNCTION external.sync_weather_forecasts_to_consolidated();

-- 6. Initial backfill of existing data
INSERT INTO external.weather_consolidated (
    id, station, weather_date, record_type,
    temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
    computed_rainfall_level, friction_weight, observed_or_forecasted_at, updated_at
)
SELECT
    'WTH-CUR-' || REPLACE(REPLACE(UPPER(station), ' ', '-'), '.', ''),
    station,
    COALESCE(observed_at::date, CURRENT_DATE),
    'CURRENT',
    temperature,
    NULL,
    humidity,
    wind_speed,
    rainfall_mm,
    computed_rainfall_level,
    external.calculate_weather_friction(computed_rainfall_level, rainfall_mm, wind_speed),
    observed_at,
    now()
FROM external.weather_current
ON CONFLICT (id) DO UPDATE SET
    station = EXCLUDED.station,
    weather_date = EXCLUDED.weather_date,
    record_type = EXCLUDED.record_type,
    temperature_temp_max = EXCLUDED.temperature_temp_max,
    temp_min = EXCLUDED.temp_min,
    humidity = EXCLUDED.humidity,
    wind_speed = EXCLUDED.wind_speed,
    rainfall_mm = EXCLUDED.rainfall_mm,
    computed_rainfall_level = EXCLUDED.computed_rainfall_level,
    friction_weight = EXCLUDED.friction_weight,
    observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
    updated_at = now();

INSERT INTO external.weather_consolidated (
    id, station, weather_date, record_type,
    temperature_temp_max, temp_min, humidity, wind_speed, rainfall_mm,
    computed_rainfall_level, friction_weight, observed_or_forecasted_at, updated_at
)
SELECT
    REPLACE(id, 'FCT-', 'WTH-FCT-'),
    station,
    forecast_date,
    'FORECAST',
    temp_max,
    temp_min,
    humidity_mean,
    wind_speed_max,
    rainfall_sum_mm,
    computed_rainfall_level,
    external.calculate_weather_friction(computed_rainfall_level, rainfall_sum_mm, wind_speed_max),
    fetched_at,
    now()
FROM external.weather_forecasts
ON CONFLICT (id) DO UPDATE SET
    station = EXCLUDED.station,
    weather_date = EXCLUDED.weather_date,
    record_type = EXCLUDED.record_type,
    temperature_temp_max = EXCLUDED.temperature_temp_max,
    temp_min = EXCLUDED.temp_min,
    humidity = EXCLUDED.humidity,
    wind_speed = EXCLUDED.wind_speed,
    rainfall_mm = EXCLUDED.rainfall_mm,
    computed_rainfall_level = EXCLUDED.computed_rainfall_level,
    friction_weight = EXCLUDED.friction_weight,
    observed_or_forecasted_at = EXCLUDED.observed_or_forecasted_at,
    updated_at = now();
