-- Find A Doctor V9 database helpers
-- Safe additions only. No data deletion.

CREATE OR REPLACE FUNCTION public.update_my_doctor_schedule(
  p_start_time time,
  p_end_time time,
  p_working_days text
)
RETURNS public.doctors
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_doctor
  FROM public.doctors
  WHERE user_id = auth.uid()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Doctor profile not found.';
  END IF;

  IF p_start_time IS NULL OR p_end_time IS NULL THEN
    RAISE EXCEPTION 'Clinic start and end time are required.';
  END IF;

  IF p_start_time >= p_end_time THEN
    RAISE EXCEPTION 'Clinic end time must be after start time.';
  END IF;

  IF p_working_days IS NULL OR length(trim(p_working_days)) = 0 THEN
    RAISE EXCEPTION 'Working days are required.';
  END IF;

  IF length(p_working_days) > 100 THEN
    RAISE EXCEPTION 'Working days value is too long.';
  END IF;

  UPDATE public.doctors
  SET
    clinic_start_time = p_start_time,
    clinic_end_time = p_end_time,
    working_days = trim(p_working_days)
  WHERE id = v_doctor.id
  RETURNING * INTO v_doctor;

  RETURN v_doctor;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_doctor_schedule(time,time,text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_doctor_schedule(time,time,text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.update_my_doctor_photo(
  p_profile_image text
)
RETURNS public.doctors
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be logged in.';
  END IF;

  SELECT * INTO v_doctor
  FROM public.doctors
  WHERE user_id = auth.uid()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Doctor profile not found.';
  END IF;

  IF p_profile_image IS NULL OR length(p_profile_image) > 1000000 THEN
    RAISE EXCEPTION 'Invalid profile picture.';
  END IF;

  UPDATE public.doctors
  SET profile_image = p_profile_image,
      img = p_profile_image
  WHERE id = v_doctor.id
  RETURNING * INTO v_doctor;

  RETURN v_doctor;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_doctor_photo(text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_doctor_photo(text)
TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Cloudflare live-queue helpers. Supabase remains the source of truth.
CREATE OR REPLACE FUNCTION public.advance_my_doctor_queue(p_doctor_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_current integer := 0;
  v_next integer;
  v_booking uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'You must be logged in.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM doctors WHERE id=p_doctor_id AND user_id=v_user) THEN
    RAISE EXCEPTION 'Not authorized for this doctor.';
  END IF;
  SELECT current_token INTO v_current FROM doctor_queues WHERE doctor_id=p_doctor_id FOR UPDATE;
  IF v_current IS NULL THEN v_current := 0; END IF;
  SELECT id, token_number INTO v_booking, v_next
  FROM bookings
  WHERE doctor_id=p_doctor_id
    AND (appointment_date IS NULL OR appointment_date=(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Karachi')::date)
    AND status IN ('booked','waiting')
    AND token_number > v_current
  ORDER BY token_number ASC
  LIMIT 1;
  IF v_next IS NULL THEN
    RETURN jsonb_build_object('ok',false,'message','No waiting patient.','current_token',v_current);
  END IF;
  UPDATE doctor_queues SET current_token=v_next WHERE doctor_id=p_doctor_id;
  UPDATE bookings SET status='called' WHERE id=v_booking;
  RETURN jsonb_build_object('ok',true,'current_token',v_next,'booking_id',v_booking);
END;
$$;
REVOKE ALL ON FUNCTION public.advance_my_doctor_queue(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.advance_my_doctor_queue(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_my_doctor_queue_paused(p_doctor_id uuid, p_paused boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'You must be logged in.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM doctors WHERE id=p_doctor_id AND user_id=v_user) THEN RAISE EXCEPTION 'Not authorized for this doctor.'; END IF;
  UPDATE doctor_queues SET paused=COALESCE(p_paused,false) WHERE doctor_id=p_doctor_id;
  RETURN jsonb_build_object('ok',true,'paused',COALESCE(p_paused,false));
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_doctor_queue_paused(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_doctor_queue_paused(uuid,boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
