-- ==============================================================================
-- DigiQ Audit: Test Claim Flow (SQL Verification)
-- File: audit/test_claim_flow.sql
-- Run inside BEGIN ... ROLLBACK to ensure zero persistent side effects.
-- ==============================================================================

BEGIN;

DO $$
DECLARE
  v_customer_id   UUID := gen_random_uuid();
  v_other_cust_id UUID := gen_random_uuid();
  v_admin_id      UUID := gen_random_uuid();
  v_prod_id       UUID;
  v_trx_paid_id   UUID;
  v_trx_unpaid_id UUID;
  v_claim_res     JSONB;
  v_msg_count     INT;
  v_event_count   INT;
  v_err_caught    BOOLEAN;
BEGIN
  RAISE NOTICE '=== MEMULAI TEST ALUR KLAIM PRODUK VIA CHAT ===';

  -- 1. Setup Mock Profiles
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES
    (v_customer_id, 'test_cust@example.com', 'Test Customer', 'customer'),
    (v_other_cust_id, 'test_other@example.com', 'Other Customer', 'customer'),
    (v_admin_id, 'test_admin@example.com', 'Admin DigiQ', 'admin');

  -- Setup Mock Product
  INSERT INTO public.products (id, name, slug, price, is_active, stock)
  VALUES (gen_random_uuid(), 'Akun Spotify Premium 1 Bulan', 'spotify-1mo', 30000, true, 10)
  RETURNING id INTO v_prod_id;

  -- Setup Mock Transactions: 1 Paid ('success'), 1 Unpaid ('pending')
  INSERT INTO public.transactions (
    id, user_id, product_id, base_amount, unique_code, total_amount, target_number, status, paid_at, trx_code
  )
  VALUES (
    gen_random_uuid(), v_customer_id, v_prod_id, 30000, 12, 30012, '08123456789', 'success', now(), 'TRX-TEST-PAID'
  )
  RETURNING id INTO v_trx_paid_id;

  INSERT INTO public.transactions (
    id, user_id, product_id, base_amount, unique_code, total_amount, target_number, status, trx_code
  )
  VALUES (
    gen_random_uuid(), v_customer_id, v_prod_id, 30000, 15, 30015, '08123456789', 'pending', 'TRX-TEST-UNPAID'
  )
  RETURNING id INTO v_trx_unpaid_id;

  -- -------------------------------------------------------------------------
  -- U1: Owner Request Claim on Paid Transaction
  -- -------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);

  v_claim_res := public.request_claim(v_trx_paid_id);
  ASSERT (v_claim_res->>'success')::boolean = true, 'U1 FAILED: success should be true';
  ASSERT (v_claim_res->>'already_requested')::boolean = false, 'U1 FAILED: already_requested should be false';
  ASSERT (v_claim_res->>'claim_status') = 'requested', 'U1 FAILED: status should be requested';

  SELECT COUNT(*) INTO v_msg_count FROM public.chat_messages WHERE trx_id = v_trx_paid_id AND kind = 'claim';
  ASSERT v_msg_count = 1, 'U1 FAILED: exactly 1 claim message must be created';

  SELECT COUNT(*) INTO v_event_count FROM public.claim_events WHERE trx_id = v_trx_paid_id AND to_status = 'requested';
  ASSERT v_event_count = 1, 'U1 FAILED: audit event for requested must be logged';

  RAISE NOTICE '[PASS] U1: Customer berhasil klaim transaksi lunas, 1 chat_message kind=claim dibuat';

  -- -------------------------------------------------------------------------
  -- U2: Idempotency: Second Request Returns already_requested: true
  -- -------------------------------------------------------------------------
  v_claim_res := public.request_claim(v_trx_paid_id);
  ASSERT (v_claim_res->>'already_requested')::boolean = true, 'U2 FAILED: should return already_requested=true';

  SELECT COUNT(*) INTO v_msg_count FROM public.chat_messages WHERE trx_id = v_trx_paid_id AND kind = 'claim';
  ASSERT v_msg_count = 1, 'U2 FAILED: no duplicate claim message should be created';

  RAISE NOTICE '[PASS] U2: Klaim berulang bersifat idempoten (tanpa duplikasi pesan)';

  -- -------------------------------------------------------------------------
  -- U3: Non-Owner Request Must Be Rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_other_cust_id::text, true);
  v_err_caught := false;
  BEGIN
    PERFORM public.request_claim(v_trx_paid_id);
  EXCEPTION WHEN OTHERS THEN
    v_err_caught := true;
  END;
  ASSERT v_err_caught = true, 'U3 FAILED: non-owner claim must throw error';
  RAISE NOTICE '[PASS] U3: Percobaan klaim oleh non-pemilik ditolak';

  -- -------------------------------------------------------------------------
  -- U4: Unpaid Transaction Request Must Be Rejected
  -- -------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);
  v_err_caught := false;
  BEGIN
    PERFORM public.request_claim(v_trx_unpaid_id);
  EXCEPTION WHEN OTHERS THEN
    v_err_caught := true;
  END;
  ASSERT v_err_caught = true, 'U4 FAILED: unpaid transaction claim must throw error';
  RAISE NOTICE '[PASS] U4: Percobaan klaim transaksi pending/belum lunas ditolak';

  -- -------------------------------------------------------------------------
  -- U5: Direct PATCH to claim_status Blocked by Trigger
  -- -------------------------------------------------------------------------
  v_err_caught := false;
  BEGIN
    UPDATE public.transactions SET claim_status = 'delivered' WHERE id = v_trx_paid_id;
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_err_caught := true;
  END;
  ASSERT v_err_caught = true, 'U5 FAILED: direct UPDATE on claim_status must be blocked by trigger';
  RAISE NOTICE '[PASS] U5: Direct PATCH ke claim_status diblokir oleh protect trigger';

  -- -------------------------------------------------------------------------
  -- U6: Admin Marks Delivered
  -- -------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

  PERFORM public.admin_mark_delivered(v_trx_paid_id);

  SELECT COUNT(*) INTO v_event_count FROM public.claim_events WHERE trx_id = v_trx_paid_id AND to_status = 'delivered';
  ASSERT v_event_count = 1, 'U6 FAILED: audit event for delivered must be logged';

  SELECT COUNT(*) INTO v_msg_count FROM public.chat_messages WHERE trx_id = v_trx_paid_id AND kind = 'system';
  ASSERT v_msg_count = 1, 'U6 FAILED: system message for delivered must be created';

  RAISE NOTICE '[PASS] U6: Admin berhasil tandai terkirim via RPC admin_mark_delivered';

  RAISE NOTICE '=== SEMUA TEST SQL KLAIM BERHASIL ===';
END;
$$;

ROLLBACK;

