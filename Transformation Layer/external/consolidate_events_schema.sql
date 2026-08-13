-- ============================================================================
-- Migration: Events Classification, Consolidation & Normalization Pipeline
-- Implements EventsNormalizationToFrictionIndex.md with CFI_Variables.md labels
-- Classification: External Dataset (Events Scraper/API)
-- ============================================================================

-- 1a. Create the consolidated events table
CREATE TABLE IF NOT EXISTS external.events_consolidated (
    id text PRIMARY KEY,
    station text NOT NULL,
    event_date date NOT NULL,
    source_table text NOT NULL,
    source_id text NOT NULL,
    source_name text,
    event_name text NOT NULL,
    event_category text NOT NULL,
    friction_domain text NOT NULL,
    trigger_category text NOT NULL,
    source_url text,
    description text,
    -- Normalized score: A_sw (Academic Surge Weight) or L_sp (Surge Probability Multiplier)
    normalized_score numeric NOT NULL DEFAULT 0.0,
    -- Raw literature weight from friction_weight for traceability
    friction_weight_ref numeric NOT NULL DEFAULT 0.0,
    announcement_time timestamp with time zone NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE external.events_consolidated ADD COLUMN IF NOT EXISTS announcement_time timestamp with time zone NULL;

CREATE INDEX IF NOT EXISTS idx_events_consolidated_lookup
ON external.events_consolidated (station, event_date, event_category);

-- 1ad. Station Name Normalization Function to match unpivoted ridership conventions
CREATE OR REPLACE FUNCTION external.normalize_station_name(p_station text)
RETURNS text AS $$
DECLARE
    v_clean text;
BEGIN
    v_clean := UPPER(TRIM(COALESCE(p_station, 'All Stations')));
    
    IF v_clean IN ('ALL', 'ALL STATIONS', 'ALL STATION', '') THEN
        RETURN 'All Stations';
    ELSIF v_clean IN ('RECTO') THEN
        RETURN 'Recto';
    ELSIF v_clean IN ('LEGARDA') THEN
        RETURN 'Legarda';
    ELSIF v_clean IN ('PUREZA') THEN
        RETURN 'Pureza';
    ELSIF v_clean IN ('V. MAPA', 'VMAPA', 'V MAPA') THEN
        RETURN 'V. Mapa';
    ELSIF v_clean IN ('J. RUIZ', 'JRUIZ', 'J RUIZ') THEN
        RETURN 'J. Ruiz';
    ELSIF v_clean IN ('GILMORE') THEN
        RETURN 'Gilmore';
    ELSIF v_clean IN ('BETTY GO-BELMONTE', 'BETTY GO BELMONTE', 'BETTY GO') THEN
        RETURN 'Betty Go-Belmonte';
    ELSIF v_clean IN ('ARANETA CENTER-CUBAO', 'ARANETA CENTER CUBAO', 'ARANETA', 'CUBAO') THEN
        RETURN 'Araneta Center Cubao';
    ELSIF v_clean IN ('ANONAS') THEN
        RETURN 'Anonas';
    ELSIF v_clean IN ('KATIPUNAN') THEN
        RETURN 'Katipunan';
    ELSIF v_clean IN ('SANTOLAN') THEN
        RETURN 'Santolan';
    ELSIF v_clean IN ('MARIKINA-PASIG', 'MARIKINA PASIG', 'MARIKINA') THEN
        RETURN 'Marikina-Pasig';
    ELSIF v_clean IN ('ANTIPOLO') THEN
        RETURN 'Antipolo';
    ELSE
        RETURN INITCAP(p_station);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 1b. Function to classify scraped text into event_category, friction_domain, and trigger_category
CREATE OR REPLACE FUNCTION external.classify_event_from_text(
    p_post_text text,
    p_image_text text,
    p_category text,
    p_event_name text DEFAULT NULL
) RETURNS TABLE (
    event_name text,
    event_category text,
    friction_domain text,
    trigger_category text,
    affects_ridership boolean
) AS $$
DECLARE
    v_combined text;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_event_name, ''));

    -- Filter 1: Planning / Administrative meetings
    IF (v_combined ~* '(coordination\s+meeting|ocular\s+visit|ocular\s+meeting|planning\s+meeting|planning\s+session|preparatory\s+meeting|committee\s+meeting|coordination\s+visit|pre-event\s+coordination)'
        OR (v_combined ~* '(meeting|ocular|planning|preparation|discussion)' 
            AND NOT v_combined ~* '(suspend|walang\s+pasok|no\s+class|strike|tigil\s+pasada|welga)')) THEN
        event_name := 'Planning/Coordination Meeting';
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 2: Administrative / Internal notices
    IF v_combined ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing\s+of\s+leave)' THEN
        event_name := 'Administrative/Internal Notice';
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Filter 3: Class / Exam / Transaction Suspensions (HIGHEST PRIORITY for cancellations)
    IF v_combined ~* '(cancel(lation|led)?\s+of\s+(medical\s+)?exam|cancel(lation|led)?\s+of\s+(classes|transactions|clearance)|class(es)?\s+.*(is|are)\s+suspend|suspend(ed|ing)?\s+(class|office|transaction)|suspension\s+of\s+(all\s+|onsite\s+|face-to-face\s+)?classes|walang\s+pasok|no\s+class|non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng|founding\s+anniversary|holiday|holy\s+week|lenten\s+break|academic\s+break|undas|sona|state\s+of\s+the\s+nation|traslacion|black\s+nazarene|day\s+of\s+valor|rizal\s+day|bonifacio\s+day|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa|eid|ramadan|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation)' THEN
        event_name := 'Class Suspension / Holiday'; 
        event_category := 'class_suspension'; 
        friction_domain := 'academic'; 
        trigger_category := 'Class Suspension / Holiday'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 4: LGU Maintenance / Tree Trimming / Clearing / Declogging Activities
    IF v_combined ~* '(tree\s+trimming|road\s+clearance|clearing\s+operation|pruning|tree\s+pruning|declogging|drainage|flushing|sewer)' THEN
        event_name := 'LGU Clearing & Maintenance Activity'; 
        event_category := 'infrastructure'; 
        friction_domain := 'lgu'; 
        trigger_category := 'Road Closure / Obstruction'; 
        affects_ridership := FALSE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 5: Transport Strike
    IF v_combined ~* '(transport\s+strike|tigil\s+pasada|welga|jeepney\s+strike|piston|manibela|transport\s+group)' THEN
        event_name := 'Transport Strike'; 
        event_category := 'transport_strike'; 
        friction_domain := 'academic'; 
        trigger_category := 'Transport Strike'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 6: Major Arena Events
    IF v_combined ~* '(uaap|ncaa|concert|sports\s+event|arena\s+event|basketball|volleyball|cheerdance|pep\s+squad|send[- ]?off|rally|pep\s+rally|game\s+day)' THEN
        event_name := 'Major Arena / Sports Event'; 
        event_category := 'major_event'; 
        friction_domain := 'academic'; 
        trigger_category := 'Major Arena Event'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 7: Examination Period (ONLY if NOT cancelled/suspended)
    IF v_combined ~* '(exam(ination)?s?|midterm|finals?\s+(exam|week)|prelim(inary)?\s+exam|long\s+exam|qualifying\s+exam)' 
       AND NOT v_combined ~* '(cancel|suspend|walang\s+pasok|no\s+class)' THEN
        event_name := 'Examination Period'; 
        event_category := 'exam_week'; 
        friction_domain := 'academic'; 
        trigger_category := 'University Exam Week'; 
        affects_ridership := TRUE;
        RETURN NEXT; 
        RETURN;
    END IF;

    -- Filter 8: Academic Start / Enrollment
    IF v_combined ~* '(enrollment|orientation|first\s+day\s+of\s+(class|regular\s+class)|start\s+of\s+class|opening\s+of\s+class)' THEN
        RETURN NEXT; RETURN;
    END IF;

    event_name := 'Unclassified'; event_category := 'unclassified'; friction_domain := NULL; trigger_category := NULL; affects_ridership := FALSE;
    RETURN NEXT; RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

-- 1b_2. Extract event date from post/image text with timezone safety and relative offset support
CREATE OR REPLACE FUNCTION external.extract_event_date_from_text(
    p_post_text text,
    p_image_text text,
    p_post_date timestamp with time zone
) RETURNS date AS $$
DECLARE
    v_combined text;
    v_match text[];
    v_month text;
    v_day integer;
    v_year integer;
    v_month_num integer;
    v_fallback date;
BEGIN
    -- Fallback is the post_date in Asia/Manila timezone
    v_fallback := (p_post_date AT TIME ZONE 'Asia/Manila')::date;
    
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, ''));
    
    -- Format 1: Month Name followed by Day (e.g., July 2, 2026 or July 2)
    -- Using \y for word boundaries to prevent matching digits inside years (like matching '20' in '2026' as July 20)
    v_match := regexp_match(
        v_combined,
        '\y(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\y\.?\s+\y(\d{1,2})\y(?:st|nd|rd|th)?(?:,?\s+\y(\d{4})\y)?'
    );
    
    IF v_match IS NULL THEN
        -- Format 2: Day followed by Month Name (e.g., 02 July 2026 or 2 July)
        v_match := regexp_match(
            v_combined,
            '\y(\d{1,2})\y(?:st|nd|rd|th)?\s+\y(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\y\.?(?:\s+\y(\d{4})\y)?'
        );
        IF v_match IS NOT NULL THEN
            v_month := v_match[2];
            v_day := v_match[1]::integer;
            v_year := v_match[3]::integer;
        END IF;
    ELSE
        v_month := v_match[1];
        v_day := v_match[2]::integer;
        v_year := v_match[3]::integer;
    END IF;

    IF v_match IS NOT NULL THEN
        v_month_num := CASE
            WHEN v_month IN ('january', 'jan') THEN 1
            WHEN v_month IN ('february', 'feb') THEN 2
            WHEN v_month IN ('march', 'mar') THEN 3
            WHEN v_month IN ('april', 'apr') THEN 4
            WHEN v_month IN ('may') THEN 5
            WHEN v_month IN ('june', 'jun') THEN 6
            WHEN v_month IN ('july', 'jul') THEN 7
            WHEN v_month IN ('august', 'aug') THEN 8
            WHEN v_month IN ('september', 'sep') THEN 9
            WHEN v_month IN ('october', 'oct') THEN 10
            WHEN v_month IN ('november', 'nov') THEN 11
            WHEN v_month IN ('december', 'dec') THEN 12
        END;
        
        -- If year is missing or in the past (stale extraction), default to post creation year (2026)
        IF v_year IS NULL OR v_year < EXTRACT(YEAR FROM v_fallback)::integer THEN
            v_year := EXTRACT(YEAR FROM v_fallback)::integer;
        END IF;

        BEGIN
            RETURN make_date(v_year, v_month_num, v_day);
        EXCEPTION WHEN OTHERS THEN
            RETURN v_fallback;
        END;
    END IF;

    -- Handle relative tomorrow keywords
    IF v_combined ~* '\y(tomorrow|bukas)\y' THEN
        RETURN v_fallback + 1;
    END IF;

    RETURN v_fallback;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 1b_3. Resolve affected stations by city/place keywords and source locations
CREATE OR REPLACE FUNCTION external.get_affected_stations(
    p_station text,
    p_post_text text,
    p_image_text text,
    p_source_name text
) RETURNS text[] AS $$
DECLARE
    v_combined text;
    v_stations text[] := ARRAY[]::text[];
    v_station_normalized text;
    v_city text := NULL;
BEGIN
    v_combined := LOWER(COALESCE(p_post_text, '') || ' ' || COALESCE(p_image_text, '') || ' ' || COALESCE(p_source_name, ''));
    v_station_normalized := external.normalize_station_name(p_station);

    -- 1. Check for specific local city keywords first to prevent city-specific holidays from defaulting to All Stations
    IF v_combined ~* '\b(manila\s+day|araw\s+ng\s+maynila|founding\s+anniversary\s+of\s+manila)\b' THEN
        v_city := 'Manila';
    ELSIF v_combined ~* '\b(quezon\s+city\s+day|araw\s+ng\s+quezon|qc\s+day)\b' THEN
        v_city := 'Quezon City';
    ELSIF v_combined ~* '\b(san\s+juan\s+day|araw\s+ng\s+san\s+juan|wattah\s+wattah)\b' THEN
        v_city := 'San Juan';
    ELSIF v_combined ~* '\b(marikina\s+day|araw\s+ng\s+marikina)\b' THEN
        v_city := 'Pasig and Marikina';
    ELSIF v_combined ~* '\b(pasig\s+day|araw\s+ng\s+pasig)\b' THEN
        v_city := 'Pasig and Marikina';
    ELSIF v_combined ~* '\b(antipolo\s+day|araw\s+ng\s+antipolo)\b' THEN
        v_city := 'Antipolo';
    END IF;

    -- 2. If no explicit local city holiday keyword, check if source station indicates "All Stations"
    IF v_city IS NULL AND v_station_normalized = 'All Stations' THEN
        RETURN ARRAY['All Stations'];
    END IF;

    -- 3. Map source station to city group if present
    IF v_city IS NULL AND v_station_normalized IS NOT NULL AND v_station_normalized != '' THEN
        IF v_station_normalized IN ('Recto', 'Legarda', 'Pureza', 'V. Mapa') THEN
            v_city := 'Manila';
        ELSIF v_station_normalized IN ('J. Ruiz') THEN
            v_city := 'San Juan';
        ELSIF v_station_normalized IN ('Gilmore', 'Betty Go-Belmonte', 'Araneta Center Cubao', 'Anonas', 'Katipunan') THEN
            v_city := 'Quezon City';
        ELSIF v_station_normalized IN ('Santolan', 'Marikina-Pasig') THEN
            v_city := 'Pasig and Marikina';
        ELSIF v_station_normalized IN ('Antipolo') THEN
            v_city := 'Antipolo';
        END IF;
    END IF;

    -- 4. Check for place/city keywords in the combined text
    -- Manila group
    IF v_city = 'Manila' OR v_combined ~* '\b(manila|recto|legarda|pureza|v\.?\s*mapa)\b' THEN
        v_stations := v_stations || ARRAY['Recto', 'Legarda', 'Pureza', 'V. Mapa'];
    END IF;

    -- San Juan group
    IF v_city = 'San Juan' OR v_combined ~* '\b(san\s+juan|j\.?\s*ruiz)\b' THEN
        v_stations := v_stations || ARRAY['J. Ruiz'];
    END IF;

    -- Quezon City group
    IF v_city = 'Quezon City' OR v_combined ~* '\b(quezon\s+city|qc|gilmore|betty\s+go|araneta|cubao|anonas|katipunan)\b' THEN
        v_stations := v_stations || ARRAY['Gilmore', 'Betty Go-Belmonte', 'Araneta Center Cubao', 'Anonas', 'Katipunan'];
    END IF;

    -- Pasig and Marikina group
    IF v_city = 'Pasig and Marikina' OR v_combined ~* '\b(pasig|marikina|santolan)\b' THEN
        v_stations := v_stations || ARRAY['Santolan', 'Marikina-Pasig'];
    END IF;

    -- Antipolo group
    IF v_city = 'Antipolo' OR v_combined ~* '\b(antipolo|rizal)\b' THEN
        v_stations := v_stations || ARRAY['Antipolo'];
    END IF;

    -- 5. Deduplicate the stations array
    IF array_length(v_stations, 1) > 0 THEN
        SELECT ARRAY(SELECT DISTINCT unnest(v_stations)) INTO v_stations;
    ELSE
        -- Default fallback to normalized source station if no city/place keywords matched
        IF v_station_normalized IS NOT NULL AND v_station_normalized != '' THEN
            v_stations := ARRAY[v_station_normalized];
        ELSE
            v_stations := ARRAY['All Stations'];
        END IF;
    END IF;

    RETURN v_stations;
END;
$$ LANGUAGE plpgsql STABLE;

-- 1c. Trigger function for academic_lgu_events → events_consolidated
CREATE OR REPLACE FUNCTION external.sync_academic_lgu_to_events_consolidated()
RETURNS trigger AS $$
DECLARE
    v_result RECORD;
    v_weight numeric;
    v_event_date date;
    v_scrape_id text;
    v_cat_code text;
    v_stations text[];
    v_station text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM external.events_consolidated WHERE source_id = OLD.id AND source_table = 'academic_lgu_events';
        RETURN OLD;
    END IF;

    SELECT * INTO v_result
    FROM external.classify_event_from_text(NEW.post_text, NEW.image_text, NEW.category);

    IF v_result.affects_ridership = FALSE OR v_result.affects_ridership IS NULL THEN
        DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';
        RETURN NEW;
    END IF;

    SELECT fw.friction_weight INTO v_weight
    FROM external.friction_weight fw
    WHERE fw.friction_domain = v_result.friction_domain 
      AND fw.trigger_category = v_result.trigger_category
    LIMIT 1;
    v_weight := COALESCE(v_weight, 0.0);

    v_event_date := external.extract_event_date_from_text(NEW.post_text, NEW.image_text, NEW.post_date);

    v_cat_code := CASE v_result.event_category
        WHEN 'class_suspension' THEN 'CS'
        WHEN 'transport_strike' THEN 'TS'
        WHEN 'major_event' THEN 'ME'
        WHEN 'exam_week' THEN 'EX'
        ELSE 'RC'
    END;

    -- Clear any existing rows for this source_id first to prevent duplicate or stale station assignments on update
    DELETE FROM external.events_consolidated WHERE source_id = NEW.id AND source_table = 'academic_lgu_events';

    -- Resolve the list of stations affected by this event
    v_stations := external.get_affected_stations(NEW.station, NEW.post_text, NEW.image_text, NEW.source_name);

    -- Loop and insert for each affected station
    FOREACH v_station IN ARRAY v_stations LOOP
        v_scrape_id := 'SCR-' || v_cat_code || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || NEW.id || '-' || REPLACE(LOWER(v_station), ' ', '_');

        INSERT INTO external.events_consolidated (
            id, station, event_date, source_table, source_id, source_name,
            event_name, event_category, friction_domain, trigger_category,
            source_url, description,
            normalized_score, friction_weight_ref, announcement_time, updated_at
        )
        VALUES (
            v_scrape_id,
            external.normalize_station_name(v_station),
            v_event_date,
            'academic_lgu_events',
            NEW.id,
            NEW.source_name,
            v_result.event_name,
            v_result.event_category,
            v_result.friction_domain,
            v_result.trigger_category,
            NEW.source_url,
            NEW.post_text,
            CASE
                WHEN v_result.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
                ELSE v_weight
            END,
            v_weight,
            NEW.post_date,
            now()
        )
        ON CONFLICT (id) DO UPDATE SET
            station = EXCLUDED.station,
            event_date = EXCLUDED.event_date,
            source_name = EXCLUDED.source_name,
            event_name = EXCLUDED.event_name,
            event_category = EXCLUDED.event_category,
            friction_domain = EXCLUDED.friction_domain,
            trigger_category = EXCLUDED.trigger_category,
            source_url = EXCLUDED.source_url,
            description = EXCLUDED.description,
            normalized_score = EXCLUDED.normalized_score,
            friction_weight_ref = EXCLUDED.friction_weight_ref,
            announcement_time = EXCLUDED.announcement_time,
            updated_at = now();
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1d. Attach trigger to academic_lgu_events
DROP TRIGGER IF EXISTS tg_sync_academic_lgu_events ON external.academic_lgu_events;
CREATE TRIGGER tg_sync_academic_lgu_events
AFTER INSERT OR UPDATE OR DELETE ON external.academic_lgu_events
FOR EACH ROW EXECUTE FUNCTION external.sync_academic_lgu_to_events_consolidated();


-- ============================================================================
-- WORKSTREAM 2: Academic Calendar Ingestion
-- ============================================================================

-- 2a. Tracking table for processed calendar tables
CREATE TABLE IF NOT EXISTS external.processed_calendar_tables (
    table_name text PRIMARY KEY,
    rows_processed integer DEFAULT 0,
    last_processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

-- 2b. Classifier for structured academic calendar event_name
CREATE OR REPLACE FUNCTION external.classify_calendar_event(
    p_event_name text
) RETURNS TABLE (
    event_category text,
    friction_domain text,
    trigger_category text,
    affects_ridership boolean
) AS $$
DECLARE
    v_lower text;
BEGIN
    v_lower := LOWER(COALESCE(p_event_name, ''));

    -- Promotions Board / Grade posting / Dropping of subjects / Leave filing (internal, no ridership impact)
    IF v_lower ~* '(promotions?\s+board|posting\s+of.*(grade|result)|deliberation|grade\s+release|final\s+grade|drop(ping)?\s+of\s+subject|leave\s+of\s+absence|filing)' THEN
        event_category := 'administrative';
        friction_domain := NULL;
        trigger_category := NULL;
        affects_ridership := FALSE;
        RETURN NEXT; RETURN;
    END IF;

    -- Exam events
    IF v_lower ~* '(exam(ination)?|long\s+exam|qualifying|prelim(inary)?|midterm|finals?)' THEN
        event_category := 'exam_week';
        friction_domain := 'academic';
        trigger_category := 'University Exam Week';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- School Breaks (scheduled academic breaks)
    IF v_lower ~* '(semestral\s+break|sem\s+break|christmas\s+break|summer\s+break|vacation|academic\s+break|lenten\s+break|undas)' THEN
        event_category := 'school_break';
        friction_domain := 'academic';
        trigger_category := 'School Break';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Holidays / Class Suspensions (unscheduled or holiday class off)
    IF v_lower ~* '(holiday|holy\s+week|class(es)?\s+suspend|suspend(ed)?\s+class|walang\s+pasok|no\s+class|non[- ]?working\s+(day|holiday)?|special\s+(non[- ]?working|public)\s+(day|holiday)?|regular\s+holiday|araw\s+ng|founding\s+anniversary|rizal\s+day|bonifacio\s+day|bonifactio|independence\s+day|labor\s+day|ninoy\s+aquino|national\s+heroes|all\s+saint|all\s+soul|christmas|new\s+year|maundy\s+thursday|good\s+friday|black\s+saturday|easter|immaculate\s+conception|edsa|eid|ramadan|day\s+of\s+valor|quezon\s+city\s+day|manila\s+day|pasig\s+day|marikina\s+day|san\s+juan\s+day|antipolo\s+day|feast\s+of\s+st|up\s+foundation|ateneo\s+president|traslacion|black\s+nazarene|sona|state\s+of\s+the\s+nation)' THEN
        event_category := 'class_suspension';
        friction_domain := 'academic';
        trigger_category := 'Class Suspension / Holiday';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Graduation / Commencement / Major Campus Festivals (major event surge)
    IF v_lower ~* '(graduation|commencement|baccalaureate|recognition\s+(day|rites)|paskuhan|lantern\s+parade)' THEN
        event_category := 'major_event';
        friction_domain := 'academic';
        trigger_category := 'Major Arena Event';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Enrollment period (regular operations)
    IF v_lower ~* '(enrollment|enrolment|registration|first\s+day\s+of\s+(class|regular)|orientation|opening)' THEN
        event_category := 'regular_class_day';
        friction_domain := 'academic';
        trigger_category := 'Regular Class Day';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Last day of classes (regular operations)
    IF v_lower ~* '(last\s+day\s+of\s+(regular\s+)?class|end\s+of\s+(regular\s+)?class)' THEN
        event_category := 'regular_class_day';
        friction_domain := 'academic';
        trigger_category := 'Regular Class Day';
        affects_ridership := TRUE;
        RETURN NEXT; RETURN;
    END IF;

    -- Default: unclassified / no ridership impact
    event_category := 'unclassified';
    friction_domain := NULL;
    trigger_category := NULL;
    affects_ridership := FALSE;
    RETURN NEXT; RETURN;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2c. Function to process a single academic calendar table
CREATE OR REPLACE FUNCTION external.process_academic_calendar(p_table_name text)
RETURNS integer AS $$
DECLARE
    v_row RECORD;
    v_class RECORD;
    v_weight numeric;
    v_count integer := 0;
    v_consolidated_id text;
    v_school_acronym text;
    v_event_date date;
    v_stations text[];
    v_station text;
BEGIN
    -- Prevent duplicates: delete all existing consolidated rows for this table first
    DELETE FROM external.events_consolidated WHERE source_table = p_table_name;

    -- Extract school acronym from table name (e.g., 'UERM_Academic_Calendar' -> 'UERM')
    v_school_acronym := SPLIT_PART(p_table_name, '_Academic_Calendar', 1);

    -- Iterate over all rows in the calendar table
    FOR v_row IN EXECUTE format(
        'SELECT id, station, source_name, event_date, event_name, category, source_url FROM external.%I',
        p_table_name
    ) LOOP
        -- Classify the event
        SELECT * INTO v_class
        FROM external.classify_calendar_event(v_row.event_name);

        -- Skip non-ridership events
        IF v_class.affects_ridership = FALSE OR v_class.affects_ridership IS NULL THEN
            CONTINUE;
        END IF;

        -- Look up literature weight
        SELECT fw.friction_weight INTO v_weight
        FROM external.friction_weight fw
        WHERE fw.friction_domain = v_class.friction_domain
          AND fw.trigger_category = v_class.trigger_category
        LIMIT 1;
        v_weight := COALESCE(v_weight, 0.0);

        -- Parse event_date safely
        BEGIN
            v_event_date := v_row.event_date::date;
        EXCEPTION WHEN OTHERS THEN
            v_event_date := CURRENT_DATE;
        END;

        -- Resolve list of stations affected by calling get_affected_stations
        v_stations := external.get_affected_stations(v_row.station, v_row.event_name, '', COALESCE(v_row.source_name, v_school_acronym));

        FOREACH v_station IN ARRAY v_stations LOOP
            -- Build deterministic consolidated ID to prevent intra-calendar duplicate rows: CAL-[SCH]-[MMDD]-[MD5_HASH]
            v_consolidated_id := 'CAL-' || UPPER(v_school_acronym) || '-' || TO_CHAR(v_event_date, 'MMDD') || '-' || SUBSTRING(MD5(LOWER(external.normalize_station_name(v_station)) || '_' || LOWER(TRIM(v_row.event_name))), 1, 8);

            INSERT INTO external.events_consolidated (
                id, station, event_date, source_table, source_id, source_name,
                event_name, event_category, friction_domain, trigger_category,
                source_url, description,
                normalized_score, friction_weight_ref, announcement_time, updated_at
            )
            VALUES (
                v_consolidated_id,
                external.normalize_station_name(v_station),
                v_event_date,
                p_table_name,
                COALESCE(v_row.id, 'row-' || v_count),
                COALESCE(v_row.source_name, v_school_acronym),
                v_row.event_name,
                v_class.event_category,
                v_class.friction_domain,
                v_class.trigger_category,
                v_row.source_url,
                'Event: ' || v_row.event_name || ' (Scraped from ' || replace(p_table_name, '_', ' ') || ')',
                CASE
                    WHEN v_class.event_category IN ('class_suspension', 'holiday', 'school_break') THEN 1.0
                    ELSE v_weight
                END,
                v_weight,
                NULL,
                now()
            )
            ON CONFLICT (id) DO UPDATE SET
                station = EXCLUDED.station,
                event_date = EXCLUDED.event_date,
                source_name = EXCLUDED.source_name,
                event_name = EXCLUDED.event_name,
                event_category = EXCLUDED.event_category,
                friction_domain = EXCLUDED.friction_domain,
                trigger_category = EXCLUDED.trigger_category,
                source_url = EXCLUDED.source_url,
                description = EXCLUDED.description,
                normalized_score = EXCLUDED.normalized_score,
                friction_weight_ref = EXCLUDED.friction_weight_ref,
                announcement_time = EXCLUDED.announcement_time,
                updated_at = now();
        END LOOP;

        v_count := v_count + 1;
    END LOOP;

    -- Track this table as processed
    INSERT INTO external.processed_calendar_tables (table_name, rows_processed, last_processed_at)
    VALUES (p_table_name, v_count, now())
    ON CONFLICT (table_name) DO UPDATE SET
        rows_processed = v_count,
        last_processed_at = now();

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 2d. Polling function: scan for new *_Academic_Calendar tables
CREATE OR REPLACE FUNCTION external.scan_and_process_new_calendars()
RETURNS text AS $$
DECLARE
    v_table RECORD;
    v_processed integer;
    v_results text := '';
BEGIN
    FOR v_table IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'external'
          AND table_name LIKE '%\_Academic\_Calendar' ESCAPE '\'
          AND table_name NOT IN (SELECT table_name FROM external.processed_calendar_tables)
        ORDER BY table_name
    LOOP
        v_processed := external.process_academic_calendar(v_table.table_name);
        v_results := v_results || v_table.table_name || ': ' || v_processed || ' events processed. ';
    END LOOP;

    IF v_results = '' THEN
        RETURN 'No new Academic Calendar tables found.';
    END IF;

    RETURN v_results;
END;
$$ LANGUAGE plpgsql;

-- Alias for scan_and_process_new_calendars
CREATE OR REPLACE FUNCTION external.poll_new_academic_calendars()
RETURNS text AS $$
BEGIN
    RETURN external.scan_and_process_new_calendars();
END;
$$ LANGUAGE plpgsql;


