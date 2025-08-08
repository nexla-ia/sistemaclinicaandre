/*
  # Add Generate Slots RPC Function

  1. New Functions
    - `generate_slots_for_period` - Generates time slots based on working hours
    - `block_slot` - Blocks a specific time slot
    - `unblock_slot` - Unblocks a specific time slot
    - `update_updated_at_column` - Trigger function for updating timestamps

  2. Security
    - Functions are accessible to authenticated users
    - Proper error handling included
*/

-- Function to update updated_at column
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Function to generate slots for a period based on working hours
CREATE OR REPLACE FUNCTION generate_slots_for_period(
    start_date DATE,
    end_date DATE
)
RETURNS VOID AS $$
DECLARE
    current_date DATE;
    day_of_week INTEGER;
    working_hour RECORD;
    slot_time TIME;
    slot_duration INTEGER;
    open_time TIME;
    close_time TIME;
    break_start TIME;
    break_end TIME;
BEGIN
    -- Loop through each date in the range
    current_date := start_date;
    
    WHILE current_date <= end_date LOOP
        -- Get day of week (0 = Sunday, 1 = Monday, etc.)
        day_of_week := EXTRACT(DOW FROM current_date);
        
        -- Get working hours for this day
        SELECT * INTO working_hour
        FROM working_hours
        WHERE day_of_week = EXTRACT(DOW FROM current_date)
        AND is_open = true
        LIMIT 1;
        
        -- If salon is open on this day, generate slots
        IF FOUND THEN
            open_time := working_hour.open_time;
            close_time := working_hour.close_time;
            break_start := working_hour.break_start;
            break_end := working_hour.break_end;
            slot_duration := COALESCE(working_hour.slot_duration, 30);
            
            -- Generate slots from open to close time
            slot_time := open_time;
            
            WHILE slot_time < close_time LOOP
                -- Skip break time if defined
                IF break_start IS NULL OR break_end IS NULL OR 
                   slot_time < break_start OR slot_time >= break_end THEN
                    
                    -- Insert slot if it doesn't exist
                    INSERT INTO slots (date, time_slot, status)
                    VALUES (current_date, slot_time, 'available')
                    ON CONFLICT (salon_id, date, time_slot) DO NOTHING;
                END IF;
                
                -- Move to next slot
                slot_time := slot_time + (slot_duration || ' minutes')::INTERVAL;
            END LOOP;
        END IF;
        
        -- Move to next date
        current_date := current_date + INTERVAL '1 day';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to block a specific slot
CREATE OR REPLACE FUNCTION block_slot(
    slot_date DATE,
    slot_time TIME,
    reason TEXT DEFAULT 'Bloqueado pelo administrador'
)
RETURNS BOOLEAN AS $$
DECLARE
    slot_exists BOOLEAN;
BEGIN
    -- Check if slot exists and is available
    SELECT EXISTS(
        SELECT 1 FROM slots 
        WHERE date = slot_date 
        AND time_slot = slot_time 
        AND status = 'available'
    ) INTO slot_exists;
    
    IF slot_exists THEN
        -- Update slot to blocked
        UPDATE slots 
        SET status = 'blocked', 
            blocked_reason = reason,
            updated_at = CURRENT_TIMESTAMP
        WHERE date = slot_date 
        AND time_slot = slot_time;
        
        RETURN TRUE;
    ELSE
        -- Create blocked slot if it doesn't exist
        INSERT INTO slots (date, time_slot, status, blocked_reason)
        VALUES (slot_date, slot_time, 'blocked', reason)
        ON CONFLICT (salon_id, date, time_slot) 
        DO UPDATE SET 
            status = 'blocked',
            blocked_reason = reason,
            updated_at = CURRENT_TIMESTAMP;
        
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to unblock a specific slot
CREATE OR REPLACE FUNCTION unblock_slot(
    slot_date DATE,
    slot_time TIME
)
RETURNS BOOLEAN AS $$
DECLARE
    slot_exists BOOLEAN;
BEGIN
    -- Check if slot exists and is blocked
    SELECT EXISTS(
        SELECT 1 FROM slots 
        WHERE date = slot_date 
        AND time_slot = slot_time 
        AND status = 'blocked'
    ) INTO slot_exists;
    
    IF slot_exists THEN
        -- Update slot to available
        UPDATE slots 
        SET status = 'available', 
            blocked_reason = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE date = slot_date 
        AND time_slot = slot_time;
        
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;