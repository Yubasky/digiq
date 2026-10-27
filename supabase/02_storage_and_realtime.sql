-- ============================================================
-- FILE 2: STORAGE, REALTIME & SEED DATA PRODUK
-- Jalankan file ini KEDUA (setelah File 1 selesai)
-- ============================================================

-- ┌────────────────────────────────────────────────────────┐
-- │  1. REALTIME ENGINE                                    │
-- └────────────────────────────────────────────────────────┘
ALTER TABLE public.products      REPLICA IDENTITY FULL;
ALTER TABLE public.transactions  REPLICA IDENTITY FULL;
ALTER TABLE public.chat_messages REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'transactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
  END IF;
END;
$$;

-- ┌────────────────────────────────────────────────────────┐
-- │  2. STORAGE: bucket 'avatars' & policies               │
-- └────────────────────────────────────────────────────────┘
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
CREATE POLICY "Avatar images are publicly accessible"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
CREATE POLICY "Users can upload their own avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ┌────────────────────────────────────────────────────────┐
-- │  3. SEED DATA: Produk Siap Jual (Opsional / Siap Pakai)│
-- └────────────────────────────────────────────────────────┘
INSERT INTO public.products (name, category, description, price, discount_price, stock, is_active, provider, image_url)
VALUES
  (
    'Netflix Premium 4K UHD',
    'Streaming',
    'Akun Netflix 1 Profile Private (PIN Khusus). Kualitas 4K Ultra HD di semua perangkat.',
    45000,
    38000,
    25,
    true,
    'Netflix',
    'https://images.unsplash.com/photo-1522869635100-9f4c5e86aa37?w=500&q=80'
  ),
  (
    'ChatGPT Plus (GPT-4o)',
    'Streaming',
    'Akun ChatGPT Plus resmi GPT-4o, DALL-E 3, Browsing, Voice Mode aktif garansi 30 hari.',
    85000,
    75000,
    15,
    true,
    'OpenAI',
    'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500&q=80'
  ),
  (
    'Spotify Premium 3 Bulan',
    'Streaming',
    'Akun Spotify Premium Individual 3 Bulan. Bebas iklan, unduh lagu offline HD.',
    40000,
    32000,
    30,
    true,
    'Spotify',
    'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80'
  ),
  (
    'YouTube Premium 1 Bulan',
    'Streaming',
    'YouTube Premium & Music bebas iklan, putar latar belakang resolusi tinggi.',
    28000,
    22000,
    20,
    true,
    'YouTube',
    'https://images.unsplash.com/photo-1611162617213-7d7a39e9b1d7?w=500&q=80'
  ),
  (
    'Token Listrik PLN Rp 50.000',
    'PLN',
    'Token listrik PLN prabayar nominal Rp 50.000 proses cepat 1-5 menit.',
    51500,
    51000,
    99,
    true,
    'PLN',
    'https://images.unsplash.com/photo-1473341304170-971dccb5ac1e?w=500&q=80'
  ),
  (
    'Pulsa Telkomsel Rp 50.000',
    'Pulsa',
    'Pulsa reguler Telkomsel Rp 50.000 menambah masa aktif nomor Anda.',
    50800,
    50000,
    99,
    true,
    'Telkomsel',
    'https://images.unsplash.com/photo-1563770660941-20978e870e26?w=500&q=80'
  ),
  (
    'Saldo GoPay Rp 50.000',
    'E-Wallet',
    'Top up saldo GoPay instan otomatis langsung masuk ke akun terdaftar.',
    51200,
    50500,
    99,
    true,
    'GoPay',
    'https://images.unsplash.com/photo-1559526324-4b87b5e36e44?w=500&q=80'
  ),
  (
    'Mobile Legends 86 Diamonds',
    'Games',
    'Top up diamond Mobile Legends instan resmi Moonton (butuh User ID + Zone ID).',
    21500,
    19900,
    50,
    true,
    'Moonton',
    'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=500&q=80'
  )
ON CONFLICT DO NOTHING;

-- ┌────────────────────────────────────────────────────────┐
-- │  4. CARA MEMBUAT AKUN ADMIN                            │
-- │  Setelah daftar akun via aplikasi:                     │
-- │  Jalankan perintah ini di SQL Editor:                  │
-- │                                                        │
-- │  UPDATE public.profiles                                │
-- │  SET role = 'admin'                                    │
-- │  WHERE id = 'PASTE_UUID_USER_ANDA_DI_SINI';            │
-- └────────────────────────────────────────────────────────┘
