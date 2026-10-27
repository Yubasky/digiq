# Task 02: Authentication, Roles, & 2FA Enforcement (AAL2)

## 1. Tujuan
Menyediakan autentikasi yang aman untuk user DigiQ (Email/Password & Google Sign-In), pemisahan role `customer` vs `admin`, dan penegakan level verifikasi dua faktor (MFA/TOTP AAL2) pada seluruh operasi administratif dan aksi user yang mengaktifkan 2FA.

## 2. File Terkait
- [lib/services/auth_service.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/services/auth_service.dart)
- [lib/screens/login_screen.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/login_screen.dart)
- [lib/screens/auth_gate_screen.dart](file:///d:/PROJEK%20FAN%20DEV/digiq/lib/screens/auth_gate_screen.dart)
- [supabase/002_qris_unique_code.sql](file:///d:/PROJEK%20FAN%20DEV/digiq/supabase/002_qris_unique_code.sql)

## 3. Keputusan Desain & Keamanan
1. **Pemisahan Role di Database**: Kolom `role` disimpan di tabel `public.profiles` (`CHECK (role IN ('customer', 'admin'))`).
2. **Enforcement AAL2 pada RPC Admin**:
   - `admin_update_transaction_status`:
     ```sql
     IF NOT (public.is_admin() AND COALESCE(auth.jwt()->>'aal', '') = 'aal2') THEN
       RAISE EXCEPTION 'Akses ditolak: hanya admin dengan verifikasi 2FA (AAL2) yang dapat mengubah status' USING ERRCODE = '42501';
     END IF;
     ```
   - `verify_payment_by_amount`:
     ```sql
     v_is_service_role := (auth.role() = 'service_role');
     v_is_admin_aal2   := (public.is_admin() AND COALESCE(auth.jwt()->>'aal', '') = 'aal2');
     IF NOT (v_is_service_role OR v_is_admin_aal2) THEN
       RAISE EXCEPTION 'Akses ditolak: fungsi ini membutuhkan izin service_role atau admin AAL2' USING ERRCODE = '42501';
     END IF;
     ```
3. **Pemberian Proteksi Akun Customer**:
   Jika user mengaktifkan `is_2fa_enabled = true`, RPC `create_purchase_transaction` memvalidasi JWT level:
   ```sql
   IF FOUND AND v_profile.is_2fa_enabled THEN
     IF COALESCE(auth.jwt()->>'aal', '') <> 'aal2' THEN
       RAISE EXCEPTION 'Aksi membutuhkan autentikasi dua faktor (AAL2)' USING ERRCODE = '42501';
     END IF;
   END IF;
   ```

## 4. Cara Uji
1. Login dengan akun bertipe role `customer`.
2. Panggil RPC `admin_update_transaction_status` melalui client Dart -> ditolak dengan exception `42501`.
3. Login dengan akun admin tanpa sesi AAL2 -> ditolak dengan pesan error AAL2.
4. Login dengan akun admin yang telah memverifikasi challenge MFA TOTP (AAL2) -> panggilan berhasil.

## 5. Status Aktual
**SELESAI (100% Verified)**: Level AAL2 terverifikasi pada RPC database dan RLS tabel.
