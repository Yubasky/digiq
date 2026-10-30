-- ==============================================================================
-- DigiQ Migration 011: pg_cron Background Job untuk expire_pending_transactions
-- File: supabase/011_cron_expire_pending_transactions.sql
-- ==============================================================================
-- LATAR BELAKANG:
-- 1. Fungsi expire_pending_transactions() secara default hanya dipicu secara lazy
--    saat pengguna memanggil create_purchase_transaction() atau saat pembayaran
--    diverifikasi via verify_payment_by_amount().
-- 2. Jika tidak ada transaksi baru, stok produk yang pending dan sudah kedaluwarsa
--    (>15 menit + grace 2 menit) tidak segera dikembalikan ke katalog.
-- 3. Live database telah mengaktifkan extension 'pg_cron'. File ini menjadwalkan
--    pembersihan otomatis setiap 2 menit di background database PostgreSQL.
-- ==============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Batalkan jadwal lama jika sudah ada (idempoten)
    PERFORM cron.unschedule('digiq_expire_pending_transactions');

    -- Jadwalkan eksekusi berkala setiap 2 menit
    PERFORM cron.schedule(
      'digiq_expire_pending_transactions',
      '*/2 * * * *',
      'SELECT public.expire_pending_transactions()'
    );

    RAISE NOTICE 'SUKSES: Cron job digiq_expire_pending_transactions dijadwalkan setiap 2 menit.';
  ELSE
    RAISE NOTICE 'INFO: Extension pg_cron tidak ditemukan. Abaikan penjadwalan otomatis.';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'INFO: Gagal menjadwalkan cron: % (Abaikaan jika izin cron dibatasi)', SQLERRM;
END $$;
