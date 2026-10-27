// supabase/functions/payment-webhook/index.ts
// Supabase Edge Function: Webhook Handler Mutasi Pembayaran Masuk
//
// Menerima notifikasi mutasi uang masuk dari forwarder / payment provider,
// memverifikasi HMAC-SHA256 signature secara constant-time,
// dan memanggil RPC public.verify_payment_by_amount menggunakan SUPABASE_SERVICE_ROLE_KEY.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Helper constant-time comparison untuk mencegah timing attacks
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff === 0;
}

// Helper verifikasi HMAC-SHA256
async function verifyHmacSignature(
  secret: string,
  rawBody: string,
  providedSignatureHex: string
): Promise<boolean> {
  try {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const signatureBuffer = await crypto.subtle.sign(
      "HMAC",
      key,
      encoder.encode(rawBody)
    );

    const calculatedSigBytes = new Uint8Array(signatureBuffer);

    // Konversi provided hex ke Uint8Array
    const cleanHex = providedSignatureHex.trim().toLowerCase().replace(/^sha256=/, "");
    if (cleanHex.length % 2 !== 0) return false;

    const providedSigBytes = new Uint8Array(cleanHex.length / 2);
    for (let i = 0; i < cleanHex.length; i += 2) {
      providedSigBytes[i / 2] = parseInt(cleanHex.substring(i, i + 2), 16);
    }

    return timingSafeEqual(calculatedSigBytes, providedSigBytes);
  } catch (_) {
    return false;
  }
}

serve(async (req: Request) => {
  // Hanya izinkan metode POST
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed. Use POST." }),
      { status: 405, headers: { "Content-Type": "application/json" } }
    );
  }

  try {
    const rawBody = await req.text();
    const webhookSecret = Deno.env.get("WEBHOOK_SECRET");

    // 1. Verifikasi HMAC signature jika WEBHOOK_SECRET dikonfigurasi
    if (webhookSecret) {
      const signature =
        req.headers.get("x-webhook-signature") ||
        req.headers.get("x-signature") ||
        "";

      if (!signature) {
        return new Response(
          JSON.stringify({ error: "Missing x-webhook-signature header" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }

      const isValid = await verifyHmacSignature(webhookSecret, rawBody, signature);
      if (!isValid) {
        return new Response(
          JSON.stringify({ error: "Invalid webhook signature" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    // 2. Parse payload JSON
    let payload: Record<string, any>;
    try {
      payload = JSON.parse(rawBody);
    } catch (_) {
      return new Response(
        JSON.stringify({ error: "Malformed JSON payload" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // 3. Adapter generik: Ekstrak nominal, tipe transaksi, referensi, dan sumber
    const amountNum = Number(
      payload.amount ?? payload.nominal ?? payload.total_amount ?? 0
    );
    const typeStr = String(
      payload.type ?? payload.mutation_type ?? payload.direction ?? "CR"
    ).toUpperCase();
    const externalRef = String(
      payload.external_ref ??
        payload.reference_id ??
        payload.trx_id ??
        payload.id ??
        `WH-${Date.now()}`
    );
    const source = String(payload.source ?? payload.provider ?? "webhook");
    const receivedAt =
      payload.received_at ?? payload.timestamp ?? new Date().toISOString();

    // 4. Filter hanya mutasi uang masuk (KREDIT)
    const isCredit =
      typeStr === "CR" ||
      typeStr === "CREDIT" ||
      typeStr === "IN" ||
      typeStr === "MASUK" ||
      typeStr === "PLUS";

    if (!isCredit) {
      return new Response(
        JSON.stringify({
          status: "ignored",
          message: "Abaikan: Hanya mutasi uang masuk (KREDIT) yang diproses",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    if (amountNum <= 0 || isNaN(amountNum)) {
      return new Response(
        JSON.stringify({ error: "Nominal pembayaran tidak valid atau <= 0" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // 5. Inisialisasi Supabase Admin Client dengan Service Role Key
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Server misconfiguration: missing Supabase credentials" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // 6. Panggil RPC verify_payment_by_amount
    const { data, error } = await supabaseAdmin.rpc("verify_payment_by_amount", {
      p_amount: amountNum,
      p_source: source,
      p_external_ref: externalRef,
      p_received_at: receivedAt,
      p_raw: payload,
    });

    if (error) {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        data,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Internal error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
