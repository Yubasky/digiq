# Task 05: Customer-Admin Live Chat & Realtime Messaging

## 1. Tujuan
Menyediakan fitur live chat antara Customer dan Admin DigiQ untuk konsultasi produk, pengiriman bukti pembayaran tambahan jika diperlukan, dan customer support 24/7.

## 2. File Terkait
- [lib/models/chat_message_model.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/models/chat_message_model.dart)
- [lib/services/chat_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/chat_service.dart)
- [supabase/01_main_schema.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/01_main_schema.sql)

## 3. Keputusan Desain & Keamanan RLS
1. **Pemisahan Chat Room**: Kolom `room_user_id` memetakan ID customer. Admin dapat membaca pesan di seluruh room, sedangkan customer hanya dapat membaca pesan di room miliknya sendiri (`room_user_id = auth.uid()`).
2. **Realtime Broadcast**: Pesan baru di-broadcast via Supabase Realtime channel postgres_changes.
3. **Read Receipts**: Status terbaca (`is_read`) diperbarui saat room dibuka oleh lawan bicara.

## 4. Cara Uji
1. Customer mengirim pesan ke admin melalui antarmuka chat.
2. Admin menerima pesan secara realtime di Dashboard Admin dan dapat langsung membalas.

## 5. Status Aktual
**SELESAI (100% Verified)**: Terintegrasi dengan backend Supabase Realtime.
