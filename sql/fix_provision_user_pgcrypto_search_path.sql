-- ==============================================================================
-- Migration: Fix pgcrypto search_path & schema qualification in public.provision_user
-- Reason: provision_user uses crypt() and gen_salt('bf'), which reside in the 
--         'extensions' schema in Supabase. Without 'extensions' in the search_path,
--         invoking provision_user threw "function gen_salt(unknown) does not exist".
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.provision_user(
  p_email text, 
  p_password text, 
  p_role text, 
  p_first_name text, 
  p_last_name text, 
  p_mobile text, 
  p_username text, 
  p_security_key text, 
  p_station text DEFAULT NULL::text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'Analytics', 'iam', 'external', 'gcs', 'AFCS'
AS $function$
DECLARE
  new_auth_id uuid;
  new_iam_id text;
BEGIN
  -- Insert into auth.users with NULL email_confirmed_at so confirmation email is sent
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    recovery_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    NULL,
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    json_build_object('role', p_role),
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
  RETURNING id INTO new_auth_id;

  -- Insert into auth.identities
  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    new_auth_id,
    new_auth_id::text,
    format('{"sub":"%s","email":"%s"}', new_auth_id::text, p_email)::jsonb,
    'email',
    now(),
    now(),
    now()
  );

  -- Insert into iam.users
  INSERT INTO iam.users (
    auth_user_id,
    username,
    first_name,
    last_name,
    role,
    email,
    mobile,
    security_key,
    station,
    status
  ) VALUES (
    new_auth_id,
    p_username,
    p_first_name,
    p_last_name,
    p_role,
    p_email,
    p_mobile,
    p_security_key,
    p_station,
    'active'
  ) RETURNING id INTO new_iam_id;

  RETURN json_build_object('success', true, 'auth_id', new_auth_id, 'iam_id', new_iam_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN json_build_object('success', false, 'error', 'Email or Username already exists.');
  WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.provision_user(text, text, text, text, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_user(text, text, text, text, text, text, text, text, text) TO service_role;
